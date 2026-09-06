import 'api_service.dart';

class AnnouncementItem {
  final int id;
  final String message;

  AnnouncementItem({required this.id, required this.message});

  factory AnnouncementItem.fromJson(Map json) => AnnouncementItem(
        id: json['id'] as int,
        message: json['message'] as String? ?? '',
      );
}

/// Mobile counterpart of the web's dismissible dashboard announcement box.
/// See AuthService.getDismissedAnnouncementIds()/dismissAnnouncement() for
/// how "stays closed until logout" is implemented without a server session.
class AnnouncementService {
  static Future<List<AnnouncementItem>> fetchActive() async {
    try {
      final res = await ApiService().get('/announcements');
      final list = (res['data'] as List?) ?? [];
      return list.map((e) => AnnouncementItem.fromJson(e as Map)).toList();
    } catch (_) {
      // Never block the dashboard on a failed fetch — same policy as
      // MaintenanceService/AppUpdateService.
      return [];
    }
  }
}
