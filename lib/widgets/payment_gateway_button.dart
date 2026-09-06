import 'package:flutter/material.dart';

/// Branded "Pay Online" button for a specific payment gateway.
///
/// Uses each gateway's own real brand colors (not the apartment's theme
/// colors) so residents recognize and trust who's actually processing the
/// payment — same reasoning as the website's .btn-pay-razorpay/.btn-pay-cashfree
/// (see resident/layouts/app.blade.php). Colors sourced from each brand's
/// official palette:
///   Razorpay: prussian blue #012652 + dodger blue #0D94FB
///   Cashfree: jade #05C16E + cherry pie #240253
class PaymentGatewayButton extends StatelessWidget {
  final String gateway; // 'razorpay' | 'cashfree'
  final String subtitle;
  final VoidCallback? onPressed;
  final bool loading;

  const PaymentGatewayButton({
    super.key,
    required this.gateway,
    required this.subtitle,
    required this.onPressed,
    this.loading = false,
  });

  const PaymentGatewayButton.razorpay({
    super.key,
    required this.subtitle,
    required this.onPressed,
    this.loading = false,
  }) : gateway = 'razorpay';

  const PaymentGatewayButton.cashfree({
    super.key,
    required this.subtitle,
    required this.onPressed,
    this.loading = false,
  }) : gateway = 'cashfree';

  static const _razorpayGradient = [Color(0xFF0D94FB), Color(0xFF012652)];
  static const _cashfreeGradient = [Color(0xFF05C16E), Color(0xFF240253)];

  @override
  Widget build(BuildContext context) {
    final isRazorpay = gateway == 'razorpay';
    final gradient = isRazorpay ? _razorpayGradient : _cashfreeGradient;
    final name = isRazorpay ? 'Razorpay' : 'Cashfree';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: gradient[1].withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -.2)),
                    Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
