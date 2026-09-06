class FlatRef {
  final int id;
  final String flatNumber;
  final String? tower;
  final String? floor;
  final bool isPrimary;

  FlatRef({
    required this.id,
    required this.flatNumber,
    this.tower,
    this.floor,
    this.isPrimary = false,
  });

  factory FlatRef.fromJson(Map<String, dynamic> json) => FlatRef(
    id: json['id'],
    flatNumber: json['flat_number']?.toString() ?? '',
    tower: json['tower'],
    floor: json['floor'],
    isPrimary: json['is_primary'] == true,
  );

  /// e.g. "A-204 (Tower B)"
  String get label => tower != null ? '$flatNumber ($tower)' : flatNumber;
}

class UserModel {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? occupancyType;
  final int? apartmentId;
  final int? flatId;
  final List<FlatRef> flats;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.occupancyType,
    this.apartmentId,
    this.flatId,
    this.flats = const [],
  });

  /// True once this resident has more than one flat linked to their account.
  bool get hasMultipleFlats => flats.length > 1;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'],
    name: json['name'],
    email: json['email'],
    phone: json['phone'],
    role: json['role'],
    occupancyType: json['occupancy_type'],
    apartmentId: json['apartment_id'],
    flatId: json['flat_id'],
    flats: (json['flats'] as List<dynamic>? ?? [])
        .map((f) => FlatRef.fromJson(f as Map<String, dynamic>))
        .toList(),
  );
}
