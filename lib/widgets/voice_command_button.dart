import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import '../models/voice_intent.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/language_service.dart';
import '../services/module_gate.dart';
import '../services/payment_service.dart';
import '../services/voice_command_catalog.dart';
import '../services/voice_command_service.dart';
import 'ams_dialog.dart';
import '../main.dart' show rootNavigatorKey, router;

/// Floating mic button that lives on every authenticated screen (added via
/// main.dart's MaterialApp.router `builder`). Tap to speak a command:
///
///   "open billing" / "show visitors" / "go to notices"   -> navigates right away
///   "generate bill for Suresh, July 2026"                -> confirmation screen, then calls the same
///                                                            /admin/bills/generate-catchup endpoint the
///                                                            manual "Catch-up Bill" dialog uses
///   "approve payment for Priya"                          -> confirmation screen, then the same
///                                                            /admin/payments/{id}/approve endpoint
///                                                            the Approvals screen uses
///
/// Speech-to-text is 100% on-device/browser-native (speech_to_text package -
/// wraps Android/iOS OS recognizers on mobile, the browser's built-in Web
/// Speech API on web). No paid API, no API key.
class VoiceCommandButton extends StatefulWidget {
  const VoiceCommandButton({super.key});

  @override
  State<VoiceCommandButton> createState() => _VoiceCommandButtonState();
}

/// Sentinel returned by [_ListeningSheet] when the speech engine itself
/// throws mid-listen (see its `_listen()`), so [_VoiceCommandButtonState._start]
/// can tell "engine failed" apart from "user cancelled / heard nothing" and
/// report it instead of silently doing nothing.
const _kVoiceListenError = '__voice_listen_error__';

class _VoiceCommandButtonState extends State<VoiceCommandButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _busy = false;
  // Tracks whether the mic button is currently being pressed, purely for
  // the transparent-until-touched background effect below - not related
  // to _listening (that's "is actively recording", a separate, longer-
  // lived state that starts after this initial press completes).
  bool _pressed = false;

  // Locales this device's speech engine actually supports, fetched once
  // right after a successful initialize(). Populated by _ensureReady(),
  // read by _resolveLocale() below.
  List<stt.LocaleName> _locales = [];

  static const _kOnboardingSeenKey = 'voice_onboarding_seen_v1';

  @override
  void dispose() {
    _voicePaymentService.dispose();
    super.dispose();
  }

  Future<bool> _ensureReady() async {
    if (_speechReady) return true;
    try {
      _speechReady = await _speech
          .initialize(
            onError: (err) {
              // Was resetting _speechReady on EVERY error, including the
              // routine, transient ones the browser's Web Speech API fires
              // constantly (no speech detected, session timeout, aborted,
              // etc. - err.permanent == false for these). That forced
              // _speech.initialize() to run again on the very next tap -
              // and calling initialize() a second time on the same engine
              // is exactly what makes speech_to_text's web layer throw
              // "Null check operator used on a null value" internally.
              // Only a *permanent* error (engine actually died - mic
              // grabbed by another app, OS service crashed) should force
              // the next tap to re-initialize from scratch; anything else
              // just ended this one listen session and the engine is fine.
              if (err.permanent) _speechReady = false;
            },
            onStatus: (_) {},
          )
          // The very first initialize() call is the one that triggers
          // Android's mic-permission dialog. If that dialog's result
          // doesn't make it back to the plugin cleanly (a known
          // speech_to_text timing issue), this Future can hang forever -
          // every tap after that first one would then await it silently
          // with zero feedback. A hard timeout guarantees we always come
          // back and can tell the user something went wrong instead of
          // going quiet.
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
    } catch (e, st) {
      debugPrint('VOICE_CMD_ERROR (initialize): $e\n$st');
      _speechReady = false;
    }
    if (_speechReady && _locales.isEmpty) {
      // Ask the OS/browser what locales it actually has installed for
      // speech recognition. This is device-specific — a phone can easily
      // be missing the recognizer pack for whatever language the app's UI
      // happens to be set to. We use this list in _resolveLocale() below
      // instead of trusting VoiceCommandService.localeIdFor()'s hardcoded
      // guess outright: handing listen() a localeId the device doesn't
      // actually have is a documented way to make speech_to_text throw a
      // raw "Null check operator used on a null value" instead of failing
      // gracefully.
      try {
        _locales = await _speech.locales();
      } catch (_) {
        _locales = [];
      }
    }
    return _speechReady;
  }

  /// Maps the app-language-derived locale guess (e.g. 'hi_IN') onto one the
  /// device's speech engine actually reports supporting, so we never hand
  /// listen() an id it doesn't recognize. Falls back to a same-language
  /// match (e.g. any 'hi_*' if 'hi_IN' isn't listed), then to null - which
  /// tells listen() below to just use the engine's own system default
  /// instead of forcing an unsupported id.
  String? _resolveLocale(String desired) {
    if (_locales.isEmpty) return null;
    if (_locales.any((l) => l.localeId == desired)) return desired;
    final prefix = desired.split('_').first.toLowerCase();
    for (final l in _locales) {
      if (l.localeId.toLowerCase().startsWith(prefix)) return l.localeId;
    }
    return null;
  }

  Future<void> _start({bool isRetry = false}) async {
    // If a previous tap is still stuck awaiting a hung plugin call (see the
    // timeout note below), a second tap would just queue up silently behind
    // it - looking, again, like the button does nothing. Block re-entry and
    // tell the person a request is already in flight instead. (Skipped on
    // our own internal retry below, which reuses this same tap.)
    if (_busy && !isRetry) return;
    _busy = true;
    try {
      final ok = await _ensureReady();
      if (!mounted) return;
      // TEMP DIAGNOSTIC: print() is more reliable than dev.log() when a
      // debug session isn't cleanly attached - it always goes to stdout,
      // which `flutter run`'s terminal (or `adb logcat -s flutter`) both
      // pick up. If you don't see even this line, the app you're testing
      // isn't the one currently running under `flutter run` - reinstall
      // via `flutter run`, don't just reopen the app icon afterward.
      print('VOICE_DEBUG: _start() reached, ensureReady=$ok');
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('voice_not_available'))),
        );
        return;
      }
      final role = await AuthService().effectiveRole();
      if (!mounted) return;

      await _maybeShowOnboardingTip(role);
      if (!mounted) return;

      final heard = await _listenSheet();
      if (!mounted) return;
      print('VOICE_DEBUG: heard="$heard"');
      if (heard == _kVoiceListenError) {
        // Engine broke mid-listen; force a clean re-initialize next tap
        // instead of reusing the (possibly wedged) session.
        _speechReady = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('voice_not_available'))),
        );
        return;
      }
      if (heard == null || heard.trim().isEmpty) {
        print('VOICE_DEBUG: heard was null/empty - returning before parse()');
        return;
      }

      final intent = VoiceCommandService.parse(heard, role);
      print('VOICE_DEBUG: intent=${intent.runtimeType}');
      await _handleIntent(intent, role);
    } catch (e, st) {
      // Was caught and shown only as a SnackBar - which meant it never
      // reached logcat/console at all (this is a Dart-level exception WE
      // catch, not a native Android crash), so `adb logcat` came up
      // completely empty when trying to diagnose the mobile "Null check
      // operator" report. Printing it (with the real stack trace) here
      // means the *next* capture will actually show something - search
      // logcat for "VOICE_CMD_ERROR" to find it quickly.
      debugPrint('VOICE_CMD_ERROR: $e\n$st');
      // AuthService now caches/de-dupes every flutter_secure_storage read
      // (see its comments), which covers the *common* trigger for "Null
      // check operator used on a null value" - several concurrent reads on
      // web. It can't guarantee zero concurrency app-wide though (some
      // other screen's own storage read can still overlap this exact tap).
      // Rather than show that raw, confusing plugin message, retry once
      // automatically after a beat, by which point AuthService's caches are
      // populated and the retry resolves cleanly - the person just sees a
      // brief pause instead of an error. Anything else (or a second
      // failure) still surfaces normally, same as before.
      if (!isRetry && e.toString().contains('Null check operator')) {
        _busy = false;
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        await _start(isRetry: true);
        return;
      }
      // Previously any error here (network hiccup fetching the role, a
      // plugin exception, etc.) just died silently mid-`await` with no
      // crash and no message - a tap would visibly do nothing. Now it
      // always surfaces, so a real failure is at least visible instead
      // of looking identical to "the button doesn't work".
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      _busy = false;
    }
  }

  /// Shown once, the very first time a given device uses the mic, so people
  /// know roughly what to say instead of guessing. A few real, tappable-free
  /// example phrases pulled straight from that role's own menu labels (so
  /// they're always accurate, and translate automatically) plus one admin
  /// action example. Flag is stored locally per device via SharedPreferences,
  /// same mechanism already used for cached branding/language.
  Future<void> _maybeShowOnboardingTip(String role) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kOnboardingSeenKey) == true) return;
    await prefs.setBool(_kOnboardingSeenKey, true);
    if (!mounted) return;

    final catalog = VoiceCommandCatalog.forRole(role);
    final openPrefix = LanguageService.t('voice_example_open_prefix');
    final examples = <String>[
      for (final cmd in catalog.take(3)) '$openPrefix ${LanguageService.t(cmd.labelKey)}',
      if (role == 'apartment_admin') LanguageService.t('voice_example_generate_bill'),
      if (role == 'resident') LanguageService.t('voice_example_raise_complaint'),
      if (role == 'security') LanguageService.t('voice_example_check_in'),
    ];

    // NOTE: deliberately NOT using this State's own `context` here. This
    // widget is inserted by VoiceCommandOverlay via MaterialApp.router's
    // `builder`, as a Stack SIBLING of the routed page - not a descendant
    // of it. That means our own context has no Navigator ancestor at all,
    // so Navigator.of(context)/showModalBottomSheet(context: context)
    // fails: in debug that throws a clear assert, but release builds strip
    // asserts, so it instead crashes with a bare "Null check operator used
    // on a null value" from inside Navigator.of - which is exactly the
    // crash this was producing. router.navigatorKey's context IS inside
    // the actual Navigator, so we use that instead.
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: navContext,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(Icons.mic_rounded, color: BrandingService.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(LanguageService.t('voice_onboarding_title'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ]),
            const SizedBox(height: 16),
            Text(LanguageService.t('voice_onboarding_body'),
                style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
            const SizedBox(height: 14),
            for (final ex in examples)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(Icons.mic_none_rounded, size: 16, color: BrandingService.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('"$ex"', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary),
                onPressed: () => Navigator.pop(ctx),
                child: Text(LanguageService.t('voice_onboarding_ok')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// On-demand version of the tip above, opened by tapping the small "?"
  /// badge on the mic button (see build() below) - unlike
  /// _maybeShowOnboardingTip, this has no "seen it once" gate and lists
  /// every navigation command for the role, not just 3 examples.
  Future<void> _showHelp() async {
    final role = await AuthService().effectiveRole();
    if (!mounted) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final catalog = VoiceCommandCatalog.forRole(role);
    final openPrefix = LanguageService.t('voice_example_open_prefix');
    final navExamples = [for (final cmd in catalog) '$openPrefix ${LanguageService.t(cmd.labelKey)}'];

    await showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        // The sheet's content (title + description + nav examples + the
        // full per-role action list + logout line + button) can run
        // taller than the screen once a role has many action commands
        // (apartment_admin, for example). Only the nav-examples Wrap used
        // to scroll on its own - everything below it didn't, so it simply
        // got pushed off the bottom of the screen ("BOTTOM OVERFLOWED").
        // Capping the sheet's height and making the *whole* thing scroll
        // fixes that for every role instead of patching one section.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(left: 24, right: 24, top: 26, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.12), shape: BoxShape.circle),
                  child: Icon(Icons.mic_rounded, color: BrandingService.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(LanguageService.t('voice_help_title'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ]),
              const SizedBox(height: 14),
              Text(LanguageService.t('voice_onboarding_body'),
                  style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
              const SizedBox(height: 18),
              Text(LanguageService.t('voice_help_nav_heading'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.3)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final ex in navExamples)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: BrandingService.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('"$ex"', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              if (_helpActionsFor(role).isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(LanguageService.t('voice_help_actions_heading'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey[600], letterSpacing: 0.3)),
                const SizedBox(height: 8),
                for (final a in _helpActionsFor(role)) ...[
                  _helpActionLine(a.$1, a.$2),
                  const SizedBox(height: 8),
                ],
              ],
              _helpActionLine(Icons.logout_rounded, LanguageService.t('voice_help_action_logout')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(LanguageService.t('voice_onboarding_ok')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Data-command examples to show in the help sheet, per role - mirrors
  /// exactly which triggers VoiceCommandService.parse() checks for that
  /// role (see its role-gated `if` blocks), so this list can never drift
  /// into advertising a command the parser wouldn't actually recognize.
  List<(IconData, String)> _helpActionsFor(String role) => [
        ...switch (role) {
          'apartment_admin' => [
              (Icons.receipt_long_rounded, LanguageService.t('voice_help_action_generate_bill')),
              (Icons.check_circle_outline_rounded, LanguageService.t('voice_help_action_approve_payment')),
              (Icons.cancel_outlined, LanguageService.t('voice_help_action_reject_payment')),
              (Icons.campaign_outlined, LanguageService.t('voice_help_action_send_notice')),
              (Icons.task_alt_rounded, LanguageService.t('voice_help_action_resolve_complaint')),
              (Icons.thumb_up_alt_outlined, LanguageService.t('voice_help_action_approve_booking')),
              (Icons.thumb_down_alt_outlined, LanguageService.t('voice_help_action_reject_booking')),
            ],
          'resident' => [
              (Icons.report_problem_outlined, LanguageService.t('voice_help_action_raise_complaint')),
              (Icons.badge_outlined, LanguageService.t('voice_help_action_add_visitor')),
              (Icons.event_available_outlined, LanguageService.t('voice_help_action_book_facility')),
              (Icons.event_busy_outlined, LanguageService.t('voice_help_action_cancel_booking')),
              (Icons.account_balance_wallet_outlined, LanguageService.t('voice_help_action_recharge_wallet')),
              (Icons.payments_outlined, LanguageService.t('voice_help_action_pay_bill')),
            ],
          'security' => [
              (Icons.login_rounded, LanguageService.t('voice_help_action_check_in')),
              (Icons.logout_rounded, LanguageService.t('voice_help_action_check_out')),
            ],
          _ => const <(IconData, String)>[],
        },
        // Shown to every role, same as Logout below - chat/emergency/
        // language aren't role-specific commands.
        if (!ModuleGate.isOff('chat'))
          (Icons.chat_bubble_outline_rounded, LanguageService.t('voice_help_action_send_message')),
        (Icons.emergency_outlined, LanguageService.t('voice_help_action_emergency_sos')),
        (Icons.translate_rounded, LanguageService.t('voice_help_action_change_language')),
      ];

  Widget _helpActionLine(IconData icon, String example) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: BrandingService.primary),
      const SizedBox(width: 8),
      Expanded(child: Text('"$example"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]);
  }

  /// Shows the listening bottom sheet, returns the final recognized text
  /// (or null if the user cancelled / nothing was heard).
  Future<String?> _listenSheet() {
    final desired = VoiceCommandService.localeIdFor(LanguageService.currentCode);
    final locale = _resolveLocale(desired);
    // Same reason as in _maybeShowOnboardingTip above: this widget's own
    // `context` has no Navigator ancestor (VoiceCommandOverlay places it as
    // a Stack sibling of the routed page, not a descendant), so
    // showModalBottomSheet(context: context) crashes in release builds
    // with "Null check operator used on a null value" from inside
    // Navigator.of - which is exactly the reported crash, at this exact
    // call site. Use the router's own navigator context instead, which
    // genuinely is inside a Navigator.
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return Future.value(null);
    return showModalBottomSheet<String>(
      context: navContext,
      isDismissible: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => _ListeningSheet(speech: _speech, localeId: locale),
    );
  }

  Future<void> _handleIntent(VoiceIntent intent, String role) async {
    if (!mounted) return;
    switch (intent) {
      case NavigateIntent():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${LanguageService.t('voice_opening')} ${intent.label}'), duration: const Duration(seconds: 1)),
        );
        // NOT context.go() here: GoRouter.of(context) needs an
        // InheritedGoRouter ancestor, and this widget's own context has
        // none (same reason as the Navigator issue above - VoiceCommandOverlay
        // places this widget as a Stack sibling of the routed page, not a
        // descendant of it). In debug that throws a clear assert; in a
        // release build the assert is stripped and it instead silently
        // fails via a null-check, which is exactly why "open dashboard"
        // showed the snackbar but never actually navigated. Calling
        // go()/push() on the top-level `router` object directly (via
        // _navigate() below) sidesteps context lookup entirely.
        // TEMP DIAGNOSTIC (safe to remove once navigation is confirmed
        // working): logs to `flutter run`'s console so you can see whether
        // this line is actually reached, and surfaces any exception go()
        // throws instead of it disappearing silently.
        dev.log('Voice nav -> ${intent.route}', name: 'VoiceCommandButton');
        try {
          _navigate(intent.route);
        } catch (e, st) {
          dev.log('router.go failed: $e', name: 'VoiceCommandButton', error: e, stackTrace: st);
        }
      case GenerateBillIntent():
        await _resolveAndConfirmBill(intent);
      case ApprovePaymentIntent():
        await _resolveAndConfirmPayment(intent);
      case RejectPaymentIntent():
        await _resolveAndConfirmRejectPayment(intent);
      case RaiseComplaintIntent():
        await _resolveAndConfirmComplaint(intent);
      case RegisterVisitorIntent():
        await _resolveAndConfirmVisitor(intent);
      case BookFacilityIntent():
        await _resolveAndConfirmBooking(intent);
      case SendNoticeIntent():
        await _resolveAndConfirmNotice(intent);
      case VisitorCheckInIntent():
        await _resolveAndConfirmCheckInOut(intent.visitorQuery, checkIn: true);
      case VisitorCheckOutIntent():
        await _resolveAndConfirmCheckInOut(intent.visitorQuery, checkIn: false);
      case CancelBookingIntent():
        await _resolveAndConfirmCancelBooking(intent);
      case ResolveComplaintIntent():
        await _resolveAndConfirmResolveComplaint(intent);
      case RechargeWalletIntent():
        await _resolveAndConfirmRechargeWallet(intent);
      case EmergencySosIntent():
        await _showEmergencyContacts();
      case SendChatMessageIntent():
        await _resolveAndConfirmSendMessage(intent);
      case ApproveBookingIntent():
        await _resolveAndConfirmBookingAction(intent.residentQuery, approve: true);
      case RejectBookingIntent():
        await _resolveAndConfirmBookingAction(intent.residentQuery, approve: false);
      case PayBillIntent():
        await _resolveAndConfirmPayBill(intent);
      case ChangeLanguageIntent():
        await _resolveAndConfirmChangeLanguage(intent);
      case LogoutIntent():
        await _confirmLogout();
      case UnknownIntent():
        await _showUnknown(intent.heardText, role);
    }
  }

  /// Fallback shown when the spoken phrase couldn't be matched to a command.
  /// A one-off snackbar disappears in a couple of seconds and leaves the
  /// person stuck if their wording didn't happen to match - not great for
  /// anyone unsure of the "correct" phrase to say. Instead: show what was
  /// heard, offer a big "Try Again" to re-listen, AND a tappable list of
  /// every destination for this role, so a failed voice match still gets
  /// them where they wanted with one tap, no retrying required.
  Future<void> _showUnknown(String heard, String role) async {
    final catalog = VoiceCommandCatalog.forRole(role);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final result = await showModalBottomSheet<String>(
      context: navContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.hearing_disabled_rounded, color: Colors.orange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(LanguageService.t('voice_not_recognized'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${LanguageService.t('voice_heard_prefix')}"$heard"',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Text(LanguageService.t('voice_or_tap_below'),
                style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    for (final cmd in catalog)
                      ActionChip(
                        label: Text(LanguageService.t(cmd.labelKey)),
                        onPressed: () => Navigator.pop(ctx, cmd.route),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(LanguageService.t('voice_cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary),
                  onPressed: () => Navigator.pop(ctx, '__retry__'),
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: Text(LanguageService.t('voice_try_again')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == '__retry__') {
      await _start();
    } else {
      _navigate(result);
    }
  }

  /// Same push-vs-go rule the drawer menu already follows (see
  /// AppDrawer._MenuEntry.tile push:): dashboard/home routes use go() to
  /// reset the stack, everything else uses push() so the destination gets
  /// a real back-stack entry. Voice navigation used to always call
  /// router.go(), which *replaces* the current route instead of stacking
  /// on top of it - go_router only draws the AppBar back arrow when
  /// there's something to pop, so a voice-launched screen never got one
  /// even though the exact same screen reached via a menu tap did.
  void _navigate(String route) {
    final isHome = route == '/dashboard' || route.endsWith('/dashboard');
    if (isHome) {
      router.go(route);
    } else {
      router.push(route);
    }
  }

  // ── Generate Bill flow ───────────────────────────────────────────────────
  Future<void> _resolveAndConfirmBill(GenerateBillIntent intent) async {
    List residents = [];
    try {
      final res = await ApiService().get('/admin/residents');
      residents = res['data']['data'] ?? res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final matches = VoiceCommandService.matchResidents(intent.residentQuery, residents);
    Map? resident;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      resident = matches.first.$1;
    } else if (matches.isNotEmpty) {
      resident = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.residentQuery);
    } else {
      resident = await _pickFromCandidates(residents, intent.residentQuery);
    }
    if (resident == null || !mounted) return;

    final confirmed = await _showBillConfirmDialog(resident, intent.month, intent.year);
    if (confirmed == null || !mounted) return;

    try {
      final res = await ApiService().post('/admin/bills/generate-catchup', {
        'user_id': resident['id'],
        'from_month': confirmed.month, 'from_year': confirmed.year,
        'to_month': confirmed.month, 'to_year': confirmed.year,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message'] ?? LanguageService.t('voice_bill_generated')),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  Future<({int month, int year})?> _showBillConfirmDialog(Map resident, int month, int year) async {
    int m = month, y = year;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return null;
    return showDialog<({int month, int year})>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            LanguageService.t('voice_confirm_generate_bill')
                .replaceFirst('{resident}', resident['name']?.toString() ?? '')
                .replaceFirst('{period}', '${months[m - 1]} $y'),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(
              value: m, decoration: InputDecoration(labelText: LanguageService.t('month')),
              items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(months[i]))),
              onChanged: (v) => setS(() => m = v!),
            )),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<int>(
              value: y, decoration: InputDecoration(labelText: LanguageService.t('year')),
              items: List.generate(4, (i) => DropdownMenuItem(value: DateTime.now().year - 2 + i, child: Text('${DateTime.now().year - 2 + i}'))),
              onChanged: (v) => setS(() => y = v!),
            )),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, (month: m, year: y)),
            child: Text(LanguageService.t('voice_confirm_and_generate')),
          ),
        ],
      )),
    );
  }

  // ── Approve Payment flow ─────────────────────────────────────────────────
  Future<void> _resolveAndConfirmPayment(ApprovePaymentIntent intent) async {
    List payments = [];
    try {
      final res = await ApiService().get('/admin/payments/pending');
      payments = res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    // Fuzzy-match against each pending payment's resident name.
    final asResidents = payments.map((p) => {'name': (p as Map)['user']?['name'] ?? '', '_payment': p}).toList();
    final matches = VoiceCommandService.matchResidents(intent.residentQuery, asResidents);

    Map? chosenPayment;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosenPayment = matches.first.$1['_payment'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.residentQuery, isPaymentList: true);
      chosenPayment = pick?['_payment'] as Map?;
    } else {
      if (mounted) {
        final navContext = rootNavigatorKey.currentContext;
        if (navContext != null) {
          await AmsDialog.info(navContext,
            title: LanguageService.t('voice_confirm_action'),
            message: LanguageService.t('voice_no_pending_payment').replaceFirst('{query}', intent.residentQuery),
            icon: Icons.search_off_rounded);
        }
      }
      return;
    }
    if (chosenPayment == null || !mounted) return;

    final p = chosenPayment;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !mounted) return;
    final confirm = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_confirm_action'),
      message: LanguageService.t('voice_confirm_approve_payment')
          .replaceFirst('{amount}', '${BrandingService.currencySymbol}${p['amount']}')
          .replaceFirst('{resident}', p['user']?['name']?.toString() ?? ''),
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      confirmText: LanguageService.t('voice_confirm_and_approve'),
    );
    if (confirm != true || !mounted) return;

    try {
      await ApiService().post('/admin/payments/${p['id']}/approve', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_payment_approved')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Reject Payment flow ──────────────────────────────────────────────────
  Future<void> _resolveAndConfirmRejectPayment(RejectPaymentIntent intent) async {
    List payments = [];
    try {
      final res = await ApiService().get('/admin/payments/pending');
      payments = res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final asResidents = payments.map((p) => {'name': (p as Map)['user']?['name'] ?? '', '_payment': p}).toList();
    final matches = VoiceCommandService.matchResidents(intent.residentQuery, asResidents);

    Map? chosenPayment;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosenPayment = matches.first.$1['_payment'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.residentQuery, isPaymentList: true);
      chosenPayment = pick?['_payment'] as Map?;
    } else {
      if (mounted) {
        final navContext = rootNavigatorKey.currentContext;
        if (navContext != null) {
          await AmsDialog.info(navContext,
            title: LanguageService.t('voice_confirm_action'),
            message: LanguageService.t('voice_no_pending_payment').replaceFirst('{query}', intent.residentQuery),
            icon: Icons.search_off_rounded);
        }
      }
      return;
    }
    if (chosenPayment == null || !mounted) return;

    final p = chosenPayment;
    final reason = await _promptRejectReason(p['user']?['name']?.toString() ?? '');
    if (reason == null || !mounted) return; // null = cancelled (empty string is a valid "no reason given")

    try {
      await ApiService().post('/admin/payments/${p['id']}/reject', {'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_payment_rejected')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  /// Prompt for an (optional) rejection reason - reuses the same
  /// AmsDialog.promptText the manual Approvals/Pending-Payments screens use
  /// for this exact step, so it looks and behaves identically to tapping
  /// "Reject" there. Returns null if cancelled, otherwise the (possibly
  /// empty) reason text.
  Future<String?> _promptRejectReason(String residentName) async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return null;
    return AmsDialog.promptText(
      navContext,
      title: LanguageService.t('reject_payment'),
      message: LanguageService.t('voice_confirm_reject_payment').replaceFirst('{resident}', residentName),
      label: LanguageService.t('reason_shown_to_resident'),
      icon: Icons.cancel_outlined,
      danger: true,
      confirmText: LanguageService.t('reject'),
      maxLines: 3,
    );
  }

  // ── Raise Complaint flow (resident) ──────────────────────────────────────
  Future<void> _resolveAndConfirmComplaint(RaiseComplaintIntent intent) async {
    final descCtrl = TextEditingController(text: intent.description);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    String priority = 'medium';
    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(LanguageService.t('voice_confirm_raise_complaint')),
          const SizedBox(height: 14),
          TextField(
            controller: descCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: LanguageService.t('description_2'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: priority,
            decoration: InputDecoration(labelText: LanguageService.t('priority'), border: const OutlineInputBorder()),
            items: ['low', 'medium', 'high', 'urgent']
                .map((p) => DropdownMenuItem(value: p, child: Text(LanguageService.t(p))))
                .toList(),
            onChanged: (v) => setS(() => priority = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_submit')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    if (descCtrl.text.trim().isEmpty) return;

    try {
      final user = await AuthService().getUser();
      final flats = (user?['flats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final flatId = flats.isNotEmpty ? flats.first['id'] as int : null;
      await ApiService().post('/complaints', {
        'title': descCtrl.text.trim().length > 60 ? '${descCtrl.text.trim().substring(0, 57)}...' : descCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'priority': priority,
        if (flatId != null) 'flat_id': flatId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('complaint_raised_successfully')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Register Visitor flow (resident) ─────────────────────────────────────
  Future<void> _resolveAndConfirmVisitor(RegisterVisitorIntent intent) async {
    final nameCtrl = TextEditingController(text: intent.visitorName);
    DateTime expectedAt = intent.expectedAt ?? DateTime.now().add(const Duration(hours: 2));
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(LanguageService.t('voice_confirm_add_visitor')),
          const SizedBox(height: 14),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: LanguageService.t('visitor_name_2'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text('${expectedAt.year}-${expectedAt.month.toString().padLeft(2, '0')}-${expectedAt.day.toString().padLeft(2, '0')}  '
                '${TimeOfDay.fromDateTime(expectedAt).format(ctx)}'),
            onPressed: () async {
              final date = await showDatePicker(
                context: ctx, initialDate: expectedAt,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 90)),
              );
              if (date == null) return;
              if (!ctx.mounted) return;
              final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(expectedAt));
              if (time == null) return;
              setS(() => expectedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_submit')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    if (nameCtrl.text.trim().isEmpty) return;

    try {
      final user = await AuthService().getUser();
      final flats = (user?['flats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final flatId = flats.isNotEmpty ? flats.first['id'] as int : null;
      await ApiService().post('/visitors/pre-approve', {
        'visitor_name': nameCtrl.text.trim(),
        'visitor_phone': '',
        'purpose': 'personal',
        'expected_at': expectedAt.toIso8601String(),
        if (flatId != null) 'flat_id': flatId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('visitor_pre_approved')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Book Facility flow (resident) ────────────────────────────────────────
  Future<void> _resolveAndConfirmBooking(BookFacilityIntent intent) async {
    List facilities = [];
    try {
      final res = await ApiService().get('/facilities');
      facilities = res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final matches = VoiceCommandService.matchResidents(intent.facilityQuery, facilities);
    Map? facility;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      facility = matches.first.$1;
    } else if (matches.isNotEmpty) {
      facility = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.facilityQuery);
    } else {
      facility = await _pickFromCandidates(facilities, intent.facilityQuery);
    }
    if (facility == null || !mounted) return;

    DateTime date = intent.date ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 19, minute: 0);
    final attendeesCtrl = TextEditingController(text: '1');
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final f = facility;
    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(LanguageService.t('voice_confirm_book_facility').replaceFirst('{facility}', f['name']?.toString() ?? '')),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx, initialDate: date,
                  firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (picked != null) setS(() => date = picked);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('${LanguageService.t('voice_from')}: ${start.format(ctx)}'),
                onPressed: () async {
                  final picked = await showTimePicker(context: ctx, initialTime: start);
                  if (picked != null) setS(() => start = picked);
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('${LanguageService.t('voice_to')}: ${end.format(ctx)}'),
                onPressed: () async {
                  final picked = await showTimePicker(context: ctx, initialTime: end);
                  if (picked != null) setS(() => end = picked);
                },
              )),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: attendeesCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: LanguageService.t('attendees'), border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_submit')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;

    String two(int n) => n.toString().padLeft(2, '0');
    try {
      await ApiService().post('/facilities/${f['id']}/book', {
        'booking_date': '${date.year}-${two(date.month)}-${two(date.day)}',
        'start_time': '${two(start.hour)}:${two(start.minute)}',
        'end_time': '${two(end.hour)}:${two(end.minute)}',
        'attendees': int.tryParse(attendeesCtrl.text.trim()) ?? 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('booking_request_submitted_for_approval')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Send Notice flow (admin) ─────────────────────────────────────────────
  Future<void> _resolveAndConfirmNotice(SendNoticeIntent intent) async {
    final titleCtrl = TextEditingController(
        text: intent.message.length > 40 ? '${intent.message.substring(0, 37)}...' : intent.message);
    final messageCtrl = TextEditingController(text: intent.message);
    String target = 'all';
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(LanguageService.t('voice_confirm_send_notice')),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(labelText: LanguageService.t('title_2'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageCtrl,
              maxLines: 4,
              decoration: InputDecoration(labelText: LanguageService.t('message'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: target,
              decoration: InputDecoration(labelText: LanguageService.t('send_to'), border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'all', child: Text(LanguageService.t('all_residents'))),
                DropdownMenuItem(value: 'owners', child: Text(LanguageService.t('owners_only'))),
                DropdownMenuItem(value: 'tenants', child: Text(LanguageService.t('tenants_only'))),
              ],
              onChanged: (v) => setS(() => target = v!),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_send')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    if (titleCtrl.text.trim().isEmpty || messageCtrl.text.trim().isEmpty) return;

    try {
      await ApiService().post('/admin/notifications/bulk', {
        'title': titleCtrl.text.trim(), 'message': messageCtrl.text.trim(), 'target': target,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_notice_sent')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Visitor Check-In / Check-Out flow (security) ─────────────────────────
  Future<void> _resolveAndConfirmCheckInOut(String visitorQuery, {required bool checkIn}) async {
    final status = checkIn ? 'approved' : 'checked_in';
    List visitors = [];
    try {
      final res = await ApiService().get('/security/visitors?status=$status');
      visitors = res['data']['data'] ?? res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final asNamed = visitors.map((v) => {'name': (v as Map)['visitor_name'] ?? '', '_visitor': v}).toList();
    final matches = VoiceCommandService.matchResidents(visitorQuery, asNamed);

    Map? chosen;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosen = matches.first.$1['_visitor'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), visitorQuery, isPaymentList: true);
      chosen = pick?['_visitor'] as Map?;
    } else {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_no_matching_visitor').replaceFirst('{query}', visitorQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }
    if (chosen == null || !mounted) return;

    final v = chosen;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !mounted) return;
    final confirm = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_confirm_action'),
      message: (checkIn ? LanguageService.t('voice_confirm_check_in') : LanguageService.t('voice_confirm_check_out'))
          .replaceFirst('{visitor}', v['visitor_name']?.toString() ?? ''),
      icon: checkIn ? Icons.login_rounded : Icons.logout_rounded,
      iconColor: Colors.green,
      confirmText: checkIn ? LanguageService.t('voice_confirm_and_check_in') : LanguageService.t('voice_confirm_and_check_out'),
    );
    if (confirm != true || !mounted) return;

    try {
      await ApiService().post('/security/visitors/${v['id']}/${checkIn ? 'checkin' : 'checkout'}', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(checkIn ? LanguageService.t('voice_visitor_checked_in') : LanguageService.t('voice_visitor_checked_out')),
          backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Cancel Booking flow (resident) ───────────────────────────────────────
  Future<void> _resolveAndConfirmCancelBooking(CancelBookingIntent intent) async {
    List bookings = [];
    try {
      final res = await ApiService().get('/my-bookings');
      final data = res['data'];
      bookings = (data is Map ? data['data'] : data) ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    // Only bookings that can actually still be cancelled - same statuses
    // MyBookingsScreen shows a Cancel button for.
    final cancellable = bookings.where((b) {
      final s = (b as Map)['status']?.toString();
      return s == 'pending' || s == 'approved';
    }).toList();

    final asNamed = cancellable.map((b) => {'name': (b as Map)['facility']?['name'] ?? '', '_booking': b}).toList();
    final matches = VoiceCommandService.matchResidents(intent.facilityQuery, asNamed);

    Map? chosen;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosen = matches.first.$1['_booking'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.facilityQuery, isPaymentList: true);
      chosen = pick?['_booking'] as Map?;
    } else {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_no_matching_booking').replaceFirst('{query}', intent.facilityQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }
    if (chosen == null || !mounted) return;

    final b = chosen;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null || !mounted) return;
    final confirm = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_confirm_action'),
      message: LanguageService.t('voice_confirm_cancel_booking').replaceFirst('{facility}', b['facility']?['name']?.toString() ?? ''),
      icon: Icons.event_busy_rounded,
      confirmText: LanguageService.t('voice_confirm_and_cancel'),
      danger: true,
    );
    if (confirm != true || !mounted) return;

    try {
      await ApiService().post('/bookings/${b['id']}/cancel', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_booking_cancelled')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Resolve Complaint flow (admin) ───────────────────────────────────────
  Future<void> _resolveAndConfirmResolveComplaint(ResolveComplaintIntent intent) async {
    List complaints = [];
    try {
      final res = await ApiService().get('/admin/complaints?status=open');
      complaints = res['data']?['data'] ?? res['data'] ?? [];
      // Also include in_progress complaints - equally valid to resolve/close.
      final res2 = await ApiService().get('/admin/complaints?status=in_progress');
      complaints = [...complaints, ...(res2['data']?['data'] ?? res2['data'] ?? [])];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final asNamed = complaints.map((c) => {'name': (c as Map)['user']?['name'] ?? '', '_complaint': c}).toList();
    final matches = VoiceCommandService.matchResidents(intent.residentQuery, asNamed);

    Map? chosen;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosen = matches.first.$1['_complaint'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), intent.residentQuery, isPaymentList: true);
      chosen = pick?['_complaint'] as Map?;
    } else {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_no_open_complaint').replaceFirst('{query}', intent.residentQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }
    if (chosen == null || !mounted) return;

    final c = chosen;
    String newStatus = 'resolved';
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(LanguageService.t('voice_confirm_resolve_complaint').replaceFirst('{resident}', c['user']?['name']?.toString() ?? '')),
          const SizedBox(height: 14),
          Text(c['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: newStatus,
            decoration: InputDecoration(labelText: LanguageService.t('new_status'), border: const OutlineInputBorder()),
            items: ['resolved', 'closed']
                .map((s) => DropdownMenuItem(value: s, child: Text(LanguageService.t(s))))
                .toList(),
            onChanged: (v) => setS(() => newStatus = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_submit')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService().post('/admin/complaints/${c['id']}/status', {'status': newStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_complaint_status_updated')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Recharge Wallet flow (resident) ──────────────────────────────────────
  // Submits a manual top-up request the same way WalletScreen's "Add Money"
  // form does (payment_method left for the resident to pick/confirm) -
  // awaits admin confirmation, same as that screen's own flow.
  Future<void> _resolveAndConfirmRechargeWallet(RechargeWalletIntent intent) async {
    final amountCtrl = TextEditingController(text: intent.amount != null ? intent.amount!.toStringAsFixed(0) : '');
    String method = 'upi';
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(LanguageService.t('voice_confirm_recharge_wallet').replaceFirst('{amount}', amountCtrl.text.isEmpty ? '' : amountCtrl.text)),
          const SizedBox(height: 14),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: LanguageService.t('amount'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: method,
            decoration: InputDecoration(labelText: LanguageService.t('payment_method'), border: const OutlineInputBorder()),
            items: ['upi', 'cash', 'bank_transfer', 'card']
                .map((m) => DropdownMenuItem(value: m, child: Text(LanguageService.t(m))))
                .toList(),
            onChanged: (v) => setS(() => method = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_submit')),
          ),
        ],
      )),
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;

    try {
      await ApiService().post('/wallet/deposit', {
        'amount': amount,
        'payment_method': method,
        'notes': 'Added via voice command',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_wallet_topup_submitted')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Emergency SOS flow (any role) ────────────────────────────────────────
  // Never dials automatically - surfaces the apartment's emergency contacts
  // for one tap-to-call, same mechanism EmergencyNumbersScreen itself uses.
  Future<void> _showEmergencyContacts() async {
    List contacts = [];
    try {
      final role = await AuthService().effectiveRole();
      final endpoint = role == 'apartment_admin' ? '/admin/emergency-numbers' : '/emergency-numbers';
      final res = await ApiService().get(endpoint);
      contacts = res['data'] ?? [];
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    await showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.emergency_outlined, color: Colors.red),
              const SizedBox(width: 8),
              Text(LanguageService.t('voice_emergency_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text(LanguageService.t('voice_emergency_body'), style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            if (contacts.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(LanguageService.t('voice_no_emergency_contacts')))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final c = contacts[i] as Map;
                    // Field is `phones` (a list) - a contact can have more
                    // than one number, same shape EmergencyNumbersScreen's
                    // own form/list uses. There is no singular `phone` key.
                    final phones = List<String>.from(c['phones'] ?? []);
                    return ListTile(
                      leading: const Icon(Icons.local_phone_rounded, color: Colors.red),
                      title: Text(c['name']?.toString() ?? ''),
                      subtitle: phones.isEmpty ? null : Text(phones.join(', ')),
                      trailing: phones.isEmpty
                          ? null
                          : PopupMenuButton<String>(
                              // Condensed "tap to call" for however many
                              // numbers this contact has - same call
                              // mechanism as EmergencyNumbersScreen's own
                              // row of call buttons, just as a menu here
                              // since this sheet is one line per contact.
                              icon: const Icon(Icons.call, color: Colors.green),
                              onSelected: (phone) async {
                                final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''));
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                              itemBuilder: (_) => phones
                                  .map((p) => PopupMenuItem(value: p, child: Text(p)))
                                  .toList(),
                            ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // ── Send Chat Message flow (any role, when Chat is enabled) ─────────────
  Future<void> _resolveAndConfirmSendMessage(SendChatMessageIntent intent) async {
    final msgCtrl = TextEditingController(text: intent.message);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(LanguageService.t('voice_confirm_send_message')),
          const SizedBox(height: 14),
          TextField(
            controller: msgCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: LanguageService.t('message'), border: const OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('voice_confirm_and_send')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (msgCtrl.text.trim().isEmpty) return;

    try {
      await ApiService().post('/chat/messages', {'message': msgCtrl.text.trim()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_message_sent')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Approve/Reject Booking flow (admin) ──────────────────────────────────
  Future<void> _resolveAndConfirmBookingAction(String residentQuery, {required bool approve}) async {
    List bookings = [];
    try {
      final res = await ApiService().get('/admin/bookings?status=pending');
      dynamic r = res['data'];
      if (r is Map) r = r['data'];
      bookings = List.from(r ?? []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    // Bookings carry the flat/resident under `user` (same shape complaints
    // use) - fall back to the facility name if that isn't present so a
    // spoken facility name can still resolve a single pending booking.
    final asNamed = bookings.map((b) => {
          'name': (b as Map)['user']?['name'] ?? b['facility']?['name'] ?? '',
          '_booking': b,
        }).toList();
    final matches = VoiceCommandService.matchResidents(residentQuery, asNamed);

    Map? chosen;
    if (matches.length == 1 || (matches.isNotEmpty && matches[0].$2 - (matches.length > 1 ? matches[1].$2 : 0) > 0.15)) {
      chosen = matches.first.$1['_booking'] as Map;
    } else if (matches.isNotEmpty) {
      final pick = await _pickFromCandidates(matches.map((m) => m.$1).toList(), residentQuery, isPaymentList: true);
      chosen = pick?['_booking'] as Map?;
    } else {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_no_pending_booking').replaceFirst('{query}', residentQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }
    if (chosen == null || !mounted) return;

    final b = chosen;
    final residentName = b['user']?['name']?.toString() ?? b['facility']?['name']?.toString() ?? '';
    final reasonCtrl = TextEditingController();
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    final confirmed = await showDialog<bool>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.t('voice_confirm_action')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((approve ? LanguageService.t('voice_confirm_approve_booking') : LanguageService.t('voice_confirm_reject_booking'))
              .replaceFirst('{resident}', residentName)),
          if (!approve) ...[
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(labelText: LanguageService.t('voice_rejection_reason'), border: const OutlineInputBorder()),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('voice_cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? LanguageService.t('voice_confirm_and_approve_booking') : LanguageService.t('voice_confirm_and_reject_booking')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService().post('/admin/bookings/${b['id']}/action', {
        'action': approve ? 'approve' : 'reject',
        if (!approve && reasonCtrl.text.trim().isNotEmpty) 'rejection_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? LanguageService.t('voice_booking_approved') : LanguageService.t('voice_booking_rejected')),
          backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Pay Bill (cash) flow (resident) ──────────────────────────────────────
  // Always uses the Cash gateway (submits a request the admin still has to
  // confirm receipt of) - same as tapping "Cash" in Billing's own payment
  // sheet. Voice never initiates a card/UPI checkout on its own.
  final PaymentService _voicePaymentService = PaymentService();

  Future<void> _resolveAndConfirmPayBill(PayBillIntent intent) async {
    List bills = [];
    try {
      final res = await ApiService().get('/bills');
      dynamic r = res['data'];
      if (r is Map) r = r['data'];
      bills = List.from(r ?? []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      return;
    }
    if (!mounted) return;

    final outstanding = bills.where((b) => double.tryParse((b as Map)['outstanding']?.toString() ?? '0') != null
        && double.parse(b['outstanding'].toString()) > 0).toList();
    if (outstanding.isEmpty) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_no_outstanding_bill').replaceFirst('{query}', intent.monthQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }

    // If a month/period was said, prefer the bill whose month name/year
    // matches; otherwise (or if nothing matched), fall back to the most
    // recent outstanding bill - same "just pick the obvious one" behavior
    // as GenerateBillIntent defaulting to the current month. Bills only
    // carry billing_month/billing_year (ints), never a ready-made label
    // (see BillModel) - build one the same way BillingScreen's card does.
    String labelFor(Map b) {
      final m = int.tryParse(b['billing_month']?.toString() ?? '');
      final y = int.tryParse(b['billing_year']?.toString() ?? '');
      if (m == null || y == null) return b['bill_number']?.toString() ?? '#${b['id']}';
      return DateFormat('MMMM yyyy').format(DateTime(y, m));
    }

    Map bill = outstanding.first as Map;
    if (intent.monthQuery.trim().isNotEmpty) {
      for (final b in outstanding) {
        if (labelFor(b as Map).toLowerCase().contains(intent.monthQuery.toLowerCase().trim())) {
          bill = b;
          break;
        }
      }
    }

    final amount = double.parse(bill['outstanding'].toString());
    final billLabel = labelFor(bill);
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final confirmed = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_confirm_action'),
      message: LanguageService.t('voice_confirm_pay_bill').replaceFirst('{bill}', billLabel),
      icon: Icons.payments_outlined,
      confirmText: LanguageService.t('voice_confirm_and_submit'),
    );
    if (confirmed != true || !mounted) return;

    final user = await AuthService().getUser();
    await _voicePaymentService.startPayment(
      context: navContext,
      billId: int.parse(bill['id'].toString()),
      gateway: 'cash',
      amount: amount,
      residentName: user?['name'] ?? '',
      residentEmail: user?['email'] ?? '',
      residentPhone: user?['phone'] ?? '',
      onSuccess: (msg) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
      },
      onFailure: (msg) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      },
    );
  }

  // ── Change Language flow (any role) ──────────────────────────────────────
  // Matched against display names for the codes VoiceCommandService already
  // knows a speech locale for (its `_localeMap`) - a fixed, known set, same
  // reasoning as the rest of this file's fuzzy matching.
  static const Map<String, String> _languageNames = {
    'en': 'English', 'hi': 'Hindi', 'bn': 'Bengali', 'ta': 'Tamil', 'te': 'Telugu',
    'mr': 'Marathi', 'gu': 'Gujarati', 'kn': 'Kannada', 'ml': 'Malayalam', 'pa': 'Punjabi',
    'ur': 'Urdu', 'ar': 'Arabic', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
    'it': 'Italian', 'ja': 'Japanese', 'zh': 'Chinese', 'ko': 'Korean',
  };

  Future<void> _resolveAndConfirmChangeLanguage(ChangeLanguageIntent intent) async {
    String? bestCode;
    double bestScore = 0.5;
    final q = intent.languageQuery.toLowerCase().trim();
    for (final entry in _languageNames.entries) {
      final name = entry.value.toLowerCase();
      final score = name == q || q.contains(name) || name.contains(q) ? 1.0 : 0.0;
      if (score > bestScore) { bestScore = score; bestCode = entry.key; }
    }
    if (bestCode == null) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && mounted) {
        await AmsDialog.info(navContext,
          title: LanguageService.t('voice_confirm_action'),
          message: LanguageService.t('voice_language_not_found').replaceFirst('{query}', intent.languageQuery),
          icon: Icons.search_off_rounded);
      }
      return;
    }

    final code = bestCode;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final confirmed = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_confirm_action'),
      message: LanguageService.t('voice_confirm_change_language').replaceFirst('{language}', _languageNames[code] ?? code),
      icon: Icons.translate_rounded,
      confirmText: LanguageService.t('voice_confirm_and_change'),
    );
    if (confirmed != true || !mounted) return;

    try {
      await LanguageService.setLanguage(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(LanguageService.t('voice_language_changed')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // ── Logout flow (any role) ───────────────────────────────────────────────
  Future<void> _confirmLogout() async {
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final confirmed = await AmsDialog.confirm(
      navContext,
      title: LanguageService.t('voice_logout_title'),
      message: LanguageService.t('voice_confirm_logout'),
      icon: Icons.logout_rounded,
      confirmText: LanguageService.t('voice_logout_title'),
      danger: true,
    );
    if (confirmed != true) return;
    await AuthService().logout();
    if (navContext.mounted) router.go('/login');
  }

  // ── Shared: manual pick list when the fuzzy match is ambiguous/absent ───
  Future<Map?> _pickFromCandidates(List candidates, String query, {bool isPaymentList = false}) async {
    // No confident fuzzy match at all (as opposed to "several close ones") -
    // let the admin search/filter the full list themselves instead of just
    // showing every resident with no way to narrow it down.
    final searchable = candidates.length > 6;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return null;
    return showModalBottomSheet<Map>(
      context: navContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        var filter = query.toLowerCase();
        final filtered = searchable
            ? candidates.where((c) => (c as Map)['name']?.toString().toLowerCase().contains(filter) ?? false).toList()
            : candidates;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                candidates.isEmpty
                    ? LanguageService.t('voice_resident_not_found').replaceFirst('{query}', query)
                    : LanguageService.t('voice_multiple_matches'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              if (searchable) ...[
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: LanguageService.t('search_by_name_or_phone')),
                  controller: TextEditingController(text: query),
                  onChanged: (v) => setS(() => filter = v.toLowerCase()),
                ),
              ],
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: filtered.isEmpty
                    ? Padding(padding: const EdgeInsets.all(20), child: Text(LanguageService.t('no_data')))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i] as Map;
                          return ListTile(
                            leading: const Icon(Icons.person_outline_rounded),
                            title: Text(c['name']?.toString() ?? ''),
                            onTap: () => Navigator.pop(ctx, c),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('voice_cancel'))),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Extra room (54x54) around the visible 48x48 mic square so the help
    // badge has space to sit in the top-right corner without needing to
    // paint outside this widget's own bounds. The mic square itself stays
    // anchored to the bottom-left corner of this box, so it lands in
    // exactly the same spot as before the badge was added.
    return SizedBox(
      width: 54, height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0, bottom: 0,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onTap: _start,
                // Solid the instant a finger is down (immediate visual
                // feedback that the touch registered), transparent again
                // as soon as it's released - this is purely a "was this
                // just touched" signal, not tied to _listening/_busy.
                onHighlightChanged: (down) => setState(() => _pressed = down),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _pressed ? BrandingService.primary : BrandingService.primary.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(_pressed ? 0.18 : 0.08), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
          // Help badge - notification-counter style: small circle peeking
          // out of the corner. Its own InkWell/tap target sits on top of
          // the mic button's, so tapping it opens help instead of starting
          // a listen session.
          Positioned(
            top: 0, right: 0,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _showHelp,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: BrandingService.primary, width: 1.4),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 3, offset: const Offset(0, 1))],
                  ),
                  child: Icon(Icons.question_mark_rounded, size: 11, color: BrandingService.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet shown while listening: live partial transcript + a big
/// pulsing mic. Pops with the final recognized text once speech_to_text
/// reports a final result, the user taps Stop, or the sheet auto-stops
/// after a pause in speech.
class _ListeningSheet extends StatefulWidget {
  final stt.SpeechToText speech;
  // Null means "let the engine pick its own default" - see
  // _VoiceCommandButtonState._resolveLocale(), which returns null when
  // the app-language-derived guess isn't actually one of the device's
  // supported speech locales, rather than risk handing listen() an id it
  // doesn't recognize.
  final String? localeId;
  const _ListeningSheet({required this.speech, required this.localeId});

  @override
  State<_ListeningSheet> createState() => _ListeningSheetState();
}

class _ListeningSheetState extends State<_ListeningSheet> {
  String _text = '';
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  Future<void> _listen() async {
    setState(() => _listening = true);
    try {
      await widget.speech.listen(
        localeId: widget.localeId,
        onResult: (result) {
          setState(() => _text = result.recognizedWords);
          if (result.finalResult) _finish();
        },
        listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      );
    } catch (e, st) {
      debugPrint('VOICE_CMD_ERROR (listen): $e\n$st');
      // speech_to_text's web engine can throw internally ("Null check
      // operator used on a null value") if listen() fires before the
      // browser's recognizer session has fully settled, or the requested
      // locale isn't actually supported by that browser. This call runs
      // fire-and-forget from initState's postFrameCallback, so it's
      // *outside* VoiceCommandButton._start()'s try/catch - left
      // unguarded, this became an unhandled exception (the raw error
      // banner) with the sheet stuck open, looking exactly like the mic
      // "doesn't work". Catching it here and popping with the error lets
      // _start() report it through its existing, user-friendly handling.
      if (!mounted) return;
      Navigator.of(context).pop(_kVoiceListenError);
      return;
    }
  }

  void _finish() {
    if (!mounted) return;
    widget.speech.stop();
    Navigator.of(context).pop(_text);
  }

  @override
  void dispose() {
    widget.speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: BrandingService.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_rounded, color: BrandingService.primary, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            _listening ? LanguageService.t('voice_listening') : LanguageService.t('voice_processing'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Text(
            _text.isEmpty ? LanguageService.t('voice_tap_mic_to_speak') : _text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(LanguageService.t('voice_cancel')),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: Text(LanguageService.t('submit')),
            ),
          ]),
        ]),
      ),
    );
  }
}