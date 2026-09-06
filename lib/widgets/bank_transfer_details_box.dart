import 'package:flutter/material.dart';
import '../services/branding_service.dart';
import '../services/language_service.dart';

/// Mirrors the website's bank-transfer details box (resident.bills.show /
/// One-Time Charges / Wallet blades): Account Holder, Account Number, IFSC
/// Code, and Bank (if set), shown right below a Payment Method dropdown
/// once "Bank Transfer" is selected — so the resident always knows exactly
/// which account to transfer to before submitting the claim.
///
/// Shared by the Maintenance Bill, One-Time Charge, and Wallet deposit pay
/// sheets — all three offer the same Bank Transfer option and should show
/// the same details, same as the website.
class BankTransferDetailsBox extends StatelessWidget {
  final Map details;
  const BankTransferDetailsBox({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final accountHolder = details['account_holder']?.toString();
    final accountNumber = details['account_number']?.toString();
    final ifscCode = details['ifsc_code']?.toString();
    final bankName = details['bank_name']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.account_balance_outlined, size: 16, color: BrandingService.primary),
            const SizedBox(width: 6),
            Text(LanguageService.t('bank_transfer_details_title'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          if (accountHolder != null && accountHolder.isNotEmpty)
            _row(LanguageService.t('account_holder_name'), accountHolder),
          if (accountNumber != null && accountNumber.isNotEmpty)
            _row(LanguageService.t('account_number'), accountNumber),
          if (ifscCode != null && ifscCode.isNotEmpty)
            _row(LanguageService.t('ifsc_code'), ifscCode),
          if (bankName != null && bankName.isNotEmpty)
            _row(LanguageService.t('bank_name'), bankName),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
