import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import '../../services/api_service.dart';
import '../../services/app_refresh.dart';
import '../../services/branding_service.dart';
import '../../services/menu_config_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../utils/type_helpers.dart';
import '../../services/language_service.dart';

class AdminSubscriptionScreen extends StatefulWidget {
  const AdminSubscriptionScreen({super.key});
  @override
  State<AdminSubscriptionScreen> createState() => _AdminSubscriptionScreenState();
}

class _AdminSubscriptionScreenState extends State<AdminSubscriptionScreen> {
  Map<String, dynamic>? _status;
  List _plans = [];
  bool _hasOnlineGateway = false;
  Map<String, dynamic>? _bankDetails;
  bool _loading = true;
  Razorpay? _razorpay;
  CFPaymentGatewayService? _cfPaymentGatewayService;
  Map? _pendingPlan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  Map<String, dynamic>? get _pendingRequest =>
      (_status?['pending_request'] as Map?)?.cast<String, dynamic>();

  // Mirrors self_service.blade.php's auto-renew card: on/off state, which
  // gateway actually collected the last successful payment (only razorpay
  // supports recurring billing — see
  // ApartmentSubscription::getPaidGatewayAttribute() server-side), and the
  // subscription id every recurring/cancel action below targets.
  int? get _currentSubscriptionId => _status?['subscription_id'] as int?;
  bool get _autoRenew => _status?['auto_renew'] == true;
  String? get _recurringGateway => _status?['recurring_gateway'] as String?;
  String? get _paidGateway => _status?['paid_gateway'] as String?;
  static const _recurringCapableGateways = ['razorpay'];

  /// Refreshes everything a plan change can affect outside this screen:
  /// disabled/locked module state (BrandingService, which ModuleGate/
  /// AppDrawer read) and the Quick Action/Bottom Nav "locked" flags
  /// (MenuConfigService, driven by SubscriptionService::isModuleAllowed
  /// server-side) - then bumps AppRefresh so the drawer, dashboard and
  /// bottom nav all pick it up immediately instead of needing a
  /// logout/login for the new plan's menu items/permissions to show.
  Future<void> _refreshPlanDependentState() async {
    await BrandingService.load();
    await MenuConfigService.load('apartment_admin');
    AppRefresh.bump();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ApiService().get('/admin/subscription/status');
      final p = await ApiService().get('/admin/subscription/plans');
      final b = await ApiService().get('/admin/subscription/bank-details');
      setState(() {
        _status = (s['data'] as Map?)?.cast<String, dynamic>();
        _plans = (p['data']?['plans'] as List?) ?? [];
        _hasOnlineGateway = p['data']?['has_online_gateway'] == true;
        _bankDetails = (b['data'] as Map?)?.cast<String, dynamic>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Widget> _bankDetailRow(String label, dynamic value) {
    if (value == null || (value is String && value.isEmpty)) return [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))),
          Expanded(child: Text('$value', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      ),
    ];
  }

  Future<void> _choosePlan(Map plan) async {
    final confirm = await AmsDialog.confirm(
      context,
      title: 'Switch to ${plan['name']}?',
      message: _hasOnlineGateway
          ? 'You will be redirected to pay online.'
          : 'No online gateway is set up. This will be marked pending until the Super Admin approves your cash payment.',
      icon: Icons.credit_card_rounded,
      confirmText: LanguageService.t('confirm'),
    );
    if (confirm != true) return;

    try {
      final res = await ApiService().post('/admin/subscription/choose', {'plan_id': plan['id']});
      final subId = res['data']?['subscription_id'];
      if (subId != null && _hasOnlineGateway && toNum(plan['price']) > 0) {
        _pendingPlan = plan;
        await _startOnlinePayment(subId, toNum(plan['price']).toDouble());
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Plan updated.'), backgroundColor: Colors.green));
        await _refreshPlanDependentState();
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  /// Resume an already-created (but unpaid) checkout from the pending-
  /// request card — same flow as _choosePlan()'s online branch, just
  /// without creating a new subscription record first.
  Future<void> _resumePendingPayment() async {
    final pending = _status?['pending_request'];
    if (pending == null || pending['state'] != 'awaiting_payment') return;
    final subId = pending['subscription_id'];
    final price = toNum(pending['plan']?['price']).toDouble();
    if (subId == null) return;
    await _startOnlinePayment(subId, price);
  }

  /// Step 1 of paying online: ask the backend which gateways are actually
  /// configured for this subscription (mirrors the website's checkout
  /// gateway picker — previously this always hard-coded 'razorpay', so
  /// Cashfree never showed up here even when enabled in Super Admin >
  /// Payment Settings).
  Future<void> _startOnlinePayment(int subscriptionId, double amount) async {
    List<Map<String, dynamic>> gateways = [];
    try {
      final res = await ApiService().get('/admin/subscription/$subscriptionId/gateways');
      gateways = List<Map<String, dynamic>>.from(res['data'] ?? []);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load payment options: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red));
      return;
    }

    if (gateways.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No online payment gateway is available right now.'), backgroundColor: Colors.red));
      return;
    }

    if (gateways.length == 1) {
      await _payOnline(subscriptionId, amount, gateways.first['gateway']);
      return;
    }

    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a payment method', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...gateways.map((gw) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: Text(gw['display_name'] ?? gw['gateway']),
                    subtitle: gw['sandbox'] == true ? const Text('Test mode', style: TextStyle(fontSize: 11, color: Colors.orange)) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(sheetContext, gw['gateway']),
                  ),
                )),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _payOnline(subscriptionId, amount, chosen);
  }

  Future<void> _payOnline(int subscriptionId, double amount, String gateway) async {
    try {
      final order = await ApiService().post('/admin/subscription/$subscriptionId/create-order', {'gateway': gateway});
      final data = order['data'];

      if (gateway == 'cashfree') {
        await _payWithCashfree(subscriptionId, data);
        return;
      }

      // Default / razorpay path.
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
        try {
          await ApiService().post('/admin/subscription/$subscriptionId/verify-payment', {
            'gateway': 'razorpay',
            'razorpay_order_id': r.orderId,
            'razorpay_payment_id': r.paymentId,
            'razorpay_signature': r.signature,
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('payment_successful_plan_activated')), backgroundColor: Colors.green));
          await _refreshPlanDependentState();
          _load();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
        }
      });
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: ${r.message ?? ''}'), backgroundColor: Colors.red));
      });
      _razorpay!.open({
        'key': data['key'],
        'amount': data['amount'],
        'currency': data['currency'] ?? 'INR',
        'order_id': data['order_id'],
        'name': BrandingService.appName,
        'description': 'Subscription plan payment',
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  // Mirrors PaymentService._payWithCashfree in payment_service.dart, but
  // targets the subscription verify-payment endpoint instead of a bill's.
  // Whichever fires — the SDK's success or its own error callback — the
  // result is confirmed against OUR backend (which re-checks Cashfree's
  // Order Status API server-to-server), not trusted from the SDK alone.
  Future<void> _payWithCashfree(int subscriptionId, Map<String, dynamic> order) async {
    final orderId = order['order_id']?.toString();
    final sessionId = order['payment_session_id']?.toString();
    final amount = double.tryParse(order['amount'].toString()) ?? 0;
    final sandbox = order['sandbox'] == true;

    if (orderId == null || sessionId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment could not be started. Please try again.'), backgroundColor: Colors.red));
      return;
    }

    Future<void> settle(String settledOrderId, String? sdkFailureMessage) async {
      try {
        await ApiService().post('/admin/subscription/$subscriptionId/verify-payment', {
          'gateway': 'cashfree',
          'order_id': settledOrderId,
          'amount': amount,
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('payment_successful_plan_activated')), backgroundColor: Colors.green));
        await _refreshPlanDependentState();
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sdkFailureMessage ?? e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
      }
    }

    _cfPaymentGatewayService = CFPaymentGatewayService();
    _cfPaymentGatewayService!.setCallback(
      (String verifiedOrderId) => settle(verifiedOrderId, null),
      (CFErrorResponse errorResponse, String failedOrderId) => settle(failedOrderId, errorResponse.getMessage()),
    );

    try {
      final session = CFSessionBuilder()
          .setEnvironment(sandbox ? CFEnvironment.SANDBOX : CFEnvironment.PRODUCTION)
          .setOrderId(orderId)
          .setPaymentSessionId(sessionId)
          .build();
      final cfWebCheckout = CFWebCheckoutPaymentBuilder().setSession(session).build();
      _cfPaymentGatewayService!.doPayment(cfWebCheckout);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  /// "Turn off" on the auto-renew badge — stops future auto-charges but
  /// leaves the plan active until it expires. Mirrors the website's
  /// cancelRecurringWeb()/POST .../recurring/cancel.
  Future<void> _turnOffAutoRenew() async {
    final subId = _currentSubscriptionId;
    if (subId == null) return;
    final confirm = await AmsDialog.confirm(
      context,
      title: LanguageService.t('auto_renew_on'),
      message: LanguageService.t('turn_off_auto_renew_confirm'),
      icon: Icons.arrow_circle_up_rounded,
      confirmText: LanguageService.t('turn_off'),
      danger: true,
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/admin/subscription/$subId/recurring/cancel', {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('auto_renew_turned_off')), backgroundColor: Colors.green));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  /// "Enable auto-renew" — opens a recurring mandate with whichever
  /// gateway actually collected the current plan's payment (never
  /// hard-coded), same restriction as the website: only reachable when
  /// _paidGateway is razorpay (see build() below).
  Future<void> _enableAutoRenew() async {
    final subId = _currentSubscriptionId;
    final gateway = _paidGateway;
    if (subId == null || gateway == null) return;

    try {
      final res = await ApiService().post('/admin/subscription/$subId/recurring/setup', {'gateway': gateway});
      final data = res['data'];

      // razorpay — Checkout opened with subscription_id instead of
      // order_id authorises the mandate AND charges the first cycle in
      // one step, same as self_service.blade.php's startRecurringSetup().
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) async {
        try {
          await ApiService().post('/admin/subscription/$subId/recurring/verify', {
            'gateway': 'razorpay',
            'razorpay_subscription_id': data['subscription_id'],
            'razorpay_payment_id': r.paymentId,
            'razorpay_signature': r.signature,
          });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('auto_renew_enabled')), backgroundColor: Colors.green));
          _load();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
        }
      });
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${LanguageService.t('could_not_confirm_auto_renew_setup')} ${r.message ?? ''}'), backgroundColor: Colors.red));
      });
      _razorpay!.open({
        'key': data['key'],
        'subscription_id': data['subscription_id'],
        'name': BrandingService.appName,
        'description': LanguageService.t('auto_renew_setup'),
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  /// Cancel Subscription — ends the plan itself (and any auto-renew
  /// mandate with it), not just auto-renew. Mirrors the website's
  /// cancelSubscription()/POST .../{subscription}/cancel with an optional
  /// reason, via the shared reason-prompt dialog.
  Future<void> _cancelSubscription() async {
    final subId = _currentSubscriptionId;
    if (subId == null) return;
    final reason = await AmsDialog.promptText(
      context,
      title: LanguageService.t('cancel_subscription'),
      message: LanguageService.t('cancel_subscription_note'),
      label: LanguageService.t('reason_optional'),
      icon: Icons.cancel_outlined,
      confirmText: LanguageService.t('confirm_cancellation'),
      danger: true,
    );
    // promptText returns null only when the sheet was dismissed/cancelled
    // outright - an empty string (submitted with no reason typed) is a
    // valid "yes, cancel, no reason given" and must still proceed.
    if (reason == null) return;
    try {
      await ApiService().post('/admin/subscription/$subId/cancel', {
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('subscription_cancelled')), backgroundColor: Colors.green));
      await _refreshPlanDependentState();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _status;
    final days = sub?['days_until_expiry'];
    return Scaffold(
      appBar: AppBar(title: Text(LanguageService.t('my_subscription'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // The plan you're actually on right now. Kept separate from
                  // any pending request below — starting a checkout must
                  // never make this card look like the plan disappeared.
                  if (sub?['current_plan'] != null)
                    Card(
                      color: (days != null && days <= 30 ? Colors.red.shade50 : null),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Current Plan: ${sub!['current_plan']?['name'] ?? '—'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          if (days != null)
                            Text(days <= 30 ? '$days day(s) left — renew soon' : '$days day(s) left',
                                style: TextStyle(color: days <= 7 ? Colors.red : Colors.black87)),
                          // Auto-renew status/actions — same three states as
                          // self_service.blade.php: on (with Turn off), can
                          // be enabled (razorpay only), or
                          // unavailable for whatever gateway was actually
                          // used to pay (e.g. Cashfree/cash).
                          if (sub['status'] == 'active') ...[
                            const SizedBox(height: 10),
                            if (_autoRenew)
                              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                                Chip(
                                  avatar: const Icon(Icons.autorenew_rounded, size: 16, color: Colors.green),
                                  label: Text(
                                    _recurringGateway != null
                                        ? '${LanguageService.t('auto_renew_on')} (${_recurringGateway![0].toUpperCase()}${_recurringGateway!.substring(1)})'
                                        : LanguageService.t('auto_renew_on'),
                                    style: const TextStyle(fontSize: 12, color: Colors.green),
                                  ),
                                  backgroundColor: Colors.green.withOpacity(0.08),
                                  side: BorderSide(color: Colors.green.withOpacity(0.3)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                TextButton(onPressed: _turnOffAutoRenew, child: Text(LanguageService.t('turn_off'))),
                              ])
                            else if (_hasOnlineGateway && toNum(sub['current_plan']?['price']) > 0 && toNum(sub['current_plan']?['duration_days']) > 0) ...[
                              if (_paidGateway != null && _recurringCapableGateways.contains(_paidGateway))
                                OutlinedButton.icon(
                                  onPressed: _enableAutoRenew,
                                  icon: const Icon(Icons.autorenew_rounded, size: 16),
                                  label: Text(LanguageService.t('enable_auto_renew')),
                                )
                              else if (_paidGateway != null)
                                Tooltip(
                                  message: LanguageService.t('auto_renew_unsupported_gateway_note'),
                                  child: Chip(
                                    avatar: const Icon(Icons.info_outline_rounded, size: 15, color: Colors.grey),
                                    label: Text(
                                      '${LanguageService.t('auto_renew_unavailable_for')} ${_paidGateway![0].toUpperCase()}${_paidGateway!.substring(1)}',
                                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                    ),
                                    backgroundColor: Colors.grey.shade100,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                            ],
                            const SizedBox(height: 4),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              OutlinedButton.icon(
                                onPressed: () => context.push('/admin/tickets/create'),
                                icon: const Icon(Icons.support_agent_rounded, size: 16),
                                label: Text(LanguageService.t('contact_super_admin')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _cancelSubscription,
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                icon: const Icon(Icons.cancel_outlined, size: 16),
                                label: Text(LanguageService.t('cancel_subscription')),
                              ),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                  if (_pendingRequest != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: _pendingRequest!['state'] == 'awaiting_approval' ? Colors.amber.shade50 : Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Plan Request: ${_pendingRequest!['plan']?['name'] ?? '—'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            _pendingRequest!['state'] == 'awaiting_approval'
                                ? LanguageService.t('pending_super_admin_approval')
                                : 'Payment not completed — your current plan stays active.',
                            style: TextStyle(color: _pendingRequest!['state'] == 'awaiting_approval' ? Colors.orange : Colors.blue.shade800),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            if (_pendingRequest!['state'] == 'awaiting_payment')
                              ElevatedButton(onPressed: _resumePendingPayment, child: const Text('Resume Payment')),
                            if (_pendingRequest!['state'] == 'awaiting_payment') const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final subId = _pendingRequest!['subscription_id'];
                                if (subId == null) return;
                                try {
                                  await ApiService().post('/admin/subscription/$subId/cancel', {});
                                  _load();
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
                                }
                              },
                              child: const Text('Cancel Request'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_bankDetails?['has_details'] == true) ...[
                    if (_bankDetails?['has_qr'] == true)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.qr_code_rounded, size: 18),
                            SizedBox(width: 6),
                            Text(LanguageService.t('pay_via_upi'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ]),
                          const SizedBox(height: 4),
                          Text(LanguageService.t('available_whether_or_not_an_online_gateway_is'), style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                          const SizedBox(height: 12),
                          if (_bankDetails?['qr_code_url'] != null)
                            Center(
                              child: Column(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(_bankDetails!['qr_code_url'], height: 160, width: 160, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const SizedBox()),
                                ),
                                if (_bankDetails?['qr_id'] != null) ...[
                                  const SizedBox(height: 6),
                                  Text('UPI ID: ${_bankDetails!['qr_id']}', style: const TextStyle(fontSize: 12)),
                                ],
                              ]),
                            )
                          else if (_bankDetails?['qr_id'] != null)
                            Text('UPI ID: ${_bankDetails!['qr_id']}', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                    if (_bankDetails?['has_qr'] == true && _bankDetails?['has_bank_account'] == true)
                      const SizedBox(height: 12),
                    if (_bankDetails?['has_bank_account'] == true)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.account_balance_outlined, size: 18),
                            SizedBox(width: 6),
                            Text(LanguageService.t('bank_transfer'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ]),
                          const SizedBox(height: 4),
                          Text(LanguageService.t('available_whether_or_not_an_online_gateway_is'), style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                          const SizedBox(height: 12),
                          ..._bankDetailRow('Bank Name', _bankDetails?['bank_name']),
                          ..._bankDetailRow('IFSC Code', _bankDetails?['ifsc_code']),
                          ..._bankDetailRow('Account No.', _bankDetails?['account_number']),
                          ..._bankDetailRow('SWIFT Code', _bankDetails?['swift_code']),
                          ..._bankDetailRow('Branch', _bankDetails?['branch_name']),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(LanguageService.t('available_plans'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  ..._plans.map((p) {
                    final isCurrent = sub?['current_plan']?['id'] == p['id'];
                    return Card(
                      child: ListTile(
                        title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${BrandingService.currencySymbol}${p['price']} / ${(p['duration_days'] ?? 0) > 0 ? '${p['duration_days']} days' : 'Unlimited'}'),
                        trailing: isCurrent
                            ? Chip(label: Text(LanguageService.t('current')))
                            : ElevatedButton(
                                onPressed: () => _choosePlan(p),
                                child: Text(toNum(p['price']) > 0
                                    ? (_hasOnlineGateway ? 'Pay Online' : 'Pay Cash')
                                    : 'Activate'),
                              ),
                      ),
                    );
                  }),
                  if (!_hasOnlineGateway)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        LanguageService.t('no_online_payment_gateway_configured_yet_paid'),
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
