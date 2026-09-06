import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/branding_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/empty_state.dart';

import '../services/language_service.dart';
/// Generic admin list screen used by Towers, Floors, Flats,
/// General Categories, Vendors, Bookings, etc.
///
/// Back button fix: uses context.canPop() so pressing back always
/// returns to the previous screen regardless of how the user got here.
class AdminListScreen extends StatefulWidget {
  final String title, apiPath;
  final String emptyMessage;
  final IconData emptyIcon;
  final Widget Function(Map item, VoidCallback reload) itemBuilder;
  final Widget? fab;
  final List<Widget>? actions;
  final Widget? filterBar; // optional filter bar below app bar

  const AdminListScreen({
    super.key,
    required this.title,
    required this.apiPath,
    required this.itemBuilder,
    this.emptyMessage = 'No records found',
    this.emptyIcon    = Icons.inbox_outlined,
    this.fab,
    this.actions,
    this.filterBar,
  });

  @override
  State<AdminListScreen> createState() => _AdminListScreenState();
}

class _AdminListScreenState extends State<AdminListScreen> {
  List    _items   = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get(widget.apiPath);
      dynamic raw = res['data'];
      if (raw is Map && raw.containsKey('data')) raw = raw['data'];
      setState(() { _items = List.from(raw ?? []); _loading = false; });
    } catch (e) {
      setState(() {
        _error   = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Safe back: pops if possible, falls back to admin dashboard.
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/admin/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ── Back button always works ──────────────────────────────────
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
        title: Text(widget.title),
        actions: [
          ...?widget.actions,
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: widget.fab,
      body: Column(children: [
        if (widget.filterBar != null) widget.filterBar!,
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(LanguageService.t('retry')),
            onPressed: _load),
      ]));
    }

    if (_items.isEmpty) {
      return EmptyState(icon: widget.emptyIcon, title: widget.emptyMessage, color: BrandingService.primary);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => widget.itemBuilder(_items[i] as Map, _load),
      ),
    );
  }
}

// ── Reusable InfoCard ────────────────────────────────────────────────────────
class InfoCard extends StatelessWidget {
  final String  title;
  final String? subtitle, badge;
  final IconData icon;
  final Color?  iconColor, badgeColor;
  final VoidCallback? onTap;
  final List<Widget>? trailing;

  const InfoCard({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.badge,
    this.iconColor,
    this.badgeColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? BrandingService.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
              ],
            )),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: (badgeColor ?? BrandingService.primary).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(badge!, style: TextStyle(
                    color: badgeColor ?? BrandingService.primary,
                    fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ...?trailing,
          ]),
        ),
      ),
    );
  }
}
