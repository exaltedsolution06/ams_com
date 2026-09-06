import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/branding_service.dart';
import '../services/language_service.dart';

/// The five CMS-page links ('Privacy Policy', 'Terms & Conditions',
/// 'Refund & Cancellation', 'EULA', 'Account Deletion') shown on the
/// Login and Register screens only - per spec there's no need to
/// duplicate them anywhere after the user is logged in. Each link opens
/// the matching route in main.dart, which renders the generic
/// CmsPageScreen for that slug.
///
/// Cookie Policy is deliberately NOT included here - it's a
/// website-only page (see the homepage/login-page footer on the web
/// side), not part of the app's legal links list.
List<Widget> buildLegalLinks(BuildContext context) {
  final entries = <(String, String)>[
    (LanguageService.t('privacy_policy'), '/privacy'),
    (LanguageService.t('terms_conditions'), '/terms'),
    ('Refund & Cancellation', '/refund-cancellation'),
    ('EULA', '/eula'),
    ('Account Deletion', '/account-deletion'),
  ];

  final widgets = <Widget>[];
  for (var i = 0; i < entries.length; i++) {
    if (i > 0) {
      widgets.add(Text('  ·  ', style: TextStyle(color: Colors.grey[500], fontSize: 12)));
    }
    final (label, path) = entries[i];
    widgets.add(GestureDetector(
      onTap: () => context.push(path),
      child: Text(label,
          style: TextStyle(color: BrandingService.primary, fontSize: 12, fontWeight: FontWeight.w600)),
    ));
  }
  return widgets;
}
