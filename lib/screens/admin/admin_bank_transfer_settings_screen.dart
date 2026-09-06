import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_form_field.dart';
import '../../services/drawer_state.dart';
import '../../services/language_service.dart';

/// Apartment Admin > Bank Transfer Settings — bank account details for
/// manual "Bank Transfer" payments, plus Cashfree Easy Split KYC and the
/// Enable/Disable/Refresh Automatic Online Collection controls. Mirrors the
/// web's admin/bank-transfer/edit.blade.php + BankTransferSettingController.
///
/// Once "Enable Automatic Online Collection" succeeds and Cashfree marks the
/// vendor ACTIVE, residents automatically see a "Pay Online" Cashfree popup
/// (see BrandingService.cashfreeOnlineEnabled) instead of only Bank Transfer
/// — funds settle straight into the bank account entered here via Easy
/// Split, same as the apartment admin's own subscription payment popup.
class AdminBankTransferSettingsScreen extends StatefulWidget {
  const AdminBankTransferSettingsScreen({super.key});
  @override
  State<AdminBankTransferSettingsScreen> createState() => _State();
}

class _State extends State<AdminBankTransferSettingsScreen> {
  bool _loading = true;
  bool _savingBank = false;
  bool _savingKyc = false;
  bool _actionBusy = false; // enable / disable / refresh
  String? _error;

  final _holderCtrl  = TextEditingController();
  final _numberCtrl  = TextEditingController();
  final _ifscCtrl    = TextEditingController();
  final _bankNameCtrl   = TextEditingController();
  final _branchCtrl     = TextEditingController();
  bool  _bankTransferStatus = false;

  final _panCtrl          = TextEditingController();
  final _accountTypeCtrl  = TextEditingController();
  final _businessTypeCtrl = TextEditingController();

  bool   _cashfreeSplitEnabled = false;
  String? _vendorStatus;
  bool   _razorpayOnlineEnabled = false;
  // Whether the whole "Automatic Online Collection (Cashfree)" section
  // should render at all — Super Admin > All PG Config > Cashfree > Easy
  // Split. Mirrors the web's $easySplitAvailable / ApartmentSetting::
  // cashfreeEasySplitAvailable().
  bool   _easySplitAvailable = false;

  @override void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _holderCtrl.dispose(); _numberCtrl.dispose(); _ifscCtrl.dispose();
    _bankNameCtrl.dispose(); _branchCtrl.dispose();
    _panCtrl.dispose(); _accountTypeCtrl.dispose(); _businessTypeCtrl.dispose();
    super.dispose();
  }

  bool get _isActive => _vendorStatus == 'ACTIVE';
  bool get _kycComplete =>
      _numberCtrl.text.trim().isNotEmpty && _ifscCtrl.text.trim().isNotEmpty &&
      _panCtrl.text.trim().isNotEmpty && _accountTypeCtrl.text.trim().isNotEmpty &&
      _businessTypeCtrl.text.trim().isNotEmpty;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res  = await ApiService().get('/admin/bank-transfer-settings');
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      _holderCtrl.text   = data['bank_account_holder'] as String? ?? '';
      _numberCtrl.text   = data['bank_account_number'] as String? ?? '';
      _ifscCtrl.text     = data['bank_ifsc_code'] as String? ?? '';
      _bankNameCtrl.text = data['bank_name'] as String? ?? '';
      _branchCtrl.text   = data['bank_branch_name'] as String? ?? '';
      _panCtrl.text          = data['cashfree_pan'] as String? ?? '';
      _accountTypeCtrl.text  = data['cashfree_account_type'] as String? ?? '';
      _businessTypeCtrl.text = data['cashfree_business_type'] as String? ?? '';
      setState(() {
        _bankTransferStatus  = data['bank_transfer_status'] == true;
        _cashfreeSplitEnabled = data['cashfree_split_enabled'] == true;
        _vendorStatus = data['cashfree_vendor_status'] as String?;
        _razorpayOnlineEnabled = data['razorpay_online_enabled'] == true;
        _easySplitAvailable = data['easy_split_available'] == true;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _saveAll({required bool bankOnly}) async {
    if (_holderCtrl.text.trim().isEmpty || _numberCtrl.text.trim().isEmpty || _ifscCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('bank_account_holder_number_and_ifsc_are_requi')), backgroundColor: Colors.red));
      return;
    }
    setState(() => bankOnly ? _savingBank = true : _savingKyc = true);
    try {
      await ApiService().put('/admin/bank-transfer-settings', {
        'bank_account_holder': _holderCtrl.text.trim(),
        'bank_account_number': _numberCtrl.text.trim(),
        'bank_ifsc_code': _ifscCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim().isEmpty ? null : _bankNameCtrl.text.trim(),
        'bank_branch_name': _branchCtrl.text.trim().isEmpty ? null : _branchCtrl.text.trim(),
        'bank_transfer_status': _bankTransferStatus,
        'cashfree_pan': _panCtrl.text.trim().isEmpty ? null : _panCtrl.text.trim(),
        'cashfree_account_type': _accountTypeCtrl.text.trim().isEmpty ? null : _accountTypeCtrl.text.trim(),
        'cashfree_business_type': _businessTypeCtrl.text.trim().isEmpty ? null : _businessTypeCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('bank_transfer_details_updated')), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => bankOnly ? _savingBank = false : _savingKyc = false);
    }
  }

  Future<void> _enableOnlineCollection() async {
    setState(() => _actionBusy = true);
    try {
      final res = await ApiService().post('/admin/bank-transfer-settings/enable-online', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Submitted.'), backgroundColor: Colors.green));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _disableOnlineCollection() async {
    setState(() => _actionBusy = true);
    try {
      await ApiService().post('/admin/bank-transfer-settings/disable-online', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LanguageService.t('automatic_online_collection_turned_off')), backgroundColor: Colors.green));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _actionBusy = true);
    try {
      final res = await ApiService().post('/admin/bank-transfer-settings/refresh-online-status', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? 'Refreshed.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')),
        title: Text(LanguageService.t('bank_transfer_settings')),
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      // ── Bank account (manual "Bank Transfer" option) ──
                      Text(LanguageService.t('bank_account_details'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(LanguageService.t('shown_to_residents_who_choose_bank_transfer_a'), style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 14),
                      AppFieldShell(accent: BrandingService.primary, child: TextField(
                        controller: _holderCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('account_holder_name'), icon: Icons.badge_outlined, accent: BrandingService.primary),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.secondary, child: TextField(
                        controller: _numberCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('account_number'), icon: Icons.numbers_rounded, accent: BrandingService.secondary),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.primary, child: TextField(
                        controller: _ifscCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: appFieldDecoration(label: LanguageService.t('ifsc_code'), icon: Icons.account_balance_outlined, accent: BrandingService.primary, hint: 'HDFC0001234'),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.secondary, child: TextField(
                        controller: _bankNameCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('bank_name_optional'), icon: Icons.account_balance, accent: BrandingService.secondary),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.primary, child: TextField(
                        controller: _branchCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('branch_name_optional'), icon: Icons.location_on_outlined, accent: BrandingService.primary),
                      )),
                      const SizedBox(height: 16),
                      SwitchListTile.adaptive(
                        value: _bankTransferStatus,
                        onChanged: (v) => setState(() => _bankTransferStatus = v),
                        title: Text(LanguageService.t('status_active'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(LanguageService.t('residents_only_see_bank_transfer_as_a_payment'), style: const TextStyle(fontSize: 12)),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _savingBank ? null : () => _saveAll(bankOnly: true),
                        icon: _savingBank ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
                        label: Text(_savingBank ? '${LanguageService.t('saving')}...' : LanguageService.t('save_bank_details')),
                        style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),

                      // ── Cashfree Easy Split ──
                      // Whole section only renders while Super Admin has
                      // Easy Split switched on for the platform's Global
                      // Cashfree gateway - see _easySplitAvailable / web's
                      // $easySplitAvailable in admin/bank-transfer/edit.
                      if (_easySplitAvailable) ...[
                      Row(children: [
                        const Icon(Icons.bolt_rounded, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(child: Text(LanguageService.t('automatic_online_collection_cashfree'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        LanguageService.t('lets_residents_pay_bills_charges_and_advance'),
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      if (_vendorStatus != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_isActive ? Colors.green : Colors.orange).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            Icon(_isActive ? Icons.check_circle : Icons.hourglass_bottom_rounded, size: 18, color: _isActive ? Colors.green : Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              '${LanguageService.t('status')}: ${_vendorStatus ?? LanguageService.t('pending_verification')}',
                              style: TextStyle(fontSize: 12.5, color: _isActive ? Colors.green.shade800 : Colors.orange.shade800, fontWeight: FontWeight.w600),
                            )),
                            if (!_isActive)
                              TextButton(
                                onPressed: _actionBusy ? null : _refreshStatus,
                                child: Text(LanguageService.t('refresh_status')),
                              ),
                          ]),
                        ),
                      const SizedBox(height: 14),
                      AppFieldShell(accent: BrandingService.secondary, child: TextField(
                        controller: _panCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: appFieldDecoration(label: LanguageService.t('pan_number'), icon: Icons.badge_outlined, accent: BrandingService.secondary, hint: 'ABCDE1234F'),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.primary, child: TextField(
                        controller: _accountTypeCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('account_type'), icon: Icons.category_outlined, accent: BrandingService.primary, hint: 'e.g. BUSINESS, Trust, Society'),
                      )),
                      const SizedBox(height: 12),
                      AppFieldShell(accent: BrandingService.secondary, child: TextField(
                        controller: _businessTypeCtrl,
                        decoration: appFieldDecoration(label: LanguageService.t('business_type'), icon: Icons.apartment_outlined, accent: BrandingService.secondary, hint: 'e.g. Real Estate'),
                      )),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _savingKyc ? null : () => _saveAll(bankOnly: false),
                        icon: _savingKyc ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                        label: Text(_savingKyc ? '${LanguageService.t('saving')}...' : LanguageService.t('save_kyc_details')),
                      ),
                      const SizedBox(height: 20),

                      if (!_cashfreeSplitEnabled)
                        ElevatedButton.icon(
                          onPressed: (_actionBusy || !_kycComplete) ? null : _enableOnlineCollection,
                          icon: _actionBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bolt),
                          label: Text(LanguageService.t('enable_automatic_online_collection')),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _actionBusy ? null : _disableOnlineCollection,
                          icon: _actionBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.block),
                          label: Text(LanguageService.t('disable_automatic_online_collection')),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      if (!_cashfreeSplitEnabled && !_kycComplete) ...[
                        const SizedBox(height: 8),
                        Text(LanguageService.t('fill_in_the_kyc_details_above_first'), style: const TextStyle(fontSize: 11.5, color: Colors.red)),
                      ],
                      const SizedBox(height: 12),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider()),
                      ],

                      // ── Razorpay (read-only) ──
                      // Counterpart to the Cashfree section above, but
                      // there's nothing for the apartment admin to fill in
                      // or verify here — set up once by Super Admin (All PG
                      // Config credentials + Branding > Payment Gateway
                      // tab), so this is a status display only. See
                      // ApartmentSetting::razorpayOnlineEnabled() and the
                      // web mirror in admin/bank-transfer/edit.blade.php.
                      Row(children: [
                        const Icon(Icons.credit_card_rounded, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Expanded(child: Text(LanguageService.t('online_collection_via_razorpay'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        LanguageService.t('razorpay_online_collection_hint'),
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_razorpayOnlineEnabled ? Colors.green : Colors.grey).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(_razorpayOnlineEnabled ? Icons.check_circle : Icons.info_outline, size: 18, color: _razorpayOnlineEnabled ? Colors.green : Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            _razorpayOnlineEnabled
                                ? LanguageService.t('razorpay_online_active')
                                : LanguageService.t('razorpay_online_inactive'),
                            style: TextStyle(fontSize: 12.5, color: _razorpayOnlineEnabled ? Colors.green.shade800 : Colors.grey.shade800, fontWeight: FontWeight.w600),
                          )),
                        ]),
                      ),
                    ]),
                  ),
                ),
    );
  }
}
