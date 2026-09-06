import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/empty_state.dart';

/// Single discussion thread - body + replies + a reply box. JSON mirror of
/// the website's public.forum.show view (see ForumApiController::show/reply).
class ForumThreadScreen extends StatefulWidget {
  final String slug;
  const ForumThreadScreen({super.key, required this.slug});
  @override
  State<ForumThreadScreen> createState() => _ForumThreadScreenState();
}

class _ForumThreadScreenState extends State<ForumThreadScreen> {
  Map<String, dynamic>? _thread;
  bool _loading = true;
  String? _error;
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/forum/${widget.slug}');
      setState(() { _thread = (res['data'] as Map).cast<String, dynamic>(); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiService().post('/forum/${widget.slug}/reply', {'body': text});
      _replyCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _thread?['is_locked'] == true;
    final replies = (_thread?['replies'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('community_forum'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : Column(children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(16), children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text(_thread?['title'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                              ),
                              if (_thread?['is_pinned'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.push_pin, size: 16, color: Colors.orange.shade700),
                                ),
                            ]),
                            const SizedBox(height: 6),
                            Wrap(spacing: 12, runSpacing: 4, children: [
                              Text(_thread?['user']?['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('${LanguageService.t('views')}: ${_thread?['views'] ?? 0}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ]),
                            const Divider(height: 20),
                            Text(_thread?['body'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('${LanguageService.t('replies')} (${replies.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      if (replies.isEmpty)
                        EmptyRow(icon: Icons.mode_comment_outlined, text: LanguageService.t('no_replies_yet'), color: BrandingService.primary)
                      else
                        ...List.generate(replies.length, (i) {
                          final r = replies[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r['user']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(r['body'] ?? ''),
                              ]),
                            ),
                          );
                        }),
                    ]),
                  ),
                  SafeArea(
                    top: false,
                    child: locked
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            width: double.infinity,
                            color: Colors.grey.shade100,
                            child: Text(LanguageService.t('discussion_closed_to_replies'),
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                          )
                        : Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, -2))]),
                            child: Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: _replyCtrl,
                                  decoration: InputDecoration(hintText: LanguageService.t('write_a_reply'), isDense: true),
                                  minLines: 1, maxLines: 3,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _sending
                                  ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                  : IconButton(icon: const Icon(Icons.send), onPressed: _sendReply),
                            ]),
                          ),
                  ),
                ]),
    );
  }
}
