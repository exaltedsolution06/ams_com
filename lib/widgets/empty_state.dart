import 'package:flutter/material.dart';

/// Shared "nothing here yet" placeholder for list screens — a soft tinted
/// circle behind the icon instead of a bare grey glyph, so an empty list
/// reads as a designed state rather than a missing one. Drop-in replacement
/// for the old `Icon + SizedBox + Text` column repeated across admin/
/// resident/security list screens.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.10)),
          child: Icon(icon, size: 38, color: color.withOpacity(0.65)),
        ),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 14.5)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
          ),
        ],
      ]),
    );
  }
}

/// Compact inline "nothing here yet" row for small dashboard sections
/// (e.g. a "Your Apartments" card list) where the full-size EmptyState
/// circle would look oversized. Icon + single line of text, no card chrome.
class EmptyRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const EmptyRow({super.key, required this.icon, required this.text, this.color = Colors.grey});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.10)),
          child: Icon(icon, size: 18, color: color.withOpacity(0.7)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
      ]),
    );
  }
}

/// Rounded "pill" TabBar look — a filled rounded-rect indicator that moves
/// behind the selected label (segmented-control style) instead of the
/// default thin underline, matching the app's pill-shaped buttons/inputs
/// elsewhere. Drop-in replacement for the identical TabBar block repeated
/// across the admin Bills/Complaints/Visitors screens.
PreferredSizeWidget pillTabBar(TabController controller, List<String> labels) {
  return TabBar(
    controller: controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    indicatorSize: TabBarIndicatorSize.tab,
    indicator: BoxDecoration(
      color: Colors.white.withOpacity(0.22),
      borderRadius: BorderRadius.circular(20),
    ),
    indicatorPadding: const EdgeInsets.symmetric(vertical: 4),
    dividerColor: Colors.transparent,
    labelColor: Colors.white,
    unselectedLabelColor: Colors.white60,
    labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
    tabs: labels.map((s) => Tab(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(s),
    ))).toList(),
  );
}
