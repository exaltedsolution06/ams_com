import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/app_refresh.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../services/text_scale_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/language_selector_widget.dart';
import '../../widgets/account_verify_otp_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _user;
  bool _loading = true;

  // Profile form
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _profileSaving = false;

  // Password form
  final _curPassCtrl  = TextEditingController();
  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _passLoading = false;
  bool _o1 = true, _o2 = true, _o3 = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  // Multi-apartment identity (Resident/Apartment Admin only) - populated
  // from /me's 'sibling_accounts'; empty for everyone else, which is what
  // keeps the switcher below invisible for the common single-apartment case.
  List<Map<String, dynamic>> get _siblingAccounts =>
      (_user?['sibling_accounts'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // Count-only nudge toward linking - see AuthController::me()'s
  // 'other_accounts_hint'. Deliberately just a number: the other
  // account's apartment/name aren't shown here until this resident
  // actually proves ownership of it via _showLinkAnotherApartmentDialog().
  int get _otherAccountsHint => (_user?['other_accounts_hint'] as int?) ?? 0;
  bool _linking = false;

  Widget _buildApartmentSwitcher(Color primary) {
    return Card(
      color: primary.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primary.withOpacity(0.25))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.apartment_rounded, color: primary, size: 20),
            const SizedBox(width: 8),
            Text(LanguageService.t('your_apartments'), style: TextStyle(fontWeight: FontWeight.w800, color: primary)),
          ]),
          const SizedBox(height: 4),
          Text(LanguageService.t('this_login_is_linked_to_more_than_one_apartment_2'),
              style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          const SizedBox(height: 10),
          // Current apartment, shown but not tappable.
          _apartmentTile(_user?['apartment']?['name'] as String? ?? 'Current', current: true, onTap: null),
          for (final a in _siblingAccounts)
            _apartmentTile(a['apartment_name']?.toString() ?? 'Unknown Apartment',
                current: false, needsVerification: a['needs_verification'] == true,
                onTap: () => _switchApartment(a['user_id'] as int, apartmentName: a['apartment_name']?.toString())),
        ]),
      ),
    );
  }

  Widget _apartmentTile(String name, {required bool current, VoidCallback? onTap, bool needsVerification = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: current ? Colors.black.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (needsVerification)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text('Not verified', style: TextStyle(fontSize: 10.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                ),
              if (current) Text(LanguageService.t('current_2'), style: TextStyle(fontSize: 11, color: Colors.black45))
              else const Icon(Icons.chevron_right, size: 18, color: Colors.black45),
            ]),
          ),
        ),
      ),
    );
  }

  /// Switches to a sibling account (same person, different apartment).
  /// Tries AuthService.lastPassword (this session's most recently
  /// successful password) first - the common case where every linked
  /// apartment shares one password. Only if that specific apartment uses a
  /// different one does this prompt for it via _askApartmentPassword(),
  /// same retry loop as LoginScreen._chooseAccountWithRetry(); see
  /// AuthController::switchApartment() (API).
  Future<void> _switchApartment(int targetUserId, {String? apartmentName}) async {
    setState(() => _loading = true);
    var password = AuthService.lastPassword;
    var isRetryAttempt = false;

    while (true) {
      try {
        final res = await ApiService().post('/switch-apartment', {
          'user_id': targetUserId,
          if (password != null) 'password': password,
        });

        // Post-login account verification (item 4) - the target apartment
        // account has never verified email or phone yet (see
        // AuthController::verificationGate()). An OTP was already sent;
        // ask for it before actually switching over.
        if (res['needs_verification'] == true) {
          final verified = await showAccountVerifyOtpDialog(context, res);
          if (verified == null) { if (mounted) setState(() => _loading = false); return; }
          await _finishSwitchApartment(verified, password);
          return;
        }

        await _finishSwitchApartment(res, password);
        return;
      } catch (e) {
        if (!mounted) return;
        final retryPassword = await _askApartmentPassword(
          apartmentName,
          isRetryAttempt ? e.toString().replaceAll('Exception: ', '') : null,
        );
        if (retryPassword == null) { setState(() => _loading = false); return; } // cancelled
        password = retryPassword;
        isRetryAttempt = true;
      }
    }
  }

  /// Common tail of _switchApartment() above, shared by both the direct
  /// success path and the post-verification path (once
  /// showAccountVerifyOtpDialog() returns the real token).
  Future<void> _finishSwitchApartment(Map<String, dynamic> res, String? password) async {
    final auth = AuthService();
    await auth.saveToken(res['access_token'] as String);
    final newUser = Map<String, dynamic>.from(res['user'] as Map);
    await auth.saveUser(newUser);
    if (password != null) AuthService.rememberPassword(password);
    if (res['branding'] != null) {
      await BrandingService.applyFromLogin(Map<String, dynamic>.from(res['branding'] as Map));
    }
    AuthService.bumpApartmentSwitch();
    if (!mounted) return;
    final role = newUser['role'] as String? ?? 'resident';
    context.go(role == 'apartment_admin' ? '/admin/dashboard' : '/dashboard');
  }

  /// Small dialog asking for one specific apartment's password when
  /// switching to it - mirrors LoginScreen._askPasswordFor() exactly.
  /// [errorText] is null on the very first prompt (neutral heads-up
  /// instead of an alarming "invalid password", since nothing was actually
  /// typed wrong yet) and set to the server's message on every retry after.
  Future<String?> _askApartmentPassword(String? apartmentName, String? errorText) {
    final ctrl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(apartmentName ?? 'This apartment'),
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

  /// Nudge card shown when other account(s) share this email/phone but
  /// aren't linked yet (see _otherAccountsHint) - offers to link them via
  /// _showLinkAnotherApartmentDialog(). This is the resident-facing "merge
  /// key" action for when a second apartment has a DIFFERENT password, so
  /// the automatic linking at login (AuthController::login()) never had a
  /// shared password to go on.
  Widget _buildLinkAnotherApartmentHint(Color primary) {
    return Card(
      color: Colors.amber.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.amber.withOpacity(0.35))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _otherAccountsHint == 1
                    ? 'We noticed 1 other account using your email or phone.'
                    : 'We noticed $_otherAccountsHint other accounts using your email or phone.',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.amber.shade900, fontSize: 13.5),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'If one of these is another apartment of yours, link it to switch between them without re-entering a password.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _linking ? null : _showLinkAnotherApartmentDialog,
              icon: _linking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded, size: 18),
              label: const Text('Link Another Apartment'),
              style: OutlinedButton.styleFrom(foregroundColor: primary, side: BorderSide(color: primary)),
            ),
          ),
        ]),
      ),
    );
  }

  /// Asks for the OTHER apartment's password and, if it checks out, links
  /// the two accounts - see AuthController::linkApartment(). A stranger who
  /// merely shares this email/phone by an admin's data-entry mistake does
  /// not know that account's password, so they can't link themselves in
  /// this way - only someone who actually owns both accounts can.
  Future<void> _showLinkAnotherApartmentDialog() async {
    final ctrl = TextEditingController();
    bool obscure = true;
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Link Another Apartment'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              "Enter the password for the other apartment's account. We'll only link it once that password checks out.",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Other apartment's password",
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
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Link')),
          ],
        ),
      ),
    );

    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _linking = true);
    try {
      final res = await ApiService().post('/link-apartment', {'password': password});
      if (!mounted) return;
      _showSnack(res['message'] as String? ?? 'Apartments linked.', false);
      _load(); // refresh /me so sibling_accounts + other_accounts_hint reflect the new link
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), true);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Widget _buildVoiceMicSwitch(Color primary) {
    // If the apartment itself has switched the mic off (Admin > Apartments
    // > Edit), this personal switch wouldn't do anything even if turned
    // on - hide it rather than offer a control with no effect.
    if (!BrandingService.voiceMicEnabled) {
      return const SizedBox.shrink();
    }
    final enabled = (_user?['voice_mic_enabled'] as bool?) ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Icon(Icons.mic_none_rounded, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(LanguageService.t('voice_mic'), style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: enabled,
            activeColor: primary,
            onChanged: _voiceMicSaving ? null : _toggleVoiceMic,
          ),
        ]),
      ),
    );
  }

  bool _voiceMicSaving = false;
  bool _dateFormatSaving = false;

  /// Profile > "Voice Mic" - a purely personal preference, doesn't affect
  /// anyone else in the apartment. See AuthService.wantsVoiceMic /
  /// User::wantsVoiceMic() for how this combines with the apartment-wide
  /// switch to decide whether the floating mic actually shows.
  Future<void> _toggleVoiceMic(bool value) async {
    setState(() => _voiceMicSaving = true);
    try {
      await ApiService().put('/profile/voice-mic', {'voice_mic_enabled': value});
      setState(() {
        _user = {...?_user, 'voice_mic_enabled': value};
      });
      // AuthService.wantsVoiceMic reads from the in-memory user cache -
      // update it too so the mic overlay picks up the change immediately,
      // without needing to log out/in.
      final auth = AuthService();
      final cached = await auth.getUser();
      if (cached != null) {
        await auth.saveUser({...cached, 'voice_mic_enabled': value});
      }
      // The dashboard is already mounted and reads AuthService.wantsVoiceMic
      // during its build() to decide where the bottom nav/FAB sits - static
      // field changes alone don't make a mounted widget rebuild, so without
      // this it stayed stale until something else happened to rebuild it.
      AppRefresh.bump();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _voiceMicSaving = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/me');
      final u   = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _user            = u;
        _loading         = false;
        _nameCtrl.text   = u['name']  as String? ?? '';
        _phoneCtrl.text  = u['phone'] as String? ?? '';
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _profileSaving = true);
    try {
      await ApiService().put('/profile', {
        'name':  _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      final me = await ApiService().get('/me');
      await AuthService().saveUser(Map<String, dynamic>.from(me['data'] as Map));
      if (mounted) {
        _showSnack(LanguageService.t('success') + ': Profile updated!', false);
        _load();
      }
    } catch (e) {
      _showSnack(e.toString().replaceAll('Exception: ',''), true);
    } finally {
      if (mounted) setState(() => _profileSaving = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPassCtrl.text.length < 8) { _showSnack('Password must be at least 8 characters', true); return; }
    if (_newPassCtrl.text != _confPassCtrl.text) { _showSnack('Passwords do not match', true); return; }
    setState(() => _passLoading = true);
    try {
      await ApiService().post('/change-password', {
        'current_password':      _curPassCtrl.text,
        'password':              _newPassCtrl.text,
        'password_confirmation': _confPassCtrl.text,
      });
      _curPassCtrl.clear(); _newPassCtrl.clear(); _confPassCtrl.clear();
      _showSnack('Password changed successfully!', false);
    } catch (e) {
      _showSnack(e.toString().replaceAll('Exception: ',''), true);
    } finally {
      if (mounted) setState(() => _passLoading = false);
    }
  }

  void _showSnack(String msg, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  // ── Delete Account ─────────────────────────────────────────────────────
  // Two-step confirmation per spec: a warning dialog explaining what
  // happens and what's retained, then a second dialog requiring the
  // user's current password before the DELETE /account call fires.

  Widget _buildDeleteAccountSection() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
        label: Text(LanguageService.t('delete_account'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: _showDeleteWarningDialog,
      ),
    );
  }

  Future<void> _showDeleteWarningDialog() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 10),
          Expanded(child: Text(LanguageService.t('delete_account'), style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
        content: SingleChildScrollView(
          child: Text(
            LanguageService.t('deleting_your_account_will_permanently_remove'),
            style: TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(LanguageService.t('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(LanguageService.t('continue'), style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (proceed == true) _showPasswordConfirmDialog();
  }

  Future<void> _showPasswordConfirmDialog() async {
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool loading = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(LanguageService.t('confirm_your_password'), style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(LanguageService.t('enter_your_password_to_permanently_delete_your'),
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: LanguageService.t('password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setDialogState(() => obscure = !obscure),
                ),
                errorText: error,
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(LanguageService.t('cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: loading
                  ? null
                  : () async {
                      if (passCtrl.text.isEmpty) {
                        setDialogState(() => error = 'Password is required');
                        return;
                      }
                      setDialogState(() { loading = true; error = null; });
                      try {
                        await ApiService().deleteWithBody('/account', {'password': passCtrl.text});
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _finishAccountDeleted();
                      } catch (e) {
                        setDialogState(() {
                          loading = false;
                          error = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(LanguageService.t('delete_account'), style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  /// Account is already deleted server-side at this point - just clear
  /// local session state and send the person back to Login, same as a
  /// normal logout.
  Future<void> _finishAccountDeleted() async {
    await AuthService().logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(LanguageService.t('your_account_has_been_deleted')),
      backgroundColor: Colors.green,
    ));
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final primary  = BrandingService.primary;
    final role     = _user?['role'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(LanguageService.t('profile')),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: const Icon(Icons.person_outline, size: 18),   text: LanguageService.t('profile')),
            Tab(icon: const Icon(Icons.lock_outline, size: 18),     text: LanguageService.t('change_password')),
            Tab(icon: const Icon(Icons.translate, size: 18),        text: LanguageService.t('select_language')),
            Tab(icon: const Icon(Icons.settings_outlined, size: 18), text: LanguageService.t('settings')),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                // ── TAB 1: Profile ─────────────────────────────────────────
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: primary.withOpacity(0.12),
                      child: Text(
                        (_user?['name'] as String? ?? '?')[0].toUpperCase(),
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: primary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_user?['email'] as String? ?? '',
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        LanguageService.t(role).toUpperCase(),
                        style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _field(_nameCtrl,  LanguageService.t('full_name'),  Icons.person_outline),
                          const SizedBox(height: 14),
                          _field(_phoneCtrl, LanguageService.t('phone'),      Icons.phone_outlined,
                              keyboardType: TextInputType.phone),
                          const SizedBox(height: 14),
                          TextField(
                            enabled: false,
                            controller: TextEditingController(text: _user?['email'] as String? ?? ''),
                            decoration: InputDecoration(
                              labelText: '${LanguageService.t('email')} (contact admin to change)',
                              prefixIcon: const Icon(Icons.email_outlined),
                              fillColor: Colors.grey[100],
                              filled: true,
                            ),
                          ),
                          if (role == 'resident') ...[
                            const SizedBox(height: 12),
                            TextField(
                              enabled: false,
                              controller: TextEditingController(
                                text: '${LanguageService.t('flat_label')} ${_user?['flat']?['flat_number'] ?? '—'}  ·  ${LanguageService.t((_user?['occupancy_type'] as String? ?? '')).toUpperCase()}',
                              ),
                              decoration: InputDecoration(
                                labelText: '${LanguageService.t('flat_number')} & ${LanguageService.t('occupancy_type')}',
                                prefixIcon: const Icon(Icons.home_outlined),
                                fillColor: Colors.grey[100],
                                filled: true,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: _profileSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_outlined),
                              label: Text(LanguageService.t('save')),
                              onPressed: _profileSaving ? null : _saveProfile,
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDeleteAccountSection(),
                    const SizedBox(height: 16),
                  ]),
                ),

                // ── TAB 2: Password ────────────────────────────────────────
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(LanguageService.t('change_password'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(LanguageService.t('use_a_strong_password_with_at_least_8_characters'),
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 20),
                        _passField(_curPassCtrl,  LanguageService.t('current_password'), _o1, () => setState(() => _o1 = !_o1)),
                        const SizedBox(height: 14),
                        _passField(_newPassCtrl,  LanguageService.t('new_password'),     _o2, () => setState(() => _o2 = !_o2)),
                        const SizedBox(height: 14),
                        _passField(_confPassCtrl, LanguageService.t('confirm_password'), _o3, () => setState(() => _o3 = !_o3)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: _passLoading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.lock_reset),
                          label: Text(LanguageService.t('change_password')),
                          onPressed: _passLoading ? null : _changePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BrandingService.success,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.help_outline, size: 16),
                          label: Text(LanguageService.t('forgot_password')),
                          onPressed: () => context.go('/forgot-password'),
                        ),
                      ]),
                    ),
                  ),
                ),

                // ── TAB 3: Language ────────────────────────────────────────
                LanguageSelectorWidget(
                  onLanguageChanged: () => setState(() {}), // rebuild with new language
                ),

                // ── TAB 4: Settings (apartments, voice mic, font size) ─────
                _buildSettingsTab(primary, role),
              ],
            ),
    );
  }

  Widget _buildSettingsTab(Color primary, String role) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      child: Column(children: [
        // Multi-apartment identity (Resident/Apartment Admin only) - only
        // rendered when this login is linked to more than one apartment,
        // per spec. See AuthController::me()'s 'sibling_accounts'.
        if (_siblingAccounts.isNotEmpty) ...[
          _buildApartmentSwitcher(primary),
          const SizedBox(height: 16),
        ],
        // Shown whenever an unlinked duplicate exists, independently of the
        // switcher above - covers both "no linked apartments yet, but we
        // found one" and "already linked to some, but there's one more".
        if (_otherAccountsHint > 0) ...[
          _buildLinkAnotherApartmentHint(primary),
          const SizedBox(height: 16),
        ],
        _buildVoiceMicSwitch(primary),
        const SizedBox(height: 16),
        _buildFontSizeCard(primary),
        // Date Format is an apartment-wide setting ("each apartment can set
        // their own need"), not a personal one like Font Size above - so
        // only the Apartment Admin gets to change it here. Everyone else
        // in the apartment still sees dates rendered in whatever format
        // the admin picked; they just don't get a control for it in their
        // own Settings tab. Mirrors who can hit POST /branding server-side.
        if (role == 'apartment_admin') ...[
          const SizedBox(height: 16),
          _buildDateFormatCard(primary),
        ],
      ]),
    );
  }

  // The currently active step's own value from TextScaleService.steps -
  // matched by tolerance (same as the old radio-list's `selected` check)
  // rather than direct equality, since the persisted scale is read back
  // from SharedPreferences rather than compared against the map literal.
  double get _currentFontStep {
    for (final v in TextScaleService.steps.values) {
      if ((v - TextScaleService.scale).abs() < 0.001) return v;
    }
    return 1.0;
  }

  Widget _buildFontSizeCard(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.text_fields, size: 20),
            SizedBox(width: 8),
            Text(LanguageService.t('font_size'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(LanguageService.t('make_text_throughout_the_app_smaller_or_larger'),
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),

          AppFieldShell(
            accent: primary,
            child: DropdownButtonFormField<double>(
              value: _currentFontStep,
              isExpanded: true,
              decoration: appFieldDecoration(label: LanguageService.t('font_size'), icon: Icons.text_fields, accent: primary),
              items: [
                for (final entry in TextScaleService.steps.entries)
                  DropdownMenuItem(value: entry.value, child: Text(entry.key, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) async {
                if (value == null) return;
                await TextScaleService.setScale(value);
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),

          // Live preview that reflects the currently-selected size, even
          // before it's saved, so the user can see the effect right away.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primary.withOpacity(0.2)),
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(TextScaleService.scale),
              ),
              child: Text(
                LanguageService.t('this_is_a_preview_of_the_apps_text_size'),
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Profile > Settings > "Date Format" - apartment-wide (Apartment Admin
  /// only), saved through BrandingService.updateDateFormat() which posts
  /// the full /branding form. Every other resident/security/guard user in
  /// the apartment picks this up automatically on their next /branding
  /// load since BrandingService.formatDate/formatDateString reads from the
  /// same shared apartment setting - they just don't get a control for it.
  Widget _buildDateFormatCard(Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.calendar_month_outlined, size: 20),
            SizedBox(width: 8),
            Text(LanguageService.t('date_format'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(
            LanguageService.t('choose_how_dates_are_shown_across_the_app_for'),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          AppFieldShell(
            accent: primary,
            child: DropdownButtonFormField<String>(
              value: BrandingService.dateFormatOptions.containsKey(BrandingService.dateFormat)
                  ? BrandingService.dateFormat
                  : null,
              isExpanded: true,
              decoration: appFieldDecoration(label: LanguageService.t('date_format'), icon: Icons.calendar_month_outlined, accent: primary),
              items: [
                for (final entry in BrandingService.dateFormatOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _dateFormatSaving ? null : _saveDateFormat,
            ),
          ),
          if (_dateFormatSaving) ...[
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
              const SizedBox(width: 8),
              Text(LanguageService.t('saving'), style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _saveDateFormat(String? value) async {
    if (value == null) return;
    setState(() => _dateFormatSaving = true);
    try {
      await BrandingService.updateDateFormat(value);
      if (mounted) _showSnack('Date format updated.', false);
    } catch (_) {
      if (mounted) _showSnack('Could not update date format. Please try again.', true);
    } finally {
      if (mounted) setState(() => _dateFormatSaving = false);
    }
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? keyboardType}) =>
      AppFieldShell(
        accent: BrandingService.primary,
        child: TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          decoration: appFieldDecoration(label: label, icon: icon, accent: BrandingService.primary),
        ),
      );

  Widget _passField(TextEditingController ctrl, String label, bool obscure, VoidCallback toggle) =>
      AppFieldShell(
        accent: BrandingService.secondary,
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          decoration: appFieldDecoration(
            label: label,
            icon: Icons.lock_outlined,
            accent: BrandingService.secondary,
            suffix: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: toggle,
            ),
          ),
        ),
      );
}
