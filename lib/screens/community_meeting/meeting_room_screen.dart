import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../services/branding_service.dart';
import '../../services/call_visibility.dart';
import '../../widgets/ams_dialog.dart';

import '../../services/language_service.dart';
/// Embeds a Community Meeting room in a web view.
///
/// Phase 1 (Default/Free): loads the Jitsi room directly. Two backends are
/// possible here, decided server-side by whether the Super Admin has
/// configured JaaS credentials (see CommunityMeetingApiController):
///   - No JaaS configured (the historical default): the public
///     https://meet.jit.si/<room>, no [jwt] passed. IMPORTANT - as of
///     August 2023 this public server requires the first person into a
///     room to log in with Google/GitHub/Microsoft to become moderator,
///     which this bare WebView has no way to complete. If "join meeting"
///     silently gets stuck, this is almost certainly why - configure JaaS
///     in Admin > Settings > Video Conferencing to fix it.
///   - JaaS configured: https://8x8.vc/<jaasAppId>/<room>, with a [jwt]
///     this app already signed server-side per join (see
///     JaasTokenService) - authenticated from the first join, no login
///     wall.
///
/// Either way this stays a plain URL load - no app credentials or native
/// SDK needed, just a browser engine capable of WebRTC (getUserMedia),
/// which a modern WKWebView / Android System WebView already provides.
///
/// IMPORTANT — native permissions this project's zip can't add for you:
/// this repo has no android/ios folders, so the following must be added by
/// hand in your real Flutter project before camera/mic will work here:
///   Android (android/app/src/main/AndroidManifest.xml):
///     <uses-permission android:name="android.permission.CAMERA" />
///     <uses-permission android:name="android.permission.RECORD_AUDIO" />
///     <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
///   iOS (ios/Runner/Info.plist):
///     <key>NSCameraUsageDescription</key><string>Used to join Community Meeting video calls.</string>
///     <key>NSMicrophoneUsageDescription</key><string>Used to join Community Meeting video calls.</string>
///   iOS also needs Podfile min platform :ios, '14.0' or higher for WKWebView
///   getUserMedia support.
///
/// Web is deliberately NOT embedded via webview_flutter: that package has
/// no built-in web implementation (WebViewPlatform.instance is null on
/// web unless you separately add the `webview_flutter_web` package - and
/// even then it's an unendorsed, "severely limited" implementation per its
/// own pub.dev description, missing the navigation-delegate/permission
/// APIs this screen relies on). Simpler and more reliable: open the Jitsi
/// room in a new browser tab instead, where the browser's own camera/mic
/// permission prompt just works.
///
/// Phase 2 (Premium/ZegoCloud) will likely replace this screen's body with
/// the native ZegoCloud SDK view instead of a web view, for a proper
/// in-app call UI (PIP, better performance, etc) on mobile.
class MeetingRoomScreen extends StatefulWidget {
  final String roomId;
  final String jitsiDomain;
  final String title;
  final String displayName;
  /// Non-null only when the backend's presentJoin() used JaaS - see class doc.
  final String? jaasAppId;
  /// The signed join JWT, paired with [jaasAppId]. Null on the public server.
  final String? jwt;

  const MeetingRoomScreen({
    super.key,
    required this.roomId,
    required this.title,
    this.jitsiDomain = 'meet.jit.si',
    this.displayName = '',
    this.jaasAppId,
    this.jwt,
  });

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  late final String _meetingUrl;

  @override
  void initState() {
    super.initState();
    // See CallVisibilityScope's doc for why this is set directly here
    // rather than wrapping the widget - this State already has a single
    // well-defined initState/dispose pair to hook into.
    CallVisibility.isInCall.value = true;

    // #config.* and #userInfo.* URL fragment params configure the Jitsi web
    // client without needing their JS API/iframe embed: hide the pre-join
    // "lobby" prejoin screen to go straight into the call, and pre-fill the
    // participant's display name from their AMS profile.
    //
    // JaaS (jwt != null): the room is prefixed with the JaaS App ID
    // (https://8x8.vc/<appId>/<room>) and the signed JWT is passed as a
    // query param - that's how 8x8.vc's web client accepts a direct join
    // link (see JaasTokenService's doc comment re: verifying this against
    // a real JaaS meeting). displayName isn't set via the hash here since
    // JaaS already bakes the name into the JWT itself (context.user.name).
    final nameParam = Uri.encodeComponent(widget.displayName);
    final roomPath = widget.jaasAppId != null
        ? '${widget.jaasAppId}/${widget.roomId}'
        : widget.roomId;
    final jwtParam = widget.jwt != null ? '?jwt=${widget.jwt}' : '';
    // JaaS already carries the display name inside the JWT itself, so the
    // hash param is only needed on the public server.
    final displayNameParam = widget.jwt == null ? '&userInfo.displayName="$nameParam"' : '';
    _meetingUrl = 'https://${widget.jitsiDomain}/$roomPath$jwtParam'
        '#config.prejoinPageEnabled=false'
        '&config.disableDeepLinking=true'
        '$displayNameParam';

    if (kIsWeb) {
      // No in-app embed on web - see class doc. Open the tab right away so
      // the user doesn't have to find/tap the fallback button first.
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInNewTab());
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(_meetingUrl));

    // Android-only setup, reached via `.platform` + a cast because these
    // methods live on AndroidWebViewController (webview_flutter_android),
    // not on the common WebViewController API. iOS doesn't need either of
    // these - WKWebView grants camera/mic and autoplays remote media once
    // the Info.plist usage-description keys (see class doc above) are
    // present.
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      // Without this, Android's WebView applies its normal "media needs a
      // user tap first" autoplay policy to Jitsi's incoming remote
      // audio/video too - the call connects, camera/mic permission is
      // granted, but the other participants' AUDIO stays silent (and
      // sometimes video frozen) until the user happens to tap something
      // inside the page. This is the most common cause of "joined the
      // meeting but can't hear anyone."
      platform.setMediaPlaybackRequiresUserGesture(false);

      // Grants the camera/mic permission prompt Jitsi's WebRTC call makes
      // on Android - without this, Android's WebView silently denies it
      // and the call joins audio/video-muted with no visible error.
      platform.setOnPlatformPermissionRequest((request) => request.grant());
    }
  }

  @override
  void dispose() {
    CallVisibility.isInCall.value = false;
    super.dispose();
  }

  Future<void> _openInNewTab() async {
    await launchUrl(Uri.parse(_meetingUrl), webOnlyWindowName: '_blank');
  }

  Future<bool> _confirmLeave() async {
    final ok = await AmsDialog.confirm(
      context,
      title: LanguageService.t('leave_meeting'),
      message: 'Are you sure you want to leave "${widget.title}"?',
      icon: Icons.call_end,
      iconColor: Colors.red,
      confirmText: 'Leave',
      danger: true,
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            tooltip: LanguageService.t('leave'),
            onPressed: () async {
              if (await _confirmLeave() && mounted) Navigator.of(context).pop();
            },
          ),
        ),
        body: Stack(
          children: [
            if (kIsWeb) _buildWebFallback() else WebViewWidget(controller: _controller),
            if (_loading)
              Container(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(color: BrandingService.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Web has no in-app embed (see class doc) - a new tab was already
  /// launched automatically; this is what's left behind in the app tab,
  /// with a button in case the browser blocked the automatic popup.
  Widget _buildWebFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              LanguageService.t('your_meeting_opened_in_a_new_browser_tab'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              LanguageService.t('if_nothing_opened_your_browser_may_have_blocked'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openInNewTab,
              icon: const Icon(Icons.videocam_rounded),
              label: Text(LanguageService.t('join_meeting')),
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandingService.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
