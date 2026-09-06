import 'package:flutter/widgets.dart';

/// Tracks whether any dialog / bottom sheet (Add, Edit, confirm, etc.) is
/// currently open anywhere in the app - i.e. a popup route pushed on top
/// of the current page, as opposed to a full page navigation.
///
/// Why this exists: the floating voice-mic button (VoiceCommandButton) is
/// injected once at the app root via VoiceCommandOverlay, in a Stack drawn
/// *above* the whole routed page. showDialog/showModalBottomSheet push onto
/// that very same Navigator, so their content ends up inside that same
/// `widget.child` subtree, underneath the mic's Stack layer - which is why
/// the mic kept floating on top of every Add/Edit form's popup (like "Add
/// Advance") instead of being covered by it.
///
/// [ModalVisibilityObserver] is wired into GoRouter's own `observers:` list
/// in main.dart, so it sees every route push/pop on the single shared
/// Navigator - no per-screen wiring needed, unlike DrawerVisibility (which
/// only needs one Drawer per screen, wired explicitly there). Both
/// DialogRoute and ModalBottomSheetRoute extend [PopupRoute] under the
/// hood, while normal page navigations (GoRoute/MaterialPageRoute) don't -
/// that's the distinction used to tell "a popup opened" apart from "the
/// user navigated to a new page".
///
/// A counter (not a bool) because forms can stack a confirm dialog on top
/// of a bottom sheet - the mic should only reappear once every popup in
/// that stack has closed, not after just the topmost one.
class ModalVisibility {
  ModalVisibility._();

  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static void _increment() => openCount.value++;
  static void _decrement() {
    if (openCount.value > 0) openCount.value--;
  }
}

class ModalVisibilityObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) ModalVisibility._increment();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) ModalVisibility._decrement();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) ModalVisibility._decrement();
  }
}
