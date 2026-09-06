import 'package:flutter/material.dart';
import '../main.dart' show router;
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/call_visibility.dart';
import '../services/drawer_state.dart';
import '../services/modal_visibility.dart';
import 'voice_command_button.dart';

/// Wraps the router's current page so a floating mic button is available
/// everywhere EXCEPT the public/pre-auth screens (login, force-update,
/// terms/privacy) - mirrors the `alwaysPublic`/`authOnlyPages` lists in
/// main.dart's GoRouter redirect logic. Plugged in via MaterialApp.router's
/// `builder` param so it doesn't need to be added to every single screen.
class VoiceCommandOverlay extends StatefulWidget {
  final Widget? child;
  const VoiceCommandOverlay({super.key, required this.child});

  @override
  State<VoiceCommandOverlay> createState() => _VoiceCommandOverlayState();
}

class _VoiceCommandOverlayState extends State<VoiceCommandOverlay> {
  // Routes where the floating mic is hidden entirely, regardless of the
  // per-apartment voice_mic_enabled setting - it would otherwise overlap
  // the chat message composer, or float awkwardly over an active/joining
  // video call. Meeting-room screens (MeetingRoomScreen/
  // ZegoMeetingRoomScreen) are pushed via Navigator.push rather than
  // go_router, so the reported location stays '/community-meeting' or
  // '/admin/community-meeting' the whole time the user is actually inside
  // a call too - no separate route needed for those.
  static const _hiddenOn = [
    '/login', '/forgot-password', '/force-update', '/terms', '/privacy',
    '/chat', '/community-meeting', '/admin/community-meeting',
  ];

  // The only 3 routes that use AppBottomNav (the pill bar with the raised
  // centre button) as their Scaffold's bottomNavigationBar - see
  // dashboard_screen.dart / admin_dashboard_screen.dart /
  // security_dashboard_screen.dart. Every other screen either has no bottom
  // bar at all, or a plain FloatingActionButton (always bottom-RIGHT, never
  // relocated anywhere in this codebase - see the "add" FABs on visitors,
  // complaints, residents, etc.), so anchoring the mic bottom-LEFT keeps it
  // clear of both without needing per-screen plumbing.
  static const _bottomNavRoutes = ['/dashboard', '/admin/dashboard', '/security/dashboard'];

  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _refreshAuth();
  }

  Future<void> _refreshAuth() async {
    final loggedIn = await AuthService().isLoggedIn();
    if (mounted && loggedIn != _loggedIn) setState(() => _loggedIn = loggedIn);
  }

  @override
  Widget build(BuildContext context) {
    // router.routerDelegate is a Listenable that fires on every navigation,
    // so AnimatedBuilder rebuilds this exactly when the current route (and
    // therefore mic visibility) might have changed.
    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        // Re-check auth on every rebuild (cheap SharedPreferences/secure-
        // storage read) so the mic appears right after login and disappears
        // after logout without needing a dedicated auth-state stream.
        _refreshAuth();

        final location = router.routerDelegate.currentConfiguration.uri.path;
        // Apartment > Edit > "Show Voice Mic Icon in App" (default on, Super
        // Admin/Company Admin) AND Profile > "Voice Mic" (default on, this
        // person's own preference) both have to be true - see
        // BrandingService.voiceMicEnabled / AuthService.wantsVoiceMic.
        final showMic = _loggedIn && BrandingService.voiceMicEnabled && AuthService.wantsVoiceMic && !_hiddenOn.contains(location);

        // All 3 bottom-nav dashboards (resident/admin/security) now give
        // AppBottomNav a wider `leftInset` (see their screen files) that
        // shifts the pill right and frees a clear strip on the left, from
        // x=0 to x=leftInset(64). Centre the 54-wide mic box in that strip
        // ((64-54)/2 = 5) so the gap to the screen edge and the gap to the
        // pill are equal, instead of nearly touching the pill.
        final hasBottomNav = _bottomNavRoutes.contains(location);
        const dashboardMicClearance = 18.0; // (pill band centre 42) - (mic half-height 24)
        const dashboardMicLeft = 5.0; // (64 leftInset - 54 mic box) / 2, equal margin both sides
        // Non-nav pages: dock right at the literal screen edge, not offset
        // by the device's bottom safe-area inset - adding that inset was
        // leaving a large empty gap below the icon on devices/emulators
        // with a sizable bottom inset, instead of it actually sitting at
        // the bottom of the screen as requested.
        const plainClearance = 6.0;
        // NOTE: intentionally NOT adding MediaQuery.padding.bottom here for
        // the bottom-nav case. AppBottomNav's own pill is positioned purely
        // within its own SizedBox (bottom: 10, no safe-area padding added),
        // so adding the safe-area inset only on the mic's side pushed it
        // higher than the pill's true centre on devices with a home
        // indicator / gesture bar - the mic ended up sitting above-centre
        // instead of level with the pill. Using the same flat clearance the
        // pill effectively uses keeps the two vertically aligned.
        final bottomOffset = hasBottomNav ? dashboardMicClearance : plainClearance;
        final leftOffset = hasBottomNav ? dashboardMicLeft : 16.0;

        // Keyboard open (any Add/Edit form's text field focused) - the mic
        // used to be positioned from the root MediaQuery's `size.height`,
        // which shrinks on Android when the keyboard resizes the window,
        // so the calculated top offset kept shrinking too and the icon
        // visibly climbed up the screen following the keyboard. The mic
        // has no use while typing anyway, so just hide it for as long as
        // the keyboard is up, the same way it's hidden for an open Drawer.
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

        return Stack(children: [
          if (widget.child != null) widget.child!,
          // Always present (not gated behind `if (showMic...)` like the
          // rest below) so it reacts to a call starting/ending on its own,
          // via CallVisibility's own ValueNotifier - regardless of whether
          // this whole AnimatedBuilder happens to rebuild at that exact
          // moment. That distinction matters: entering a video call is a
          // plain Navigator.push on top of the already-hidden
          // '/community-meeting' page, which doesn't reliably trigger a
          // rebuild here - '/community-meeting' being in `_hiddenOn` was
          // NOT enough on its own; the mic was still visible once actually
          // inside a live Jitsi call.
          ValueListenableBuilder<bool>(
            valueListenable: CallVisibility.isInCall,
            builder: (context, inCall, _) {
              if (!showMic || keyboardOpen || inCall) return const SizedBox.shrink();
              // Hide the mic while any dialog/bottom-sheet Add/Edit form is
              // open (e.g. "Add Advance") - those popups render inside this
              // same `widget.child` subtree, underneath the mic's Stack
              // layer, so without this the mic kept floating on top of them.
              // See modal_visibility.dart for how open/close is tracked.
              return ValueListenableBuilder<int>(
                valueListenable: ModalVisibility.openCount,
                builder: (context, popupCount, _) {
                  // Also hide the mic while a screen's sidebar (Drawer) is
                  // open, so it never floats visually above the open sidebar
                  // - see drawer_state.dart for how screens report
                  // drawer open/close.
                  return ValueListenableBuilder<bool>(
                    valueListenable: DrawerVisibility.isOpen,
                    builder: (context, drawerOpen, _) {
                      // IMPORTANT: hide via Visibility(maintainState: true),
                      // NOT by conditionally returning SizedBox.shrink().
                      // ModalVisibility's counter goes up for EVERY PopupRoute
                      // - including the mic's own listening sheet
                      // (_listenSheet() is itself a showModalBottomSheet). If
                      // this widget is swapped out of the tree for a
                      // SizedBox while that sheet is open, VoiceCommandButton's
                      // State (mid-_start(), awaiting the sheet's result) gets
                      // disposed right then. It comes back as a brand-new
                      // State once the sheet closes and popupCount drops back
                      // to 0 - but the OLD State's `await _listenSheet()` call
                      // resumes into a State whose `mounted` is now false, so
                      // its `if (!mounted) return;` right after silently
                    // aborts before the heard text is ever parsed or acted
                    // on. That's the "mic sheet opens, shows what I said,
                    // closes, then nothing happens" symptom - Visibility
                    // keeps the subtree (and its State) alive the whole
                    // time, just invisible and non-hit-testable, so the
                    // in-flight _start() survives its own sheet closing.
                    final hideMic = popupCount > 0 || drawerOpen;
                    // Positioned must stay the direct wrapper here (with
                    // Visibility nested inside it), not the other way
                    // around: Visibility(maintainState: true) hides its
                    // child via an internal Offstage, and Positioned needs
                    // Stack as its immediate ancestor to apply its
                    // StackParentData - if Offstage sat between them
                    // instead, that would throw at runtime.
                    return Positioned(
                      left: leftOffset,
                      bottom: bottomOffset,
                      child: Visibility(
                        visible: !hideMic,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: false,
                        child: const VoiceCommandButton(),
                      ),
                    );
                  },
                );
              },
            );
          },
          ),
        ]);
      },
    );
  }
}

