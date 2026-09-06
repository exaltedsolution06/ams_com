import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';
import '../main.dart' show router;

/// Handles Firebase initialisation and keeping the backend's `fcm_token`
/// column in sync with the device's current push token.
///
/// Call [init] once at app startup (before login, so Firebase itself is
/// ready), and call [registerToken] right after a successful login. A
/// listener is also attached for token refreshes (FCM tokens can rotate),
/// so a previously-logged-in user stays registered across app restarts.
///
/// ── Notification branding ──────────────────────────────────────────────
/// The backend (see SmsGatewayService::sendPushNotification) sends each
/// apartment's logo as `data.image_url` and brand primary color as
/// `data.color`, so a push notification shows the apartment's own logo as
/// a big-picture image and its brand color. When a push doesn't carry
/// either (or the image download fails), _showForegroundNotification
/// falls back to the app's bundled default_logo.png and a fixed brand
/// blue rather than leaving the notification plain - see _fallbackLogo/
/// _fallbackColor below. That's wired up for the app-open case; FCM's own
/// OS-level auto-display (app backgrounded/killed) reads the equivalent
/// `notification.image`/`android.notification.color` fields directly (or
/// falls back to the manifest's `default_notification_color` meta-data -
/// see AndroidManifest.xml), no app code needed for that case.
///
/// IMPORTANT — a real asset this repo's zip can't add for you: Android
/// requires a notification's SMALL icon (the one in the status bar) to be
/// a flat white/transparent silhouette, not a full-color image - pointing
/// it at your full-color launcher icon (the old default here) renders as
/// an ugly solid block, not your logo. You need to add, in your real
/// Flutter project:
///   1. A monochrome PNG (white shape, transparent background) at
///      android/app/src/main/res/drawable/ic_stat_notification.png
///      (and drawable-hdpi/xdpi/xxdpi variants for crisp scaling) - Android
///      Studio's Image Asset Studio ("Notification Icons" type) generates
///      these correctly from a single source image.
///   2. This meta-data in android/app/src/main/AndroidManifest.xml's
///      <application> tag, so FCM's own OS-level auto-display (app
///      backgrounded/killed) uses it too, not just this file's foreground path:
///        <meta-data android:name="com.google.firebase.messaging.default_notification_icon"
///                   android:resource="@drawable/ic_stat_notification" />
/// Until that drawable exists, both this file's `icon:` reference below
/// and the backend's `android.notification.icon` will silently fall back
/// to the launcher icon (Android ignores an unresolvable icon reference
/// rather than crashing) - so nothing breaks by adding the code changes
/// here first and the asset afterwards, but the status-bar icon won't
/// actually look right until the asset lands.
class FcmService {
  static bool _initialized = false;

  // Falls back here whenever a push doesn't carry its own apartment
  // logo/color (see _showForegroundNotification) — matches
  // BrandingService's default primary so an "unbranded" push still looks
  // like the app, not a bare system notification.
  static const _fallbackColor = Color(0xFF2563EB);
  static Uint8List? _fallbackLogoBytes;

  /// Loads the bundled default logo once and caches it, for use as the
  /// large icon when a push has no `data.image_url` (or the download
  /// fails). Returns null (silent, no fallback icon) if the asset is
  /// missing — a cosmetic miss shouldn't take the notification down.
  static Future<Uint8List?> _fallbackLogo() async {
    if (_fallbackLogoBytes != null) return _fallbackLogoBytes;
    try {
      final data = await rootBundle.load('assets/images/default_logo.png');
      _fallbackLogoBytes = data.buffer.asUint8List();
    } catch (e) {
      dev.log('Fallback logo load failed: $e', name: 'FcmService');
    }
    return _fallbackLogoBytes;
  }

  // FCM's "notification" payload is only auto-displayed by the OS while the
  // app is backgrounded/closed - when it's in the FOREGROUND, Android and
  // iOS both deliver the message to onMessage silently and show nothing on
  // their own. flutter_local_notifications is what actually puts a banner
  // on screen for that case; without wiring it up (as before), a push that
  // arrives while someone's actively using the app just vanishes.
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static const _androidChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'Important Notifications',
    description: 'Used for notices, complaints, approvals, and other push alerts.',
    importance: Importance.high,
  );

  /// Initialise Firebase and attach the token-refresh + notification-tap
  /// listeners. Safe to call multiple times — only runs once.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      _initialized = true;

      // Ask for notification permission (iOS requires this explicitly;
      // Android 13+ also requires it — see AndroidManifest POST_NOTIFICATIONS).
      await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );

      await _initLocalNotifications();

      // Foreground delivery - see _localNotifications comment above.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // If the token rotates while the user is logged in, push the new
      // one immediately so notifications don't silently stop arriving.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sendTokenIfLoggedIn(newToken);
      });

      // WhatsApp-style tap-to-open: app was in the background and the user
      // tapped the notification banner.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // App was fully closed and got opened BY tapping the notification —
      // check once at startup for this "cold start" case.
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) _handleNotificationTap(initialMessage);
    } catch (e) {
      // Don't block app startup if Firebase isn't configured on this
      // build (e.g. google-services.json missing) — just log it.
      dev.log('FCM init failed: $e', name: 'FcmService');
    }
  }

  static Future<void> _initLocalNotifications() async {
    // See class doc's "IMPORTANT" note - this drawable needs adding to your
    // real Android project; falls back to the launcher icon until then.
    const androidInit = AndroidInitializationSettings('ic_stat_notification');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      // Tap on the banner while the app is in the foreground - same
      // deep-link behaviour as tapping a background notification.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
          if (data['screen'] == 'chat') router.push('/chat');
        } catch (e) {
          dev.log('Notification payload decode failed: $e', name: 'FcmService');
        }
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return; // data-only message - nothing to show

    // Branding (see class doc): per-apartment values are preferred, but we
    // no longer leave a push fully unbranded when either is missing/fails
    // to parse or download - it falls back to the app's own logo and
    // brand blue so every push still looks intentional, not like a bare
    // system notification.
    final imageUrl = message.data['image_url'] as String?;
    final color = _parseHexColor(message.data['color'] as String?) ?? _fallbackColor;
    final bigPicture = imageUrl != null ? await _downloadImage(imageUrl) : null;
    final largeIconBytes = bigPicture ?? await _fallbackLogo();

    try {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id, _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high, priority: Priority.high,
            icon: 'ic_stat_notification',
            color: color,
            // Large icon: the small circular avatar next to the title,
            // always shown (apartment logo, or the app's own logo when
            // the push has none). Big picture: only shown when the push
            // actually sent a photo/logo to expand full-width - matches
            // how a WhatsApp/Gmail-style branded push looks, without
            // stretching a small app logo into a blurry banner.
            largeIcon: largeIconBytes != null ? ByteArrayAndroidBitmap(largeIconBytes) : null,
            styleInformation: bigPicture != null
                ? BigPictureStyleInformation(
                    ByteArrayAndroidBitmap(bigPicture),
                    largeIcon: largeIconBytes != null ? ByteArrayAndroidBitmap(largeIconBytes) : null,
                    contentTitle: notification.title,
                    summaryText: notification.body,
                  )
                : BigTextStyleInformation(
                    notification.body ?? '',
                    contentTitle: notification.title,
                  ),
          ),
          iOS: DarwinNotificationDetails(
            // iOS's own big-picture equivalent needs a Notification
            // Service Extension target this repo's zip can't add (no ios/
            // folder - see class doc's manifest note for the Android
            // equivalent of this same "asset the sandbox can't place"
            // caveat); attachments here are a no-op without it, so iOS
            // stays a plain (still correctly colored-by-the-OS) alert
            // until that extension exists in your real Xcode project.
            sound: 'default',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      dev.log('Foreground notification display failed: $e', name: 'FcmService');
    }
  }

  /// Best-effort image fetch for the notification's big-picture/large-icon -
  /// returns null (plain notification, no crash) on any failure: bad URL,
  /// network error, non-image response, timeout, etc. A cosmetic feature
  /// should never be the reason a notification fails to show at all.
  static Future<Uint8List?> _downloadImage(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return res.bodyBytes;
    } catch (e) {
      dev.log('Notification image download failed: $e', name: 'FcmService');
    }
    return null;
  }

  /// Parses a "#RRGGBB" hex string (as sent by ApartmentSetting::pushColor())
  /// into a Color - null on anything malformed/missing rather than throwing,
  /// since a mistyped brand color shouldn't take the whole notification down.
  static Color? _parseHexColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    return value != null ? Color(0xFF000000 | value) : null;
  }

  /// Deep-links straight into the relevant screen based on the
  /// notification's data payload (see NotificationService::sendToUser meta
  /// on the backend). Any future screen key just needs a case added here.
  static void _handleNotificationTap(RemoteMessage message) async {
    final screen = message.data['screen'];
    if (screen == 'chat') {
      router.push('/chat');
    } else if (screen == 'community_meeting') {
      // Same screen either way (CommunityMeetingScreen) - only the route
      // differs, mirroring AppDrawer's admin vs resident 'Meet Live' tiles.
      final role = await AuthService().effectiveRole();
      final isManager = role == 'apartment_admin' || role == 'company_admin' || role == 'super_admin';
      router.push(isManager ? '/admin/community-meeting' : '/community-meeting');
    }
  }

  /// Safe to call from anywhere (e.g. right before login) - returns null
  /// instead of throwing if Firebase never finished initialising (or isn't
  /// configured on this build), rather than letting a raw
  /// FirebaseMessaging.instance access blow up with "No Firebase App
  /// '[DEFAULT]' has been created".
  static Future<String?> getTokenSafely() async {
    if (!_initialized) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      dev.log('FCM getTokenSafely failed: $e', name: 'FcmService');
      return null;
    }
  }

  /// Fetch the current device token and register it with the backend.
  /// Call this right after login succeeds (and optionally on app resume
  /// for an already-logged-in user, as a safety net).
  static Future<String?> registerToken() async {
    if (!_initialized) return null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _sendTokenIfLoggedIn(token);
      }
      return token;
    } catch (e) {
      dev.log('FCM getToken failed: $e', name: 'FcmService');
      return null;
    }
  }

  static Future<void> _sendTokenIfLoggedIn(String token) async {
    final loggedIn = await AuthService().isLoggedIn();
    if (!loggedIn) return;
    try {
      await ApiService().post('/fcm-token', {'fcm_token': token});
    } catch (e) {
      dev.log('FCM token upload failed: $e', name: 'FcmService');
    }
  }
}
