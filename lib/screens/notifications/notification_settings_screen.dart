import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_notification_settings_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/empty_state.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _loading = true;
  String? _error;
  List<Map> _availableTypes = [];
  Map<String, bool> _types = {};
  bool _mute = false;
  bool _sound = true;
  bool _vibrate = true;
  bool _saving = false;

  // ── Apartment-wide (Admin only) settings — activities + reminder
  // intervals, same as the web's Notification Settings page. ─────────────
  final _adminService = AdminNotificationSettingsService();
  bool _isManager = false;
  bool _adminLoading = true;
  bool _adminSaving = false;
  List<Map> _adminAvailableTypes = [];
  Map<String, bool> _adminEnabledTypes = {};
  final _paymentDaysCtrl = TextEditingController(text: '3');
  final _agreementDaysCtrl = TextEditingController(text: '3');

  @override
  void initState() {
    super.initState();
    _load();
    _loadAdminSettingsIfManager();
  }

  @override
  void dispose() {
    _paymentDaysCtrl.dispose();
    _agreementDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminSettingsIfManager() async {
    final isManager = await _adminService.isManager();
    if (!isManager) {
      setState(() { _isManager = false; _adminLoading = false; });
      return;
    }
    try {
      final data = await _adminService.get();
      final rawEnabled = List<String>.from(data['enabled_types'] ?? []);
      setState(() {
        _isManager = true;
        _adminAvailableTypes = List<Map>.from(data['available_types'] ?? []);
        _adminEnabledTypes = {
          for (final t in _adminAvailableTypes) t['key'] as String: rawEnabled.contains(t['key']),
        };
        _paymentDaysCtrl.text = '${data['pending_payment_reminder_days'] ?? 3}';
        _agreementDaysCtrl.text = '${data['agreement_expiry_reminder_days'] ?? 3}';
        _adminLoading = false;
      });
    } catch (_) {
      setState(() { _isManager = true; _adminLoading = false; });
    }
  }

  Future<void> _saveAdmin() async {
    final paymentDays = int.tryParse(_paymentDaysCtrl.text) ?? 3;
    final agreementDays = int.tryParse(_agreementDaysCtrl.text) ?? 3;
    setState(() => _adminSaving = true);
    try {
      await _adminService.update(
        enabledTypes: _adminEnabledTypes.entries.where((e) => e.value).map((e) => e.key).toList(),
        pendingPaymentReminderDays: paymentDays,
        agreementExpiryReminderDays: agreementDays,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('apartment_settings_saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _adminSaving = false);
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/notification-settings');
      final data = res['data'] as Map;
      // 'types' is a map of {activity_key: bool}. An empty PHP array
      // serializes as JSON `[]` (a list), not `{}` (a map) - if that ever
      // slips through, treat it as "no overrides saved yet" instead of
      // crashing the whole screen.
      final rawTypes = data['types'];
      setState(() {
        _availableTypes = List<Map>.from(data['available_types'] ?? []);
        _types = rawTypes is Map ? Map<String, bool>.from(rawTypes) : <String, bool>{};
        _mute = data['mute'] == true;
        _sound = data['sound'] != false;
        _vibrate = data['vibrate'] != false;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  bool _typeEnabled(String key) => _types[key] ?? true; // default ON (opt-out)

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().put('/notification-settings', {
        'types': _types,
        'mute': _mute,
        'sound': _sound,
        'vibrate': _vibrate,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('notification_settings_saved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('notification_settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: SwitchListTile(
                        value: _mute,
                        onChanged: (v) => setState(() => _mute = v),
                        activeColor: Colors.red,
                        title: Text(LanguageService.t('mute_all_notifications'), style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(LanguageService.t('turns_off_push_notifications_entirely_regardl'), style: TextStyle(fontSize: 12)),
                        secondary: const Icon(Icons.notifications_off_outlined, color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Opacity(
                      opacity: _mute ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: _mute,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(LanguageService.t('sound_vibration'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 6),
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                            child: Column(children: [
                              SwitchListTile(
                                value: _sound,
                                onChanged: (v) => setState(() => _sound = v),
                                activeColor: primary,
                                title: Text(LanguageService.t('sound')),
                                secondary: const Icon(Icons.volume_up_outlined),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                value: _vibrate,
                                onChanged: (v) => setState(() => _vibrate = v),
                                activeColor: primary,
                                title: Text(LanguageService.t('vibrate')),
                                secondary: const Icon(Icons.vibration),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 20),

                          Text(LanguageService.t('activities'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            LanguageService.t('your_apartment_admin_controls_which_of_these'),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 6),
                          if (_availableTypes.isEmpty)
                            EmptyRow(icon: Icons.notifications_off_outlined, text: LanguageService.t('no_push_notification_activities_have_been_ena'), color: BrandingService.primary)
                          else
                            Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: Column(
                                children: _availableTypes.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final t = entry.value;
                                  final key = t['key'] as String;
                                  final label = t['label'] as String;
                                  return Column(children: [
                                    if (i > 0) const Divider(height: 1),
                                    SwitchListTile(
                                      value: _typeEnabled(key),
                                      onChanged: (v) => setState(() => _types[key] = v),
                                      activeColor: primary,
                                      title: Text(label),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                        ]),
                      ),
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? '' : LanguageService.t('save_settings')),
                      ),
                    ),

                    if (_isManager) ...[
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(LanguageService.t('apartment_notification_settings'),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        LanguageService.t('apartment_notification_settings_hint'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),

                      if (_adminLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_adminAvailableTypes.isEmpty)
                          EmptyRow(icon: Icons.notifications_off_outlined, text: LanguageService.t('no_push_notification_activities_have_been_ena'), color: BrandingService.primary)
                        else
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                            child: Column(
                              children: _adminAvailableTypes.asMap().entries.map((entry) {
                                final i = entry.key;
                                final t = entry.value;
                                final key = t['key'] as String;
                                final label = t['label'] as String;
                                return Column(children: [
                                  if (i > 0) const Divider(height: 1),
                                  SwitchListTile(
                                    value: _adminEnabledTypes[key] ?? false,
                                    onChanged: (v) => setState(() => _adminEnabledTypes[key] = v),
                                    activeColor: primary,
                                    title: Text(label),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 20),

                        if (_adminEnabledTypes.containsKey('payment_due'))
                          _ReminderIntervalField(
                            label: LanguageService.t('pending_payment_reminder_interval'),
                            hint: LanguageService.t('pending_payment_reminder_interval_hint'),
                            controller: _paymentDaysCtrl,
                          ),
                        if (_adminEnabledTypes.containsKey('agreement_expiry'))
                          _ReminderIntervalField(
                            label: LanguageService.t('agreement_expiry_reminder_interval'),
                            hint: LanguageService.t('agreement_expiry_reminder_interval_hint'),
                            controller: _agreementDaysCtrl,
                          ),

                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _adminSaving ? null : _saveAdmin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: primary,
                              side: BorderSide(color: primary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _adminSaving
                                ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                                : const Icon(Icons.save_outlined),
                            label: Text(_adminSaving ? '' : LanguageService.t('save_apartment_settings')),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
    );
  }
}

/// A labelled "N days" number field, matching the web's
/// Pending/Agreement Expiry Reminder Interval inputs.
class _ReminderIntervalField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  const _ReminderIntervalField({required this.label, required this.hint, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        SizedBox(
          width: 140,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: LanguageService.t('days_label'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ]),
    );
  }
}
