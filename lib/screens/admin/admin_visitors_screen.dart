import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../utils/type_helpers.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';

class AdminVisitorsScreen extends StatefulWidget {
  const AdminVisitorsScreen({super.key});
  @override
  State<AdminVisitorsScreen> createState() => _AdminVisitorsScreenState();
}

class _AdminVisitorsScreenState extends State<AdminVisitorsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _statuses = ['all', 'pending', 'approved', 'checked_in', 'checked_out', 'rejected'];
  List _visitors = [];
  bool _loading  = true;
  int  _tabIdx   = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _statuses.length, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) {
          setState(() => _tabIdx = _tabs.index);
          _load();
        }
      });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = _statuses[_tabIdx];
    final q = s == 'all' ? '' : '?status=$s';
    try {
      final res = await ApiService().get('/admin/visitors$q');
      setState(() {
        _visitors = res['data']['data'] ?? res['data'] ?? [];
        _loading  = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _action(String route, String msg) async {
    try {
      await ApiService().post(route, {});
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  void _showVisitorDetail(Map v) {
    final id     = v['id'];
    final status = v['status'] as String? ?? 'pending';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.blue.withOpacity(0.1),
              child: Text((v['visitor_name'] as String? ?? '?')[0].toUpperCase(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v['visitor_name'] ?? '—',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(v['visitor_phone'] ?? '—', style: const TextStyle(color: Colors.grey)),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            _VisitorStatusBadge(status: status),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          _InfoRow(label: LanguageService.t('purpose'),   value: v['purpose'] ?? '—'),
          _InfoRow(label: LanguageService.t('resident'),  value: v['user']?['name'] ?? '—'),
          _InfoRow(label: LanguageService.t('flat'),      value: 'Flat ${v['flat']?['flat_number'] ?? '—'}'),
          if (v['vehicle_number'] != null)
            _InfoRow(label: LanguageService.t('vehicle'), value: v['vehicle_number']),
          if (v['expected_at'] != null)
            _InfoRow(label: LanguageService.t('expected'), value: friendlyDateTime(v['expected_at'])),
          if (v['checked_in_at'] != null)
            _InfoRow(label: LanguageService.t('checked_in'), value: v['checked_in_at']),
          if (v['checked_out_at'] != null)
            _InfoRow(label: LanguageService.t('checked_out'), value: v['checked_out_at']),
          const SizedBox(height: 16),
          // Action buttons based on status
          if (status == 'pending') ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.close, color: Colors.red, size: 16),
                label: Text(LanguageService.t('reject'), style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _action('/admin/visitors/$id/reject', 'Visitor rejected');
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: Text(LanguageService.t('approve')),
                onPressed: () {
                  Navigator.pop(ctx);
                  _action('/admin/visitors/$id/approve', 'Visitor approved');
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              )),
            ]),
          ] else if (status == 'approved') ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.login, size: 16),
              label: Text(LanguageService.t('check_in')),
              onPressed: () {
                Navigator.pop(ctx);
                _action('/admin/visitors/$id/checkin', 'Visitor checked in');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ] else if (status == 'checked_in') ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.logout, size: 16),
              label: Text(LanguageService.t('check_out')),
              onPressed: () {
                Navigator.pop(ctx);
                _action('/admin/visitors/$id/checkout', 'Visitor checked out');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('visitors')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: pillTabBar(_tabs, _statuses.map((s) => LanguageService.t(s).toUpperCase()).toList()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _visitors.isEmpty
              ? EmptyState(
                  icon: Icons.badge_outlined,
                  color: BrandingService.primary,
                  title: LanguageService.t('no_visitors_found'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _visitors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final v      = _visitors[i] as Map;
                      final status = v['status'] as String? ?? 'pending';
                      final sc     = _statusColor(status);
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withOpacity(0.05)),
                          boxShadow: [BoxShadow(color: sc.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showVisitorDetail(v),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(children: [
                                Container(
                                  width: 44, height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [sc, sc.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: sc.withOpacity(0.32), blurRadius: 8, offset: const Offset(0, 3))],
                                  ),
                                  child: const Icon(Icons.person_outline, color: Colors.white, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(v['visitor_name'] ?? '—',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text(v['visitor_phone'] ?? '—',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    '→ ${v['user']?['name'] ?? '—'}  ·  Flat ${v['flat']?['flat_number'] ?? '—'}',
                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                  ),
                                ])),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  _VisitorStatusBadge(status: status),
                                  const SizedBox(height: 4),
                                  Text(v['purpose'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ]),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'approved':    return Colors.green;
      case 'checked_in':  return Colors.teal;
      case 'checked_out': return Colors.grey;
      case 'rejected':    return Colors.red;
      default:            return Colors.orange;
    }
  }
}

class _VisitorStatusBadge extends StatelessWidget {
  final String status;
  const _VisitorStatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'approved':    c = Colors.green;  break;
      case 'checked_in':  c = Colors.teal;   break;
      case 'checked_out': c = Colors.grey;   break;
      case 'rejected':    c = Colors.red;    break;
      default:            c = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(LanguageService.t(status).toUpperCase(),
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
  );
}
