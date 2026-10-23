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

  static String? getSuggestedImageUrl(String name, String category) {
    final lowerName = name.trim().toLowerCase();
    final lowerCat = category.trim().toLowerCase();

    if (lowerName.contains('aloe') || lowerName.contains('alovera')) {
      return 'https://images.unsplash.com/photo-1596547609652-9cf5d8d76921?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('areca') || lowerName.contains('palm')) {
      return 'https://images.unsplash.com/photo-1614594975525-e45190c55d0b?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('rose')) {
      return 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('pakoda') || lowerName.contains('pakora')) {
      return 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('spinach')) {
      return 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('tulsi') || lowerName.contains('basil')) {
      return 'https://images.unsplash.com/photo-1618375569909-3c8616cf7733?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('brinjal') || lowerName.contains('eggplant')) {
      return 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('bamboo')) {
      return 'https://images.unsplash.com/photo-1546842931-886c185b4c8c?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('neem')) {
      return 'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('coriander')) {
      return 'https://images.unsplash.com/photo-1592417817098-8f3d69109853?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('mint')) {
      return 'https://images.unsplash.com/photo-1628556270448-4d4e4148e1b1?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('curry')) {
      return 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('jasmine')) {
      return 'https://images.unsplash.com/photo-1587314168485-3236d6710814?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('hibiscus')) {
      return 'https://images.unsplash.com/photo-1550950158-d0d960dff51b?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('money plant') || lowerName.contains('pothos')) {
      return 'https://images.unsplash.com/photo-1614594975525-e45190c55d0b?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('snake plant') || lowerName.contains('sansevieria')) {
      return 'https://images.unsplash.com/photo-1593482892290-f54927ae1bf6?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('plant') || lowerCat.contains('garden')) {
      return 'https://images.unsplash.com/photo-1485955900006-10f4d324d411?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerName.contains('biryani') || lowerName.contains('rice') || lowerCat.contains('food')) {
      return 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=600&q=80';
    }
    if (lowerCat.contains('baking') || lowerName.contains('cake') || lowerName.contains('pastry')) {
      return 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?auto=format&fit=crop&w=600&q=80';
    }
    return null;
  }

  static List<String> _extractImages(Map<String, dynamic> map) {
    final List<String> result = [];

    void addCleanUrl(dynamic raw) {
      if (raw == null) return;
      if (raw is Map) {
        final mapUrl = raw['url'] ??
            raw['secure_url'] ??
            raw['downloadURL'] ??
            raw['src'] ??
            raw['imageUrl'];
        if (mapUrl != null) addCleanUrl(mapUrl);
        return;
      }
      var str = raw.toString().trim();
      if (str.isEmpty || str.length < 5) return;

      if ((str.startsWith('"') && str.endsWith('"')) ||
          (str.startsWith("'") && str.endsWith("'"))) {
        str = str.substring(1, str.length - 1).trim();
      }
      if (str.startsWith('(') && str.endsWith(')')) {
        str = str.substring(1, str.length - 1).trim();
      }
      if (str.startsWith('[') && str.endsWith(']')) {
        str = str.substring(1, str.length - 1).trim();
      }

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
      map['productImages'],
      map['product_images'],
      map['pictureUrls'],
      map['gallery'],
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
      map['image_url'],
      map['productImage'],
      map['product_image'],
      map['product_image_url'],
      map['photoUrl'],
      map['photo_url'],
      map['photoURL'],
      map['thumbnail'],
      map['thumbnail_url'],
      map['thumbnailUrl'],
      map['picture'],
      map['pictureUrl'],
      map['picture_url'],
      map['img'],
      map['imgUrl'],
      map['img_url'],
      map['banner'],
      map['bannerUrl'],
      map['banner_url'],
      map['url'],
      map['itemImage'],
      map['itemImageUrl'],
    ];
    for (final candidate in candidateStrings) {
      if (candidate != null) {
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
    final rawName = (map['name'] ?? '').toString();
    final rawCategory = (map['category'] ?? '').toString();

    // If no valid image was extracted from the document, provide matching high-quality suggestion
    if (resolvedImages.isEmpty) {
      final suggested = getSuggestedImageUrl(rawName, rawCategory);
      if (suggested != null) {
        resolvedImages.add(suggested);
      }
    }

    return ProductModel(
      id: id,
      userId: resolvedUserId,
      sourceType: sourceType,
      displayShopName: (map['displayShopName'] as String?)?.trim(),
      assignedByAdminId: (map['assignedByAdminId'] as String?)?.trim(),
      name: rawName,
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      images: resolvedImages,
      category: rawCategory,
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
