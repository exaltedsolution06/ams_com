import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/curved_header.dart';
import '../../services/language_service.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/login_hero_painter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  // Super Admin / Company Admin accounts have no apartment_id, so they
  // can't use the apartment-scoped OTP-channel flow the rest of this
  // screen otherwise uses - they hit the /elevated endpoints instead,
  // which always resolve to the email channel. Same screen, same steps,
  // just a different set of API calls and a bit of copy.
  final bool elevated;
  const ForgotPasswordScreen({super.key, this.elevated = false});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with SingleTickerProviderStateMixin {
  int    _step    = 1; // 1=identifier, 2=otp, 3=new password
  bool   _loading = false;
  String? _error;
  String _identifier = ''; // email OR phone, whichever the user entered
  String _channel     = 'email'; // which channel the backend actually sent the OTP through
  String? _maskedTo;          // e.g. "jo**@example.com" or "******7890"
  // Set once the person picks a specific account from the "which one is
  // yours?" sheet below (see _sendOtp()) - only ever needed when more than
  // one DISTINCT identity shares the typed email/phone (unlinked
  // duplicates). Carried through every remaining step so verify/reset act
  // on that exact account. See PasswordResetOtpService::resolveForReset().
  int? _pendingResetUserId;

  final _identifierCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _confCtrl  = TextEditingController();
  bool  _obscure1  = true, _obscure2 = true;

  // Purely cosmetic: the step card fades/slides in fresh each time the
  // step advances, echoing the login screen's entrance treatment instead
  // of content just snapping into place.
  late final AnimationController _stepAnim;
  late final Animation<double> _stepFade;
  late final Animation<Offset> _stepSlide;

  @override
  void initState() {
    super.initState();
    _stepAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _stepFade = CurvedAnimation(parent: _stepAnim, curve: Curves.easeOut);
    _stepSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stepAnim, curve: Curves.easeOutCubic));
    _stepAnim.forward();
  }

  @override
  void dispose() {
    _stepAnim.dispose();
    super.dispose();
  }

  void _replayStepAnim() {
    _stepAnim.forward(from: 0);
  }

  Future<void> _sendOtp() async {
    _identifier = _identifierCtrl.text.trim();
    if (_identifier.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final path = widget.elevated ? '/forgot-password-elevated' : '/forgot-password';
      final res = await ApiService().post(path, {
        'email': _identifier,
        if (_pendingResetUserId != null) 'user_id': _pendingResetUserId,
      }, auth: false);

      // More than one DISTINCT identity shares this email/phone (unlinked
      // duplicates - see PasswordResetOtpService::resolveForReset()). Ask
      // which account this is for rather than guessing - guessing wrong
      // could reset a stranger's password. Not shown for a resident whose
      // apartments are already linked; that case resets all of them
      // together automatically, no picking needed.
      if (res['multiple_accounts'] == true) {
        setState(() => _loading = false);
        if (!mounted) return;
        final accounts = (res['accounts'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final chosen = await _showChooseAccountSheet(accounts);
        if (chosen == null) return; // dismissed, stay on step 1
        setState(() => _pendingResetUserId = chosen['user_id'] as int?);
        return _sendOtp(); // retry now that user_id disambiguates it
      }

      setState(() {
        _channel  = (res['channel'] as String?) ?? 'email';
        _maskedTo = res['sent_to'] as String?;
        _step     = 2;
        _loading  = false;
      });
      _replayStepAnim();
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; });
    }
  }

  /// Bottom sheet listing every distinct account using the typed email/
  /// phone - tap one to reset that specific account's password. Mirrors
  /// LoginScreen's apartment picker. Returns null if dismissed.
  Future<Map<String, dynamic>?> _showChooseAccountSheet(List<Map<String, dynamic>> accounts) {
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
            const Text('Which account is yours?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('More than one account uses this email or phone. Choose the one to reset.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
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
                    onTap: () => Navigator.pop(ctx, a),
                  ),
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) { setState(() => _error = 'Enter the 6-digit OTP'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final path = widget.elevated ? '/verify-otp-elevated' : '/verify-otp';
      await ApiService().post(path, {
        'email': _identifier,
        'otp': otp,
        if (_pendingResetUserId != null) 'user_id': _pendingResetUserId,
      }, auth: false);
      setState(() { _step = 3; _loading = false; });
      _replayStepAnim();
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; });
    }
  }

  Future<void> _resetPassword() async {
    if (_passCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters'); return;
    }
    if (_passCtrl.text != _confCtrl.text) {
      setState(() => _error = 'Passwords do not match'); return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final path = widget.elevated ? '/reset-password-elevated' : '/reset-password';
      await ApiService().post(path, {
        'email':                 _identifier,
        'otp':                   _otpCtrl.text.trim(),
        'password':              _passCtrl.text,
        'password_confirmation': _confCtrl.text,
        if (_pendingResetUserId != null) 'user_id': _pendingResetUserId,
      }, auth: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(LanguageService.t('password_reset_please_login')),
            backgroundColor: BrandingService.success,
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; });
    }
  }

  IconData get _stepIcon => _step == 1
      ? (widget.elevated ? Icons.email_outlined : Icons.person_search_rounded)
      : _step == 2
          ? (_channel == 'phone' ? Icons.sms_outlined : Icons.mark_email_read_outlined)
          : Icons.lock_reset_rounded;

  String get _stepTitle => _step == 1
      ? (widget.elevated ? 'Enter your Super Admin / Company Admin email' : 'Enter your email or phone number')
      : _step == 2
          ? 'Enter OTP'
          : 'New Password';

  String get _stepSubtitle => _step == 1
      ? (widget.elevated
          ? 'We will send a 6-digit OTP to your registered email address.'
          : 'We will send a 6-digit OTP to your registered email or phone number.')
      : _step == 2
          ? (_channel == 'phone'
              ? 'An OTP is sent to your registered phone${_maskedTo != null ? ' - ${_maskedTo!}' : ''}'
              : 'An OTP is sent to your registered email${_maskedTo != null ? ' - ${_maskedTo!}' : ''}')
          : 'Choose a strong password (min 8 characters).';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Same soft tinted backdrop as the login screen, so navigating back
      // and forth between the two feels like one continuous flow instead
      // of two differently-themed pages.
      backgroundColor: const Color(0xFFF6F7FB),
      body: SingleChildScrollView(
        child: Column(children: [
          CurvedHeader(
            height: 226,
            colors: [BrandingService.primary, BrandingService.secondary],
            child: Stack(
              children: [
                const Positioned.fill(child: LoginWindowGrid()),
                SafeArea(
                  bottom: false,
                  child: Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                      child: Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          onPressed: () {
                            if (_step > 1) {
                              setState(() { _step--; _error = null; });
                              _replayStepAnim();
                            } else {
                              context.go('/login');
                            }
                          },
                        ),
                        Expanded(
                          child: Text(
                            widget.elevated ? LanguageService.t('elevated_forgot_password_title') : LanguageService.t('forgot_password_2'),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    // Step icon in a soft white "chip", echoing the login
                    // screen's logo treatment rather than a bare glyph.
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: Icon(_stepIcon, size: 28, color: BrandingService.primary),
                    ),
                    const SizedBox(height: 14),
                    // Step progress dots
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i + 1 == _step ? 22 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i + 1 <= _step ? Colors.white : Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ))),
                  ]),
                ),
              ],
            ),
          ),
          // Pulled up over the header's wave edge, matching the login
          // screen's "no dead gap" layout. Sits directly on the page
          // background now (no boxed white card) for a flatter, more
          // modern look that flows straight out of the curved header.
          Transform.translate(
            offset: const Offset(0, -18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: FadeTransition(
                opacity: _stepFade,
                child: SlideTransition(
                  position: _stepSlide,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 26, 0, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_stepTitle,
                          style: const TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, color: Color(0xFF171923)),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text(_stepSubtitle,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 22),
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

                      // Step 1: Email / phone identifier
                      if (_step == 1) ...[
                        AppFieldShell(
                          accent: BrandingService.primary,
                          child: TextFormField(
                            controller: _identifierCtrl,
                            keyboardType: widget.elevated ? TextInputType.emailAddress : TextInputType.text,
                            decoration: appFieldDecoration(
                              label: widget.elevated ? 'Email Address' : 'Email or Phone Number',
                              icon: widget.elevated ? Icons.email_outlined : Icons.person_outline,
                              accent: BrandingService.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        GradientButton(
                          label: LanguageService.t('send_otp'),
                          loading: _loading,
                          onPressed: _loading ? null : _sendOtp,
                          colors: [BrandingService.primary, BrandingService.secondary],
                        ),
                      ],

                      // Step 2: OTP
                      if (_step == 2) ...[
                        AppFieldShell(
                          accent: BrandingService.secondary,
                          child: TextFormField(
                            controller: _otpCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 14, color: BrandingService.secondary),
                            decoration: appFieldDecoration(
                              label: '',
                              hint: '••••••',
                              accent: BrandingService.secondary,
                            ).copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _sendOtp,
                            child: Text(LanguageService.t('resend_otp'),
                                style: TextStyle(color: BrandingService.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GradientButton(
                          label: LanguageService.t('verify_otp'),
                          loading: _loading,
                          onPressed: _loading ? null : _verifyOtp,
                          colors: [BrandingService.primary, BrandingService.secondary],
                        ),
                      ],

                      // Step 3: New Password
                      if (_step == 3) ...[
                        AppFieldShell(
                          accent: BrandingService.primary,
                          child: TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscure1,
                            decoration: appFieldDecoration(
                              label: LanguageService.t('new_password'),
                              icon: Icons.lock_outline,
                              accent: BrandingService.primary,
                              suffix: IconButton(
                                icon: Icon(_obscure1 ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey[600]),
                                onPressed: () => setState(() => _obscure1 = !_obscure1),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppFieldShell(
                          accent: BrandingService.secondary,
                          child: TextFormField(
                            controller: _confCtrl,
                            obscureText: _obscure2,
                            decoration: appFieldDecoration(
                              label: LanguageService.t('confirm_password'),
                              icon: Icons.lock_outline,
                              accent: BrandingService.secondary,
                              suffix: IconButton(
                                icon: Icon(_obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey[600]),
                                onPressed: () => setState(() => _obscure2 = !_obscure2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        GradientButton(
                          label: LanguageService.t('reset_password'),
                          loading: _loading,
                          onPressed: _loading ? null : _resetPassword,
                          colors: [BrandingService.success, BrandingService.success],
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
