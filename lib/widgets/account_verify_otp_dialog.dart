import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        bool loading = false;
        bool resending = false;
        String? error;
        String message = pending['message']?.toString() ?? 'An OTP has been sent to verify your account.';

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
              const SizedBox(height: 14),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Enter OTP',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
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
