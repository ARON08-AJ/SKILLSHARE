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
  final bool isVerified;
  final String? verificationStatus; // pending, submitted, approved, rejected
  final Map<String, dynamic>? verificationData;
  final String? rejectionReason;
  final String? vehicleType;
  final String? vehicleNumber;
  final String? licenseNumber;
  final String? operatingCity;
  final String? documentUrl;
  final DateTime? verifiedAt;

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
    this.isVerified = false,
    this.verificationStatus,
    this.verificationData,
    this.rejectionReason,
    this.vehicleType,
    this.vehicleNumber,
    this.licenseNumber,
    this.operatingCity,
    this.documentUrl,
    this.verifiedAt,
  });

  bool get isFullyVerified =>
      isVerified ||
      (verificationStatus?.toLowerCase().trim() == 'approved') ||
      (verificationStatus?.toLowerCase().trim() == 'verified');

  bool get isPendingVerification =>
      !isFullyVerified &&
      (verificationStatus?.toLowerCase().trim() == 'pending' ||
          verificationStatus?.toLowerCase().trim() == 'submitted');

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

    final verificationData = map['verificationData'] is Map
        ? Map<String, dynamic>.from(map['verificationData'] as Map)
        : null;

    final rawVerifStatus = ((map['verificationStatus'] ??
            map['approvalStatus'] ??
            verificationData?['status']) as String?)
        ?.trim();

    final isVerifiedVal = map['isVerified'] == true ||
        rawVerifStatus?.toLowerCase() == 'approved' ||
        rawVerifStatus?.toLowerCase() == 'verified' ||
        map['verifiedAt'] != null;

    final vehicleType = (map['vehicleType'] ?? verificationData?['vehicleType']) as String?;
    final vehicleNumber = (map['vehicleNumber'] ?? verificationData?['vehicleNumber']) as String?;
    final licenseNumber = (map['licenseNumber'] ?? verificationData?['licenseNumber']) as String?;
    final operatingCity = (map['operatingCity'] ?? map['city'] ?? verificationData?['operatingCity'] ?? verificationData?['city']) as String?;
    final documentUrl = (map['documentUrl'] ?? map['idDocumentUrl'] ?? verificationData?['documentUrl']) as String?;
    final rejectionReason = (map['rejectionReason'] ?? verificationData?['rejectionReason']) as String?;
    final verifiedAt = (map['verifiedAt'] as Timestamp?)?.toDate();

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
      isVerified: isVerifiedVal,
      verificationStatus: rawVerifStatus,
      verificationData: verificationData,
      rejectionReason: rejectionReason,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      licenseNumber: licenseNumber,
      operatingCity: operatingCity,
      documentUrl: documentUrl,
      verifiedAt: verifiedAt,
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
      'isVerified': isVerified,
      if (verificationStatus != null) 'verificationStatus': verificationStatus,
      if (verificationData != null) 'verificationData': verificationData,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (vehicleType != null) 'vehicleType': vehicleType,
      if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
      if (licenseNumber != null) 'licenseNumber': licenseNumber,
      if (operatingCity != null) 'operatingCity': operatingCity,
      if (documentUrl != null) 'documentUrl': documentUrl,
      if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
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
    bool? isVerified,
    String? verificationStatus,
    Map<String, dynamic>? verificationData,
    String? rejectionReason,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseNumber,
    String? operatingCity,
    String? documentUrl,
    DateTime? verifiedAt,
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
      isVerified: isVerified ?? this.isVerified,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationData: verificationData ?? this.verificationData,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      operatingCity: operatingCity ?? this.operatingCity,
      documentUrl: documentUrl ?? this.documentUrl,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
