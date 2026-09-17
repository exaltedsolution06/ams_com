import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/branding_service.dart';
import 'otp_box_input.dart';

/// Shown whenever a login/choose-account/switch-apartment API call comes
/// back with `needs_verification: true` (see AuthController::
/// verificationGate() on the backend) - i.e. this Resident/Apartment Admin
/// account has never verified email or phone. Lets the person enter the
/// OTP that was already sent, with a Resend option, and returns the final
/// login response (containing the real access_token) once verified.
///
/// Returns null if the person dismisses the dialog without verifying -
/// callers should treat that the same as a cancelled/failed login.
Future<Map<String, dynamic>?> showAccountVerifyOtpDialog(
  BuildContext context,
  Map<String, dynamic> pending, {
  String? fcmToken,
}) {
  final userId = pending['user_id'];
  final otpCtrl = TextEditingController();

  // These live in this OUTER builder (called once, when the dialog is
  // first shown) rather than inside StatefulBuilder's own `builder`
  // below - that inner one re-runs on every setState() call, so anything
  // declared there gets reset to its initial value on every rebuild,
  // silently discarding whatever verify()/resend() just set (loading,
  // error, message) before it ever reaches the screen. That was why a
  // wrong OTP appeared to do nothing: the error WAS set, then immediately
  // wiped by the very rebuild that setState triggered.
  bool loading = false;
  bool resending = false;
  String? error;
  String message = pending['message']?.toString() ?? 'An OTP has been sent to verify your account.';

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> verify() async {
          if (otpCtrl.text.trim().length != 6) {
            setState(() => error = 'Enter the 6-digit OTP.');
            return;
          }
          setState(() { loading = true; error = null; });
          try {
            final res = await ApiService().post('/verify-account-otp', {
              'user_id': userId,
              'otp': otpCtrl.text.trim(),
              if (fcmToken != null) 'fcm_token': fcmToken,
            }, auth: false);
            if (ctx.mounted) Navigator.pop(ctx, res);
          } catch (e) {
            setState(() { loading = false; error = e.toString().replaceAll('Exception: ', ''); });
          }
        }

        Future<void> resend() async {
          setState(() => resending = true);
          try {
            final res = await ApiService().post('/verify-account-otp/resend', {'user_id': userId}, auth: false);
            setState(() { message = res['message']?.toString() ?? message; resending = false; });
          } catch (e) {
            setState(() { resending = false; error = e.toString().replaceAll('Exception: ', ''); });
          }
        }

        return AlertDialog(
          title: const Text('Verify Your Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 16),
              OtpBoxInput(
                controller: otpCtrl,
                accent: BrandingService.primary,
                boxWidth: 38,
                boxHeight: 48,
                hasError: error != null,
                onCompleted: (_) { if (!loading) verify(); },
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!, style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: resending ? null : resend,
                  child: resending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Resend OTP'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: loading ? null : verify,
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify'),
            ),
          ],
        );
      },
    ),
  );
}
