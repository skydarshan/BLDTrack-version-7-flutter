class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.organisation,
    this.role,
    this.roleName,
    this.sites = const [],
  });

  final String id;
  final String name;
  final String email;
  final dynamic organisation;
  final dynamic role;
  final String? roleName;
  final List<dynamic> sites;

  String get displayRole {
    if (roleName != null && roleName!.trim().isNotEmpty) return roleName!;
    if (role is Map && role['name'] != null) return role['name'].toString();
    return 'User';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['_id'] ?? '';
    final role = json['role'];
    String? roleName = json['roleName']?.toString();
    if ((roleName == null || roleName.isEmpty) && role is Map) {
      roleName = role['name']?.toString();
    }

    return UserModel(
      id: id.toString(),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      organisation: json['organisation'],
      role: role,
      roleName: roleName,
      sites: json['sites'] is List ? List<dynamic>.from(json['sites'] as List) : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'organisation': organisation,
        'role': role,
        'roleName': roleName,
        'sites': sites,
      };

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    dynamic organisation,
    dynamic role,
    String? roleName,
    List<dynamic>? sites,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      organisation: organisation ?? this.organisation,
      role: role ?? this.role,
      roleName: roleName ?? this.roleName,
      sites: sites ?? this.sites,
    );
  }
}
