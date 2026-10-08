import 'package:cloud_firestore/cloud_firestore.dart';

/// Customer Profile Model
/// Represents a customer's profile with their interests and preferences
/// Customers specify WHAT THEY NEED, not what skills they have
class CustomerProfile {
  final String userId;
  final String bio;
  final List<String> interests; // What they're interested in (e.g., "DIY projects", "Home improvement")
  final List<String> lookingFor; // Service categories they need (e.g., "Carpenter", "Baker", "Electrician")
  final String? profilePicture;
  final String? location;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final double? latitude;
  final double? longitude;
  final List<String> preferredCategories; // Skill categories they frequently search for
  final Map<String, dynamic>? preferences; // Additional preferences (budget range, distance, etc.)
  /// Projects assigned by this customer (request IDs or project titles).
  final List<Map<String, dynamic>> assignedProjects;
  /// Banner customisation data (image or styled text).
  final Map<String, dynamic>? bannerData;
  /// Emoji avatar key (e.g. 'avatar_smile'). When set, shown instead of photo.
  final String? avatarKey;
  /// Animated avatar configuration.
  final Map<String, dynamic>? avatarConfig;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerProfile({
    required this.userId,
    this.bio = '',
    this.interests = const [],
    this.lookingFor = const [],
    this.profilePicture,
    this.location,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.latitude,
    this.longitude,
    this.preferredCategories = const [],
    this.preferences,
    this.assignedProjects = const [],
    this.bannerData,
    this.avatarKey,
    this.avatarConfig,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerProfile.fromMap(Map<String, dynamic> map, String userId) {
    final rawAddress = (map['address'] ?? map['location'] as String?)?.toString().trim();
    final rawLocation = (map['location'] ?? map['address'] as String?)?.toString().trim();
    final rawPincode = (map['pincode'] ?? map['postalCode'] ?? map['zip'] as String?)?.toString().trim();

    return CustomerProfile(
      userId: userId,
      bio: map['bio'] ?? '',
      interests: List<String>.from(map['interests'] ?? []),
      lookingFor: List<String>.from(map['lookingFor'] ?? []),
      profilePicture: map['profilePicture'],
      location: (rawLocation != null && rawLocation.isNotEmpty) ? rawLocation : null,
      address: (rawAddress != null && rawAddress.isNotEmpty) ? rawAddress : null,
      city: map['city'],
      state: map['state'],
      pincode: (rawPincode != null && rawPincode.isNotEmpty) ? rawPincode : null,
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      preferredCategories: List<String>.from(map['preferredCategories'] ?? []),
      preferences: map['preferences'],
      assignedProjects: (map['assignedProjects'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e is Map ? e : {}))
          .toList(),
      bannerData: map['bannerData'] is Map
          ? Map<String, dynamic>.from(map['bannerData'] as Map)
          : null,
      avatarKey: map['avatarKey'] as String?,
      avatarConfig: map['avatarConfig'] is Map
          ? Map<String, dynamic>.from(map['avatarConfig'] as Map)
          : null,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bio': bio,
      'interests': interests,
      'lookingFor': lookingFor,
      if (profilePicture != null) 'profilePicture': profilePicture,
      'location': location ?? address,
      if (address != null) 'address': address,
      'city': city,
      'state': state,
      if (pincode != null) 'pincode': pincode,
      'latitude': latitude,
      'longitude': longitude,
      'preferredCategories': preferredCategories,
      'preferences': preferences,
      'assignedProjects': assignedProjects,
      if (bannerData != null) 'bannerData': bannerData,
      if (avatarKey != null) 'avatarKey': avatarKey,
      if (avatarConfig != null) 'avatarConfig': avatarConfig,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  CustomerProfile copyWith({
    String? bio,
    List<String>? interests,
    List<String>? lookingFor,
    String? profilePicture,
    String? location,
    String? address,
    String? city,
    String? state,
    String? pincode,
    double? latitude,
    double? longitude,
    List<String>? preferredCategories,
    Map<String, dynamic>? preferences,
    List<Map<String, dynamic>>? assignedProjects,
    Map<String, dynamic>? bannerData,
    bool clearBanner = false,
    String? avatarKey,
    bool clearAvatar = false,
    Map<String, dynamic>? avatarConfig,
  }) {
    return CustomerProfile(
      userId: userId,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      lookingFor: lookingFor ?? this.lookingFor,
      profilePicture: profilePicture ?? this.profilePicture,
      location: location ?? this.location,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      preferredCategories: preferredCategories ?? this.preferredCategories,
      preferences: preferences ?? this.preferences,
      assignedProjects: assignedProjects ?? this.assignedProjects,
      bannerData: clearBanner ? null : (bannerData ?? this.bannerData),
      avatarKey: clearAvatar ? null : (avatarKey ?? this.avatarKey),
      avatarConfig: avatarConfig ?? this.avatarConfig,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
