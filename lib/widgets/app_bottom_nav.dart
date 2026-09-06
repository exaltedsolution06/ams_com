import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/branding_service.dart';

/// A single destination in the bottom nav.
class NavItem {
  final IconData icon;
  final String label;
  final String route;
  /// true  → context.go   (Home tab: resets the stack)
  /// false → context.push (everything else: back button works)
  final bool isHome;
  /// Outside the apartment's current plan (Menu Visibility = "All", Super
  /// Admin > Apartment > Edit). Shown dimmed with a padlock; tapping shows
  /// an upgrade notice instead of navigating.
  final bool locked;
  const NavItem({required this.icon, required this.label, required this.route, this.isHome = false, this.locked = false});
}

/// Modern floating bottom nav: a rounded "pill" bar with 4 flanking icons
/// and one raised circular button in the centre for the single most
/// important action (mirrors the mechanic/plant-shop reference designs).
/// Keeps the existing side drawer - this is an additive fast-access strip
/// for the handful of things used every day, not a full IndexedStack tab
/// system, since every screen already has its own back-stack via GoRouter.
class AppBottomNav extends StatelessWidget {
  final List<NavItem> items; // exactly 4: [left, left, right, right]
  final NavItem centerItem;
  final String currentRoute;
  // How far the pill sits from each screen edge. Defaults (12/12) match the
  // original edge-to-edge pill used on admin/security dashboards. Dashboard
  // screen passes a larger [leftInset] to narrow the pill and free up space
  // on the left for the voice mic to dock in by default (see
  // VoiceCommandOverlay) - this widget stays visually identical everywhere
  // else since nothing else overrides these.
  final double leftInset;
  final double rightInset;

  const AppBottomNav({
    super.key,
    required this.items,
    required this.centerItem,
    required this.currentRoute,
    this.leftInset = 12,
    this.rightInset = 12,
  });

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'AppBottomNav expects exactly 4 flanking items');
    final primary = BrandingService.primary;
    final accent  = BrandingService.accent;

    return SizedBox(
      height: 84,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // The pill-shaped bar itself
          Positioned(
            left: leftInset, right: rightInset, bottom: 10,
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                // Faint vertical gradient (rather than flat white) gives the
                // bar a subtle glossy, raised feel instead of a flat card.
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.white, const Color(0xFFFCFCFF)],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white, width: 1),
                boxShadow: [
                  BoxShadow(color: primary.withOpacity(0.18), blurRadius: 24, offset: const Offset(0, 10)),
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navIcon(context, items[0], primary),
                  _navIcon(context, items[1], primary),
                  const SizedBox(width: 10), // extra breathing room before the centre button gap
                  const SizedBox(width: 60), // gap for the raised centre button
                  _navIcon(context, items[2], primary),
                  _navIcon(context, items[3], primary),
                ],
              ),
            ),
          ),
          // Raised centre button. Positioned with the SAME left/right insets
          // as the pill (rather than relying on the outer Stack's
          // bottomCenter alignment, which only centers over the full screen
          // width) so it stays centred over the pill's own gap even when
          // leftInset != rightInset.
          Positioned(
            left: leftInset, right: rightInset, bottom: 32,
            child: Center(
              child: GestureDetector(
              onTap: () => _navigate(context, centerItem),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Soft outer halo — gives the button a glowing "spotlight"
                  // presence rather than sitting flat against the bar.
                  Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.14)),
                  ),
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [accent, _deepen(accent)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: accent.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 8)),
                        BoxShadow(color: accent.withOpacity(0.25), blurRadius: 4, offset: const Offset(0, 1)),
                      ],
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(centerItem.icon, color: Colors.white.withOpacity(centerItem.locked ? 0.55 : 1), size: 27),
                        if (centerItem.locked)
                          Positioned(
                            right: 2, bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
                              child: const Icon(Icons.lock, size: 10, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _deepen(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor();
  }

  Widget _navIcon(BuildContext context, NavItem item, Color primary) {
    final active = currentRoute == item.route;
    return GestureDetector(
      onTap: () => _navigate(context, item),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minWidth: 48),
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: active ? 12 : 10),
        decoration: BoxDecoration(
          // Soft tinted "pill" behind the active tab — much easier to spot
          // at a glance than a plain color swap + tiny dot.
          color: active ? primary.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(item.icon, size: 21, color: item.locked ? Colors.grey[300] : (active ? primary : Colors.grey[500])),
                if (item.locked)
                  Positioned(
                    right: -3, top: -3,
                    child: Icon(Icons.lock, size: 10, color: Colors.grey[500]),
                  ),
              ],
            ),
            // Active label — animates in beside the icon so the current
            // section is legible, not just "some icon turned blue". Skipped
            // for the Home tab: its icon alone is unambiguous, and the label
            // ("Home"/"Dashboard") was extra clutter on the first tab.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: (active && !item.isHome)
                  ? Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        item.label,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primary),
                      ),
                    )
                  : const SizedBox(width: 0, height: 0),
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, NavItem item) {
    if (item.locked) {
      _showLockedNotice(context, item.label);
      return;
    }
    if (item.route == currentRoute) return;
    if (item.isHome) {
      context.go(item.route);
    } else {
      context.push(item.route);
    }
  }

  void _showLockedNotice(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label isn\'t included in your current plan. Contact your Apartment Admin to upgrade.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
