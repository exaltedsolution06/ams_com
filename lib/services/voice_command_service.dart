import 'dart:developer' as dev;
import 'language_service.dart';
import 'module_gate.dart';
import 'voice_command_catalog.dart';
import '../models/voice_intent.dart';

/// Dice's coefficient (bigram overlap) string similarity, 0.0-1.0. This is
/// the exact algorithm the popular "string-similarity" JS/Dart packages use
/// under the hood - implemented locally (no external package) so this file
/// has zero dependency risk. Good enough to forgive small mishearings
/// ("billng" vs "billing", "genrate" vs "generate") against a small fixed
/// vocabulary, which is all this feature needs.
double _similarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.length < 2 || b.length < 2) return 0.0;

  List<String> bigrams(String s) =>
      [for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)];

  final bigramsA = bigrams(a);
  final bigramsBOriginalCount = bigrams(b).length;
  final bigramsBRemaining = bigrams(b);
  int intersection = 0;
  for (final bg in bigramsA) {
    final idx = bigramsBRemaining.indexOf(bg);
    if (idx != -1) {
      intersection++;
      bigramsBRemaining.removeAt(idx); // don't double-count a repeated bigram
    }
  }
  return (2.0 * intersection) / (bigramsA.length + bigramsBOriginalCount);
}

/// Turns recognized speech text into a [VoiceIntent], and does the fuzzy
/// matching needed along the way (command labels, resident names). Free /
/// on-device — no external NLP API. All matching uses simple normalization
/// + Dice-coefficient similarity (see [_similarity] above), which is enough
/// for a fixed, known command set with minor mishearing tolerance.
class VoiceCommandService {
  /// Minimum similarity (0-1) for a spoken phrase to count as matching a
  /// menu item's label. Tuned to forgive 1-2 mis-heard letters on short
  /// labels while still not matching something unrelated.
  static const double _navMatchThreshold = 0.42;

  /// Minimum similarity for matching a spoken name against a resident record.
  static const double _residentMatchThreshold = 0.35;

  // ── Locale mapping ─────────────────────────────────────────────────────
  // Maps the app's language code (LanguageService.currentCode, e.g. 'hi')
  // to the locale id speech_to_text/the browser expects (e.g. 'hi_IN').
  // Kept in sync with database/seeders/LanguageSeeder.php's language list.
  static const Map<String, String> _localeMap = {
    'en': 'en_US',
    'hi': 'hi_IN',
    'bn': 'bn_IN',
    'ta': 'ta_IN',
    'te': 'te_IN',
    'mr': 'mr_IN',
    'gu': 'gu_IN',
    'kn': 'kn_IN',
    'ml': 'ml_IN',
    'pa': 'pa_IN',
    'ur': 'ur_PK',
    'or': 'or_IN',
    'as': 'as_IN',
    'ne': 'ne_NP',
    'si': 'si_LK',
    'ms': 'ms_MY',
    'ar': 'ar_SA',
    'es': 'es_ES',
    'fr': 'fr_FR',
    'de': 'de_DE',
    'it': 'it_IT',
    'ja': 'ja_JP',
    'zh': 'zh_CN',
    'ko': 'ko_KR',
  };

  /// Best-guess locale id for the given app language code. Falls back to
  /// en_US for any language we don't have a mapping for (the recognizer
  /// still works, it just won't be tuned for that language's phonemes).
  static String localeIdFor(String langCode) => _localeMap[langCode] ?? 'en_US';

  static String _normalize(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // ── Month parsing ───────────────────────────────────────────────────────
  static const List<String> _monthNames = [
    'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
  ];
  static const List<String> _monthShort = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// Finds a month name/abbreviation anywhere in [text] (English, fuzzy —
  /// tolerant of things like "jully" or "febuary"). Returns 1-12, or null.
  static int? _findMonth(String text) {
    final words = text.split(' ');
    int? bestMonth;
    double bestScore = 0.55; // require a reasonably close match
    for (final w in words) {
      if (w.length < 3) continue;
      for (var i = 0; i < 12; i++) {
        final score = [
          _similarity(w, _monthNames[i]),
          _similarity(w, _monthShort[i]),
        ].reduce((a, b) => a > b ? a : b);
        if (score > bestScore) {
          bestScore = score;
          bestMonth = i + 1;
        }
      }
    }
    return bestMonth;
  }

  static int? _findYear(String text) {
    final m = RegExp(r'\b(20\d{2})\b').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  /// Finds a plain money amount like "500" or "1500.50" anywhere in [text]
  /// (no currency symbol expected - recognizers don't produce those).
  /// Deliberately excludes 4-digit numbers that look like a year (so
  /// "recharge wallet 2026" doesn't get mistaken for an amount) since the
  /// only caller of this ([RechargeWalletIntent] parsing) has no legitimate
  /// reason to hear a year in the same phrase.
  static double? _findAmount(String text) {
    for (final m in RegExp(r'\b(\d+(?:\.\d{1,2})?)\b').allMatches(text)) {
      final raw = m.group(1)!;
      if (RegExp(r'^20\d{2}$').hasMatch(raw)) continue;
      final v = double.tryParse(raw);
      if (v != null && v > 0) return v;
    }
    return null;
  }

  // ── Relative-date / clock-time parsing (visitor + facility-booking voice
  // commands) ────────────────────────────────────────────────────────────
  static const List<String> _weekdayNames = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];

  /// Finds "today", "tomorrow", or a (fuzzy) weekday name anywhere in
  /// [text] and returns the matching calendar date (time set to midnight).
  /// A named weekday always resolves to the NEXT occurrence of that day
  /// (today counts as "next" only if the word "today" was actually said),
  /// same as how a person would expect "book it for Saturday" to behave.
  /// Returns null if nothing date-like was said - callers fall back to
  /// their own default and let the confirmation screen's date picker take
  /// over from there.
  static DateTime? _findRelativeDate(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r'\btoday\b').hasMatch(text)) return today;
    if (RegExp(r'\btomorrow\b').hasMatch(text)) return today.add(const Duration(days: 1));

    final words = text.split(' ');
    for (final w in words) {
      if (w.length < 4) continue;
      for (var i = 0; i < 7; i++) {
        if (_similarity(w, _weekdayNames[i]) > 0.6) {
          final target = i + 1; // DateTime.monday == 1 ... DateTime.sunday == 7
          var delta = target - today.weekday;
          if (delta <= 0) delta += 7;
          return today.add(Duration(days: delta));
        }
      }
    }
    return null;
  }

  /// Finds a clock time like "5pm", "5:30 pm", "at 9 am" anywhere in
  /// [text]. Returns (hour, minute) in 24-hour form, or null if no
  /// confident time-with-am/pm was heard (bare numbers are deliberately
  /// NOT treated as a time - too easy to misfire on an unrelated digit).
  static (int, int)? _findClockTime(String text) {
    final m = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(text);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    final isPm = m.group(3) == 'pm';
    if (hour == 12) hour = 0;
    if (isPm) hour += 12;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  /// Combines [_findRelativeDate] + [_findClockTime] into a single
  /// DateTime, defaulting to noon when a date was said but no clock time
  /// was. Returns null only when no date at all could be found.
  static DateTime? _findDateTime(String text) {
    final date = _findRelativeDate(text);
    if (date == null) return null;
    final time = _findClockTime(text);
    return time == null
        ? DateTime(date.year, date.month, date.day, 12)
        : DateTime(date.year, date.month, date.day, time.$1, time.$2);
  }

  /// Strips recognized date/time words out of [text], leaving (hopefully)
  /// just a free-text name - mirrors [_stripDateWords] above but for the
  /// today/tomorrow/weekday + clock-time vocabulary used by visitor and
  /// facility-booking commands rather than month/year.
  static String _stripDateTimeWords(String text) {
    var out = text
        .replaceAll(RegExp(r'\btoday\b'), '')
        .replaceAll(RegExp(r'\btomorrow\b'), '')
        .replaceAll(RegExp(r'\b\d{1,2}(:\d{2})?\s*(am|pm)\b'), '');
    for (final d in _weekdayNames) {
      out = out.replaceAll(RegExp('\\b$d\\w*\\b'), '');
    }
    final atWord = _normalize(LanguageService.t('voice_word_at'));
    if (atWord.isNotEmpty) out = out.replaceAll(RegExp('\\b${RegExp.escape(atWord)}\\b'), '');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// True when [normalized] either contains [trigger] outright, or its
  /// leading portion is a close-enough (mishearing-tolerant) match for it.
  /// Factored out of the original inline generate-bill/approve-payment
  /// checks so every trigger phrase below is matched the same way.
  static bool _triggerMatches(String normalized, String trigger) {
    final prefix = normalized.length > trigger.length ? normalized.substring(0, trigger.length) : normalized;
    return normalized.contains(trigger) || _similarity(prefix, trigger) > 0.55;
  }

  /// Pulls out the free-text name someone said after a trigger phrase, e.g.
  /// "generate bill for suresh july 2026" -> "suresh july 2026" (month/year
  /// are stripped by the caller once parsed separately). Handles the
  /// trigger phrase appearing with or without the localized "for" word.
  static String _textAfterTrigger(String normalized, String triggerPhrase) {
    final idx = normalized.indexOf(triggerPhrase);
    if (idx == -1) return normalized;
    var rest = normalized.substring(idx + triggerPhrase.length).trim();
    final forWord = _normalize(LanguageService.t('voice_word_for'));
    if (rest.startsWith('$forWord ')) rest = rest.substring(forWord.length).trim();
    return rest;
  }

  /// Strips any recognized month name/abbreviation and 4-digit year out of
  /// [text], leaving (hopefully) just the resident's name.
  static String _stripDateWords(String text) {
    var out = text;
    for (final m in [..._monthNames, ..._monthShort]) {
      out = out.replaceAll(RegExp('\\b$m\\w*\\b'), '');
    }
    out = out.replaceAll(RegExp(r'\b20\d{2}\b'), '');
    out = out.replaceAll(RegExp(r',+'), ' ');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Main entry point: classify [heard] speech for the given [role] into an
  /// actionable intent. Checked in order: data commands (they're more
  /// specific) first, then plain navigation, then give up. [role] is
  /// 'resident', 'apartment_admin', or 'security' - each data-command
  /// trigger below is only checked for the role(s) it actually applies to,
  /// same principle as VoiceCommandCatalog.forRole filtering navigation.
  static VoiceIntent parse(String heard, String role) {
    final normalized = _normalize(heard);
    // TEMP DIAGNOSTIC (safe to remove once commands are confirmed working
    // again): shows exactly what was heard/normalized in `flutter run`'s
    // console for every attempt, regardless of which branch below ends up
    // matching (or not).
    dev.log('parse() heard="$heard" normalized="$normalized" role=$role', name: 'VoiceCommandService');
    if (normalized.isEmpty) return UnknownIntent(heard);

    // ── 1. "logout" / "log out" - any role. Checked as both one word and
    // two, since speech recognizers are inconsistent about which they
    // return for the same spoken phrase. ─────────────────────────────────
    final logoutTrigger = _normalize(LanguageService.t('voice_trigger_logout'));
    final sosTrigger = _normalize(LanguageService.t('voice_trigger_emergency_sos'));
    // TEMP DIAGNOSTIC: these two run before everything else below, so a
    // blank value here (missing/empty translation) would match every
    // single phrase you say - "".contains('') and X.contains('') are both
    // true - and silently swallow every command as Logout or Emergency.
    if (logoutTrigger.isEmpty) dev.log('  ! voice_trigger_logout translation is EMPTY - this will hijack every command!', name: 'VoiceCommandService');
    if (sosTrigger.isEmpty) dev.log('  ! voice_trigger_emergency_sos translation is EMPTY - this will hijack every command!', name: 'VoiceCommandService');
    if (normalized.replaceAll(' ', '').contains('logout') || _triggerMatches(normalized, logoutTrigger)) {
      return const LogoutIntent();
    }

    // ── "emergency" / "sos" - any role, checked early (like logout) since it's urgent and shouldn't have to compete with
    // more specific data-command triggers below. Deliberately excludes any
    // phrase that also says "number(s)" - "open emergency numbers" / "show
    // emergency number" is the pre-existing NAVIGATE command to the
    // Emergency Numbers screen (see VoiceCommandCatalog's 'emergency_numbers'
    // entry) and must keep working exactly as before, not get hijacked into
    // popping up the SOS quick-call sheet instead. ─────────────────────────
    final saysNumber = RegExp(r'\bnumbers?\b').hasMatch(normalized);
    if (!saysNumber && (RegExp(r'\bsos\b').hasMatch(normalized) || _triggerMatches(normalized, sosTrigger))) {
      return const EmergencySosIntent();
    }

    if (role == 'apartment_admin') {
      // ── "resolve complaint for X" / "close complaint for X" ───────────
      final resolveComplaintTrigger = _normalize(LanguageService.t('voice_trigger_resolve_complaint'));
      if (_triggerMatches(normalized, resolveComplaintTrigger)) {
        final rest = _textAfterTrigger(normalized, resolveComplaintTrigger);
        if (rest.isNotEmpty) return ResolveComplaintIntent(residentQuery: rest);
      }

      // ── "generate bill for X, month year" ────────────────────────────
      final billTrigger = _normalize(LanguageService.t('voice_trigger_generate_bill'));
      if (_triggerMatches(normalized, billTrigger)) {
        final rest = _textAfterTrigger(normalized, billTrigger);
        final month = _findMonth(rest);
        final year = _findYear(rest);
        final residentQuery = _stripDateWords(rest);
        final now = DateTime.now();
        if (residentQuery.isNotEmpty) {
          return GenerateBillIntent(
            residentQuery: residentQuery,
            month: month ?? now.month,
            year: year ?? now.year,
          );
        }
      }

      // ── "reject payment for X" - checked before "approve payment" isn't
      // necessary (trigger words don't overlap), but IS checked before the
      // "approve" trigger below in source order purely so a mis-said
      // "reject" never has a chance to partially match "approve" first. ──
      final rejectTrigger = _normalize(LanguageService.t('voice_trigger_reject_payment'));
      if (_triggerMatches(normalized, rejectTrigger)) {
        final rest = _textAfterTrigger(normalized, rejectTrigger);
        if (rest.isNotEmpty) return RejectPaymentIntent(residentQuery: rest);
      }

      // ── "approve payment for X" ───────────────────────────────────────
      final approveTrigger = _normalize(LanguageService.t('voice_trigger_approve_payment'));
      if (_triggerMatches(normalized, approveTrigger)) {
        final rest = _textAfterTrigger(normalized, approveTrigger);
        if (rest.isNotEmpty) return ApprovePaymentIntent(residentQuery: rest);
      }

      // ── "send a notice: X" / "send announcement X" ───────────────────
      final noticeTrigger = _normalize(LanguageService.t('voice_trigger_send_notice'));
      if (_triggerMatches(normalized, noticeTrigger)) {
        final rest = _textAfterTrigger(normalized, noticeTrigger);
        if (rest.isNotEmpty) return SendNoticeIntent(message: rest);
      }

      // ── "reject booking for X" - checked before "approve booking" for the
      // same reason as reject/approve payment above. ────────────────────
      final rejectBookingTrigger = _normalize(LanguageService.t('voice_trigger_reject_booking'));
      if (_triggerMatches(normalized, rejectBookingTrigger)) {
        final rest = _textAfterTrigger(normalized, rejectBookingTrigger);
        if (rest.isNotEmpty) return RejectBookingIntent(residentQuery: rest);
      }

      // ── "approve booking for X" ───────────────────────────────────────
      final approveBookingTrigger = _normalize(LanguageService.t('voice_trigger_approve_booking'));
      if (_triggerMatches(normalized, approveBookingTrigger)) {
        final rest = _textAfterTrigger(normalized, approveBookingTrigger);
        if (rest.isNotEmpty) return ApproveBookingIntent(residentQuery: rest);
      }
    }

    if (role == 'resident' && !ModuleGate.isOff('complaint_raise')) {
      // ── "raise a complaint about X" / "file a complaint X" ────────────
      final complaintTrigger = _normalize(LanguageService.t('voice_trigger_raise_complaint'));
      if (_triggerMatches(normalized, complaintTrigger)) {
        final rest = _textAfterTrigger(normalized, complaintTrigger);
        if (rest.isNotEmpty) return RaiseComplaintIntent(description: rest);
      }
    }

    if (role == 'resident' && !ModuleGate.isOff('wallet')) {
      // ── "recharge wallet 500" / "add money to wallet 500" ─────────────
      final rechargeTrigger = _normalize(LanguageService.t('voice_trigger_recharge_wallet'));
      if (_triggerMatches(normalized, rechargeTrigger)) {
        final rest = _textAfterTrigger(normalized, rechargeTrigger);
        return RechargeWalletIntent(amount: _findAmount(rest));
      }
    }

    if (role == 'resident') {
      // ── "pay bill for July" / "pay my bill in cash" - always submits
      // a cash payment request (see PayBillIntent's own docs). ──────────
      final payBillTrigger = _normalize(LanguageService.t('voice_trigger_pay_bill'));
      if (_triggerMatches(normalized, payBillTrigger)) {
        final rest = _textAfterTrigger(normalized, payBillTrigger);
        return PayBillIntent(monthQuery: _stripDateWords(rest));
      }
    }

    // ── "change language to Hindi" - any role. ───────────────────────────
    final changeLangTrigger = _normalize(LanguageService.t('voice_trigger_change_language'));
    if (_triggerMatches(normalized, changeLangTrigger)) {
      final rest = _textAfterTrigger(normalized, changeLangTrigger);
      if (rest.isNotEmpty) return ChangeLanguageIntent(languageQuery: rest);
    }

    if (!ModuleGate.isOff('chat')) {
      // ── "send a message: I'm running late" / "message everyone X" -
      // any role. Checked after every more-specific data command above so
      // it never steals a phrase meant for one of those (e.g. "send
      // notice" for admins). ─────────────────────────────────────────────
      final sendMessageTrigger = _normalize(LanguageService.t('voice_trigger_send_message'));
      if (_triggerMatches(normalized, sendMessageTrigger)) {
        final rest = _textAfterTrigger(normalized, sendMessageTrigger);
        if (rest.isNotEmpty) return SendChatMessageIntent(message: rest);
      }
    }

    if (role == 'resident' && !ModuleGate.isOff('visitors')) {
      // ── "add visitor X, tomorrow 5pm" / "register visitor X" ──────────
      final visitorTrigger = _normalize(LanguageService.t('voice_trigger_add_visitor'));
      if (_triggerMatches(normalized, visitorTrigger)) {
        final rest = _textAfterTrigger(normalized, visitorTrigger);
        final when = _findDateTime(rest);
        final name = _stripDateTimeWords(rest);
        if (name.isNotEmpty) {
          return RegisterVisitorIntent(visitorName: name, expectedAt: when);
        }
      }
    }

    if (role == 'resident' && !ModuleGate.isOff('facilities')) {
      // ── "cancel booking for the clubhouse" - checked before "book the
      // clubhouse" below since "cancel booking" would otherwise also
      // partially satisfy a loose "book" match. ─────────────────────────
      final cancelBookingTrigger = _normalize(LanguageService.t('voice_trigger_cancel_booking'));
      if (_triggerMatches(normalized, cancelBookingTrigger)) {
        final rest = _textAfterTrigger(normalized, cancelBookingTrigger);
        if (rest.isNotEmpty) return CancelBookingIntent(facilityQuery: rest);
      }

      // ── "book the clubhouse for Saturday" ──────────────────────────────
      // Deliberately whole-word matched (not via _triggerMatches' fuzzy
      // prefix check) - "book" is a substring of "bookings" (the Facilities
      // "My Bookings" nav label), so a loose contains()/prefix-similarity
      // match here would hijack "open bookings" into a booking attempt.
      // \b...\b requires an actual word boundary on both sides, which
      // "book" doesn't have inside "bookings".
      final bookTrigger = _normalize(LanguageService.t('voice_trigger_book_facility'));
      if (RegExp('\\b${RegExp.escape(bookTrigger)}\\b').hasMatch(normalized)) {
        final rest = _textAfterTrigger(normalized, bookTrigger);
        final date = _findRelativeDate(rest);
        final facilityQuery = _stripDateTimeWords(rest);
        if (facilityQuery.isNotEmpty) {
          return BookFacilityIntent(facilityQuery: facilityQuery, date: date);
        }
      }
    }

    if (role == 'security') {
      // ── "check out X" checked before "check in X" - both triggers start
      // with "check ", and "check out" contains "check in"'s trigger only
      // as a false-friend on short/noisy recognizer output, so trying the
      // longer, more specific phrase first avoids any ambiguity. ──────────
      final checkOutTrigger = _normalize(LanguageService.t('voice_trigger_check_out'));
      if (_triggerMatches(normalized, checkOutTrigger)) {
        final rest = _textAfterTrigger(normalized, checkOutTrigger);
        if (rest.isNotEmpty) return VisitorCheckOutIntent(visitorQuery: rest);
      }
      final checkInTrigger = _normalize(LanguageService.t('voice_trigger_check_in'));
      if (_triggerMatches(normalized, checkInTrigger)) {
        final rest = _textAfterTrigger(normalized, checkInTrigger);
        if (rest.isNotEmpty) return VisitorCheckInIntent(visitorQuery: rest);
      }
    }

    // ── Plain navigation - fuzzy-match against every known menu label ──
    // Strip filler/command words first ("open", "go to", "please", ...) so a
    // sentence like "open bills" is scored as just "bills" against the label
    // "billing", instead of the whole noisy phrase diluting the similarity
    // score below threshold.
    final stripped = _stripFillerWords(normalized);
    final navText = stripped.isNotEmpty ? stripped : normalized;

    final catalog = VoiceCommandCatalog.forRole(role);
    VoiceNavCommand? best;
    double bestScore = 0;
    for (final cmd in catalog) {
      final label = _normalize(LanguageService.t(cmd.labelKey));
      if (label.isEmpty) {
        // TEMP DIAGNOSTIC: a blank translation here means cmd.labelKey has
        // no value in your translations source - it's silently skipped
        // (this `continue`), so it just won't match, which usually reads
        // as "that command doesn't work" with no visible error anywhere.
        dev.log('  ! empty label for key="${cmd.labelKey}" (route=${cmd.route}) - skipped', name: 'VoiceCommandService');
        continue;
      }
      final score = _similarity(navText, label);
      // Also reward containment either way (e.g. "open billing please"
      // contains "billing"; leftover "bill" is contained *by* "billing").
      final containScore = (navText.length >= 3 && label.contains(navText)) ||
              (label.length >= 3 && navText.contains(label))
          ? 0.9
          : 0.0;
      final combined = score > containScore ? score : containScore;
      if (combined > bestScore) {
        bestScore = combined;
        best = cmd;
      }
    }
    // TEMP DIAGNOSTIC: shows the winning candidate and its score even when
    // it loses to the threshold below - a match that's just under 0.42 is
    // invisible any other way (it silently falls through to UnknownIntent).
    dev.log('  nav best="${best?.key}" label="${best != null ? LanguageService.t(best.labelKey) : null}" '
        'score=${bestScore.toStringAsFixed(2)} threshold=$_navMatchThreshold', name: 'VoiceCommandService');
    if (best != null && bestScore >= _navMatchThreshold) {
      return NavigateIntent(best.route, LanguageService.t(best.labelKey));
    }

    dev.log('  -> UnknownIntent', name: 'VoiceCommandService');
    return UnknownIntent(heard);
  }

  // ── Filler-word stripping ────────────────────────────────────────────────
  // Command phrasing like "open", "go to", "show me", "please" carries no
  // navigational meaning but dilutes the Dice-coefficient score against a
  // short label - exactly what caused "open bills" to score 0.40 against
  // "billing" (just under the 0.42 threshold) while "open billing" scored
  // 0.70. Stripping these first means the *destination word* is what gets
  // compared, not the whole sentence.
  static String _stripFillerWords(String normalized) {
    final raw = LanguageService.t('voice_filler_words');
    final fillers = raw
        .split(',')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList()
      // Longest phrases first so "go to" is removed whole before its
      // substring "go" would be (order matters for multi-word fillers).
      ..sort((a, b) => b.length.compareTo(a.length));

    var out = normalized;
    for (final f in fillers) {
      out = out.replaceAll(RegExp('\\b${RegExp.escape(f)}\\b'), ' ');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Fuzzy-matches [query] against a list of resident maps (each with a
  /// 'name' field, as returned by GET /admin/residents). Returns candidates
  /// sorted best-first, each as (resident, score). Callers decide what to
  /// do with ties/low-confidence via [_residentMatchThreshold].
  static List<(Map, double)> matchResidents(String query, List residents) {
    final q = _normalize(query);
    final scored = <(Map, double)>[];
    for (final r in residents) {
      final name = (r as Map)['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final score = _similarity(q, _normalize(name));
      if (score >= _residentMatchThreshold) scored.add((r, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }
}
