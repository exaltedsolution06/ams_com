import 'package:package_info_plus/package_info_plus.dart';
import 'api_service.dart';

class UpdateInfo {
  final int versionCode;
  final String? versionName;
  final String? description;
  final String? apkUrl;
  final bool forceUpdateEnabled;

  UpdateInfo({
    required this.versionCode,
    this.versionName,
    this.description,
    this.apkUrl,
    required this.forceUpdateEnabled,
  });

  factory UpdateInfo.fromJson(Map json) => UpdateInfo(
        versionCode: json['version_code'] is int ? json['version_code'] : int.tryParse('${json['version_code']}') ?? 0,
        versionName: json['version_name'],
        description: json['description'],
        apkUrl: json['apk_url'],
        forceUpdateEnabled: json['force_update_enabled'] == true,
      );
}

class AppUpdateService {
  /// Returns the server's current update info, or null if the check
  /// failed (e.g. no internet) - callers should treat a failed check as
  /// "don't block the user", not as "force an update".
  static Future<UpdateInfo?> fetchLatest() async {
    try {
      final res = await ApiService().get('/app-update-check');
      return UpdateInfo.fromJson(res['data'] as Map);
    } catch (_) {
      return null;
    }
  }

  /// The app's own installed build number (the number after '+' in
  /// pubspec.yaml's version, e.g. "1.0.0+3" -> 3).
  static Future<int> currentVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// True only when the server has a force-update switched on AND its
  /// version is strictly newer than what's installed. A failed network
  /// check or missing data never blocks the user.
  static Future<UpdateInfo?> checkForMandatoryUpdate() async {
    final latest = await fetchLatest();
    if (latest == null || !latest.forceUpdateEnabled) return null;

    final current = await currentVersionCode();
    if (latest.versionCode > current) return latest;
    return null;
  }
}
