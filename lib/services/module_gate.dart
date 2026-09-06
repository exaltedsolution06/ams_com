import 'branding_service.dart';

/// Client-side mirror of app/Services/MenuModuleMap.php + the toggleable
/// module list in app/Services/ApartmentModuleCatalog.php on the backend.
///
/// Maps a Drawer tile / voice command key to the ApartmentModuleCatalog
/// module key that gates it, so AppDrawer and VoiceCommandCatalog can hide
/// an entry exactly when the Super Admin has switched that module OFF for
/// this apartment (Apartment > Branding > "Assign Menu") - the same modules
/// MenuSetting::resolveQuickAction/resolveBottomNav already filter out of
/// the Quick Action grid and Bottom Nav on the backend.
///
/// Keys with no entry here are core/ungated features (billing, wallet,
/// residents, dashboard, profile, ...) and are never hidden by this check.
/// `security_guard` is deliberately absent - it isn't a menu item, it's the
/// whole Security role/login, already blocked server-side at login
/// (Api\AuthController) - see ApartmentModuleCatalog's docblock.
///
/// Keep this map in sync with app/Services/MenuModuleMap.php when either
/// side adds/removes a toggleable module.
class ModuleGate {
  static const Map<String, String> _map = {
    'complaints'         : 'complaints',
    'complaint_raise'    : 'complaints',
    'reports_complaints' : 'reports',
    'visitors'           : 'visitors',
    'notices'            : 'notices',
    'facilities'         : 'facilities',
    'bookings'           : 'facilities',
    'my_bookings'        : 'facilities',
    'parking'            : 'parking',
    'chat'               : 'chat',
    'financial'          : 'reports',
    'reports_financial'  : 'reports',
    'reports_occupancy'  : 'reports',
    'emergency_numbers'  : 'emergency_numbers',
    'agreements'         : 'agreements',
    'referral'           : 'referral',
    'upi'                : 'upi',
  };

  /// True when [key]'s underlying module has been switched OFF for the
  /// current apartment - the entry should not be shown at all (not locked,
  /// not padlocked, simply not offered).
  static bool isOff(String key) {
    final module = _map[key];
    if (module == null) return false; // core/ungated, never hidden
    return BrandingService.isModuleOff(module);
  }
}
