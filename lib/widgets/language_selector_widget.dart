import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/branding_service.dart';

/// Full country → language selector widget.
/// Used in Profile screen language tab.
class LanguageSelectorWidget extends StatefulWidget {
  final VoidCallback? onLanguageChanged;
  const LanguageSelectorWidget({super.key, this.onLanguageChanged});
  @override
  State<LanguageSelectorWidget> createState() => _LanguageSelectorWidgetState();
}

class _LanguageSelectorWidgetState extends State<LanguageSelectorWidget> {
  List<Map<String, dynamic>> _countries  = [];
  List<Map<String, dynamic>> _languages  = [];
  String? _selectedCountry;
  String  _selectedLang   = LanguageService.currentCode;
  bool    _loadingCountries  = true;
  bool    _loadingLanguages  = false;
  bool    _saving            = false;
  String? _message;
  bool    _isError = false;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    try {
      final res = await ApiService().get('/countries');
      setState(() {
        _countries       = List<Map<String, dynamic>>.from(res['data'] as List);
        _loadingCountries = false;
      });
    } catch (_) {
      setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadLanguages(String countryCode) async {
    setState(() { _loadingLanguages = true; _languages = []; });
    try {
      final res = await ApiService().get('/languages?country=$countryCode');
      setState(() {
        _languages       = List<Map<String, dynamic>>.from(res['data'] as List);
        _loadingLanguages = false;
        // Keep current selection if still in new list, else pick first
        if (!_languages.any((l) => l['code'] == _selectedLang)) {
          _selectedLang = _languages.isNotEmpty ? _languages[0]['code'] as String : 'en';
        }
      });
    } catch (_) {
      setState(() => _loadingLanguages = false);
    }
  }

  Future<void> _saveLanguage() async {
    setState(() { _saving = true; _message = null; });
    try {
      await LanguageService.setLanguage(_selectedLang);
      setState(() {
        _message = 'Language changed to ${_getLangName(_selectedLang)}.';
        _isError = false;
        _saving  = false;
      });
      widget.onLanguageChanged?.call();
    } catch (e) {
      setState(() {
        _message = e.toString().replaceAll('Exception: ', '');
        _isError = true;
        _saving  = false;
      });
    }
  }

  String _getLangName(String code) {
    final lang = _languages.firstWhere(
        (l) => l['code'] == code, orElse: () => {'name': code});
    return '${lang['flag_emoji'] ?? ''} ${lang['name'] ?? code}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final currentLang = LanguageService.currentCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Current language indicator ──────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(Icons.translate, color: primary, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(LanguageService.t('current_language'), style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text(
                _getLangName(currentLang).isEmpty ? currentLang.toUpperCase() : _getLangName(currentLang),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primary),
              ),
              Text('Code: $currentLang', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(currentLang.toUpperCase(),
                  style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Step 1: Country selector ────────────────────────────────────
        Text(LanguageService.t('step_1_select_country'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        _loadingCountries
            ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            : Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCountry,
                    isExpanded: true,
                    hint: Text(LanguageService.t('choose_your_country')),
                    items: _countries.map((c) => DropdownMenuItem<String>(
                      value: c['code'] as String,
                      child: Row(children: [
                        Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                        const Spacer(),
                        if ((c['language_count'] as int? ?? 0) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${c['language_count']} langs',
                                style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ),
                      ]),
                    )).toList(),
                    onChanged: (code) {
                      setState(() => _selectedCountry = code);
                      if (code != null) _loadLanguages(code);
                    },
                  ),
                ),
              ),
        const SizedBox(height: 20),

        // ── Step 2: Language selector ───────────────────────────────────
        Text(LanguageService.t('step_2_choose_language'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (_selectedCountry == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text(LanguageService.t('select_a_country_first_to_see_available'),
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
          )
        else if (_loadingLanguages)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_languages.isEmpty)
          Text(LanguageService.t('no_languages_found_for_this_country'), style: TextStyle(color: Colors.grey))
        else ...[
          // Language cards
          ...(_languages.map((lang) {
            final code     = lang['code'] as String;
            final isActive = _selectedLang == code;
            final isRtl    = lang['direction'] == 'rtl';
            return GestureDetector(
              onTap: () => setState(() => _selectedLang = code),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        isActive ? primary.withOpacity(0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(
                    color:  isActive ? primary : Colors.grey.shade200,
                    width:  isActive ? 2 : 1,
                  ),
                ),
                child: Row(children: [
                  Text(lang['flag_emoji'] as String? ?? '🌐',
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(lang['name'] as String? ?? code,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isActive ? primary : Colors.black87,
                          )),
                      Text('${lang['native_name'] ?? ''}  ·  ${isRtl ? "RTL" : "LTR"}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                  if (code == currentLang)
                    Tooltip(
                      message: LanguageService.t('currently_active'),
                      child: Icon(Icons.check_circle, color: Colors.green, size: 20),
                    )
                  else if (isActive)
                    Icon(Icons.radio_button_checked, color: primary, size: 20)
                  else
                    const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                ]),
              ),
            );
          })),
          const SizedBox(height: 4),
        ],

        // ── Message ─────────────────────────────────────────────────────
        if (_message != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isError ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _isError ? Colors.red.shade200 : Colors.green.shade200),
            ),
            child: Row(children: [
              Icon(_isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: _isError ? Colors.red : Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_message!, style: TextStyle(
                  color: _isError ? Colors.red.shade700 : Colors.green.shade700,
                  fontSize: 13))),
            ]),
          ),
        ],

        // ── Save button ─────────────────────────────────────────────────
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.language),
          label: Text(_saving ? 'Applying...' : 'Apply Language'),
          onPressed: (_saving || _selectedCountry == null || _languages.isEmpty)
              ? null
              : _saveLanguage,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          LanguageService.t('this_sets_your_personal_preference_the'),
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}
