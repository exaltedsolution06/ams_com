import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminTicketsScreen extends StatefulWidget {
  const AdminTicketsScreen({super.key});
  @override
  State<AdminTicketsScreen> createState() => _AdminTicketsScreenState();
}

class _AdminTicketsScreenState extends State<AdminTicketsScreen> {
  List _tickets = [];
  bool _loading = true;
  String? _error;

  static const _statusColors = {
    'open': Colors.red, 'in_progress': Colors.orange,
    'resolved': Colors.green, 'closed': Colors.grey,
  };
  static const _priorityColors = {
    'low': Colors.grey, 'normal': Colors.blue, 'high': Colors.orange, 'urgent': Colors.red,
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/tickets');
      final data = res['data'];
      setState(() {
        _tickets = (data is Map ? data['data'] : data) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('support_tickets')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(LanguageService.t('new_ticket'), style: TextStyle(color: Colors.white)),
        onPressed: () async {
          final created = await context.push('/admin/tickets/create');
          if (created == true) _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _tickets.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          EmptyState(icon: Icons.support_agent, title: LanguageService.t('no_support_tickets_yet'), color: BrandingService.primary),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                          itemCount: _tickets.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final t = _tickets[i];
                            final status = (t['status'] ?? 'open').toString();
                            final priority = (t['priority'] ?? 'normal').toString();
                            return Card(
                              child: ListTile(
                                onTap: () => context.push('/admin/tickets/${t['id']}'),
                                title: Text(t['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${t['messages_count'] ?? 0} message(s)', style: const TextStyle(fontSize: 12)),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (_statusColors[status] ?? Colors.grey).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(LanguageService.t(status).toUpperCase(),
                                          style: TextStyle(color: _statusColors[status], fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(LanguageService.t(priority).toUpperCase(),
                                        style: TextStyle(color: _priorityColors[priority], fontSize: 10)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
