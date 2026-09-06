import 'api_service.dart';
import 'auth_service.dart';

/// Community Meeting (video conferencing) — Phase 1: Default/Free provider
/// only (public Jitsi via meet.jit.si). Resident endpoints are read/join
/// only; scheduling and lifecycle control (create/start/end/cancel) go
/// through the /admin/community-meetings endpoints and are Apartment
/// Admin / Company Admin / Super Admin only — mirrored here by whichever
/// base path [_isAdminContext] resolves to.
class CommunityMeetingService {
  Future<bool> _isManager() async {
    final role = await AuthService().effectiveRole();
    return role == 'apartment_admin' || role == 'company_admin' || role == 'super_admin';
  }

  Future<String> _base() async => (await _isManager()) ? '/admin/community-meetings' : '/community-meetings';

  /// [status] optional filter: 'upcoming' | 'live' | 'past'.
  Future<List<Map>> list({String? status}) async {
    final base = await _base();
    final qs = status != null ? '?status=$status' : '';
    final res = await ApiService().get('$base$qs');
    dynamic data = res['data'];
    if (data is Map) data = data['data']; // paginated envelope
    return List<Map>.from(data ?? []);
  }

  Future<Map> show(int id) async {
    final base = await _base();
    final res = await ApiService().get('$base/$id');
    return Map<String, dynamic>.from(res['data'] ?? {});
  }

  /// Admin-only. [scheduledAt] null = ad-hoc "start now" meeting.
  Future<Map> create({required String title, String? description, DateTime? scheduledAt}) async {
    final res = await ApiService().post('/admin/community-meetings', {
      'title': title,
      if (description != null && description.isNotEmpty) 'description': description,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
    });
    return Map<String, dynamic>.from(res['data'] ?? {});
  }

  Future<void> start(int id) => ApiService().post('/admin/community-meetings/$id/start', {});
  Future<void> end(int id) => ApiService().post('/admin/community-meetings/$id/end', {});
  Future<void> cancel(int id) => ApiService().delete('/admin/community-meetings/$id');
}
