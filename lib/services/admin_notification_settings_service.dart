import 'api_service.dart';
import 'auth_service.dart';

/// Apartment-wide notification settings (which activities are on, plus the
/// reminder day-intervals) for the Apartment/Company Admin - mirrors the
/// web's Admin > Setup & Settings > Notification Settings page.
///
/// Distinct from the per-resident mute/sound/vibrate/type preferences
/// exposed by the plain GET/PUT /notification-settings endpoints (see
/// NotificationSettingsScreen) - this hits the admin-only
/// /admin/notification-settings endpoints instead.
class AdminNotificationSettingsService {
  Future<bool> isManager() async {
    final role = await AuthService().effectiveRole();
    return role == 'apartment_admin' || role == 'company_admin';
  }

  Future<Map> get() async {
    final res = await ApiService().get('/admin/notification-settings');
    return Map<String, dynamic>.from(res['data'] ?? {});
  }

  Future<void> update({
    required List<String> enabledTypes,
    required int pendingPaymentReminderDays,
    required int agreementExpiryReminderDays,
  }) async {
    await ApiService().put('/admin/notification-settings', {
      'enabled_types': enabledTypes,
      'pending_payment_reminder_days': pendingPaymentReminderDays,
      'agreement_expiry_reminder_days': agreementExpiryReminderDays,
    });
  }
}
