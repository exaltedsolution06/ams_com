import 'package:flutter/foundation.dart';

/// Bump [tick] whenever global app-wide state that isn't tied to Flutter's
/// normal widget tree (e.g. static services like LanguageService or
/// BrandingService) changes, so the root app widget can listen and force
/// a full rebuild. Without this, screens already built and sitting in the
/// navigation stack keep showing stale text/colors until they happen to
/// rebuild for an unrelated reason.
class AppRefresh {
  static final ValueNotifier<int> tick = ValueNotifier(0);

  static void bump() => tick.value++;
}
