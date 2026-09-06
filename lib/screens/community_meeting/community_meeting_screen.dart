import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/community_meeting_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import 'meeting_room_screen.dart';
import 'zego_meeting_room_screen.dart';

import '../../services/language_service.dart';
/// Community Meeting — video conferencing. Default/Free (Jitsi, web view)
/// and Premium (ZegoCloud, native call UI) - see _openRoom() for the
/// provider branch.
///
/// Same screen for residents and admins (mirrors EmergencyNumbersScreen's
/// pattern): residents see a read-only list and can join; Apartment Admin /
/// Company Admin / Super Admin additionally get a "Schedule" FAB and
/// Start/End/Cancel controls on their own meetings.
class CommunityMeetingScreen extends StatefulWidget {
  const CommunityMeetingScreen({super.key});
  @override
  State<CommunityMeetingScreen> createState() => _CommunityMeetingScreenState();
}

class _CommunityMeetingScreenState extends State<CommunityMeetingScreen> with SingleTickerProviderStateMixin {
  final _service = CommunityMeetingService();
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  bool _isManager = false;
  String _displayName = '';
  List<Map> _meetings = [];

  static const _statuses = ['upcoming', 'live', 'past'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this, initialIndex: 1); // default to "Live"
    _tabs.addListener(() { if (!_tabs.indexIsChanging) _load(); });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final role = await AuthService().effectiveRole();
      final user = await AuthService().getUser();
      final isManager = role == 'apartment_admin' || role == 'company_admin' || role == 'super_admin';
      final meetings = await _service.list(status: _statuses[_tabs.index]);
      setState(() {
        _isManager = isManager;
        _displayName = user?['name'] as String? ?? '';
        _meetings = meetings;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  void _showScheduleForm() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool startNow = true;
    DateTime? scheduledAt;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: BrandingService.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.video_camera_front_outlined, color: BrandingService.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(LanguageService.t('schedule_meet_live'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: appFieldDecoration(label: LanguageService.t('title'), icon: Icons.short_text_rounded, accent: BrandingService.primary),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: BrandingService.secondary),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Material(
                // See admin_reports_financial_screen.dart's _VisibilityCard
                // for why this is needed - SwitchListTile paints its
                // background/ink on the nearest Material ancestor, and the
                // Container above (needed for the grey card look) would
                // otherwise block that.
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: SwitchListTile(
                  value: startNow,
                  activeColor: BrandingService.primary,
                  title: Text(LanguageService.t('start_now'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(startNow ? 'Meeting goes live immediately' : 'Pick a date & time below', style: const TextStyle(fontSize: 12)),
                  onChanged: (v) => setS(() => startNow = v),
                ),
              ),
            ),
            if (!startNow) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(Icons.event_outlined, color: BrandingService.primary),
                label: Text(scheduledAt == null ? 'Pick date & time' : BrandingService.formatDateTime(scheduledAt), style: TextStyle(color: Colors.grey[800])),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: ctx, initialDate: DateTime.now().add(const Duration(hours: 1)),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null) return;
                  final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (time == null) return;
                  setS(() => scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.video_call_outlined),
              label: Text(LanguageService.t('schedule')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: BrandingService.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                setS(() => formError = null);
                if (titleCtrl.text.trim().isEmpty) {
                  setS(() => formError = 'Please enter a title');
                  return;
                }
                if (!startNow && scheduledAt == null) {
                  setS(() => formError = 'Please pick a date & time');
                  return;
                }
                try {
                  final meeting = await _service.create(
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    scheduledAt: startNow ? null : scheduledAt,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                  if (startNow && meeting['id'] != null && mounted) {
                    await _startAndJoin(Map<String, dynamic>.from(meeting));
                  }
                } catch (e) {
                  setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                }
              },
            ),
          ]),
        )),
      ),
    );
  }

  Future<void> _startAndJoin(Map meeting) async {
    try {
      if (meeting['status'] == 'scheduled') {
        await _service.start(meeting['id'] as int);
      }
      final fresh = await _service.show(meeting['id'] as int);
      await _load();
      _openRoom(fresh);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  /// Residents don't hit /start (that's admin-only), but they still need a
  /// FRESH copy of the meeting before opening the room - the list/index
  /// response a card is built from may not carry a fully-populated `join`
  /// block (room id, and for Zego the per-user token/app id), since minting
  /// that for every meeting in a list, for every viewer, isn't something an
  /// index endpoint typically does. `show()` is the endpoint that mints it.
  Future<void> _joinAsResident(Map meeting) async {
    try {
      final fresh = await _service.show(meeting['id'] as int);
      if (!mounted) return;
      _openRoom(fresh);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  void _openRoom(Map meeting) {
    final join = meeting['join'] as Map?;
    if (join == null || join['room_id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('this_meeting_isnt_ready_to_join_right_now'))),
      );
      return;
    }
    _ensureCallPermissions().then((granted) {
      if (!granted || !mounted) return;
      _openRoomAfterPermissions(meeting, join);
    });
  }

  /// Asks for camera + microphone up front, the first time (and every time
  /// after, if previously denied) someone taps into a room - rather than
  /// relying on Jitsi's WebView silently failing to get media, or
  /// ZegoCloud's own internal prompt with no explanatory copy first.
  ///
  /// No-op on web: the browser handles its own getUserMedia permission
  /// prompt the moment the Jitsi tab actually requests media, and
  /// permission_handler has nothing to check there.
  Future<bool> _ensureCallPermissions() async {
    if (kIsWeb) return true;

    final statuses = await [Permission.camera, Permission.microphone].request();
    final camera = statuses[Permission.camera] ?? PermissionStatus.denied;
    final mic = statuses[Permission.microphone] ?? PermissionStatus.denied;
    if (camera.isGranted && mic.isGranted) return true;
    if (!mounted) return false;

    // permanentlyDenied means the OS won't show its own prompt again - the
    // only way forward is the app's own Settings page, so send them there
    // directly instead of just repeating a request that will silently
    // no-op.
    final permanentlyDenied = camera.isPermanentlyDenied || mic.isPermanentlyDenied;
    final goToSettings = await AmsDialog.confirm(
      context,
      title: LanguageService.t('camera_microphone_needed'),
      message: permanentlyDenied
          ? 'Meet Live needs camera and microphone access to join a video call. '
              'Please enable both for this app in your device Settings.'
          : 'Meet Live needs camera and microphone access to join a video call. '
              'Please allow both permissions to continue.',
      icon: Icons.videocam_off_rounded,
      confirmText: permanentlyDenied ? 'Open Settings' : 'Try Again',
    );
    if (goToSettings != true || !mounted) return false;
    if (permanentlyDenied) {
      await openAppSettings();
      return false; // they'll need to tap the meeting again after enabling it
    }
    return _ensureCallPermissions(); // one retry after they've had a chance to reconsider
  }

  void _openRoomAfterPermissions(Map meeting, Map join) {
    final provider = meeting['provider'] as String? ?? 'jitsi';
    final title = meeting['title'] as String? ?? 'Meet Live';

    // Premium (ZegoCloud) — app only (see ZegoMeetingRoomScreen's class
    // doc). On web, fall back to the same "not supported" message Jitsi's
    // web view uses for anything it can't embed, rather than attempting a
    // native-only plugin.
    if (provider == 'zego') {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('premium_video_meetings_are_supported_on_the'))),
        );
        return;
      }
      final appId = join['app_id'];
      final token = join['token'] as String?;
      if (appId == null || token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('this_meetings_premium_video_provider_isnt_fully'))),
        );
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => ZegoMeetingRoomScreen(
        appId: appId is int ? appId : int.parse(appId.toString()),
        token: token,
        roomId: join['room_id'] as String,
        userId: join['user_id'] as String? ?? '',
        userName: join['user_name'] as String? ?? _displayName,
        title: title,
      )));
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => MeetingRoomScreen(
      roomId: join['room_id'] as String,
      jitsiDomain: join['jitsi_domain'] as String? ?? 'meet.jit.si',
      title: title,
      displayName: _displayName,
      jaasAppId: join['jaas_app_id'] as String?,
      jwt: join['jwt'] as String?,
    )));
  }

  Future<void> _endMeeting(Map meeting) async {
    final ok = await AmsDialog.confirm(
      context, title: LanguageService.t('end_meeting'),
      message: 'End "${meeting['title']}" for everyone?',
      icon: Icons.call_end, iconColor: Colors.red, confirmText: 'End', danger: true,
    );
    if (ok != true) return;
    try {
      await _service.end(meeting['id'] as int);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    }
  }

  Future<void> _cancelMeeting(Map meeting) async {
    final ok = await AmsDialog.confirm(
      context, title: LanguageService.t('cancel_meeting'),
      message: 'Cancel "${meeting['title']}"? This can\'t be undone.',
      icon: Icons.delete_outline, iconColor: Colors.red, confirmText: 'Cancel Meeting', danger: true,
    );
    if (ok != true) return;
    try {
      await _service.cancel(meeting['id'] as int);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('community_meeting')),
        backgroundColor: BrandingService.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Upcoming'), Tab(text: 'Live'), Tab(text: 'Past')],
        ),
      ),
      body: _buildBody(),
      floatingActionButton: _isManager
          ? FloatingActionButton.extended(
              backgroundColor: BrandingService.primary,
              onPressed: _showScheduleForm,
              icon: const Icon(Icons.add),
              label: Text(LanguageService.t('schedule')),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
        ]),
      ));
    }
    if (_meetings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          EmptyState(icon: Icons.video_camera_front_outlined, title: 'No ${_statuses[_tabs.index]} meetings', color: BrandingService.primary),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _meetings.length,
        itemBuilder: (_, i) => _MeetingCard(
          meeting: _meetings[i],
          isManager: _isManager,
          onJoin: () => _isManager ? _startAndJoin(_meetings[i]) : _joinAsResident(_meetings[i]),
          onEnd: () => _endMeeting(_meetings[i]),
          onCancel: () => _cancelMeeting(_meetings[i]),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final Map meeting;
  final bool isManager;
  final VoidCallback onJoin;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  const _MeetingCard({required this.meeting, required this.isManager, required this.onJoin, required this.onEnd, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final status = meeting['status'] as String? ?? 'scheduled';
    final isLive = status == 'live';
    final isScheduled = status == 'scheduled';
    final scheduledAt = meeting['scheduled_at'] != null ? DateTime.tryParse(meeting['scheduled_at'] as String) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(meeting['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(LanguageService.t('live'), style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ),
          ]),
          if ((meeting['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(meeting['description'] as String, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text('by ${meeting['created_by_name'] ?? '—'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            if (scheduledAt != null) ...[
              const SizedBox(width: 12),
              Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(BrandingService.formatDateTimeShort(scheduledAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (meeting['is_joinable'] == true)
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: BrandingService.primary, foregroundColor: Colors.white),
                  icon: const Icon(Icons.videocam, size: 18),
                  label: Text(isLive ? 'Join' : (isManager ? 'Start' : 'Join')),
                  onPressed: onJoin,
                ),
              ),
            if (isManager && isLive) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: onEnd, icon: const Icon(Icons.call_end, size: 16), label: Text(LanguageService.t('end')), style: OutlinedButton.styleFrom(foregroundColor: Colors.red)),
            ],
            if (isManager && isScheduled) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.delete_outline, size: 16), label: Text(LanguageService.t('cancel')), style: OutlinedButton.styleFrom(foregroundColor: Colors.red)),
            ],
          ]),
        ]),
      ),
    );
  }
}
