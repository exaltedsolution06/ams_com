import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';

/// Displays a CMS-managed page (Terms & Conditions, Privacy Policy) fetched
/// from the backend. Works before login too, since the endpoint is public.
class CmsPageScreen extends StatefulWidget {
  final String slug;
  final String fallbackTitle;
  const CmsPageScreen({super.key, required this.slug, required this.fallbackTitle});

  @override
  State<CmsPageScreen> createState() => _CmsPageScreenState();
}

class _CmsPageScreenState extends State<CmsPageScreen> {
  String? _title;
  String? _content;
  String? _updatedAt;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/cms/${widget.slug}', );
      final data = (res['data'] as Map?)?.cast<String, dynamic>();
      setState(() {
        _title = data?['title'] as String? ?? widget.fallbackTitle;
        _content = data?['content'] as String? ?? '';
        _updatedAt = data?['updated_at'] as String?;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: BrandingService.primary,
        title: Text(_title ?? widget.fallbackTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _load),
                    ]),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_updatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text('Last updated: ${_updatedAt!.split('T').first}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                    Text(_content ?? '', style: const TextStyle(fontSize: 14, height: 1.6)),
                    const SizedBox(height: 24),
                  ]),
                ),
    );
  }
}
