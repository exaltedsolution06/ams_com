import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';
import '../../widgets/app_drawer.dart';

/// Company Admin > My Company Subscription - read-only status for this
/// Company's own platform subscription (what Super Admin's Company Plans
/// billed the company, NOT the plans this company resells to its
/// apartments - that's the separate "My Plans"/CompanyPlansScreen).
///
/// Choosing a new plan and paying for it stays a website-only flow for
/// now (admin.company-plans.selfService already has the full Razorpay/
/// Cashfree checkout, same as AdminSubscriptionScreen does for an
/// apartment) - duplicating that payment flow here wasn't worth the risk
/// for this pass, so this screen shows exactly where things stand and
/// hands off to the website for anything that changes the plan.
class CompanySubscriptionScreen extends StatefulWidget {
  const CompanySubscriptionScreen({super.key});
  @override
  State<CompanySubscriptionScreen> createState() => _CompanySubscriptionScreenState();
}

class _CompanySubscriptionScreenState extends State<CompanySubscriptionScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/company/my-subscription');
      setState(() { _status = (res['data'] as Map?)?.cast<String, dynamic>() ?? {}; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _openWebsite() async {
    final url = _status?['manage_on_website_url'] as String?;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final isActive = _status?['is_active'] == true;
    final isFree = _status?['is_free'] == true;
    final planName = _status?['plan'] as String? ?? LanguageService.t('free');
    final daysLeft = _status?['days_left'] as int?;
    final autoRenew = _status?['auto_renew'] == true;
    final expiresAt = _status?['expires_at'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/company/dashboard')),
        title: Text(LanguageService.t('my_company_subscription')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: Text(LanguageService.t('retry'))),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [primary, BrandingService.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.credit_card, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(planName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              isFree
                                  ? LanguageService.t('free_plan')
                                  : (isActive ? LanguageService.t('active') : LanguageService.t('subscription_expired')),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (!isFree && expiresAt != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              isActive
                                  ? '${LanguageService.t('expires_on')}: $expiresAt${daysLeft != null ? ' (${daysLeft} ${LanguageService.t('days_lc')})' : ''}'
                                  : '${LanguageService.t('expired_on')}: $expiresAt',
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                          ],
                          if (!isFree) ...[
                            const SizedBox(height: 4),
                            Text(
                              autoRenew ? LanguageService.t('auto_renew_on') : LanguageService.t('auto_renew_off'),
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                            ),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            LanguageService.t('manage_company_subscription_on_website'),
                            style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(LanguageService.t('manage_on_website')),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: _openWebsite,
                      ),
                    ]),
                  ),
                ),
    );
  }
}
