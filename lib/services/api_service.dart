import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'maintenance_service.dart';
import '../main.dart' show router;

class ApiService {
	// Base URL is chosen at BUILD time via --dart-define, not hardcoded here,
	// so a release build can never accidentally ship pointed at localhost.
	//
	//   Local (desktop/web, server on same machine):
	//     flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
	//
	//   Local (Android emulator talking to host machine):
	//     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
	//
	//   Live server:
	//     flutter run --dart-define=API_BASE_URL=https://ams.exaltedsolution.com/api/v1
	//     (same flag for `flutter build apk` / `flutter build ios` release builds)
	//
	// If no flag is passed, it falls back to the local dev URL below —
	// intentionally the LEAST convenient default, so a forgotten flag is
	// obvious immediately (nothing loads) rather than silently working
	// against the wrong server.
	static const String baseUrl = String.fromEnvironment(
		'API_BASE_URL',
		defaultValue: 'https://ams.exaltedsolution.com/api/v1',
	);

  // Every request below is wrapped with this. Without it, a stalled or
  // unreachable connection (e.g. phone briefly drops off the local Wi-Fi,
  // dev server is slow to respond) leaves the caller's Future pending
  // forever - the screen just shows its loading spinner indefinitely with
  // no error, which reads as the app "hanging". Timing out turns that into
  // a normal caught exception the UI already knows how to display.
  static const Duration _timeout = Duration(seconds: 20);

  Future<http.Response> _withTimeout(Future<http.Response> req) {
    return req.timeout(
      _timeout,
      onTimeout: () => throw Exception('Request timed out. Please check your connection and try again.'),
    );
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (auth) {
      final token = await AuthService().getToken();
      if (token != null) h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  /// A Company Admin has no single apartment_id of their own - every
  /// /admin/* endpoint (dashboard, residents, billing, complaints, ...)
  /// needs to know WHICH of their apartments to operate on. Rather than
  /// touching every screen that calls one of those endpoints, we attach it
  /// here, once, centrally - using whichever apartment they last picked
  /// from the Company Dashboard (see AuthService.getSelectedApartmentId()).
  /// Every other role's apartment is resolved server-side from their own
  /// account, so this is a no-op for them.
  ///
  /// /menu-settings/{role} needs the same treatment even though it isn't
  /// under /admin/ - it's shared by resident/apartment_admin/security too,
  /// so it lives at the top level, but a Company Admin viewing the
  /// apartment_admin menu still needs to say which apartment that's for.
  Future<String> _withApartmentContext(String path) async {
    final needsApartmentContext = (path.startsWith('/admin/') && !path.startsWith('/admin/apartments'))
        || path.startsWith('/menu-settings/')
        || path.startsWith('/branding')
        || path.startsWith('/announcements');
    if (!needsApartmentContext) return path;
    final user = await AuthService().getUser();
    if (user?['role'] != 'company_admin') return path;
    final aptId = await AuthService().getSelectedApartmentId();
    if (aptId == null) return path; // server will 422 with a clear message
    final sep = path.contains('?') ? '&' : '?';
    return '$path${sep}apartment_id=$aptId';
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode == 503) {
      // Distinguish "platform is in Maintenance Mode" from a plain server
      // outage - only the former should force-navigate, since a real 503
      // (e.g. server briefly down) has no maintenance_mode body to read.
      Map? body;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) body = decoded;
      } catch (_) {}
      if (body != null && body['error'] == 'maintenance_mode') {
        final msg = body['message'] as String?;
        _forceMaintenance(msg);
        throw Exception(msg ?? 'The platform is currently under maintenance.');
      }
    }
    if (res.statusCode == 401) {
      // A 401 from /login itself (wrong password, unknown account, etc.)
      // is an authentication FAILURE, not an expired SESSION - there was
      // never a session to expire, since login is sent unauthenticated.
      // Previously this branch always forced a logout + showed the fixed
      // "session expired" text no matter which endpoint failed, so a wrong
      // password on the login screen showed a misleading message instead
      // of the server's actual "Invalid email/phone or password." Only
      // treat this as an expired session (and force the redirect-to-login
      // flow) when there was actually a token in play for this request.
      String msg = 'Your session has expired. Please login again.';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] != null) msg = body['message'];
      } catch (_) {}
      if (res.request?.headers['Authorization'] != null) {
        _forceLogout();
      }
      throw Exception(msg);
    }
    if (res.statusCode == 403) {
      String msg = 'You do not have permission to perform this action.';
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['message'] != null) msg = body['message'];
      } catch (_) {}
      throw Exception(msg);
    }
    if (res.statusCode == 422) {
      final body = jsonDecode(res.body);
      final errors = body['errors'] as Map?;
      if (errors != null) {
        throw Exception(errors.values.first is List ? errors.values.first[0] : errors.values.first);
      }
      throw Exception(body['message'] ?? 'Validation error');
    }
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body);
      throw Exception(body['message'] ?? 'Server error (${res.statusCode})');
    }
  }

  Future<Map<String, dynamic>> get(String path) async {
    path = await _withApartmentContext(path);
    final res = await _withTimeout(http.get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    ));
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data,
      {bool auth = true}) async {
    path = await _withApartmentContext(path);
    final res = await _withTimeout(http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(auth: auth),
      body: jsonEncode(data),
    ));
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) async {
    path = await _withApartmentContext(path);
    final res = await _withTimeout(http.put(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(data),
    ));
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    path = await _withApartmentContext(path);
    final res = await _withTimeout(http.delete(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    ));
    _checkStatus(res);
    if (res.body.isEmpty) return {'message': 'Deleted'};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Same as [delete] but sends a JSON body - used where the DELETE needs
  /// to carry data along with it (e.g. DELETE /account requiring the
  /// user's current password as confirmation).
  Future<Map<String, dynamic>> deleteWithBody(String path, Map<String, dynamic> data) async {
    path = await _withApartmentContext(path);
    final res = await _withTimeout(http.delete(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(data),
    ));
    _checkStatus(res);
    if (res.body.isEmpty) return {'message': 'Deleted'};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Multipart POST for endpoints that accept a file plus form fields
  /// (e.g. branding logo upload). [filePath] may be null to submit fields only.
  ///
  /// [httpMethod] lets callers target a PUT/PATCH route (e.g. updating an
  /// agreement's file). PHP doesn't populate $_FILES for a real PUT request,
  /// so we still send over the wire as POST and let Laravel's method-spoofing
  /// (the `_method` field) route it to the PUT handler.
  Future<Map<String, dynamic>> uploadMultipart(
    String path,
    Map<String, String> fields, {
    String? filePath,
    String fileField = 'app_logo',
    String httpMethod = 'POST',
  }) async {
    path = await _withApartmentContext(path);
    final uri = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest('POST', uri);
    final token = await AuthService().getToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.fields.addAll(fields);
    if (httpMethod.toUpperCase() != 'POST') {
      request.fields['_method'] = httpMethod.toUpperCase();
    }
    if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }
    final streamed = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw Exception('Upload timed out. Please check your connection and try again.'),
    );
    final res = await http.Response.fromStream(streamed);
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static bool _loggingOut = false;

  /// Clears the stale session and sends the user back to the login screen.
  /// Guarded so several 401s arriving around the same time (e.g. a screen
  /// that fires off multiple requests at once) only trigger this once.
  void _forceLogout() {
    if (_loggingOut) return;
    _loggingOut = true;
    AuthService().logout().then((_) {
      router.go('/login');
      _loggingOut = false;
    });
  }

  static bool _enteringMaintenance = false;

  /// Signs the user out and sends them to the Maintenance screen, right
  /// away, from wherever they were in the app - this is what makes an
  /// already-open session for a non-Super-Admin get "kicked out"
  /// immediately the moment Maintenance Mode is switched on server-side,
  /// the same way a 401 kicks an expired session back to /login. Guarded
  /// the same way _forceLogout is, so concurrent requests only fire once.
  void _forceMaintenance(String? message) {
    MaintenanceService.current = MaintenanceInfo(enabled: true, message: message);
    if (_enteringMaintenance) return;
    _enteringMaintenance = true;
    AuthService().logout().then((_) {
      router.go('/maintenance');
      _enteringMaintenance = false;
    });
  }
}
