import 'api_service.dart';

class MaintenanceInfo {
  final bool enabled;
  final String? message;

  MaintenanceInfo({required this.enabled, this.message});

  factory MaintenanceInfo.fromJson(Map json) => MaintenanceInfo(
        enabled: json['enabled'] == true,
        message: json['message'],
      );
}

/// Platform-wide Maintenance Mode (Super Admin > Settings > Maintenance).
/// Mirrors AppUpdateService's pattern - checked at every app startup,
/// before login, so even a never-logged-in visitor sees the Maintenance
/// screen. See MaintenanceScreen for the blocking UI and ApiService for
/// how an already-open session gets force-navigated here mid-use (any
/// authenticated call that comes back with the 'maintenance_mode' error
/// code triggers the same screen).
class MaintenanceService {
  /// Single live source of truth for the router's redirect logic (see
  /// main.dart) - set at startup by check(), and updated directly by
  /// ApiService._forceMaintenance() the moment any authenticated call
  /// comes back blocked, so a later in-app navigation doesn't slip past
  /// the router redirect using a stale startup snapshot.
  static MaintenanceInfo? current;

  /// Returns the server's current maintenance status, or null if the
  /// check failed (e.g. no internet) - a failed check never blocks the
  /// user, same policy as AppUpdateService.
  static Future<MaintenanceInfo?> check() async {
    try {
      final res = await ApiService().get('/maintenance-status');
      final info = MaintenanceInfo.fromJson(res['data'] as Map);
      current = info;
      return info;
    } catch (_) {
      return null;
    }
  }
}
