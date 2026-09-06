// ─────────────────────────────────────────────────────────────────────────────
// admin_general_categories_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../../utils/type_helpers.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminGeneralCategoriesScreen extends StatefulWidget {
  const AdminGeneralCategoriesScreen({super.key});
  @override State<AdminGeneralCategoriesScreen> createState() => _GCState();
}

class _GCState extends State<AdminGeneralCategoriesScreen> {
  List _cats = []; bool _loading = true; String? _error;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final res = await ApiService().get('/admin/general-categories'); dynamic r = res['data']; if (r is Map) r = r['data']; setState(() { _cats = List.from(r ?? []); _loading = false; }); }
    catch (e) { setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; }); }
  }

  void _showForm({Map? cat}) {
    final nameCtrl = TextEditingController(text: cat?['name'] as String? ?? '');
    final descCtrl = TextEditingController(text: cat?['description'] as String? ?? '');
    bool active    = cat != null ? (toBool(cat['is_active'])) : true;
    String? formError;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: StatefulBuilder(builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FormSheetHeader(icon: Icons.tag, title: cat == null ? 'Add Category' : 'Edit Category', accent: Colors.purple, onClose: () => Navigator.pop(ctx)),
          FormErrorBanner(message: formError),
          AppFieldShell(accent: BrandingService.primary, child: TextField(controller: nameCtrl, autofocus: true, decoration: appFieldDecoration(label: LanguageService.t('category_name'), icon: Icons.tag, accent: BrandingService.primary))),
          const SizedBox(height: 14),
          AppFieldShell(accent: BrandingService.secondary, child: TextField(controller: descCtrl, maxLines: 2, decoration: appFieldDecoration(label: LanguageService.t('description_optional'), icon: Icons.notes_outlined, accent: BrandingService.secondary).copyWith(alignLabelWithHint: true))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[300]!)),
            child: Row(children: [Expanded(child: Text(LanguageService.t('active'))), Switch(value: active, onChanged: (v) => setS(() => active = v), activeColor: BrandingService.primary)])),
          const SizedBox(height: 20),
          ElevatedButton.icon(icon: Icon(cat == null ? Icons.add : Icons.save_outlined), label: Text(cat == null ? 'Add Category' : 'Save'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              setS(() => formError = null);
              if (nameCtrl.text.trim().isEmpty) { setS(() => formError = LanguageService.t('name_required')); return; }
              try {
                final body = {'name': nameCtrl.text.trim(), 'description': descCtrl.text.trim(), 'is_active': active};
                if (cat != null) { await ApiService().put('/admin/general-categories/${cat['id']}', body); } else { await ApiService().post('/admin/general-categories', body); }
                if (ctx.mounted) Navigator.pop(ctx); _load();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cat == null ? 'Category added!' : 'Category updated!'), backgroundColor: Colors.green));
              } catch (e) { setS(() => formError = e.toString().replaceAll('Exception: ', '')); }
            }),
        ])),
      ),
    );
  }

  Future<void> _delete(Map c) async {
    final ok = await AmsDialog.confirm(context, title: LanguageService.t('delete_category'), message: 'Delete "${c['name']}"?', icon: Icons.delete_outline_rounded, confirmText: LanguageService.t('delete'), danger: true);
    if (ok == true) { try { await ApiService().delete('/admin/general-categories/${c['id']}'); _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red)); } }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/admin/dashboard')), title: Text(LanguageService.t('general_categories')), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
    drawer: const AppDrawer(),
    onDrawerChanged: DrawerVisibility.onChanged,
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _showForm(), icon: const Icon(Icons.add), label: Text(LanguageService.t('add_category')), backgroundColor: Colors.purple),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, size: 48, color: Colors.grey), Text(_error!, style: const TextStyle(color: Colors.grey)), ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry')))])) : _cats.isEmpty ? EmptyState(icon: Icons.tag, title: LanguageService.t('no_categories_yet'), color: Colors.purple)
        : ListView.separated(padding: const EdgeInsets.fromLTRB(12,12,12,90), itemCount: _cats.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) { final c = _cats[i] as Map; final active = toBool(c['is_active']);
              return Card(child: ListTile(leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.tag, color: Colors.purple, size: 20)),
                title: Text(c['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: c['description'] != null ? Text(c['description'] as String, style: const TextStyle(fontSize: 12)) : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: (active ? Colors.green : Colors.grey).withOpacity(0.12), borderRadius: BorderRadius.circular(20)), child: Text(active ? 'Active' : 'Inactive', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: active ? Colors.green : Colors.grey))),
                  PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _showForm(cat: c); if (v == 'delete') _delete(c); }, itemBuilder: (_) => [PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text(LanguageService.t('edit'))])), const PopupMenuDivider(), PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 10), Text(LanguageService.t('delete'), style: TextStyle(color: Colors.red))]))]),
                ]),
              ));
            }),
  );
}
