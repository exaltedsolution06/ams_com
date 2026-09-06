import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/admin_screen_header.dart';
import '../../widgets/dashboard_graphics.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

const _kBg = Color(0xFFF4F6FA);

// ── Complaints Report ─────────────────────────────────────────────────────────
class AdminReportsComplaintsScreen extends StatefulWidget {
  const AdminReportsComplaintsScreen({super.key});
  @override
  State<AdminReportsComplaintsScreen> createState() => _CState();
}

class _CState extends State<AdminReportsComplaintsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true; String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/reports/complaints');
      setState(() { _data = (res['data'] as Map?)?.cast<String,dynamic>(); _loading = false; });
    } catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final total   = (_data?['total'] as int?) ?? 0;
    final open        = (_data?['open'] as int?) ?? 0;
    final inProgress  = (_data?['in_progress'] as int?) ?? 0;
    final resolved    = (_data?['resolved'] as int?) ?? 0;
    final closed      = (_data?['closed'] as int?) ?? 0;
    final resolvedPct = total > 0 ? (resolved + closed) / total : 0.0;

    return Scaffold(
      backgroundColor: _kBg,
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: Column(children: [
        AdminScreenHeader(title: LanguageService.t('complaints_report'), onRefresh: _load),
        if (!_loading && _error == null && _data != null)
          AdminStatRow(chips: [
            AdminStatChip(label: LanguageService.t('total'), value: '$total', icon: Icons.assignment_outlined, color: primary),
            AdminStatChip(label: LanguageService.t('open'), value: '$open', icon: Icons.mark_chat_unread_outlined, color: Colors.blue),
            AdminStatChip(label: LanguageService.t('resolved'), value: '$resolved', icon: Icons.check_circle_outline, color: Colors.green),
          ]),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 10),
                      ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                    ]))
                  : _data == null
                      ? Center(child: Text(LanguageService.t('no_data_2')))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(16, _loading ? 16 : 0, 16, 16),
                            children: [
                              // Resolution rate + status breakdown
                              InsightCard(
                                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                  StatRing(
                                    percent: resolvedPct,
                                    color: Colors.green,
                                    size: 92,
                                    strokeWidth: 11,
                                    center: Text('${(resolvedPct * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.green)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(LanguageService.t('resolution_rate'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text('$resolved of $total complaints resolved or closed',
                                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                                      const SizedBox(height: 10),
                                      _legendDot(Colors.blue, 'Open', open),
                                      const SizedBox(height: 6),
                                      _legendDot(Colors.orange, 'In Progress', inProgress),
                                      const SizedBox(height: 6),
                                      _legendDot(Colors.green, 'Resolved', resolved),
                                      const SizedBox(height: 6),
                                      _legendDot(Colors.grey, 'Closed', closed),
                                    ]),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 12),
                              // Avg resolution time + a quick status glance
                              Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Expanded(
                                  child: InsightCard(
                                    child: Column(children: [
                                      Icon(Icons.timer_outlined, color: Colors.teal, size: 22),
                                      const SizedBox(height: 6),
                                      Text('${_data!['avg_resolution_days'] ?? '—'}',
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.teal)),
                                      const SizedBox(height: 2),
                                      Text(LanguageService.t('avg_days_to_resolve'), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                                    ]),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InsightCard(
                                    child: Column(children: [
                                      Text(LanguageService.t('by_status'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
                                      const SizedBox(height: 6),
                                      ComparisonBarChart(items: [
                                        BarChartItem(label: LanguageService.t('open'), value: open, color: Colors.blue),
                                        BarChartItem(label: LanguageService.t('in_prog'), value: inProgress, color: Colors.orange),
                                        BarChartItem(label: LanguageService.t('resolved'), value: resolved, color: Colors.green),
                                        BarChartItem(label: LanguageService.t('closed'), value: closed, color: Colors.grey),
                                      ]),
                                    ]),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 20),
                              // By category
                              if ((_data!['by_category'] as List?)?.isNotEmpty == true) ...[
                                Text(LanguageService.t('by_category'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 10),
                                ...(_data!['by_category'] as List).map((cat) {
                                  final c = cat as Map;
                                  final count = c['count'] as int? ?? 0;
                                  final pct = total > 0 ? count / total : 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: AdminListCard(
                                      color: primary,
                                      child: Row(children: [
                                        AdminTileIcon(icon: Icons.handyman_outlined, color: primary, size: 40),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(c['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: pct, minHeight: 7,
                                                backgroundColor: primary.withOpacity(0.1),
                                                valueColor: AlwaysStoppedAnimation(primary),
                                              ),
                                            ),
                                          ]),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                          Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 16)),
                                          Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        ]),
                                      ]),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label, int value) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87))),
    Text('$value', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
  ]);
}

// ── Occupancy Report ──────────────────────────────────────────────────────────
class AdminReportsOccupancyScreen extends StatefulWidget {
  const AdminReportsOccupancyScreen({super.key});
  @override
  State<AdminReportsOccupancyScreen> createState() => _OState();
}

class _OState extends State<AdminReportsOccupancyScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true; String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/reports/occupancy');
      setState(() { _data = (res['data'] as Map?)?.cast<String,dynamic>(); _loading = false; });
    } catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final totalFlats   = (_data?['total_flats'] as int?) ?? 0;
    final occupied     = (_data?['occupied_flats'] as int?) ?? 0;
    final vacant       = (_data?['vacant_flats'] as int?) ?? 0;
    final owners       = (_data?['owner_occupied'] as int?) ?? 0;
    final tenants      = (_data?['tenant_occupied'] as int?) ?? 0;
    final residents    = (_data?['total_residents'] as int?) ?? 0;
    final occRate      = totalFlats > 0 ? occupied / totalFlats : 0.0;

    return Scaffold(
      backgroundColor: _kBg,
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: Column(children: [
        AdminScreenHeader(title: LanguageService.t('occupancy_report'), onRefresh: _load),
        if (!_loading && _error == null && _data != null)
          AdminStatRow(chips: [
            AdminStatChip(label: LanguageService.t('occupied'), value: '$occupied', icon: Icons.home_outlined, color: Colors.green),
            AdminStatChip(label: LanguageService.t('vacant'), value: '$vacant', icon: Icons.house_outlined, color: Colors.orange),
            AdminStatChip(label: LanguageService.t('rate'), value: '${(occRate * 100).toStringAsFixed(0)}%', icon: Icons.pie_chart_outline, color: primary),
          ]),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 10),
                      ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                    ]))
                  : _data == null
                      ? Center(child: Text(LanguageService.t('no_data_2')))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(16, _loading ? 16 : 0, 16, 16),
                            children: [
                              // Occupancy rate + owner/tenant/resident split
                              InsightCard(
                                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                  StatRing(
                                    percent: occRate,
                                    color: primary,
                                    size: 92,
                                    strokeWidth: 11,
                                    center: Text('${(occRate * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: primary)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(LanguageService.t('occupancy'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(height: 2),
                                      Text('$occupied of $totalFlats flats occupied',
                                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                                      const SizedBox(height: 10),
                                      _legendDot(primary, 'Owners', owners),
                                      const SizedBox(height: 6),
                                      _legendDot(Colors.teal, 'Tenants', tenants),
                                      const SizedBox(height: 6),
                                      _legendDot(Colors.purple, 'Residents', residents),
                                    ]),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 12),
                              // Full stat grid
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 190, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.9,
                                ),
                                itemCount: 6,
                                itemBuilder: (_, i) {
                                  const items = [
                                    ['Total Flats', Icons.apartment_outlined, Colors.blue],
                                    ['Occupied', Icons.home_outlined, Colors.green],
                                    ['Vacant', Icons.house_outlined, Colors.orange],
                                    ['Owners', Icons.key_outlined, null],
                                    ['Tenants', Icons.badge_outlined, Colors.teal],
                                    ['Residents', Icons.groups_outlined, Colors.purple],
                                  ];
                                  final values = [totalFlats, occupied, vacant, owners, tenants, residents];
                                  final label = items[i][0] as String;
                                  final icon  = items[i][1] as IconData;
                                  final color = (items[i][2] as Color?) ?? primary;
                                  return GradientStatTile(label: label, value: values[i], icon: icon, color: color);
                                },
                              ),
                              const SizedBox(height: 20),
                              // By tower
                              if ((_data!['by_tower'] as List?)?.isNotEmpty == true) ...[
                                Text(LanguageService.t('by_tower'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 10),
                                ...(_data!['by_tower'] as List).map((t) {
                                  final tower    = t as Map;
                                  final tTotal   = tower['total'] as int?   ?? 0;
                                  final tOccup   = tower['occupied'] as int? ?? 0;
                                  final pct      = tTotal > 0 ? tOccup / tTotal : 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: AdminListCard(
                                      color: primary,
                                      child: Row(children: [
                                        AdminTileIcon(icon: Icons.cell_tower_outlined, color: primary, size: 40),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Row(children: [
                                              Expanded(child: Text(tower['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                                              Text('$tOccup / $tTotal', style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 13)),
                                            ]),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: pct, minHeight: 7,
                                                backgroundColor: primary.withOpacity(0.1),
                                                valueColor: AlwaysStoppedAnimation(primary),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text('${(pct * 100).toStringAsFixed(0)}% occupied', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ]),
                                        ),
                                      ]),
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label, int value) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87))),
    Text('$value', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
  ]);
}
