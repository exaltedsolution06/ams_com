import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';

/// App Menu Settings - pick which apartment to configure Quick Action /
/// Bottom Nav menus for. Same content and purpose as the website's
/// Admin\MenuSettingsController@index (admin.menu-settings.index): a plain
/// list of this Company's apartments, each opening the "Configure Menus"
/// editor (CompanyMenuSettingsEditScreen) for that one apartment.
class CompanyMenuSettingsScreen extends StatefulWidget {
  const CompanyMenuSettingsScreen({super.key});
  @override
  State<CompanyMenuSettingsScreen> createState() => _CompanyMenuSettingsScreenState();
}

class _CompanyMenuSettingsScreenState extends State<CompanyMenuSettingsScreen> {
  List _apartments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Reuses the same apartment listing the "My Apartments" screen uses -
      // menu settings has no favourite/extra fields of its own, just needs
      // id + name for the picker.
      final res = await ApiService().get('/company/apartments');
      setState(() { _apartments = List.from(res['data'] as List? ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: Text(LanguageService.t('app_menu_settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      color: Colors.white,
                      child: Text(
                        LanguageService.t('app_menu_settings_hint'),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                      ),
                    ),
                    Expanded(
                      child: _apartments.isEmpty
                          ? ListView(children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 60),
                                child: EmptyState(icon: Icons.apartment_outlined, color: primary, title: LanguageService.t('no_apartments_found')),
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _apartments.length,
                              itemBuilder: (ctx, i) {
                                final a = _apartments[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                                  child: ListTile(
                                    leading: CircleAvatar(backgroundColor: primary.withOpacity(0.12), child: Icon(Icons.list_alt_outlined, color: primary)),
                                    title: Text(a['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(LanguageService.t('configure_menus')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => context.push('/company/menu-settings/${a['id']}', extra: a['name']),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]),
                ),
    );
  }
}
