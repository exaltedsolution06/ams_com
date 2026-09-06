import 'package:flutter/material.dart';

import '../services/language_service.dart';
/// The fuller "hero" field treatment used on the login screen — a small
/// circular icon chip inside the field, plus a soft accent-tinted shadow
/// around it — factored out here so every form screen can reuse the exact
/// same look instead of re-implementing it (and drifting out of sync)
/// file by file.
///
/// Usage:
///   AppFieldShell(
///     accent: BrandingService.primary,
///     child: TextFormField(
///       decoration: appFieldDecoration(label: LanguageService.t('full_name'), icon: Icons.person_outline, accent: BrandingService.primary),
///       ...
///     ),
///   )
class AppFieldShell extends StatelessWidget {
  final Color accent;
  final Widget child;
  const AppFieldShell({super.key, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: child,
    );
  }
}

/// Small circular "chip" behind a field's leading icon, tinted with
/// whichever brand color that field is paired with.
Widget _iconChip(IconData icon, Color color) => Padding(
      padding: const EdgeInsets.all(11),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)),
        child: Icon(icon, size: 17, color: color),
      ),
    );

/// Drop-in replacement for a plain `InputDecoration(labelText: ...)` that
/// adds the icon chip and keeps the app-wide rounded/white-fill look (see
/// main.dart's inputDecorationTheme) while layering the field's accent
/// color into the icon and focus border.
InputDecoration appFieldDecoration({
  required String label,
  IconData? icon,
  required Color accent,
  Widget? suffix,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : _iconChip(icon, accent),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent, width: 1.8)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.red.shade300)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.red.shade400, width: 1.8)),
    labelStyle: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500),
    floatingLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w600),
  );
}
