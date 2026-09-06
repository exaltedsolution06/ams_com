import 'package:flutter/material.dart';
import 'app_form_field.dart';

import '../services/language_service.dart';
/// A small set of reusable, nicely-styled dialogs — an icon in a soft
/// colored circle, a clear title, and consistent button treatment — so
/// confirm/delete/info popups look the same (and look good) everywhere
/// in the app, instead of each screen hand-rolling a plain AlertDialog.
///
/// Usage:
///   final ok = await AmsDialog.confirm(
///     context,
///     title: LanguageService.t('delete_tower'),
///     message: 'Delete "${tower['name']}"? This will also affect all '
///               'floors and flats in this tower.',
///     icon: Icons.delete_outline,
///     iconColor: Colors.red,
///     confirmText: 'Delete',
///     danger: true,
///   );
///   if (ok == true) { ... }
///
///   await AmsDialog.info(context, title: LanguageService.t('saved'), message: LanguageService.t('plan_updated'));
class AmsDialog {
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.help_outline_rounded,
    Color? iconColor,
    String confirmText = 'Yes, proceed',
    String cancelText = 'Cancel',
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final accent = danger ? Colors.red : (iconColor ?? theme.colorScheme.primary);

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: accent.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(cancelText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: accent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmText),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// A single-field text prompt — reason for rejection, a short note, a
  /// remark to attach to an action — styled with the same icon-circle
  /// header as [confirm]/[info] and the app's shared [AppFieldShell] input,
  /// instead of a bare `AlertDialog` + `TextField`.
  ///
  /// Returns the trimmed text, or null if the sheet was cancelled.
  static Future<String?> promptText(
    BuildContext context, {
    required String title,
    String? message,
    required String label,
    String? hint,
    IconData icon = Icons.edit_note_rounded,
    Color? iconColor,
    String confirmText = 'Submit',
    String cancelText = 'Cancel',
    int maxLines = 3,
    String? initialValue,
    bool danger = false,
    bool requireValue = false,
    TextInputType? keyboardType,
  }) async {
    final theme = Theme.of(context);
    final accent = danger ? Colors.red : (iconColor ?? theme.colorScheme.primary);
    final ctrl = TextEditingController(text: initialValue ?? '');
    final formKey = GlobalKey<FormState>();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: accent.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, color: accent, size: 30),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
              ],
              const SizedBox(height: 20),
              AppFieldShell(
                accent: accent,
                child: TextFormField(
                  controller: ctrl,
                  maxLines: maxLines,
                  keyboardType: keyboardType,
                  decoration: appFieldDecoration(label: label, hint: hint, accent: accent),
                  validator: requireValue
                      ? (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null
                      : null,
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(cancelText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: accent),
                    onPressed: () {
                      if (requireValue && !(formKey.currentState?.validate() ?? true)) return;
                      Navigator.pop(ctx, true);
                    },
                    child: Text(confirmText),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    return submitted == true ? ctrl.text.trim() : null;
  }

  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.check_circle_outline_rounded,
    Color? iconColor,
    String buttonText = 'OK',
  }) {
    final theme = Theme.of(context);
    final accent = iconColor ?? theme.colorScheme.primary;

    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: accent.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: () => Navigator.pop(ctx),
                child: Text(buttonText),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
