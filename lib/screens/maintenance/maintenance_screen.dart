import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/branding_service.dart';
import '../../services/maintenance_service.dart';

import '../../services/language_service.dart';
/// Full-screen, non-dismissible maintenance gate. Shown whenever the
/// Super Admin has switched Maintenance Mode on (Settings > Maintenance)
/// and the current user isn't a Super Admin — including someone who was
/// never logged in at all. See main.dart's router redirect logic (checked
/// at startup) and ApiService._checkStatus (checked on every authenticated
/// call, so an already-open session gets forced here mid-use too).
///
/// Mirrors the web's resources/views/admin/maintenance.blade.php design:
/// branded gradient, animated gear badge, and a silent background poll
/// that leaves automatically the moment Maintenance Mode is switched off
/// — no manual refresh needed, though "Check Again" is still there for
/// anyone who doesn't want to wait for the next poll.
class MaintenanceScreen extends StatefulWidget {
  final String? message;
  const MaintenanceScreen({super.key, this.message});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> with SingleTickerProviderStateMixin {
  bool _checking = false;
  Timer? _pollTimer;
  late final AnimationController _gearController;

  String get _message =>
      widget.message ?? MaintenanceService.current?.message ?? "We're currently performing scheduled maintenance. Please check back shortly.";

  @override
  void initState() {
    super.initState();
    _gearController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    // Same idea as the web page's background HEAD-poll: quietly check every
    // 15s and leave automatically once maintenance is switched back off.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _retry(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _gearController.dispose();
    super.dispose();
  }

  Future<void> _retry({bool silent = false}) async {
    if (!silent) setState(() => _checking = true);
    final info = await MaintenanceService.check();
    if (!mounted) return;
    if (!silent) setState(() => _checking = false);
    if (info == null || !info.enabled) {
      // Maintenance has been switched off (or the check failed, which we
      // don't want to keep the user stuck on) - let the router's normal
      // redirect logic decide where they land.
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final accent = BrandingService.accent;
    final primaryDark = Color.lerp(primary, Colors.black, 0.28)!;

    return PopScope(
      canPop: false, // no back button out of this screen, by design
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primary, primaryDark],
            ),
          ),
          child: Stack(
            children: [
              // Faint drifting gear icons for texture, matching the web page.
              Positioned(top: -30, left: -30, child: _bgIcon(Icons.settings_rounded, 130)),
              Positioned(bottom: -40, right: -30, child: _bgIcon(Icons.settings_rounded, 170)),
              Positioned(top: 140, right: 30, child: _bgIcon(Icons.build_rounded, 70)),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 40, offset: const Offset(0, 20)),
                          ],
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          if (BrandingService.appLogoUrl != null) ...[
                            Image.network(
                              BrandingService.appLogoUrl!,
                              height: 40,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Gear badge with a dashed rotating ring + a gear
                          // that gently rocks back and forth.
                          SizedBox(
                            width: 96,
                            height: 96,
                            child: Stack(alignment: Alignment.center, children: [
                              RotationTransition(
                                turns: _gearController,
                                child: CustomPaint(size: const Size(96, 96), painter: _DashedRingPainter(accent)),
                              ),
                              Container(
                                width: 76, height: 76,
                                decoration: BoxDecoration(color: primary.withOpacity(0.08), shape: BoxShape.circle),
                              ),
                              AnimatedBuilder(
                                animation: _gearController,
                                builder: (_, child) {
                                  final t = _gearController.value;
                                  final angle = (t < 0.5 ? t : 1 - t) * 0.6 - 0.15; // gentle rock
                                  return Transform.rotate(angle: angle, child: child);
                                },
                                child: Icon(Icons.settings_rounded, size: 40, color: primary),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 20),

                          Text(LanguageService.t('scheduled_maintenance'),
                              style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          Text(LanguageService.t('well_be_right_back'),
                              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: primaryDark),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text(
                            _message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13.5, height: 1.45),
                          ),
                          const SizedBox(height: 22),

                          // Indeterminate progress bar, same visual language
                          // as the web page.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: 5,
                              child: LinearProgressIndicator(
                                backgroundColor: const Color(0xFFEEF1F5),
                                valueColor: AlwaysStoppedAnimation(accent),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _PulsingDot(color: const Color(0xFFF59E0B)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(LanguageService.t('checking_automatically_in_the_background'),
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12), textAlign: TextAlign.center),
                            ),
                          ]),
                          const SizedBox(height: 22),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _checking ? null : () => _retry(),
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: _checking
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(LanguageService.t('check_again'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Super Admin is never blocked, but we have no way of
                          // knowing who's tapping this before they enter
                          // credentials - so we simply offer the login form; the
                          // server rejects anyone who isn't Super Admin with
                          // this same maintenance message.
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(LanguageService.t('login_as_administrator'), style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bgIcon(IconData icon, double size) => Icon(icon, size: size, color: Colors.white.withOpacity(0.06));
}

/// Small pulsing status dot, like a "live" indicator.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final scale = 1.0 + (0.9 * (1 - (_c.value - 0.5).abs() * 2)).clamp(0.0, 1.0) * 0.6;
        final opacity = (1 - _c.value).clamp(0.0, 1.0);
        return Stack(alignment: Alignment.center, children: [
          Transform.scale(
            scale: scale,
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withOpacity(opacity * 0.5)),
            ),
          ),
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
        ]);
      },
    );
  }
}

/// Dashed circular ring drawn behind the gear icon.
class _DashedRingPainter extends CustomPainter {
  final Color color;
  _DashedRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const dashCount = 24;
    const gapFraction = 0.4;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = (i / dashCount) * 2 * 3.14159265;
      final sweep = (2 * 3.14159265 / dashCount) * (1 - gapFraction);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) => oldDelegate.color != color;
}
