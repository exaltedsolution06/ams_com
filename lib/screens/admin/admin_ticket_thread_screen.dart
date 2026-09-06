import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';

class AdminTicketThreadScreen extends StatefulWidget {
  final int ticketId;
  const AdminTicketThreadScreen({super.key, required this.ticketId});
  @override
  State<AdminTicketThreadScreen> createState() => _AdminTicketThreadScreenState();
}

class _AdminTicketThreadScreenState extends State<AdminTicketThreadScreen> {
  Map<String, dynamic>? _ticket;
  bool _loading = true;
  String? _error;
  int? _myUserId;
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  static const _statusColors = {
    'open': Colors.red, 'in_progress': Colors.orange,
    'resolved': Colors.green, 'closed': Colors.grey,
  };

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final user = await AuthService().getUser();
    _myUserId = user?['id'] as int?;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/admin/tickets/${widget.ticketId}');
      setState(() { _ticket = (res['data'] as Map).cast<String, dynamic>(); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _reply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiService().post('/admin/tickets/${widget.ticketId}/reply', {'message': text});
      _replyCtrl.clear();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_ticket?['subject'] ?? 'Support Ticket')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: (_statusColors[_ticket?['status']] ?? Colors.grey).withOpacity(0.08),
                    child: Row(children: [
                      Icon(Icons.circle, size: 10, color: _statusColors[_ticket?['status']] ?? Colors.grey),
                      const SizedBox(width: 8),
                      Text('${LanguageService.t('status')}: ${LanguageService.t((_ticket?['status'] ?? '').toString()).toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: ((_ticket?['messages'] as List?) ?? []).map<Widget>((m) {
                        final isSuper = (m['user']?['role']) == 'super_admin';
                        final isMine = m['user_id'] == _myUserId;
                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: isSuper ? Colors.blue.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(m['user']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                if (isSuper) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                                    child: Text(LanguageService.t('super_admin'), style: TextStyle(color: Colors.white, fontSize: 9)),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 4),
                              Text(m['message'] ?? ''),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_ticket?['status'] != 'closed')
                    Container(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 20),
                      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, -2))]),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _replyCtrl,
                            decoration: InputDecoration(hintText: LanguageService.t('type_your_reply'), isDense: true),
                            minLines: 1, maxLines: 4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _sending
                            ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(icon: const Icon(Icons.send), onPressed: _reply),
                      ]),
                    )
                  else
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(16), color: Colors.grey.shade100,
                      child: Text(LanguageService.t('this_ticket_is_closed'), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    ),
                ]),
    );
  }
}
