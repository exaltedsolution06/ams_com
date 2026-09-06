import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../widgets/ams_dialog.dart';
import '../../services/call_visibility.dart';

import '../../services/language_service.dart';
/// Community Meeting — Premium provider (ZegoCloud), native in-app call UI.
///
/// Unlike Jitsi (Default/Free — see meeting_room_screen.dart, embedded via
/// a web view), Premium joins through ZegoCloud's own native SDK: no URL,
/// just an appID + a short-lived Token04 the backend minted for exactly
/// this user + this room (CommunityMeetingApiController::presentJoin() ->
/// App\Services\ZegoTokenService). The raw ZegoCloud ServerSecret never
/// reaches the device — only this one-hour token does.
///
/// "video meeting only for APP": this screen is intentionally never routed
/// to on Flutter Web (see CommunityMeetingScreen._openRoom) — ZegoCloud's
/// Flutter SDK targets mobile natively; Jitsi (web view / new tab) remains
/// the path for any web usage of this feature.
class ZegoMeetingRoomScreen extends StatelessWidget {
  final int appId;
  final String token;
  final String roomId;
  final String userId;
  final String userName;
  final String title;

  const ZegoMeetingRoomScreen({
    super.key,
    required this.appId,
    required this.token,
    required this.roomId,
    required this.userId,
    required this.userName,
    this.title = 'Meet Live',
  });

  @override
  Widget build(BuildContext context) => CallVisibilityScope(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (kIsWeb) {
      // Shouldn't normally be reached (see class doc), but fail safely
      // with a clear message rather than a native-plugin crash if it ever
      // is (e.g. a future web build of this screen).
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              LanguageService.t('premium_zegocloud_video_meetings_are_supported'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await AmsDialog.confirm(
          context,
          title: LanguageService.t('leave_meeting'),
          message: 'Are you sure you want to leave "$title"?',
          icon: Icons.call_end,
          iconColor: Colors.red,
          confirmText: 'Leave',
          danger: true,
        );
        if (ok == true && context.mounted) Navigator.of(context).pop();
      },
      child: ZegoUIKitPrebuiltCall(
        appID: appId,
        // Token-based auth (production-recommended) instead of appSign -
        // leave appSign empty when a token is supplied. See ZegoCloud's
        // "Use Tokens for authentication" docs.
        appSign: '',
        token: token,
        userID: userId,
        userName: userName,
        callID: roomId,
        config: ZegoUIKitPrebuiltCallConfig.groupVideoCall()
          ..topMenuBar.isVisible = true
          ..topMenuBar.buttons = []
          ..bottomMenuBar.hideAutomatically = false,
        // As of zego_uikit_prebuilt_call v4.0, onOnlySelfInRoom (along with
        // onHangUp / onMeRemovedFromRoom) was consolidated into a single
        // onCallEnd event on `events`, distinguished by `event.reason`. See:
        // https://pub.dev/documentation/zego_uikit_prebuilt_call/latest/topics/Migration_v4.x-topic.html
        events: ZegoUIKitPrebuiltCallEvents(
          onCallEnd: (event, defaultAction) {
            // Everyone else has left (remoteHangUp), the local user hung up
            // (localHangUp), or the local user was kicked out (kickOut) -
            // in every case, just close the screen back to the meeting
            // list rather than sitting alone in an empty room.
            defaultAction.call();
          },
        ),
      ),
    );
  }
}
