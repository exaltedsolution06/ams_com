import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/fcm_service.dart';
import '../../services/curved_header.dart';
import '../../services/language_service.dart';
import '../../widgets/login_hero_painter.dart';
import '../../widgets/legal_links_row.dart';
import '../../widgets/account_verify_otp_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey       = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController(); // accepts email OR phone number
  final _passCtrl      = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  // Purely cosmetic entrance animation (logo pops + form fades/slides up)
  // - no bearing on login logic, just makes the first frame feel less static.
  late final AnimationController _intro;
  late final Animation<double> _logoScale;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();
    // Refresh the platform default app name/logo/tagline (Admin > Settings
    // > General) in case it changed since app launch — cheap, unauthenticated.
    BrandingService.loadPublicDefaults().then((_) {
      if (mounted) setState(() {});
    });

    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _logoScale = CurvedAnimation(parent: _intro, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack));
    _formFade = CurvedAnimation(parent: _intro, curve: const Interval(0.25, 1.0, curve: Curves.easeOut));
    _formSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _intro, curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic)));
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Grab the current device push token (if Firebase is ready) so the
      // backend registers it in the very same request as login. Safe even
      // if Firebase never finished initialising on this build.
      final fcmToken = await FcmService.getTokenSafely();

      final res = await ApiService().post('/login', {
        // Backend 'email' field doubles as a generic login identifier —
        // it accepts either a registered email address or a phone number.
        'email':    _identifierCtrl.text.trim(),
        'password': _passCtrl.text,
        if (fcmToken != null) 'fcm_token': fcmToken,
      }, auth: false);

      // Multi-apartment identity (Resident/Apartment Admin only) - the
      // same login matched more than one apartment's account. Never shown
      // for anyone with just one apartment - see AuthController::login().
      if (res['multiple_accounts'] == true) {
        final accounts = (res['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (!mounted) return;
        final chosen = await _showChooseApartmentSheet(accounts);
        if (chosen == null) { setState(() => _loading = false); return; } // dismissed

        // The chosen apartment's password isn't necessarily the one just
        // typed above (accounts can be linked with DIFFERENT passwords per
        // apartment - see AuthController::login()) - this tries the typed
        // one first, and only prompts for a different one if that fails.
        await _chooseAccountWithRetry(chosen, _passCtrl.text, fcmToken);
        return;
      }

      // Post-login account verification (item 3) - this account has never
      // verified email or phone (see AuthController::verificationGate()).
      // An OTP was already sent; ask for it before finishing the login.
      if (res['needs_verification'] == true) {
        final verified = await showAccountVerifyOtpDialog(context, res, fcmToken: fcmToken);
        if (verified == null) { setState(() => _loading = false); return; } // cancelled
        await _completeLogin(verified);
        AuthService.rememberPassword(_passCtrl.text);
        return;
      }

      await _completeLogin(res);
      // Remember this password (in memory only) so a later apartment
      // switch can try it silently first - see AuthService.lastPassword.
      AuthService.rememberPassword(_passCtrl.text);
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shared by both the direct single-account login and the second step
  /// after picking an apartment below - saves the token/user, applies
  /// branding, and routes to the right dashboard for the role.
  Future<void> _completeLogin(Map<String, dynamic> res) async {
    final auth = AuthService();
    await auth.saveToken(res['access_token'] as String);

    final user = Map<String, dynamic>.from(res['user'] as Map);
    await auth.saveUser(user);
    await auth.setViewMode('admin'); // reset any stale switch from a previous session

    // Safety net: if getToken() above wasn't ready yet or failed silently,
    // this makes sure the token still gets registered post-login.
    FcmService.registerToken();

    // Apply branding immediately from login response (no extra API call)
    if (res['branding'] != null) {
      await BrandingService.applyFromLogin(
          Map<String, dynamic>.from(res['branding'] as Map));
    }

    if (!mounted) return;
    final role = user['role'] as String? ?? '';
    if (role != 'company_admin') {
      // This app is Company Admin only - any other role (a mistyped
      // super_admin/apartment_admin/resident login that still somehow
      // authenticated) is logged straight back out with a clear message,
      // rather than landing on a route this app doesn't have.
      await auth.logout();
      if (!mounted) return;
      setState(() => _error = 'This app is for Company Admin accounts only.');
      return;
    }
    context.go('/company/dashboard');
  }

  /// Bottom sheet listing every apartment this login is linked to - tap one
  /// to continue logging in as that specific account. Returns null if the
  /// person dismisses it without choosing (login aborts, same as an error).
  Future<Map<String, dynamic>?> _showChooseApartmentSheet(List<Map<String, dynamic>> accounts) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)))),
            Text(LanguageService.t('choose_an_apartment'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(LanguageService.t('this_login_is_linked_to_more_than_one_apartment'), style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 14),
            ...accounts.map((a) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.black12)),
                  child: ListTile(
                    leading: const Icon(Icons.apartment_rounded),
                    title: Text(a['apartment_name']?.toString() ?? 'Unknown Apartment', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (a['flat_number'] != null) 'Flat ${a['flat_number']}',
                      (a['role']?.toString() ?? '').replaceAll('_', ' '),
                    ].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: a['needs_verification'] == true
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                            child: Text('Not verified', style: TextStyle(fontSize: 10.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, a),
                  ),
                )),
          ]),
        ),
      ),
    );
  }

  /// Finishes login for [account]. Tries [password] (whatever was typed on
  /// the main form) first - the common case where every linked apartment
  /// shares one password, per AuthController::login()'s auto-link. If that
  /// specific account uses a different password, prompts for it instead of
  /// just failing the whole login - see AuthController::linkApartment() for
  /// how these end up sharing one password going forward, if the person
  /// chooses to link them from Profile.
  Future<void> _chooseAccountWithRetry(Map<String, dynamic> account, String password, String? fcmToken) async {
    var isRetryAttempt = false;
    while (true) {
      try {
        final res2 = await ApiService().post('/login/choose-account', {
          'user_id':  account['user_id'],
          'password': password,
          if (fcmToken != null) 'fcm_token': fcmToken,
        }, auth: false);

        if (res2['needs_verification'] == true) {
          final verified = await showAccountVerifyOtpDialog(context, res2, fcmToken: fcmToken);
          if (verified == null) { if (mounted) setState(() => _loading = false); return; }
          await _completeLogin(verified);
          AuthService.rememberPassword(password);
          return;
        }

        await _completeLogin(res2);
        // Whichever password actually worked for THIS specific account -
        // see the same rememberPassword() note in _login() above.
        AuthService.rememberPassword(password);
        return;
      } catch (e) {
        if (!mounted) return;
        final retryPassword = await _askPasswordFor(
          account,
          isRetryAttempt ? e.toString().replaceAll('Exception: ', '') : null,
        );
        if (retryPassword == null) { setState(() => _loading = false); return; } // cancelled
        password = retryPassword;
        isRetryAttempt = true;
      }
    }
  }

  /// Small dialog asking for one specific apartment's password. [errorText]
  /// is null on the very first prompt (shows a neutral heads-up instead of
  /// an alarming "invalid password", since nothing was actually typed wrong
  /// yet) and set to the server's message on every attempt after that.
  Future<String?> _askPasswordFor(Map<String, dynamic> account, String? errorText) {
    final ctrl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(account['apartment_name']?.toString() ?? 'This apartment'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              errorText ?? "This apartment uses a different password. Enter it to continue. You can use same password to avoid this step.",
              style: TextStyle(fontSize: 13, color: errorText != null ? Colors.red.shade700 : Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Continue')),
          ],
        ),
      ),
    );
  }

  /// Small circular "chip" behind each field's leading icon — reads as a
  /// more premium/considered field than a bare grey glyph. Tints with the
  /// apartment's own brand color(s): the identifier field uses primary, the
  /// password field uses secondary, echoing the header's two-stop gradient
  /// rather than repeating one color four times down the screen.
  Widget _iconChip(IconData icon, Color color) => Padding(
        padding: const EdgeInsets.all(11),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)),
          child: Icon(icon, size: 17, color: color),
        ),
      );

  InputDecoration _pillDecoration(String hint, IconData icon, Color accent, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14.5),
        prefixIcon: _iconChip(icon, accent),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: accent, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Soft tinted backdrop - the form now sits directly on this, with
      // no white card/sheet behind it.
      backgroundColor: const Color(0xFFF6F7FB),
      body: SingleChildScrollView(
        child: Column(children: [
          CurvedHeader(
            // Login is a one-off "first impression" screen, not a utility
            // dashboard sitting above a bottom nav bar - so unlike those
            // screens, there's no shared-shape constraint pulling its height
            // to 168. Taller (248) reads as a deliberate hero rather than a
            // cramped strip, now that the window-grid texture below gives it
            // somewhere to breathe.
            height: 248,
            // Two-stop brand gradient (primary → secondary) instead of the
            // single-color auto-lightened default, so apartments with a
            // distinct secondary brand color actually see both of them -
            // echoed again in the Sign In button below for a cohesive
            // "one gradient identity" story across the screen.
            colors: [BrandingService.primary, BrandingService.secondary],
            child: Stack(
              // Without this, the SafeArea/Column below (being the only
              // non-Positioned child in the Stack) shrink-wraps to its own
              // width and gets pinned to the Stack's default top-start
              // corner — so the logo + app name render left-aligned instead
              // of centered, even though the Column itself asks for
              // centered children internally.
              alignment: Alignment.center,
              children: [
                const Positioned.fill(child: LoginWindowGrid()),
                SafeArea(
                  bottom: false,
                  child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                    ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6))],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset('assets/images/default_logo.png', height: 64, width: 64, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(Icons.apartment_rounded, size: 32, color: BrandingService.primary)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(BrandingService.appName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
                    ),
                    if (BrandingService.appTagline != null && BrandingService.appTagline!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(BrandingService.appTagline!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white70)),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          // Form sits directly on the page background - no card/sheet
          // behind it, per request. Kept pulled up slightly over the
          // header's wave edge so there's no dead gap between the two.
          Transform.translate(
            offset: const Offset(0, -10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
              child: FadeTransition(
                opacity: _formFade,
                child: SlideTransition(
                  position: _formSlide,
                  child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(LanguageService.t('welcome_back'), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Color(0xFF171923))),
                  const SizedBox(height: 5),
                  Text(LanguageService.t('sign_in_to_continue'), style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 28),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.red.shade200)),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                  ]),
                ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: BrandingService.primary.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: TextFormField(
                  controller: _identifierCtrl,
                  keyboardType: TextInputType.text,
                  decoration: _pillDecoration('Email or Phone Number', Icons.person_outline, BrandingService.primary),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Email or phone number is required' : null,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: BrandingService.secondary.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: _pillDecoration('Password', Icons.lock_outline, BrandingService.secondary,
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey[600]),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      )),
                  validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go('/forgot-password-elevated'),
                  child: Text(LanguageService.t('forgot_password'), style: TextStyle(fontSize: 13, color: BrandingService.primary)),
                ),
              ),
              const SizedBox(height: 6),
              GradientButton(
                label: LanguageService.t('sign_in'),
                loading: _loading,
                onPressed: _loading ? null : _login,
                colors: [BrandingService.primary, BrandingService.secondary],
              ),
              const SizedBox(height: 18),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.verified_user_outlined, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(LanguageService.t('your_data_is_encrypted_and_never_shared'), style: TextStyle(color: Colors.grey[600], fontSize: 11.5, fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 0,
                runSpacing: 6,
                children: buildLegalLinks(context),
              ),
              const SizedBox(height: 14),
              Text(LanguageService.t('powered_by_exalted_solution'), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                ]), // Column children
              ), // Form
            ), // SlideTransition
          ), // FadeTransition
        ), // Padding
      ), // Transform.translate
        ]), // outer Column children
      ), // SingleChildScrollView
    );
  }
}
