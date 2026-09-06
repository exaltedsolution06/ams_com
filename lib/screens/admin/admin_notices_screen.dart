import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';

class AdminNoticesScreen extends StatefulWidget {
  const AdminNoticesScreen({super.key});
  @override
  State<AdminNoticesScreen> createState() => _AdminNoticesScreenState();
}

class _AdminNoticesScreenState extends State<AdminNoticesScreen> {
  List _notices = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService().get('/admin/notices');
      setState(() { _notices = res['data']['data'] ?? res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _showCreate() {
    final formKey   = GlobalKey<FormState>();
    final titleCtrl = TextEditingController();
    final bodyCtrl  = TextEditingController();
    String type     = 'general';
    bool sendPush   = true;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(builder: (ctx, setS) => Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FormSheetHeader(
              icon: Icons.campaign_outlined,
              title: LanguageService.t('new_notice'),
              accent: BrandingService.primary,
              onClose: () => Navigator.pop(ctx),
            ),
            FormErrorBanner(message: formError),
            AppFieldShell(
              accent: BrandingService.primary,
              child: DropdownButtonFormField<String>(
                value: type,
                decoration: appFieldDecoration(label: LanguageService.t('notice_type'), icon: Icons.label_outlined, accent: BrandingService.primary),
                items: [
                  DropdownMenuItem(value: 'general',     child: Text(LanguageService.t('general_2'))),
                  DropdownMenuItem(value: 'urgent',      child: Text(LanguageService.t('urgent_2'))),
                  DropdownMenuItem(value: 'maintenance', child: Text(LanguageService.t('maintenance_2'))),
                  DropdownMenuItem(value: 'event',       child: Text(LanguageService.t('event_2'))),
                ],
                onChanged: (v) => setS(() => type = v!),
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.secondary,
              child: TextFormField(
                controller: titleCtrl,
                decoration: appFieldDecoration(label: LanguageService.t('title'), icon: Icons.short_text_rounded, accent: BrandingService.secondary),
                validator: (v) => v!.isEmpty ? 'Title is required' : null,
              ),
            ),
            const SizedBox(height: 14),
            AppFieldShell(
              accent: BrandingService.primary,
              child: TextFormField(
                controller: bodyCtrl,
                maxLines: 5,
                decoration: appFieldDecoration(
                  label: LanguageService.t('content'),
                  hint: LanguageService.t('write_notice_content'),
                  icon: Icons.article_outlined,
                  accent: BrandingService.primary,
                ).copyWith(alignLabelWithHint: true),
                validator: (v) => v!.isEmpty ? 'Content is required' : null,
              ),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: sendPush,
              onChanged: (v) => setS(() => sendPush = v ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(LanguageService.t('send_push_notification'), style: TextStyle(fontSize: 13.5)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.campaign_outlined),
              label: Text(LanguageService.t('publish_notice')),
              onPressed: () async {
                setS(() => formError = null);
                if (!formKey.currentState!.validate()) return;
                try {
                  await ApiService().post('/admin/notices', {
                    'title':   titleCtrl.text.trim(),
                    'content': bodyCtrl.text.trim(),
                    'type':    type,
                    'is_push_notification': sendPush,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(LanguageService.t('notice_published')), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  setS(() => formError = e.toString().replaceAll('Exception: ', ''));
                }
              },
            ),
          ]),
        )),
      ),
    );
  }

  Future<void> _delete(Map notice) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('delete_notice'),
      message: 'Delete "${notice['title']}"?',
      icon: Icons.delete_outline_rounded,
      confirmText: LanguageService.t('delete'),
      danger: true,
    );
    if (confirm == true) {
      try {
        await ApiService().delete('/admin/notices/${notice['id']}');
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('notice_deleted')), backgroundColor: Colors.red),
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _typeColor(String? t) {
    switch (t) {
      case 'urgent':      return Colors.red;
      case 'maintenance': return Colors.orange;
      case 'event':       return Colors.purple;
      default:            return Colors.blue;
    }
  }

  String _typeEmoji(String? t) {
    switch (t) {
      case 'urgent':      return '🚨';
      case 'maintenance': return '🔧';
      case 'event':       return '🎉';
      default:            return '📢';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('notices')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreate,
        icon: const Icon(Icons.campaign_outlined),
        label: Text(LanguageService.t('post_notice')),
        backgroundColor: BrandingService.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notices.isEmpty
              ? EmptyState(
                  icon: Icons.campaign_outlined,
                  title: LanguageService.t('no_notices_yet'),
                  subtitle: LanguageService.t('tap_the_button_below_to_post_one'),
                  color: BrandingService.primary,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: _notices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n    = _notices[i] as Map;
                      final type = n['type'] as String? ?? 'general';
                      final c    = _typeColor(type);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: c.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${_typeEmoji(type)}  ${LanguageService.t(type).toUpperCase()}',
                                    style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _delete(n),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text(n['title'] ?? '—',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(n['content'] ?? '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.black87)),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
