import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/user_roles.dart';

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String role; // skilled_user, customer, company, admin
  final String? phone;
  final String? profilePhoto;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final bool? isSuspended;
  final Map<String, dynamic>? avatarConfig;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.phone,
    this.profilePhoto,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.isSuspended,
    this.avatarConfig,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    final rawRole = ((map['role'] ??
            map['userRole'] ??
            map['user_role'] ??
            map['type']) as String?) ??
        '';
    final normalizedRole = UserRoles.normalizeRole(rawRole) ?? rawRole;

    final rawEmail = ((map['email'] ??
            map['userEmail'] ??
            map['user_email'] ??
            map['contactEmail'] ??
            map['mail']) as String?) ??
        '';

    final rawName = ((map['name'] ??
            map['displayName'] ??
            map['fullName'] ??
            map['userName']) as String?) ??
        '';

    return UserModel(
      uid: uid,
      email: rawEmail,
      name: rawName,
      role: normalizedRole,
      phone: map['phone'],
      profilePhoto: map['profilePhoto'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] ?? true,
      isSuspended: map['isSuspended'] as bool?,
      avatarConfig: map['avatarConfig'] is Map
          ? Map<String, dynamic>.from(map['avatarConfig'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      if (phone != null) 'phone': phone,
      if (profilePhoto != null) 'profilePhoto': profilePhoto,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
      if (isSuspended != null) 'isSuspended': isSuspended,
      if (avatarConfig != null) 'avatarConfig': avatarConfig,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? phone,
    String? profilePhoto,
    bool? isActive,
    bool? isSuspended,
    Map<String, dynamic>? avatarConfig,
  }) {
    return UserModel(
      uid: uid,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      isActive: isActive ?? this.isActive,
      isSuspended: isSuspended ?? this.isSuspended,
      avatarConfig: avatarConfig ?? this.avatarConfig,
    );
  }
}
