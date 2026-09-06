import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/app_form_field.dart';

/// Start a new discussion thread. JSON mirror of the website's
/// public.forum.create view (see ForumApiController::store).
class ForumCreateScreen extends StatefulWidget {
  const ForumCreateScreen({super.key});
  @override
  State<ForumCreateScreen> createState() => _ForumCreateScreenState();
}

class _ForumCreateScreenState extends State<ForumCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  Map<String, dynamic> _categories = {};
  String? _category;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await ApiService().get('/forum/categories');
      final cats = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _categories = cats;
        if (cats.isNotEmpty) _category = cats.keys.first;
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().post('/forum', {
        'title': _titleCtrl.text.trim(),
        'category': _category,
        'body': _bodyCtrl.text.trim(),
      });
      final slug = res['data']?['slug'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('discussion_posted_successfully')), backgroundColor: Colors.green),
        );
        if (slug != null) {
          context.pushReplacement('/forum/$slug');
        } else {
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('start_a_discussion'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_categories.isNotEmpty)
                AppFieldShell(
                  accent: BrandingService.primary,
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    decoration: appFieldDecoration(label: LanguageService.t('category'), icon: Icons.category_outlined, accent: BrandingService.primary),
                    items: _categories.entries.map<DropdownMenuItem<String>>((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value.toString()))).toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
                ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.secondary,
                child: TextFormField(
                  controller: _titleCtrl,
                  decoration: appFieldDecoration(label: LanguageService.t('discussion_title'), icon: Icons.short_text_rounded, accent: BrandingService.secondary),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 14),
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextFormField(
                  controller: _bodyCtrl,
                  decoration: appFieldDecoration(label: LanguageService.t('discussion_body_hint'), icon: Icons.notes_rounded, accent: BrandingService.primary)
                      .copyWith(alignLabelWithHint: true),
                  maxLines: 6,
                  validator: (v) {
                    if (v == null || v.trim().length < 10) return 'Please write at least 10 characters';
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded, size: 20),
                  label: Text(_loading ? '' : LanguageService.t('post_discussion')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
