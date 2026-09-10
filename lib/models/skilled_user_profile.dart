import 'package:cloud_firestore/cloud_firestore.dart';

class SkilledUserProfile {
  final String userId;
  final String? name;
  final String bio;
  final List<String> skills;
  final String? category; // Home Baking, Handicrafts, Content Creation, etc.
  final String? profilePicture; // Profile photo URL
  final String verificationStatus; // pending, approved, rejected
  final String visibility; // public, private
  final List<String> portfolioImages;
  final List<String> portfolioVideos;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? city;
  final String? state;
  final Map<String, dynamic>? verificationData; // Aadhaar info
  final double rating;
  final int reviewCount;
  final int projectCount;
  final int profileViews;
  final bool isVerified;
  final DateTime? verifiedAt;
  final String? rejectionReason;

  /// Number of companies that have endorsed (liked) this professional.
  final int companyEndorsementCount;

  /// Banner customisation data (image or styled text).
  final Map<String, dynamic>? bannerData;

  /// Animated avatar configuration.
  final Map<String, dynamic>? avatarConfig;
  final DateTime createdAt;
  final DateTime updatedAt;

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  SkilledUserProfile({
    required this.userId,
    this.name,
    required this.bio,
    required this.skills,
    this.category,
    this.profilePicture,
    this.verificationStatus = 'pending',
    this.visibility = 'private',
    this.portfolioImages = const [],
    this.portfolioVideos = const [],
    this.latitude,
    this.longitude,
    this.address,
    this.city,
    this.state,
    this.verificationData,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.projectCount = 0,
    this.profileViews = 0,
    this.isVerified = false,
    this.verifiedAt,
    this.rejectionReason,
    this.companyEndorsementCount = 0,
    this.bannerData,
    this.avatarConfig,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SkilledUserProfile.fromMap(Map<String, dynamic> map, String userId) {
    final mappedUserId = (map['userId'] as String?)?.trim() ??
        (map['uid'] as String?)?.trim() ??
        (map['userUid'] as String?)?.trim() ??
        (map['ownerId'] as String?)?.trim() ??
        (map['createdBy'] as String?)?.trim() ??
        '';
    final effectiveUserId = mappedUserId.isNotEmpty ? mappedUserId : userId;

    List<String> asStringList(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList();
      }
      return const <String>[];
    }

    return SkilledUserProfile(
      userId: effectiveUserId,
      name: map['name'],
      bio: map['bio'] ?? '',
      skills: asStringList(map['skills']),
      category: map['category'],
      profilePicture: map['profilePicture'],
      verificationStatus: map['verificationStatus'] ?? 'pending',
      visibility: map['visibility'] ?? 'private',
      portfolioImages: asStringList(map['portfolioImages']),
      portfolioVideos: asStringList(map['portfolioVideos']),
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      address: map['address'],
      city: map['city'],
      state: map['state'],
      verificationData: map['verificationData'],
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      projectCount: map['projectCount'] ?? 0,
      profileViews: map['profileViews'] ?? 0,
      isVerified: map['isVerified'] ?? false,
      verifiedAt: (map['verifiedAt'] as Timestamp?)?.toDate(),
      rejectionReason: map['rejectionReason'],
      companyEndorsementCount: map['companyEndorsementCount'] ?? 0,
      bannerData: map['bannerData'] is Map
          ? Map<String, dynamic>.from(map['bannerData'] as Map)
          : null,
      avatarConfig: map['avatarConfig'] is Map
          ? Map<String, dynamic>.from(map['avatarConfig'] as Map)
          : null,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      if (name != null) 'name': name,
      'bio': bio,
      'skills': skills,
      'category': category,
      'profilePicture': profilePicture,
      'verificationStatus': verificationStatus,
      'visibility': visibility,
      'portfolioImages': portfolioImages,
      'portfolioVideos': portfolioVideos,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'city': city,
      'state': state,
      'verificationData': verificationData,
      'rating': rating,
      'reviewCount': reviewCount,
      'projectCount': projectCount,
      'profileViews': profileViews,
      'isVerified': isVerified,
      'verifiedAt': verifiedAt != null ? Timestamp.fromDate(verifiedAt!) : null,
      'rejectionReason': rejectionReason,
      'companyEndorsementCount': companyEndorsementCount,
      if (bannerData != null) 'bannerData': bannerData,
      'avatarConfig': avatarConfig,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  SkilledUserProfile copyWith({
    String? name,
    String? bio,
    List<String>? skills,
    String? category,
    String? profilePicture,
    String? verificationStatus,
    String? visibility,
    List<String>? portfolioImages,
    List<String>? portfolioVideos,
    double? latitude,
    double? longitude,
    String? address,
    String? city,
    String? state,
    Map<String, dynamic>? verificationData,
    double? rating,
    int? reviewCount,
    int? projectCount,
    int? profileViews,
    bool? isVerified,
    DateTime? verifiedAt,
    String? rejectionReason,
    int? companyEndorsementCount,
    Map<String, dynamic>? bannerData,
    Map<String, dynamic>? avatarConfig,
    bool clearBanner = false,
  }) {
    return SkilledUserProfile(
      userId: userId,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      skills: skills ?? this.skills,
      category: category ?? this.category,
      profilePicture: profilePicture ?? this.profilePicture,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      visibility: visibility ?? this.visibility,
      portfolioImages: portfolioImages ?? this.portfolioImages,
      portfolioVideos: portfolioVideos ?? this.portfolioVideos,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      verificationData: verificationData ?? this.verificationData,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      projectCount: projectCount ?? this.projectCount,
      profileViews: profileViews ?? this.profileViews,
      isVerified: isVerified ?? this.isVerified,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      companyEndorsementCount:
          companyEndorsementCount ?? this.companyEndorsementCount,
      bannerData: clearBanner ? null : (bannerData ?? this.bannerData),
      avatarConfig: avatarConfig ?? this.avatarConfig,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> get credentialSummary {
    final data = verificationData;
    if (data == null) return const <String, dynamic>{};
    final summary = data['credentialSummary'];
    if (summary is Map) {
      return Map<String, dynamic>.from(summary);
    }
    return const <String, dynamic>{};
  }

  bool get hasConfidentialCredentials =>
      credentialSummary['hasConfidentialCredentials'] == true;

  int get confidentialCredentialCount {
    final value = credentialSummary['verifiedCredentialCount'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  DateTime? get credentialsLastCheckedAt =>
      _readDate(credentialSummary['lastCheckedAt']);
}
