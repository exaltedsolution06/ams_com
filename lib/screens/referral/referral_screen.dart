import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/curved_header.dart';
import '../../widgets/dashboard_graphics.dart';

/// "Refer a Society" screen - shown to residents and Apartment Admins alike
/// (registered at both /referral and /admin/referral in main.dart, same as
/// the Emergency Numbers / Agreements screens' pattern). Fetches the
/// apartment's own referral code + share link from GET /referral and offers
/// copy / WhatsApp / native-share options, mirroring the web portal's
/// resident.referral / admin.referrals.mine pages.
///
/// Visual redesign: a gradient hero (matching the login/dashboard curved
/// header language) leads straight into flat, card-less sections - no boxed
/// white containers - mirroring the Forgot Password screen's "flows
/// straight out of the curved header" look. A tear-line divider (echoing a
/// physical invite/coupon) separates the link from the share actions
/// instead of a boxed card.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _loading = true;
  String? _error;
  Map _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/referral');
      setState(() {
        _data = Map<String, dynamic>.from(res['data'] ?? {});
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  bool get _hasCode => _data['has_code'] == true && (_data['share_url'] as String?)?.isNotEmpty == true;
  String get _shareUrl => (_data['share_url'] as String?) ?? '';
  String get _shareText =>
      'Join AMS and simplify managing our society! Sign up here: $_shareUrl';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(LanguageService.t('link_copied_to_clipboard'))),
    );
  }

  Future<void> _shareOnWhatsApp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('could_not_open_whatsapp'))),
      );
    }
  }

  Future<void> _shareGeneric() async {
    await Share.share(_shareText);
  }

  static const _bg = Color(0xFFF7F8FC);

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final secondary = BrandingService.secondary;

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(children: [
            _buildHero(primary, secondary),
            Transform.translate(
              offset: const Offset(0, -14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? _buildErrorState()
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _buildLinkSection(primary),
                            const SizedBox(height: 26),
                            Divider(color: Colors.grey.shade200, height: 1),
                            const SizedBox(height: 26),
                            _buildHowItWorksSection(primary),
                          ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // Hero: back button + icon badge + heading + a two-line-max blurb. Height
  // is sized with headroom above what the content actually needs (checked
  // against SafeArea top inset + icon + title + a wrapped 2-line subtitle)
  // so the text never gets pushed past the curved header's bottom edge or
  // clipped by the wave, even on notch devices / larger system font scales.
  Widget _buildHero(Color primary, Color secondary) {
    return CurvedHeader(
      height: 228,
      colors: [primary, secondary],
      // Same "clean, mostly-square card" treatment as the dashboards - see
      // CurvedHeader's bottomRadius doc comment.
      bottomRadius: 24,
      child: Stack(children: [
        const Positioned.fill(child: HeaderBlobs()),
        SafeArea(
          bottom: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ]),
            ),
            Container(
              width: 56, height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.16),
                border: Border.all(color: Colors.white.withOpacity(0.45), width: 1.4),
              ),
              child: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              LanguageService.t('refer_and_earn'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.2),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                _hasCode ? LanguageService.t('referral_benefit_text') : LanguageService.t('referral_not_setup'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withOpacity(0.86), fontSize: 11.5, height: 1.3),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildErrorState() {
    return Column(children: [
      Icon(Icons.wifi_off_rounded, size: 30, color: Colors.grey.shade400),
      const SizedBox(height: 10),
      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 14),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded, size: 17),
        label: Text(LanguageService.t('retry')),
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandingService.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ]);
  }

  Widget _buildLinkSection(Color primary) {
    if (!_hasCode) {
      return Column(children: [
        Container(
          width: 52, height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
          child: Icon(Icons.hourglass_top_rounded, color: Colors.grey.shade400, size: 24),
        ),
        const SizedBox(height: 12),
        Text(
          LanguageService.t('referral_not_setup'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, height: 1.4, fontSize: 13),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if ((_data['description'] as String?)?.isNotEmpty == true) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.percent_rounded, size: 14, color: Colors.amber.shade800),
              const SizedBox(width: 5),
              Text(_data['description'], style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Text(
        LanguageService.t('referral_link').toUpperCase(),
        style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
      ),
      const SizedBox(height: 9),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _copyLink,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary.withOpacity(0.18)),
          ),
          child: Row(children: [
            Icon(Icons.link_rounded, size: 17, color: primary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _shareUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 17, color: primary),
          ]),
        ),
      ),
      const SizedBox(height: 20),
      // Tear-line separating the link from the share actions - echoes a
      // physical invite/coupon without needing a boxed card around it.
      _DashedLine(color: Colors.grey.shade300),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _shareOnWhatsApp,
            icon: const Icon(Icons.chat, size: 17),
            label: Text(LanguageService.t('share_via_whatsapp')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: _shareGeneric,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Icon(Icons.share_rounded, size: 19, color: Colors.grey.shade700),
        ),
      ]),
    ]);
  }

  Widget _buildHowItWorksSection(Color primary) {
    final steps = [
      (Icons.person_add_alt_1_rounded, LanguageService.t('referral_step_1')),
      (Icons.fact_check_outlined, LanguageService.t('referral_step_2')),
      (Icons.celebration_rounded, LanguageService.t('referral_step_3')),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 4, height: 16, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(LanguageService.t('how_it_works'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 16),
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 34, height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: primary.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(steps[i].$1, size: 16, color: primary),
              ),
              if (i != steps.length - 1)
                Expanded(
                  child: Container(
                    width: 1.4,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: primary.withOpacity(0.15),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 18),
                child: Text(steps[i].$2, style: TextStyle(color: Colors.grey.shade700, height: 1.35, fontSize: 13.5)),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(30, (i) => Expanded(
        child: Container(
          height: 1.4,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          color: i.isEven ? color : Colors.transparent,
        ),
      )),
    );
  }
}
