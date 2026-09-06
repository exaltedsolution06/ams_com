import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_update_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';

/// Full-screen, non-dismissible update gate. Shown when the server has a
/// force-update switched on and the app's own installed version is behind
/// it. There is deliberately no back button, no skip option, and no way to
/// reach any other screen from here - see main.dart's router redirect
/// logic, which routes here instead of the normal login/dashboard whenever
/// AppUpdateService.checkForMandatoryUpdate() returns non-null.
class ForceUpdateScreen extends StatefulWidget {
  final UpdateInfo update;
  const ForceUpdateScreen({super.key, required this.update});

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _opening = false;

  Future<void> _downloadUpdate() async {
    final url = widget.update.apkUrl;
    if (url == null) return;
    setState(() => _opening = true);
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return PopScope(
      canPop: false, // no back button out of this screen, by design
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(color: primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.system_update_alt_rounded, size: 44, color: primary),
              ),
              const SizedBox(height: 24),
              Text(LanguageService.t('update_required'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                widget.update.versionName != null
                    ? 'A new version (${widget.update.versionName}) is available and required to continue.'
                    : 'A new version is available and required to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              if ((widget.update.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(LanguageService.t('what_s_new'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey[700])),
                    const SizedBox(height: 6),
                    Text(widget.update.description!, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              // Important: explains the Android "install unknown apps"
              // warning the user is about to see, so they don't think
              // something is wrong or malicious.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade200)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade800, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LanguageService.t('your_phone_may_show_a_security_warning_during') +
                      'directly by us, not through the Play Store. This is expected and safe — please allow the install to continue.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_opening || widget.update.apkUrl == null) ? null : _downloadUpdate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _opening
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.system_update_alt),
                  label: Text(_opening ? '' : LanguageService.t('update_now'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              if (widget.update.apkUrl == null) ...[
                const SizedBox(height: 10),
                Text(LanguageService.t('the_update_file_isn_t_available_right_now_ple'),
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500]), textAlign: TextAlign.center),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
