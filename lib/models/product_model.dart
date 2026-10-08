import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_constants.dart';

class ProductModel {
  final String id;
  final String userId;
  final String sourceType; // seller, skillshare
  final String? displayShopName;
  final String? assignedByAdminId;
  final String name;
  final String description;
  final double price;
  final List<String> images;
  final String category;
  final int stock;
  final bool isAvailable;
  final double rating;
  final int reviewCount;
  final String type; // 'product' or 'service'
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductModel({
    required this.id,
    required this.userId,
    this.sourceType = 'seller',
    this.displayShopName,
    this.assignedByAdminId,
    required this.name,
    required this.description,
    required this.price,
    this.images = const [],
    required this.category,
    this.stock = 0,
    this.isAvailable = true,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.type = AppConstants.listingTypeProduct,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isService => type == AppConstants.listingTypeService;
  bool get isPhysicalProduct => type != AppConstants.listingTypeService;

  static List<String> _extractImages(Map<String, dynamic> map) {
    final List<String> result = [];

    void addCleanUrl(dynamic raw) {
      if (raw == null) return;
      var str = raw.toString().trim();
      if (str.isEmpty || str.length < 5) return;
      if (str.startsWith('http://')) {
        str = 'https://${str.substring(7)}';
      }
      if (!result.contains(str)) {
        result.add(str);
      }
    }

    // Try array fields first
    final candidateLists = [
      map['images'],
      map['imageUrls'],
      map['photos'],
      map['media'],
    ];
    for (final candidate in candidateLists) {
      if (candidate is List) {
        for (final item in candidate) {
          addCleanUrl(item);
        }
      } else if (candidate is String && candidate.trim().isNotEmpty) {
        if (candidate.contains(',')) {
          for (final part in candidate.split(',')) {
            addCleanUrl(part);
          }
        } else {
          addCleanUrl(candidate);
        }
      }
    }

    // Also try single-string image fields if empty or additional
    final candidateStrings = [
      map['imageUrl'],
      map['image'],
      map['productImage'],
      map['photoUrl'],
      map['thumbnail'],
    ];
    for (final candidate in candidateStrings) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        addCleanUrl(candidate);
      }
    }

    return result;
  }

  factory ProductModel.fromMap(Map<String, dynamic> map, String id) {
    String normalizeId(dynamic value) => value?.toString().trim() ?? '';
    final userId = normalizeId(map['userId']);
    final sellerId = normalizeId(map['sellerId']);
    final ownerId = normalizeId(map['ownerId']);
    final uid = normalizeId(map['uid']);
    final resolvedUserId = userId.isNotEmpty
        ? userId
        : sellerId.isNotEmpty
            ? sellerId
            : ownerId.isNotEmpty
                ? ownerId
                : uid;
    final rawSourceType = (map['sourceType'] as String?)?.trim().toLowerCase();
    final sourceType = rawSourceType != null && rawSourceType.isNotEmpty
        ? rawSourceType
        : (map['isSkillShareProduct'] == true ? 'skillshare' : 'seller');

    final rawType = (map['type'] ?? map['productType'] ?? map['listingType'])
        ?.toString()
        .trim()
        .toLowerCase();
    final type = (rawType == AppConstants.listingTypeService || rawType == 'service')
        ? AppConstants.listingTypeService
        : AppConstants.listingTypeProduct;

    final resolvedImages = _extractImages(map);

    return ProductModel(
      id: id,
      userId: resolvedUserId,
      sourceType: sourceType,
      displayShopName: (map['displayShopName'] as String?)?.trim(),
      assignedByAdminId: (map['assignedByAdminId'] as String?)?.trim(),
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      images: resolvedImages,
      category: map['category'] ?? '',
      stock: (map['stock'] ?? 0) is num ? (map['stock'] as num).toInt() : int.tryParse(map['stock']?.toString() ?? '0') ?? 0,
      isAvailable: map['isAvailable'] ?? true,
      rating: (map['rating'] ?? 0.0).toDouble(),
      reviewCount: (map['reviewCount'] ?? 0) is num ? (map['reviewCount'] as num).toInt() : int.tryParse(map['reviewCount']?.toString() ?? '0') ?? 0,
      type: type,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sourceType': sourceType,
      if (displayShopName != null && displayShopName!.isNotEmpty)
        'displayShopName': displayShopName,
      if (assignedByAdminId != null && assignedByAdminId!.isNotEmpty)
        'assignedByAdminId': assignedByAdminId,
      'name': name,
      'description': description,
      'price': price,
      'images': images,
      'imageUrl': images.isNotEmpty ? images.first : '',
      'image': images.isNotEmpty ? images.first : '',
      'category': category,
      'stock': stock,
      'isAvailable': isAvailable,
      'rating': rating,
      'reviewCount': reviewCount,
      'type': type,
      'productType': type,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
