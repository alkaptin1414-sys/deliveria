class UserProfile {
  UserProfile({
    required this.id,
    required this.phone,
    this.name,
    this.accountType,
    this.avatarUrl,
    this.notifOrders = true,
    this.notifChat = true,
    this.role = 'CUSTOMER',
    this.courierStatus,
  });

  final String id;
  final String phone;
  final String? name;
  final String? accountType;
  final String? avatarUrl;
  final bool notifOrders;
  final bool notifChat;
  final String role;
  final String? courierStatus;

  bool get isBusiness => accountType == 'BUSINESS';
  bool get isCourier => role == 'COURIER';
  bool get isAdmin => role == 'ADMIN';
  String get firstName {
    final value = (name ?? '').trim();
    if (value.isEmpty) return '';
    return value.split(' ').first;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String?,
      accountType: json['accountType'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      notifOrders: json['notifOrders'] as bool? ?? true,
      notifChat: json['notifChat'] as bool? ?? true,
      role: json['role'] as String? ?? 'CUSTOMER',
      courierStatus: json['courierStatus'] as String?,
    );
  }
}

class PlaceInput {
  PlaceInput({
    required this.name,
    required this.line,
    this.details,
    required this.lat,
    required this.lng,
  });

  final String name;
  final String line;
  final String? details;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {
        'name': name,
        'line': line,
        'details': details,
        'lat': lat,
        'lng': lng,
      };
}

class DeliveryOrder {
  DeliveryOrder(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get publicNumber => json['publicNumber'] as String;
  String get status => json['status'] as String;
  String get statusTitle => json['statusTitle'] as String? ?? status;
  Map<String, dynamic> get pickup => Map<String, dynamic>.from(json['pickup'] as Map);
  Map<String, dynamic> get dropoff => Map<String, dynamic>.from(json['dropoff'] as Map);
  Map<String, dynamic>? get courier => json['courier'] == null ? null : Map<String, dynamic>.from(json['courier'] as Map);
  int get totalMinor => json['totalMinor'] as int;
  String get totalLabel => json['totalLabel'] as String? ?? '';
  int get etaMinutes => json['etaMinutes'] as int? ?? 0;
  int get distanceMeters => json['distanceMeters'] as int? ?? 0;
  DateTime get createdAt => DateTime.parse(json['createdAt'] as String);
  bool get active => !['DELIVERED', 'CANCELLED', 'NO_COURIER'].contains(status);
}

class SavedAddress {
  SavedAddress(this.json);
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  String get line => json['line'] as String;
  String get label => json['label'] as String;
  bool get isDefault => json['isDefault'] as bool? ?? false;
  double get lat => (json['lat'] as num).toDouble();
  double get lng => (json['lng'] as num).toDouble();
  String? get details => json['details'] as String?;
  String get governorate => json['governorate'] as String? ?? '';
  String get city => json['city'] as String? ?? '';
  String get area => json['area'] as String? ?? '';
}
