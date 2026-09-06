import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/app_form_field.dart';

class AdminTicketCreateScreen extends StatefulWidget {
  const AdminTicketCreateScreen({super.key});
  @override
  State<AdminTicketCreateScreen> createState() => _AdminTicketCreateScreenState();
}

class _AdminTicketCreateScreenState extends State<AdminTicketCreateScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _priority = 'normal';
  bool _submitting = false;

  static const _priorities = [
    {'value': 'low',    'label': 'Low',    'icon': Icons.south_rounded,      'color': Colors.blueGrey},
    {'value': 'normal', 'label': 'Normal', 'icon': Icons.remove_rounded,     'color': Colors.blue},
    {'value': 'high',   'label': 'High',   'icon': Icons.north_rounded,      'color': Colors.orange},
    {'value': 'urgent', 'label': 'Urgent', 'icon': Icons.priority_high_rounded, 'color': Colors.red},
  ];

  Color get _priorityColor =>
      (_priorities.firstWhere((p) => p['value'] == _priority)['color'] as Color);

  Future<void> _submit() async {
    if (_subjectCtrl.text.trim().isEmpty || _messageCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('please_fill_in_subject_and_message')), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService().post('/admin/tickets', {
        'subject': _subjectCtrl.text.trim(),
        'priority': _priority,
        'message': _messageCtrl.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(title: Text(LanguageService.t('new_support_ticket'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), children: [
        // Hero header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary, primary.withOpacity(0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(LanguageService.t('new_support_ticket'),
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(LanguageService.t('our_team_typically_responds_within_24_hours'),
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),

        AppFieldShell(
          accent: primary,
          child: TextField(
            controller: _subjectCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: appFieldDecoration(
              label: LanguageService.t('subject'),
              hint: 'A short summary of your issue',
              icon: Icons.subject_rounded, accent: primary,
            ),
          ),
        ),
        const SizedBox(height: 18),

        Text(LanguageService.t('priority'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: _priorities.map((p) {
          final sel = _priority == p['value'];
          final c = p['color'] as Color;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: p == _priorities.last ? 0 : 8),
              child: GestureDetector(
                onTap: () => setState(() => _priority = p['value'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? c : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel ? c : Colors.grey.shade300),
                    boxShadow: sel ? [BoxShadow(color: c.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : null,
                  ),
                  child: Column(children: [
                    Icon(p['icon'] as IconData, size: 18, color: sel ? Colors.white : c),
                    const SizedBox(height: 4),
                    Text(p['label'] as String, style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white : Colors.black87)),
                  ]),
                ),
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 18),

        AppFieldShell(
          accent: primary,
          child: TextField(
            controller: _messageCtrl,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: appFieldDecoration(
              label: LanguageService.t('message_2'),
              hint: LanguageService.t('describe_your_issue_or_question_in_detail'),
              icon: Icons.notes_outlined, accent: primary,
            ).copyWith(alignLabelWithHint: true),
          ),
        ),
        const SizedBox(height: 26),

        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [_priorityColor, _priorityColor.withOpacity(0.75)], begin: Alignment.centerLeft, end: Alignment.centerRight),
            boxShadow: [BoxShadow(color: _priorityColor.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: ElevatedButton.icon(
            icon: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(_submitting ? 'Submitting...' : 'Submit Ticket', style: const TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: _submitting ? null : _submit,
          ),
        ),
      ]),
    );
  }
}
