import 'package:flutter/foundation.dart';

/// Tracks whether the currently-visible screen's Scaffold `drawer:` (the
/// left sidebar, see widgets/app_drawer.dart) is open.
///
/// Why this exists: the floating voice-mic button (VoiceCommandButton) is
/// injected once at the app root via VoiceCommandOverlay, in a Stack drawn
/// *above* the whole routed page - including that page's own Drawer, since
/// the Drawer lives inside `widget.child`. Without this, the mic would float
/// on top of an open sidebar instead of sitting under it.
///
/// Every screen that sets `drawer: const AppDrawer()` on its Scaffold also
/// wires `onDrawerChanged: DrawerVisibility.onChanged` so this notifier
/// flips true/false in sync with the sidebar's open/close animation.
/// VoiceCommandOverlay listens to [isOpen] and hides the mic while true.
class DrawerVisibility {
  DrawerVisibility._();

  static final ValueNotifier<bool> isOpen = ValueNotifier<bool>(false);

  static void onChanged(bool open) => isOpen.value = open;
}
