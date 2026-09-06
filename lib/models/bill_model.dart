class BillModel {
  final int id;
  final String billNumber;
  final int billingMonth;
  final int billingYear;
  final double baseAmount;
  final double lateFee;
  final double totalAmount;
  final double paidAmount;
  final double outstanding;
  final String status;
  final String dueDate;

  BillModel({
    required this.id,
    required this.billNumber,
    required this.billingMonth,
    required this.billingYear,
    required this.baseAmount,
    required this.lateFee,
    required this.totalAmount,
    required this.paidAmount,
    required this.outstanding,
    required this.status,
    required this.dueDate,
  });

  factory BillModel.fromJson(Map<String, dynamic> json) => BillModel(
    id: json['id'],
    billNumber: json['bill_number'],
    billingMonth: json['billing_month'],
    billingYear: json['billing_year'],
    baseAmount: double.parse(json['base_amount'].toString()),
    lateFee: double.parse(json['late_fee'].toString()),
    totalAmount: double.parse(json['total_amount'].toString()),
    paidAmount: double.parse(json['paid_amount'].toString()),
    outstanding: double.parse(json['outstanding'].toString()),
    status: json['status'],
    dueDate: json['due_date'],
  );
}
