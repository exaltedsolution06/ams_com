import 'package:flutter/widgets.dart';

/// Tracks whether a Community Meeting video call (Jitsi or ZegoCloud) is
/// currently on screen, so [VoiceCommandOverlay] can hide the floating
/// voice-mic button for as long as a call is open.
///
/// Why this exists, instead of relying on the '/community-meeting' /
/// '/admin/community-meeting' entries already in VoiceCommandOverlay's
/// `_hiddenOn` list: those routes only cover the *meeting list* screen.
/// The actual call (MeetingRoomScreen / ZegoMeetingRoomScreen) is opened
/// via a plain Navigator.push on top of that list screen rather than a
/// separate GoRoute, on the assumption that go_router's reported location
/// stays unchanged throughout - which held up in theory but not in every
/// case in practice (confirmed: the mic was still visible once actually
/// inside a Jitsi call). This flag makes the hiding explicit and
/// independent of navigation mechanics entirely.
class CallVisibility {
  CallVisibility._();

  static final ValueNotifier<bool> isInCall = ValueNotifier<bool>(false);
}

/// Wrap a full-screen call widget in this so [CallVisibility.isInCall]
/// tracks its actual on-screen lifetime (set true in initState, false in
/// dispose) regardless of how many different widgets its build() method
/// conditionally returns (e.g. a web "not supported" fallback vs the real
/// call UI) - a single State object still has exactly one initState/
/// dispose pair no matter what its build() renders each time.
class CallVisibilityScope extends StatefulWidget {
  final Widget child;
  const CallVisibilityScope({super.key, required this.child});

  @override
  State<CallVisibilityScope> createState() => _CallVisibilityScopeState();
}

class _CallVisibilityScopeState extends State<CallVisibilityScope> {
  @override
  void initState() {
    super.initState();
    CallVisibility.isInCall.value = true;
  }

  @override
  void dispose() {
    CallVisibility.isInCall.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
