/// Result of parsing a piece of recognized speech into something the app
/// can act on. Sealed-style via a base class + `is` checks (no external
/// package needed) so `VoiceCommandButton` can switch on the concrete type.
sealed class VoiceIntent {
  const VoiceIntent();
}

/// "Open billing", "show visitors", "go to notices" etc. - matched a known
/// menu item. Acted on immediately (no confirmation - same as tapping the
/// menu item itself).
class NavigateIntent extends VoiceIntent {
  final String route;
  final String label;
  const NavigateIntent(this.route, this.label);
}

/// "Generate bill for Suresh, July 2026". Data command - requires the
/// confirmation screen before executing.
class GenerateBillIntent extends VoiceIntent {
  final String residentQuery; // raw name as heard, before fuzzy-matching to a resident record
  final int month;
  final int year;
  const GenerateBillIntent({required this.residentQuery, required this.month, required this.year});
}

/// "Approve payment for Priya". Data command - requires the confirmation
/// screen before executing.
class ApprovePaymentIntent extends VoiceIntent {
  final String residentQuery;
  const ApprovePaymentIntent({required this.residentQuery});
}

/// "Raise a complaint about water leakage" (resident). Data command -
/// requires the confirmation screen before executing.
class RaiseComplaintIntent extends VoiceIntent {
  final String description; // raw free text heard after the trigger phrase
  const RaiseComplaintIntent({required this.description});
}

/// "Add visitor Ramesh tomorrow 5pm" (resident). Data command - requires
/// the confirmation screen before executing.
class RegisterVisitorIntent extends VoiceIntent {
  final String visitorName;
  final DateTime? expectedAt; // null if no day/time could be parsed
  const RegisterVisitorIntent({required this.visitorName, this.expectedAt});
}

/// "Book the clubhouse for Saturday" (resident). Data command - requires
/// the confirmation screen (with editable date/time) before executing.
class BookFacilityIntent extends VoiceIntent {
  final String facilityQuery; // raw name as heard, before fuzzy-matching
  final DateTime? date; // null if no day could be parsed
  const BookFacilityIntent({required this.facilityQuery, this.date});
}

/// "Reject payment for Priya" (admin). Data command - requires the
/// confirmation screen (with a reason prompt) before executing.
class RejectPaymentIntent extends VoiceIntent {
  final String residentQuery;
  const RejectPaymentIntent({required this.residentQuery});
}

/// "Send a notice: water will be shut off tomorrow" (admin). Data command -
/// requires the confirmation screen (with editable title/message/target)
/// before executing.
class SendNoticeIntent extends VoiceIntent {
  final String message; // raw free text heard after the trigger phrase
  const SendNoticeIntent({required this.message});
}

/// "Check in Ramesh" (security). Data command - requires the confirmation
/// screen before executing.
class VisitorCheckInIntent extends VoiceIntent {
  final String visitorQuery;
  const VisitorCheckInIntent({required this.visitorQuery});
}

/// "Check out Ramesh" (security). Data command - requires the confirmation
/// screen before executing.
class VisitorCheckOutIntent extends VoiceIntent {
  final String visitorQuery;
  const VisitorCheckOutIntent({required this.visitorQuery});
}

/// "Logout" / "log me out" (any role). Acted on after a confirmation dialog
/// (same as tapping the existing Logout button, which also confirms first).
class LogoutIntent extends VoiceIntent {
  const LogoutIntent();
}

/// "Cancel my booking for the clubhouse" (resident). Data command -
/// requires the confirmation screen before executing.
class CancelBookingIntent extends VoiceIntent {
  final String facilityQuery; // raw name as heard, before fuzzy-matching
  const CancelBookingIntent({required this.facilityQuery});
}

/// "Resolve complaint for Priya" / "close complaint for Priya" (admin).
/// Data command - requires the confirmation screen (with editable status)
/// before executing.
class ResolveComplaintIntent extends VoiceIntent {
  final String residentQuery;
  const ResolveComplaintIntent({required this.residentQuery});
}

/// "Recharge wallet 500" / "add 500 to my wallet" (resident). Data command -
/// requires the confirmation screen (with editable amount/payment method)
/// before executing.
class RechargeWalletIntent extends VoiceIntent {
  final double? amount; // null if no number could be parsed from speech
  const RechargeWalletIntent({this.amount});
}

/// "Emergency" / "SOS" / "call security" (any role). Acted on after a
/// confirmation screen that surfaces the apartment's emergency contacts for
/// one-tap calling - never dials automatically on its own.
class EmergencySosIntent extends VoiceIntent {
  const EmergencySosIntent();
}

/// "Send a message: I'm running late" (any role, when Chat is enabled).
/// Data command - requires the confirmation screen (with editable text)
/// before executing.
class SendChatMessageIntent extends VoiceIntent {
  final String message; // raw free text heard after the trigger phrase
  const SendChatMessageIntent({required this.message});
}

/// "Approve booking for Priya" (admin). Data command - requires the
/// confirmation screen before executing.
class ApproveBookingIntent extends VoiceIntent {
  final String residentQuery;
  const ApproveBookingIntent({required this.residentQuery});
}

/// "Reject booking for Priya" (admin). Data command - requires the
/// confirmation screen (with a reason prompt) before executing.
class RejectBookingIntent extends VoiceIntent {
  final String residentQuery;
  const RejectBookingIntent({required this.residentQuery});
}

/// "Pay bill for July in cash" / "pay my bill" (resident). Data command -
/// requires the confirmation screen before executing. Only ever submits a
/// CASH payment request (awaiting admin confirmation, same as tapping Cash
/// on the Billing screen) - voice never initiates a card/UPI checkout.
class PayBillIntent extends VoiceIntent {
  final String monthQuery; // raw free text heard, used to find a matching outstanding bill
  const PayBillIntent({required this.monthQuery});
}

/// "Change language to Hindi" (any role). Data command - requires the
/// confirmation screen before executing.
class ChangeLanguageIntent extends VoiceIntent {
  final String languageQuery; // raw language name as heard
  const ChangeLanguageIntent({required this.languageQuery});
}

/// Heard speech didn't match anything in the known command set.
class UnknownIntent extends VoiceIntent {
  final String heardText;
  const UnknownIntent(this.heardText);
}
