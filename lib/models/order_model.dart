import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_constants.dart';

class OrderModel {
  final String id;
  final String buyerId;
  final String sellerId;
  final String productId;
  final String productName;
  final String? productImage;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String
      status; // pending, confirmed, shipped, out_for_delivery, delivered, cancelled, failed_delivery, requested, accepted, rejected, finished
  final String? buyerName;
  final String? buyerEmail;
  final String paymentMethod; // gpay_simulation, cod, etc.
  final String paymentStatus; // paid, pending, failed
  final String? paymentReference;
  final DateTime? paidAt;
  final String sellerTransferStatus; // credited_simulated, pending
  final DateTime? sellerTransferAt;
  final String? notes;
  final Map<String, DateTime> statusTimeline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? deliveryAddress;
  final String? deliveryLocation;
  final String? deliveryVerificationCode;
  final DateTime? deliveryCodeVerifiedAt;
  final String? deliveryPartnerId;
  final String? deliveryPartnerName;
  final DateTime? estimatedDelivery;
  final bool deliveryByPartner;
  final int? deliveryQuantityLimit;

  // ─── New fields for Product Type, Address Snapshots, Service Flow ──────────
  final String productType; // 'product' or 'service'
  final String? sellerName;
  final String? sellerAddress;
  final Map<String, dynamic>? deliveryAddressSnapshot;
  final Map<String, dynamic>? pickupAddressSnapshot;
  final String? serviceStatus; // requested, accepted, requirement_gathering, project_work, testing, review, finished, rejected, cancelled
  final List<Map<String, dynamic>> serviceTimeline;
  final String? workChatId;

  const OrderModel({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.productId,
    required this.productName,
    this.productImage,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.status = 'pending',
    this.buyerName,
    this.buyerEmail,
    this.paymentMethod = 'gpay_simulation',
    this.paymentStatus = 'paid',
    this.paymentReference,
    this.paidAt,
    this.sellerTransferStatus = 'credited_simulated',
    this.sellerTransferAt,
    this.notes,
    this.statusTimeline = const {},
    required this.createdAt,
    required this.updatedAt,
    this.deliveryAddress,
    this.deliveryLocation,
    this.deliveryVerificationCode,
    this.deliveryCodeVerifiedAt,
    this.deliveryPartnerId,
    this.deliveryPartnerName,
    this.estimatedDelivery,
    this.deliveryByPartner = false,
    this.deliveryQuantityLimit,
    this.productType = AppConstants.listingTypeProduct,
    this.sellerName,
    this.sellerAddress,
    this.deliveryAddressSnapshot,
    this.pickupAddressSnapshot,
    this.serviceStatus,
    this.serviceTimeline = const [],
    this.workChatId,
  });

  bool get isService =>
      productType == AppConstants.listingTypeService ||
      productType == 'service';

  bool get isPhysicalProduct => !isService;

  static Map<String, DateTime> _parseTimeline(dynamic rawTimeline) {
    if (rawTimeline is! Map) return const {};
    final parsed = <String, DateTime>{};
    rawTimeline.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      if (normalizedKey.isEmpty) return;
      if (value is Timestamp) {
        parsed[normalizedKey] = value.toDate();
        return;
      }
      if (value is DateTime) {
        parsed[normalizedKey] = value;
        return;
      }
      if (value is String) {
        final parsedDate = DateTime.tryParse(value);
        if (parsedDate != null) {
          parsed[normalizedKey] = parsedDate;
        }
      }
    });
    return parsed;
  }

  static List<Map<String, dynamic>> _parseServiceTimeline(dynamic rawTimeline) {
    if (rawTimeline is! List) return const [];
    return rawTimeline
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  factory OrderModel.fromMap(Map<String, dynamic> map, String id) {
    final rawType = (map['productType'] ?? map['type'])?.toString().trim().toLowerCase();
    final productType = (rawType == AppConstants.listingTypeService || rawType == 'service')
        ? AppConstants.listingTypeService
        : AppConstants.listingTypeProduct;

    String? productImage = (map['productImage'] ?? map['imageUrl'] ?? map['image'])?.toString().trim();
    if ((productImage == null || productImage.isEmpty) && map['images'] is List && (map['images'] as List).isNotEmpty) {
      productImage = (map['images'] as List).first?.toString().trim();
    }
    if (productImage != null && productImage.startsWith('http://')) {
      productImage = 'https://${productImage.substring(7)}';
    }

    return OrderModel(
      id: id,
      buyerId: map['buyerId'] ?? '',
      sellerId: map['sellerId'] ?? '',
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      productImage: (productImage != null && productImage.isNotEmpty) ? productImage : null,
      quantity: (map['quantity'] ?? 1) is num ? (map['quantity'] as num).toInt() : int.tryParse(map['quantity']?.toString() ?? '1') ?? 1,
      unitPrice: (map['unitPrice'] ?? 0).toDouble(),
      totalPrice: (map['totalPrice'] ?? 0).toDouble(),
      status: map['status'] ?? 'pending',
      buyerName: map['buyerName'],
      buyerEmail: map['buyerEmail'],
      paymentMethod: map['paymentMethod'] ?? 'gpay_simulation',
      paymentStatus: map['paymentStatus'] ?? 'paid',
      paymentReference: map['paymentReference'],
      paidAt: (map['paidAt'] as Timestamp?)?.toDate(),
      sellerTransferStatus: map['sellerTransferStatus'] ?? 'pending',
      sellerTransferAt: (map['sellerTransferAt'] as Timestamp?)?.toDate(),
      notes: map['notes'],
      statusTimeline: _parseTimeline(map['statusTimeline']),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      deliveryAddress: map['deliveryAddress'],
      deliveryLocation: map['deliveryLocation'],
      deliveryVerificationCode: map['deliveryVerificationCode'],
      deliveryCodeVerifiedAt:
          (map['deliveryCodeVerifiedAt'] as Timestamp?)?.toDate(),
      deliveryPartnerId: map['deliveryPartnerId'],
      deliveryPartnerName: map['deliveryPartnerName'],
      estimatedDelivery: (map['estimatedDelivery'] as Timestamp?)?.toDate(),
      deliveryByPartner: map['deliveryByPartner'] == true,
      deliveryQuantityLimit: (map['deliveryQuantityLimit'] as num?)?.toInt(),
      productType: productType,
      sellerName: map['sellerName'] as String?,
      sellerAddress: map['sellerAddress'] as String?,
      deliveryAddressSnapshot: map['deliveryAddressSnapshot'] is Map
          ? Map<String, dynamic>.from(map['deliveryAddressSnapshot'] as Map)
          : null,
      pickupAddressSnapshot: map['pickupAddressSnapshot'] is Map
          ? Map<String, dynamic>.from(map['pickupAddressSnapshot'] as Map)
          : null,
      serviceStatus: map['serviceStatus'] as String?,
      serviceTimeline: _parseServiceTimeline(map['serviceTimeline']),
      workChatId: map['workChatId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'buyerId': buyerId,
      'sellerId': sellerId,
      'productId': productId,
      'productName': productName,
      if (productImage != null) 'productImage': productImage,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
      'status': status,
      if (buyerName != null) 'buyerName': buyerName,
      if (buyerEmail != null) 'buyerEmail': buyerEmail,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      if (paymentReference != null) 'paymentReference': paymentReference,
      if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
      'sellerTransferStatus': sellerTransferStatus,
      if (sellerTransferAt != null)
        'sellerTransferAt': Timestamp.fromDate(sellerTransferAt!),
      if (notes != null) 'notes': notes,
      'statusTimeline': statusTimeline.map(
        (key, value) => MapEntry(key, Timestamp.fromDate(value)),
      ),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
      if (deliveryLocation != null) 'deliveryLocation': deliveryLocation,
      if (deliveryVerificationCode != null)
        'deliveryVerificationCode': deliveryVerificationCode,
      if (deliveryCodeVerifiedAt != null)
        'deliveryCodeVerifiedAt': Timestamp.fromDate(deliveryCodeVerifiedAt!),
      if (deliveryPartnerId != null) 'deliveryPartnerId': deliveryPartnerId,
      if (deliveryPartnerName != null)
        'deliveryPartnerName': deliveryPartnerName,
      if (estimatedDelivery != null)
        'estimatedDelivery': Timestamp.fromDate(estimatedDelivery!),
      'deliveryByPartner': deliveryByPartner,
      if (deliveryQuantityLimit != null)
        'deliveryQuantityLimit': deliveryQuantityLimit,
      'productType': productType,
      if (sellerName != null) 'sellerName': sellerName,
      if (sellerAddress != null) 'sellerAddress': sellerAddress,
      if (deliveryAddressSnapshot != null)
        'deliveryAddressSnapshot': deliveryAddressSnapshot,
      if (pickupAddressSnapshot != null)
        'pickupAddressSnapshot': pickupAddressSnapshot,
      if (serviceStatus != null) 'serviceStatus': serviceStatus,
      if (serviceTimeline.isNotEmpty) 'serviceTimeline': serviceTimeline,
      if (workChatId != null) 'workChatId': workChatId,
    };
  }

  OrderModel copyWith({
    String? id,
    String? buyerId,
    String? sellerId,
    String? productId,
    String? productName,
    String? productImage,
    int? quantity,
    double? unitPrice,
    double? totalPrice,
    String? status,
    String? buyerName,
    String? buyerEmail,
    String? paymentMethod,
    String? paymentStatus,
    String? paymentReference,
    DateTime? paidAt,
    String? sellerTransferStatus,
    DateTime? sellerTransferAt,
    String? notes,
    Map<String, DateTime>? statusTimeline,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deliveryAddress,
    String? deliveryLocation,
    String? deliveryVerificationCode,
    DateTime? deliveryCodeVerifiedAt,
    String? deliveryPartnerId,
    String? deliveryPartnerName,
    DateTime? estimatedDelivery,
    bool? deliveryByPartner,
    int? deliveryQuantityLimit,
    String? productType,
    String? sellerName,
    String? sellerAddress,
    Map<String, dynamic>? deliveryAddressSnapshot,
    Map<String, dynamic>? pickupAddressSnapshot,
    String? serviceStatus,
    List<Map<String, dynamic>>? serviceTimeline,
    String? workChatId,
  }) {
    return OrderModel(
      id: id ?? this.id,
      buyerId: buyerId ?? this.buyerId,
      sellerId: sellerId ?? this.sellerId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productImage: productImage ?? this.productImage,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      status: status ?? this.status,
      buyerName: buyerName ?? this.buyerName,
      buyerEmail: buyerEmail ?? this.buyerEmail,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentReference: paymentReference ?? this.paymentReference,
      paidAt: paidAt ?? this.paidAt,
      sellerTransferStatus: sellerTransferStatus ?? this.sellerTransferStatus,
      sellerTransferAt: sellerTransferAt ?? this.sellerTransferAt,
      notes: notes ?? this.notes,
      statusTimeline: statusTimeline ?? this.statusTimeline,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
      deliveryVerificationCode:
          deliveryVerificationCode ?? this.deliveryVerificationCode,
      deliveryCodeVerifiedAt:
          deliveryCodeVerifiedAt ?? this.deliveryCodeVerifiedAt,
      deliveryPartnerId: deliveryPartnerId ?? this.deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName ?? this.deliveryPartnerName,
      estimatedDelivery: estimatedDelivery ?? this.estimatedDelivery,
      deliveryByPartner: deliveryByPartner ?? this.deliveryByPartner,
      deliveryQuantityLimit:
          deliveryQuantityLimit ?? this.deliveryQuantityLimit,
      productType: productType ?? this.productType,
      sellerName: sellerName ?? this.sellerName,
      sellerAddress: sellerAddress ?? this.sellerAddress,
      deliveryAddressSnapshot:
          deliveryAddressSnapshot ?? this.deliveryAddressSnapshot,
      pickupAddressSnapshot:
          pickupAddressSnapshot ?? this.pickupAddressSnapshot,
      serviceStatus: serviceStatus ?? this.serviceStatus,
      serviceTimeline: serviceTimeline ?? this.serviceTimeline,
      workChatId: workChatId ?? this.workChatId,
    );
  }
}
