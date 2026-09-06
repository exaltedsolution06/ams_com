import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/curved_header.dart';
import 'dashboard_graphics.dart';

import '../services/language_service.dart';
/// Gradient "hero" header for Apartment Admin list/detail screens (Flats,
/// Towers, Vendors, ...), replacing a plain flat AppBar with the same
/// branded gradient + soft blob decoration used on the Admin/Resident
/// dashboards, so every screen in the admin section reads as one
/// consistent, polished product instead of a mix of styles.
///
/// Drop-in usage: remove Scaffold's `appBar:` entirely and put this as the
/// first child of the Scaffold body's Column, e.g.:
///
///   body: Column(children: [
///     AdminScreenHeader(title: LanguageService.t('flats'), onRefresh: _loadAll),
///     Expanded(child: ...rest of the existing body...),
///   ]),
class AdminScreenHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;
  final List<Widget>? actions;
  final double height;

  const AdminScreenHeader({
    super.key,
    required this.title,
    this.onRefresh,
    this.actions,
    this.height = 116,
  });

  @override
  Widget build(BuildContext context) {
    return CurvedHeader(
      height: height,
      // Same "clean, mostly-square card" treatment as the dashboards/
      // referral screen - see CurvedHeader's bottomRadius doc comment.
      bottomRadius: 24,
      child: Stack(children: [
        const Positioned.fill(child: HeaderBlobs()),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 10, 14),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  // Deliberately synchronous + deferred to the next frame
                  // (rather than `await Navigator.maybePop()`) - popping the
                  // route from *inside* the tap's own event dispatch could
                  // race the framework's mouse-tracker device-update pass on
                  // desktop/web, which is what surfaced as "back arrow does
                  // nothing" followed by a mouse_tracker.dart assertion in
                  // the console. Running the actual navigation on the next
                  // frame sidesteps that race entirely.
                  final navigator = Navigator.of(context);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      context.go('/admin/dashboard');
                    }
                  });
                },
              ),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              if (actions != null) ...actions!,
              if (onRefresh != null)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  onPressed: onRefresh,
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Compact colorful stat pill used in the summary row directly under
/// [AdminScreenHeader] — a smaller, row-friendly cousin of [GradientStatTile]
/// (that one's built for 2-across grids; this one comfortably fits 3-4 in a
/// single row). Replaces the old plain icon+number+label with no card/color
/// treatment.
class AdminStatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const AdminStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.12)),
            boxShadow: [BoxShadow(color: color.withOpacity(0.14), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(9),
                boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 5, offset: const Offset(0, 2))],
              ),
              child: Icon(icon, color: Colors.white, size: 14),
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

/// Floating white row of [AdminStatChip]s that sits pulled up over the
/// header's wave edge, mirroring the "hero + sheet" layered look used on
/// the dashboards. Pass 3–4 chips.
class AdminStatRow extends StatelessWidget {
  final List<AdminStatChip> chips;
  const AdminStatRow({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: chips[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colored gradient icon "avatar" used as the leading element of list-item
/// cards (flat/tower/vendor rows, etc.) — square with rounded corners, a
/// soft colored glow shadow, replacing the old flat single-opacity tint box.
class AdminTileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final Widget? child;

  const AdminTileIcon({super.key, required this.icon, required this.color, this.size = 52, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: child ?? Icon(icon, color: Colors.white, size: size * 0.42),
    );
  }
}

/// Standard card shell for list-item rows on Admin list screens — replaces
/// bare `Card()` with a white rounded container carrying a colored border
/// tint + colored soft shadow (matching [AdminTileIcon]'s accent color)
/// instead of a flat grey Material shadow.
class AdminListCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;

  const AdminListCard({super.key, required this.child, required this.color, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.10)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
