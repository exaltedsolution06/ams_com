import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// A single Quick Action grid item resolved from the Super Admin's menu
/// allocation for this apartment.
class QuickActionItem {
  final String key, label, route;
  final IconData icon;
  /// True when this item is outside the apartment's current subscription
  /// plan. Only ever true under Menu Visibility = "All" (Super Admin >
  /// Apartment > Edit) - under "plan_based" locked items aren't sent at all.
  final bool locked;
  const QuickActionItem({required this.key, required this.label, required this.route, required this.icon, this.locked = false});
}

/// A single Bottom Nav destination resolved from the Super Admin's menu
/// allocation for this apartment. Mirrors widgets/app_bottom_nav.dart's NavItem
/// but carries the extra fields MenuConfigService needs to build one.
class ResolvedNavItem {
  final String key, label, route;
  final IconData icon;
  final bool isHome;
  /// Outside the apartment's current plan. Bottom Nav items are never
  /// dropped for being locked (fixed 4-slot shape) - the UI is responsible
  /// for showing a padlock and blocking the tap instead.
  final bool locked;
  const ResolvedNavItem({required this.key, required this.label, required this.route, required this.icon, this.isHome = false, this.locked = false});
}

/// Full resolved bottom nav: Home + 3 flanking items + 1 centre item.
class ResolvedBottomNav {
  final List<ResolvedNavItem> flanking; // exactly 4, first is Home
  final ResolvedNavItem center;
  const ResolvedBottomNav({required this.flanking, required this.center});
}

/// Fetches the app menu (Quick Action + Bottom Nav) that the Super Admin has
/// allocated for this apartment/role, via GET /menu-settings/{role}. Falls
/// back to the screen's own hard-coded defaults whenever the fetch fails or
/// the Super Admin hasn't customized this apartment - callers pass those
/// defaults in so behaviour never regresses for un-configured apartments.
class MenuConfigService {
  // Maps every key the backend's MenuRegistry can send to a Flutter icon.
  // Keep in sync with app/Services/MenuRegistry.php on the backend.
  static const Map<String, IconData> _icons = {
    'home_rounded': Icons.home_rounded,
    'receipt_long': Icons.receipt_long,
    'receipt_long_rounded': Icons.receipt_long_rounded,
    'account_balance_wallet': Icons.account_balance_wallet,
    'account_balance_wallet_rounded': Icons.account_balance_wallet_rounded,
    'chat_bubble': Icons.chat_bubble,
    'chat_bubble_rounded': Icons.chat_bubble_rounded,
    'badge': Icons.badge,
    'badge_rounded': Icons.badge_rounded,
    'campaign': Icons.campaign,
    'campaign_rounded': Icons.campaign_rounded,
    'location_city': Icons.location_city,
    'location_city_rounded': Icons.location_city_rounded,
    'forum': Icons.forum,
    'forum_rounded': Icons.forum_rounded,
    'pie_chart': Icons.pie_chart,
    'contact_phone': Icons.contact_phone,
    'file_present': Icons.file_present,
    'notifications': Icons.notifications,
    'person': Icons.person,
    'person_rounded': Icons.person_rounded,
    'people': Icons.people,
    'people_rounded': Icons.people_rounded,
    'local_parking': Icons.local_parking,
    'local_parking_rounded': Icons.local_parking_rounded,
    'event_available': Icons.event_available,
    'event_available_rounded': Icons.event_available_rounded,
    'video_camera_front': Icons.video_camera_front,
    'add_comment_rounded': Icons.add_comment_rounded,
    // Bold rounded style to match every other Quick Action icon (badge_rounded,
    // receipt_long_rounded, etc.) - the plain 'card_giftcard' key is kept mapped
    // to the SAME rounded glyph (instead of the thin default one) so "Refer a
    // Society" looks consistent no matter which of the two keys the backend sends.
    'card_giftcard': Icons.card_giftcard_rounded,
    'card_giftcard_rounded': Icons.card_giftcard_rounded,
    // Approvals (Merged Approvals Center) - keep in sync with
    // app/Services/MenuRegistry.php ADMIN_QUICK_ACTION / ADMIN_BOTTOM_NAV.
    'fact_check': Icons.fact_check,
    'fact_check_rounded': Icons.fact_check_rounded,
    // Rules - keep in sync with app/Services/MenuRegistry.php RESIDENT/ADMIN
    // *_QUICK_ACTION and *_BOTTOM_NAV 'rules' entries.
    'menu_book': Icons.menu_book,
    'menu_book_rounded': Icons.menu_book_rounded,
    // Community Forum - keep in sync with app/Services/MenuRegistry.php
    // RESIDENT/ADMIN *_QUICK_ACTION 'forum' entries. Deliberately not the
    // 'forum'/'forum_rounded' glyph above - that's already used for the
    // 'chat' key, and Chat/Forum are two different screens.
    'groups_rounded': Icons.groups_rounded,
  };

  static IconData _iconFor(String key) => _icons[key] ?? Icons.apps_rounded;

  static List<QuickActionItem> _quickFromJson(List data) => data.map((e) {
    final m = e as Map<String, dynamic>;
    return QuickActionItem(
      key: m['key'] as String,
      label: m['label'] as String,
      route: m['route'] as String,
      icon: _iconFor(m['icon'] as String? ?? ''),
      locked: m['locked'] == true,
    );
  }).toList();

  static ResolvedBottomNav _navFromJson(Map<String, dynamic> data) {
    final flanking = (data['flanking'] as List).map((e) {
      final m = e as Map<String, dynamic>;
      return ResolvedNavItem(
        key: m['key'] as String,
        label: m['label'] as String,
        route: m['route'] as String,
        icon: _iconFor(m['icon'] as String? ?? ''),
        isHome: m['is_home'] == true,
        locked: m['locked'] == true,
      );
    }).toList();
    final c = data['center'] as Map<String, dynamic>;
    final center = ResolvedNavItem(
      key: c['key'] as String, label: c['label'] as String, route: c['route'] as String,
      icon: _iconFor(c['icon'] as String? ?? ''),
      locked: c['locked'] == true,
    );
    return ResolvedBottomNav(flanking: flanking, center: center);
  }

  /// [role] is 'resident' or 'apartment_admin'. Returns null on any failure
  /// (offline, not yet configured on an old backend, etc.) so the caller can
  /// keep using its existing hard-coded layout.
  static Future<({List<QuickActionItem> quickActions, ResolvedBottomNav bottomNav})?> load(String role) async {
    // Try cache first so the UI has something to paint immediately.
    ({List<QuickActionItem> quickActions, ResolvedBottomNav bottomNav})? cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('menu_config_$role');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        cached = (
          quickActions: _quickFromJson(data['quick_action'] as List),
          bottomNav: _navFromJson(data['bottom_nav'] as Map<String, dynamic>),
        );
      }
    } catch (_) {}

    try {
      final res = await ApiService().get('/menu-settings/$role');
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return cached;

      final result = (
        quickActions: _quickFromJson(data['quick_action'] as List),
        bottomNav: _navFromJson(data['bottom_nav'] as Map<String, dynamic>),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('menu_config_$role', jsonEncode(data));

      return result;
    } catch (_) {
      return cached; // offline / error -> use cache if we had one
    }
  }
}
