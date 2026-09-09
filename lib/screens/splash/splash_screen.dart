import 'package:flutter/material.dart';
import '../../widgets/splash_grid_painter.dart';

/// Shown immediately on cold start, before branding has loaded and before
/// AppBootstrap (see main.dart) has finished checking for a mandatory
/// update, maintenance mode, and the current session. Uses the default
/// brand colors (not BrandingService, which isn't ready yet) so this
/// never flashes unstyled/white before the real theme kicks in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message});

  /// Optional status line under the loader (e.g. "Checking for updates…").
  /// Defaults to a generic "Loading…" when omitted.
  final String? message;

  static const _primary = Color(0xFF2563EB);
  static const _secondary = Color(0xFF1A3C5E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Full-page diagonal brand gradient, matching the login header's
        // primary → secondary story but stretched across the whole screen
        // instead of just a hero strip.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_secondary, _primary],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Uniform grid of soft rounded squares across the entire
            // background — the same "building facade" motif as the login
            // header's window grid, but even/untapered top-to-bottom since
            // it now covers the full page rather than a short hero strip.
            const Positioned.fill(child: SplashWindowGrid()),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // Logo mark in a large white rounded badge, same shape
                  // language as the login header's circle but sized up
                  // to read as a proper splash centerpiece.
                  Container(
                    width: 140,
                    height: 140,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 10)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/default_logo.png',
                      height: 140,
                      width: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.apartment_rounded, size: 68, color: _primary),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Apartment Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Company',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(flex: 3),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.6, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message ?? 'Loading…',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
