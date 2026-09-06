import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
// Cashfree Easy Split "Pay Online" — mirrors the website's
// cashfree.checkout({paymentSessionId, redirectTarget: '_modal'}) using
// Cashfree's official Flutter SDK. Package name is flutter_cashfree_pg_sdk
// (confirmed against https://pub.dev/packages/flutter_cashfree_pg_sdk,
// currently 2.4.0+52) - import paths below match that package's actual
// lib/ layout, confirmed via its example app and API docs.
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'api_service.dart';

/// Handles the full "Pay Now" flow for bills, one-time charges, and wallet
/// deposits alike:
/// 1. Fetch available payment options (bills only — always includes Cash)
/// 2. Create an order with the chosen gateway via the backend
/// 3. Launch the gateway's native checkout (Razorpay SDK, Cashfree SDK, or
///    browser for others)
/// 4. Verify the payment with the backend after success — same as the
///    website, the backend's server-to-server check with the gateway is the
///    actual source of truth, not anything the SDK callback reports.
class PaymentService {
  final ApiService _api = ApiService();
  Razorpay? _razorpay;
  CFPaymentGatewayService? _cfPaymentGatewayService;

  /// Step 1 — get the list of gateways enabled for this apartment (bills only)
  Future<List<Map<String, dynamic>>> getPaymentOptions(int billId) async {
    final res = await _api.get('/bills/$billId/payment-options');
    return List<Map<String, dynamic>>.from(res['data']);
  }

  /// Step 2 + 3 — start payment with the chosen gateway (maintenance bill)
  Future<void> startPayment({
    required BuildContext context,
    required int billId,
    required String gateway,
    required double amount,
    required String residentName,
    required String residentEmail,
    required String residentPhone,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    if (gateway == 'cash') {
      await _payWithCash(billId, onSuccess, onFailure);
      return;
    }
    if (gateway == 'upi') {
      await _payWithUpi(billId, onSuccess, onFailure);
      return;
    }

    try {
      final order = await _api.post('/bills/$billId/create-order', {
        'gateway': gateway,
        'amount': amount,
      });
      final data = order['data'];

      switch (gateway) {
        case 'razorpay':
          _openRazorpay(
            data, billId, amount, residentName, residentEmail, residentPhone,
            onSuccess, onFailure,
          );
          break;
        case 'cashfree':
          await _payWithCashfree(
            order: data,
            verify: (orderId, verifiedAmount) => _api.post('/bills/$billId/verify-payment', {
              'gateway': 'cashfree',
              'order_id': orderId,
              'amount': verifiedAmount,
            }),
            onSuccess: onSuccess,
            onFailure: onFailure,
          );
          break;
        default:
          onFailure('Unsupported gateway: $gateway');
      }
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ─────────────────────────── RAZORPAY ─────────────────────────────────

  void _openRazorpay(
    Map<String, dynamic> data,
    int billId,
    double amount,
    String name,
    String email,
    String phone,
    Function(String) onSuccess,
    Function(String) onFailure,
  ) {
    _razorpay = Razorpay();

    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      try {
        await _api.post('/bills/$billId/verify-payment', {
          'gateway': 'razorpay',
          'amount': amount,
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        });
        onSuccess('Payment successful!');
      } catch (e) {
        onFailure('Payment captured but verification failed. Contact support with payment ID: ${response.paymentId}');
      } finally {
        _razorpay?.clear();
      }
    });

    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      onFailure(response.message ?? 'Payment failed or cancelled.');
      _razorpay?.clear();
    });

    _razorpay!.open({
      'key': data['key'],
      'order_id': data['order_id'],
      'amount': data['amount'],
      'currency': data['currency'],
      'name': 'Maintenance Payment',
      'description': 'Bill #$billId',
      'prefill': {'contact': phone, 'email': email, 'name': name},
      'theme': {'color': '#1A3C5E'},
    });
  }

  // ─────────────────────────── CASHFREE (Easy Split) ─────────────────────
  //
  // Generic across bills / one-time charges / wallet deposits — the caller
  // just supplies the already-created `order` map (order_id,
  // payment_session_id, amount, sandbox — see PaymentGatewayService::
  // createCashfreeOrder()/createGenericCashfreeOrder() on the backend) and a
  // `verify` callback pointed at the right endpoint. Easy Split itself
  // (splitting settlement into the apartment's own bank account) is decided
  // entirely server-side — nothing gateway-specific to do differently here.

  Future<void> _payWithCashfree({
    required Map<String, dynamic> order,
    required Future<void> Function(String orderId, double amount) verify,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    final orderId = order['order_id']?.toString();
    final sessionId = order['payment_session_id']?.toString();
    final amount = double.tryParse(order['amount'].toString()) ?? 0;
    final sandbox = order['sandbox'] == true;

    if (orderId == null || sessionId == null) {
      onFailure('Payment could not be started. Please try again.');
      return;
    }

    // Whichever fires — success or the SDK's own error callback — we still
    // ask OUR backend, which re-checks Cashfree's Order Status API
    // server-to-server (see PaymentGatewayService::verifyCashfreeStatus()).
    // That's the same "don't trust the checkout modal's own verdict"
    // philosophy as the website's `cashfree.checkout().catch(() => {})`
    // followed by an unconditional verify call.
    Future<void> settle(String settledOrderId, String? sdkFailureMessage) async {
      try {
        await verify(settledOrderId, amount);
        onSuccess('Payment successful!');
      } catch (e) {
        onFailure(sdkFailureMessage ?? e.toString().replaceAll('Exception: ', ''));
      }
    }

    _cfPaymentGatewayService = CFPaymentGatewayService();
    _cfPaymentGatewayService!.setCallback(
      (String verifiedOrderId) => settle(verifiedOrderId, null),
      (CFErrorResponse errorResponse, String failedOrderId) =>
          settle(failedOrderId, errorResponse.getMessage()),
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
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// "Pay Online" for a one-time charge — mirrors the website's
  /// pay-online-otc-btn: creates an order via the generic (non-bill) path
  /// for the chosen gateway ('cashfree' or 'razorpay', defaults to
  /// 'cashfree' for callers that don't care) and does NOT touch the item's
  /// status; it stays exactly as-is until the verify call below (or the
  /// Cashfree webhook) confirms the money.
  Future<void> payOneTimeChargeOnline({
    required int itemId,
    String gateway = 'cashfree',
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    try {
      final order = await _api.post('/one-time-charges/$itemId/pay-online/create-order', {'gateway': gateway});
      if (gateway == 'razorpay') {
        _openRazorpayGeneric(
          order['data'],
          verify: (payload) => _api.post('/one-time-charges/$itemId/pay-online/verify', payload),
          onSuccess: onSuccess,
          onFailure: onFailure,
        );
        return;
      }
      await _payWithCashfree(
        order: order['data'],
        verify: (orderId, amount) => _api.post('/one-time-charges/$itemId/pay-online/verify', {
          'gateway': 'cashfree',
          'order_id': orderId,
          'amount': amount,
        }),
        onSuccess: onSuccess,
        onFailure: onFailure,
      );
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// "Pay Online" for a wallet/advance deposit — amount is resident-entered
  /// (a deposit has no fixed amount), same as the website's
  /// walletPayOnlineBtn flow. gateway defaults to 'cashfree'.
  Future<void> depositWalletOnline({
    required double amount,
    String gateway = 'cashfree',
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    try {
      final order = await _api.post('/wallet/deposit-online/create-order', {'amount': amount, 'gateway': gateway});
      if (gateway == 'razorpay') {
        _openRazorpayGeneric(
          order['data'],
          verify: (payload) => _api.post('/wallet/deposit-online/verify', payload),
          onSuccess: onSuccess,
          onFailure: onFailure,
        );
        return;
      }
      await _payWithCashfree(
        order: order['data'],
        verify: (orderId, verifiedAmount) => _api.post('/wallet/deposit-online/verify', {
          'gateway': 'cashfree',
          'order_id': orderId,
          'amount': verifiedAmount,
        }),
        onSuccess: onSuccess,
        onFailure: onFailure,
      );
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Generic Razorpay checkout for the non-bill "Pay Online" flows above
  /// (one-time charges, wallet deposits) — same SDK/event-handling shape as
  /// _openRazorpay() above (used for bills), but hands the verify payload
  /// straight to whichever endpoint the caller supplies instead of always
  /// posting to /bills/{id}/verify-payment, since those two entry points
  /// aren't tied to a MaintenanceBill.
  void _openRazorpayGeneric(
    Map<String, dynamic> data, {
    required Future<void> Function(Map<String, dynamic> payload) verify,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) {
    final amount = double.tryParse(data['amount'].toString()) ?? 0;
    _razorpay = Razorpay();

    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      try {
        await verify({
          'gateway': 'razorpay',
          'amount': amount / 100,
          'razorpay_order_id': response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        });
        onSuccess('Payment successful!');
      } catch (e) {
        onFailure('Payment captured but verification failed. Contact support with payment ID: ${response.paymentId}');
      } finally {
        _razorpay?.clear();
      }
    });

    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      onFailure(response.message ?? 'Payment failed or cancelled.');
      _razorpay?.clear();
    });

    _razorpay!.open({
      'key': data['key'],
      'order_id': data['order_id'],
      'amount': data['amount'],
      'currency': data['currency'],
      'name': 'Online Payment',
      'theme': {'color': '#1A3C5E'},
    });
  }

  // ─────────────────────────── CASH ─────────────────────────────────────

  Future<void> _payWithCash(int billId, Function(String) onSuccess, Function(String) onFailure) async {
    try {
      await _api.post('/bills/$billId/pay-cash', {});
      onSuccess('Cash payment request submitted. The apartment admin will confirm receipt.');
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Unified cash / bank-transfer / cheque claim for a maintenance bill -
  /// mirrors the One-Time Charges "Pay" sheet's submission exactly (single
  /// endpoint, payment_method + optional transaction ref). Bill Details'
  /// Pay sheet uses this instead of the old cash-only/no-transaction-ref
  /// _payWithCash() above, so the two flows match.
  Future<void> payBillManual({
    required int billId,
    required String method, // 'cash' | 'bank_transfer' | 'cheque'
    String? transactionId,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    try {
      await _api.post('/bills/$billId/pay', {
        'payment_method': method,
        if (transactionId != null && transactionId.trim().isNotEmpty) 'transaction_id': transactionId.trim(),
      });
      onSuccess('Payment claim submitted. The apartment admin will confirm receipt.');
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ─────────────────────────── UPI ───────────────────────────────────────

  /// Creates the pending payment record (same "awaiting admin confirmation"
  /// shape as Cash above), then launches the resident's installed UPI app
  /// pre-filled with the apartment's UPI ID/payee name/amount/currency,
  /// which the backend returns as a ready-made `upi://pay?...` URI.
  Future<void> _payWithUpi(int billId, Function(String) onSuccess, Function(String) onFailure) async {
    try {
      final res = await _api.post('/bills/$billId/pay-upi', {});
      final uri = res['upi']?['uri'];
      if (uri != null) {
        final launched = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
        if (!launched) {
          onFailure('No UPI app found on this device. Your payment request was submitted - you can still pay manually and the admin will confirm receipt.');
          return;
        }
      }
      onSuccess('UPI payment request submitted. Complete the payment in your UPI app; the apartment admin will confirm receipt.');
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Same one-tap UPI flow as the maintenance bill above, but for a
  /// One-Time Charge item — used by the Billing screen's charge pay sheet.
  Future<void> payOneTimeChargeUpi({
    required int itemId,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    try {
      final res = await _api.post('/one-time-charges/$itemId/pay-upi', {});
      final uri = res['upi']?['uri'];
      if (uri != null) {
        final launched = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
        if (!launched) {
          onFailure('No UPI app found on this device. Your payment request was submitted - you can still pay manually and the admin will confirm receipt.');
          return;
        }
      }
      onSuccess('UPI payment request submitted. Complete the payment in your UPI app; the apartment admin will confirm receipt.');
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Same one-tap UPI flow as the maintenance bill above, but for an
  /// advance/Wallet deposit — used by the Wallet screen's deposit sheet.
  /// Amount is resident-entered (a deposit has no fixed amount).
  Future<void> depositWalletUpi({
    required double amount,
    String? notes,
    required Function(String message) onSuccess,
    required Function(String message) onFailure,
  }) async {
    try {
      final res = await _api.post('/wallet/deposit-upi', {
        'amount': amount,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });
      final uri = res['upi']?['uri'];
      if (uri != null) {
        final launched = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
        if (!launched) {
          onFailure('No UPI app found on this device. Your payment request was submitted - you can still pay manually and the admin will confirm receipt.');
          return;
        }
      }
      onSuccess('UPI advance payment submitted. Complete the payment in your UPI app; the apartment admin will confirm receipt.');
    } catch (e) {
      onFailure(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void dispose() {
    _razorpay?.clear();
  }
}

/*
 * ─────────────────────────────────────────────────────────────────────
 * NOTES FOR PRODUCTION COMPLETION
 * ─────────────────────────────────────────────────────────────────────
 *
 * CASHFREE:
 *   Implemented above via cashfree_pg (CFPaymentGatewayService / CFSessionBuilder /
 *   CFWebCheckoutPaymentBuilder) — mirrors the website's Drop-in Checkout modal.
 *   Cashfree completion is also confirmed server-side via the
 *   /payments/cashfree/webhook already wired up in PaymentWebhookController
 *   — the bill/charge/wallet auto-updates even if the app-side confirmation
 *   callback never fires (app killed mid-payment, etc.).
 *
 * FCM PUSH TOKEN:
 *   On app startup after login, call:
 *     final token = await FirebaseMessaging.instance.getToken();
 *     await ApiService().post('/fcm-token', {'fcm_token': token});
 * ─────────────────────────────────────────────────────────────────────
 */
