import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../services/language_service.dart';

class AdminComplaintsScreen extends StatefulWidget {
  const AdminComplaintsScreen({super.key});
  @override
  State<AdminComplaintsScreen> createState() => _AdminComplaintsScreenState();
}

class _AdminComplaintsScreenState extends State<AdminComplaintsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _statuses = ['all', 'open', 'in_progress', 'resolved', 'closed'];
  List _complaints = [];
  bool _loading    = true;
  int  _tabIdx     = 0;

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
      final res = await ApiService().get('/admin/complaints$q');
      setState(() {
        _complaints = res['data']['data'] ?? res['data'] ?? [];
        _loading    = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showDetail(Map c) {
    final commentCtrl = TextEditingController();
    String newStatus  = c['status'] as String? ?? 'open';
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, ctrl) => StatefulBuilder(builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Text(c['title'] ?? 'Complaint',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                _StatusBadge(status: c['status'] as String? ?? 'open'),
                const SizedBox(width: 6),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.all(16),
              children: [
                FormErrorBanner(message: formError),
                _InfoRow(label: LanguageService.t('resident'),  value: c['user']?['name'] ?? '—'),
                _InfoRow(label: LanguageService.t('flat_label'), value: '${LanguageService.t('flat_label')} ${c['flat']?['flat_number'] ?? '—'}'),
                _InfoRow(label: LanguageService.t('category'),  value: c['category']?['name'] ?? '—'),
                _InfoRow(label: LanguageService.t('priority'),  value: LanguageService.t((c['priority'] ?? 'normal').toString()).toUpperCase()),
                const SizedBox(height: 12),
                Text(c['description'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 16),
                Text(LanguageService.t('comments'), style: TextStyle(fontWeight: FontWeight.bold)),
                ...((c['comments'] as List? ?? []).map((cm) => Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cm['user']?['name'] ?? '—',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 4),
                    Text(cm['comment'] ?? '', style: const TextStyle(fontSize: 13)),
                  ]),
                ))),
                const SizedBox(height: 16),
                Text(LanguageService.t('update_status'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: DropdownButtonFormField<String>(
                    value: newStatus,
                    decoration: appFieldDecoration(label: LanguageService.t('new_status'), icon: Icons.flag_outlined, accent: BrandingService.primary),
                    items: ['open','in_progress','resolved','closed'].map((s) =>
                      DropdownMenuItem(value: s, child: Text(LanguageService.t(s).toUpperCase()))
                    ).toList(),
                    onChanged: (v) => setS(() => newStatus = v!),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.update, size: 16),
                  label: Text(LanguageService.t('update_status')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BrandingService.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    setS(() => formError = null);
                    try {
                      await ApiService().post('/admin/complaints/${c['id']}/status', {'status': newStatus});
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(LanguageService.t('status_updated')), backgroundColor: Colors.green),
                      );
                    } catch (e) {
                      setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(LanguageService.t('add_comment'), style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                AppFieldShell(
                  accent: BrandingService.secondary,
                  child: TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: appFieldDecoration(hint: LanguageService.t('write_a_comment'), label: LanguageService.t('comment'), icon: Icons.comment_outlined, accent: BrandingService.secondary),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.send_outlined),
                  label: Text(LanguageService.t('post_comment')),
                  onPressed: () async {
                    if (commentCtrl.text.trim().isEmpty) return;
                    setS(() => formError = null);
                    try {
                      await ApiService().post('/admin/complaints/${c['id']}/comment',
                          {'comment': commentCtrl.text.trim()});
                      commentCtrl.clear();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(LanguageService.t('comment_added')), backgroundColor: Colors.green),
                      );
                    } catch (e) {
                      setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                    }
                  },
                ),
              ],
            )),
          ]),
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('complaints')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: pillTabBar(_tabs, _statuses.map((s) => LanguageService.t(s).toUpperCase()).toList()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _complaints.isEmpty
              ? EmptyState(
                  icon: Icons.chat_bubble_outline,
                  color: BrandingService.primary,
                  title: LanguageService.t('no_complaints_found'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _complaints.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c   = _complaints[i] as Map;
                      final pri = c['priority'] as String? ?? 'normal';
                      final pc  = _priorityColor(pri);
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withOpacity(0.05)),
                          boxShadow: [BoxShadow(color: pc.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showDetail(c),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(children: [
                                Container(
                                  width: 42, height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [pc, pc.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [BoxShadow(color: pc.withOpacity(0.32), blurRadius: 7, offset: const Offset(0, 3))],
                                  ),
                                  child: Icon(_categoryIcon(c['category']?['name'] as String? ?? ''),
                                      color: Colors.white, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c['title'] ?? '—',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  Text('${c['user']?['name'] ?? '—'}  ·  Flat ${c['flat']?['flat_number'] ?? '—'}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if ((c['description'] ?? '').toString().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(c['description'], maxLines: 2, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                    ),
                                  if (c['category'] != null)
                                    Text(c['category']['name'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                ])),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  _StatusBadge(status: c['status'] as String? ?? 'open'),
                                  const SizedBox(height: 4),
                                  if ((c['comments'] as List?)?.isNotEmpty == true)
                                    Row(children: [
                                      const Icon(Icons.chat_bubble_outline, size: 12, color: Colors.grey),
                                      const SizedBox(width: 2),
                                      Text('${(c['comments'] as List).length}',
                                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ]),
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

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':   return Colors.red;
      case 'high':     return Colors.orange;
      case 'low':      return Colors.blue;
      default:         return Colors.grey;
    }
  }

  IconData _categoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'plumbing':     return Icons.plumbing;
      case 'electrical':   return Icons.electrical_services;
      case 'lift':         return Icons.elevator;
      case 'security':     return Icons.security;
      case 'cleaning':     return Icons.cleaning_services;
      default:             return Icons.handyman;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color c;
    switch (status) {
      case 'resolved': c = Colors.green;  break;
      case 'closed':   c = Colors.grey;   break;
      case 'in_progress': c = Colors.orange; break;
      default:         c = Colors.blue;
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
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}
