import '../services/branding_service.dart';

/// Safely coerce a value coming back from the Laravel API into a bool.
///
/// Several backend models don't cast their `is_active`-style columns to
/// `boolean`, so MySQL's TINYINT(1) comes across the wire as a JSON integer
/// (1/0) rather than a JSON boolean (true/false). Doing `value as bool?` on
/// an int throws a TypeError in Dart instead of returning null, which is
/// what was crashing the Towers/Facilities/Vendors/General Categories/
/// Charge Setup screens. Use this helper instead of a raw cast anywhere an
/// API boolean flag is read.
bool toBool(dynamic value, {bool defaultValue = true}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes';
  }
  return defaultValue;
}

/// Safely coerce a value coming back from the Laravel API into a num.
///
/// Model attributes without a `decimal:2`-style cast (e.g. `price` on
/// SubscriptionPlan) come across the wire as JSON strings like "0.00"
/// rather than numbers, because MySQL DECIMAL columns are returned as
/// strings by the PDO driver. Comparing that directly (`price > 0`) throws
/// a NoSuchMethodError in Dart instead of a compile error, since the value
/// is `dynamic`. Use this helper instead of a raw cast anywhere an API
/// numeric field is read.
num toNum(dynamic value, {num defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? defaultValue;
  return defaultValue;
}

/// Format an API date string (e.g. "2026-07-10" or a full ISO timestamp)
/// into a friendly display honoring the current apartment's Date Format
/// (Profile > Settings > Date Format, default "01 Aug 2027" style). Falls
/// back to the raw string if it can't be parsed, so it never throws on
/// unexpected input.
String friendlyDate(dynamic value) {
  if (value == null) return '';
  return BrandingService.formatDateString(value.toString());
}

/// Same as [friendlyDate] but also includes the time, e.g. "10 Jul 2026, 2:30 PM".
String friendlyDateTime(dynamic value) {
  if (value == null) return '';
  return BrandingService.formatDateTimeString(value.toString());
}
