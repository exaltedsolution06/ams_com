import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/branding_service.dart';

/// Always-visible "Powered by Exalted Solution" footer widget.
/// Used inside resident app screens.
class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final b = BrandingService.current;
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(b.poweredByUrl);
        if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${b.poweredBy} ',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              'Exalted Solution',
              style: TextStyle(
                fontSize: 11,
                color: BrandingService.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
