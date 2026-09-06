import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/empty_state.dart';

/// Community Forum - list of discussion threads, with category filter and
/// a FAB to start a new discussion. JSON mirror of the website's
/// public.forum.index view (see ForumApiController on the backend).
class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key});
  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  List _threads = [];
  Map<String, dynamic> _categories = {};
  bool _loading = true;
  String? _category; // null = all categories

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await ApiService().get('/forum/categories');
      setState(() => _categories = (res['data'] as Map?)?.cast<String, dynamic>() ?? {});
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final path = _category != null ? '/forum?category=$_category' : '/forum';
      final res = await ApiService().get(path);
      setState(() { _threads = res['data']['data'] ?? []; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
      );
    }
  }

  void _onCategoryChanged(String? category) {
    setState(() => _category = category);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('community_forum'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/forum/new');
          _load();
        },
        icon: const Icon(Icons.add),
        label: Text(LanguageService.t('new_discussion')),
        backgroundColor: BrandingService.secondary,
        foregroundColor: Colors.white,
      ),
      body: Column(children: [
        if (_categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _CategoryChip(label: LanguageService.t('all'), selected: _category == null, onTap: () => _onCategoryChanged(null)),
                ..._categories.entries.map((e) => _CategoryChip(
                      label: e.value.toString(),
                      selected: _category == e.key,
                      onTap: () => _onCategoryChanged(e.key),
                    )),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _threads.isEmpty
                      ? EmptyState(icon: Icons.forum_outlined, title: LanguageService.t('no_discussions_yet'), color: BrandingService.primary)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: _threads.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final t = _threads[i];
                            final pinned = t['is_pinned'] == true;
                            final locked = t['is_locked'] == true;
                            return Card(
                              child: ListTile(
                                onTap: () async {
                                  await context.push('/forum/${t['slug']}');
                                  _load();
                                },
                                leading: CircleAvatar(
                                  backgroundColor: BrandingService.primary.withOpacity(0.1),
                                  child: Icon(Icons.forum_outlined, color: BrandingService.primary),
                                ),
                                title: Row(children: [
                                  if (pinned) Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.push_pin, size: 14, color: Colors.orange.shade700),
                                  ),
                                  if (locked) Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                                  ),
                                  Expanded(child: Text(t['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                                ]),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: BrandingService.secondary.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text((t['category'] ?? '').toString(),
                                          style: TextStyle(color: BrandingService.secondary, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(t['user']?['name'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const Spacer(),
                                    Icon(Icons.mode_comment_outlined, size: 13, color: Colors.grey.shade500),
                                    const SizedBox(width: 3),
                                    Text('${t['replies_count'] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ]),
                                ),
                                isThreeLine: false,
                              ),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: BrandingService.primary,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 12.5, fontWeight: FontWeight.w600),
        backgroundColor: Colors.grey.shade100,
      ),
    );
  }
}
