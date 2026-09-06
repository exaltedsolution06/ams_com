/// LITE stub for `zego_uikit_prebuilt_call`.
///
/// This file exists purely so the app compiles and runs without pulling in
/// the real ZegoCloud native SDK (the single heaviest dependency in this
/// app — see pubspec.yaml's "SIZE TOGGLE" comment). It reproduces just the
/// classes/constructor parameters that
/// lib/screens/community_meeting/zego_meeting_room_screen.dart actually
/// calls, so that file needs zero changes when you switch between LITE
/// (this stub) and FULL (the real pub.dev package) — only pubspec.yaml's
/// `zego_uikit_prebuilt_call:` entry changes.
///
/// In this LITE build, [ZegoUIKitPrebuiltCall] never actually connects to
/// anything — it just shows a "not available in this build" message. Swap
/// back to the real package (`flutter pub add zego_uikit_prebuilt_call`,
/// or uncomment the pub.dev version in pubspec.yaml) to enable real
/// Premium (ZegoCloud) video meetings.
library zego_uikit_prebuilt_call;

import 'package:flutter/material.dart';

/// Mirrors the real package's `ZegoMenuBarButtonName`-style button list
/// type closely enough for `..topMenuBar.buttons = []` to type-check.
typedef ZegoMenuBarButtonName = Object;

/// Stand-in for the real `ZegoTopMenuBarConfig`.
class ZegoTopMenuBarConfig {
  bool isVisible;
  List<ZegoMenuBarButtonName> buttons;

  ZegoTopMenuBarConfig({this.isVisible = true, List<ZegoMenuBarButtonName>? buttons})
      : buttons = buttons ?? [];
}

/// Stand-in for the real `ZegoBottomMenuBarConfig`.
class ZegoBottomMenuBarConfig {
  bool hideAutomatically;

  ZegoBottomMenuBarConfig({this.hideAutomatically = true});
}

/// Stand-in for the real `ZegoUIKitPrebuiltCallConfig`.
///
/// Only the members [zego_meeting_room_screen.dart] actually touches
/// (`topMenuBar`, `bottomMenuBar`, and the `.groupVideoCall()` factory) are
/// implemented — enough for that call site's `..` cascade to compile.
class ZegoUIKitPrebuiltCallConfig {
  ZegoTopMenuBarConfig topMenuBar;
  ZegoBottomMenuBarConfig bottomMenuBar;

  ZegoUIKitPrebuiltCallConfig({
    ZegoTopMenuBarConfig? topMenuBar,
    ZegoBottomMenuBarConfig? bottomMenuBar,
  })  : topMenuBar = topMenuBar ?? ZegoTopMenuBarConfig(),
        bottomMenuBar = bottomMenuBar ?? ZegoBottomMenuBarConfig();

  /// The real package has separate presets per call type (one-on-one voice/
  /// video, group voice/video). This stub only needs the one the app uses.
  factory ZegoUIKitPrebuiltCallConfig.groupVideoCall() => ZegoUIKitPrebuiltCallConfig();
}

/// Reason a call ended — mirrors the real package's event reason enum
/// closely enough for app code branching on it (if any is added later) to
/// keep compiling.
enum ZegoCallEndReason { localHangUp, remoteHangUp, kickOut }

/// Stand-in for the real `ZegoCallEndEvent`.
class ZegoCallEndEvent {
  final ZegoCallEndReason reason;
  const ZegoCallEndEvent({this.reason = ZegoCallEndReason.localHangUp});
}

/// Stand-in for the real `ZegoUIKitPrebuiltCallEvents`.
class ZegoUIKitPrebuiltCallEvents {
  final void Function(ZegoCallEndEvent event, VoidCallback defaultAction)? onCallEnd;

  const ZegoUIKitPrebuiltCallEvents({this.onCallEnd});
}

/// Stand-in for the real `ZegoUIKitPrebuiltCall` widget.
///
/// Renders a simple "not available in this build" screen instead of
/// connecting to anything — see the library doc above.
class ZegoUIKitPrebuiltCall extends StatelessWidget {
  final int appID;
  final String appSign;
  final String token;
  final String userID;
  final String userName;
  final String callID;
  final ZegoUIKitPrebuiltCallConfig? config;
  final ZegoUIKitPrebuiltCallEvents? events;

  const ZegoUIKitPrebuiltCall({
    super.key,
    required this.appID,
    required this.appSign,
    required this.token,
    required this.userID,
    required this.userName,
    required this.callID,
    this.config,
    this.events,
  });

  void _close(BuildContext context) {
    events?.onCallEnd?.call(
      const ZegoCallEndEvent(reason: ZegoCallEndReason.localHangUp),
      () {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Premium video meetings are not available in this build.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => _close(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
