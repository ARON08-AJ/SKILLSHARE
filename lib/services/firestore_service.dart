import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/skilled_user_profile.dart';
import '../models/customer_profile.dart';
import '../models/company_profile.dart';
import '../models/service_model.dart';
import '../models/product_model.dart';
import '../models/cart_item_model.dart';
import '../models/order_model.dart';
import '../models/job_model.dart';
import '../models/review_model.dart';
import '../models/service_request_model.dart';
import '../models/appeal_model.dart';
import '../models/user_model.dart';
import '../utils/app_constants.dart';
import '../utils/user_roles.dart';

class AdminDashboardData {
  final List<UserModel> users;
  final List<Map<String, dynamic>> reports;
  final List<SkilledUserProfile> pendingVerifications;

  const AdminDashboardData({
    required this.users,
    required this.reports,
    required this.pendingVerifications,
  });
}

class CompanyBuyerHighlight {
  final String companyId;
  final String companyName;
  final int totalOrders;
  final int totalUnits;
  final double totalSpend;
  final DateTime latestOrderAt;

  const CompanyBuyerHighlight({
    required this.companyId,
    required this.companyName,
    required this.totalOrders,
    required this.totalUnits,
    required this.totalSpend,
    required this.latestOrderAt,
  });
}

class SkilledCompanySocialProof {
  final int uniqueCompanyBuyers;
  final int companyOrdersCount;
  final int companyUnitsBought;
  final double companyRevenue;
  final List<CompanyBuyerHighlight> topCompanyBuyers;

  const SkilledCompanySocialProof({
    this.uniqueCompanyBuyers = 0,
    this.companyOrdersCount = 0,
    this.companyUnitsBought = 0,
    this.companyRevenue = 0,
    this.topCompanyBuyers = const <CompanyBuyerHighlight>[],
  });
}

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Random _random = Random.secure();
  static const String _aadhaarRegistryCollection =
      AppConstants.aadhaarRegistryCollection;
  static const String _companyVerificationReportType = 'company_verification';

  String _generateDeliveryVerificationCode() =>
      (_random.nextInt(900000) + 100000).toString();
  static const String _aadhaarChangeRequestType = 'aadhaar_change_request';
  static const String _chatWorkRequestType = 'chat_work_request';
  static const String _legacyDirectHireServiceId = 'direct_hire';

  String _normalizeAadhaar(String aadhaar) =>
      aadhaar.replaceAll(' ', '').trim();

  String _maskAadhaar(String aadhaar) {
    final clean = _normalizeAadhaar(aadhaar);
    if (clean.length < 4) return clean;
    return 'XXXX XXXX ${clean.substring(clean.length - 4)}';
  }

  bool _isSkilledUserDataAadhaarVerified(Map<String, dynamic> data) {
    final verificationData = data['verificationData'];
    final verificationMap = verificationData is Map
        ? Map<String, dynamic>.from(verificationData)
        : <String, dynamic>{};

    final aadhaarNumber =
        ((verificationMap['aadhaarNumber'] as String?)?.trim() ??
                (verificationMap['aadharNumber'] as String?)?.trim() ??
                (verificationMap['adharNumber'] as String?)?.trim() ??
                (data['aadhaarNumber'] as String?)?.trim() ??
                (data['aadharNumber'] as String?)?.trim() ??
                (data['adharNumber'] as String?)?.trim() ??
                '')
            .replaceAll(' ', '');
    final aadhaarLocked = verificationMap['aadhaarLocked'] == true ||
        verificationMap['aadharLocked'] == true ||
        aadhaarNumber.length == 12;
    final status =
        ((data['verificationStatus'] as String?) ?? '').toLowerCase().trim();
    final statusApproved = status == AppConstants.verificationApproved ||
        status == 'verified' ||
        status == 'approved';
    final visibility =
        ((data['visibility'] as String?) ?? '').toLowerCase().trim();

    return (data['isVerified'] == true || statusApproved) &&
        (visibility == AppConstants.visibilityPublic) &&
        statusApproved &&
        aadhaarLocked &&
        aadhaarNumber.length == 12;
  }

  bool _isSkilledProfileAadhaarVerified(SkilledUserProfile profile) {
    final verificationData = profile.verificationData ?? <String, dynamic>{};
    final aadhaarNumber =
        ((verificationData['aadhaarNumber'] as String?)?.trim() ??
                (verificationData['aadharNumber'] as String?)?.trim() ??
                (verificationData['adharNumber'] as String?)?.trim() ??
                '')
            .replaceAll(' ', '');
    final aadhaarLocked = verificationData['aadhaarLocked'] == true ||
        verificationData['aadharLocked'] == true ||
        aadhaarNumber.length == 12;
    final status = profile.verificationStatus.toLowerCase().trim();
    final statusApproved = status == AppConstants.verificationApproved ||
        status == 'verified' ||
        status == 'approved';

    return profile.isVerified &&
        profile.visibility.toLowerCase().trim() ==
            AppConstants.visibilityPublic &&
        statusApproved &&
        aadhaarLocked &&
        aadhaarNumber.length == 12;
  }

  bool _isCompanyProfileVerified(CompanyProfile? profile) {
    if (profile == null) return false;
    final status = profile.verificationStatus.toLowerCase().trim();
    final statusApproved =
        status == AppConstants.verificationApproved || status == 'verified';
    return profile.isVerified || statusApproved;
  }

  Uri? _parseCredentialUri(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return uri;
  }

  bool _isAcceptableCredentialStatus(int statusCode) {
    return (statusCode >= 200 && statusCode < 400) ||
        statusCode == 401 ||
        statusCode == 403;
  }

  Future<bool> _isCredentialUrlReachable(Uri uri) async {
    try {
      final headResponse = await http.head(uri, headers: const {
        'Cache-Control': 'no-cache'
      }).timeout(const Duration(seconds: 5));
      if (_isAcceptableCredentialStatus(headResponse.statusCode)) {
        return true;
      }
      if (headResponse.statusCode != 405) {
        return false;
      }
    } catch (_) {
      // Fall back to GET for servers that block HEAD.
    }

    try {
      final getResponse = await http.get(
        uri,
        headers: const {
          'Cache-Control': 'no-cache',
          'Range': 'bytes=0-0',
        },
      ).timeout(const Duration(seconds: 5));
      return _isAcceptableCredentialStatus(getResponse.statusCode);
    } catch (_) {
      return false;
    }
  }

  bool _isSuccessfulOrderStatus(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
      case 'confirmed':
      case 'shipped':
      case 'out_for_delivery':
      case 'delivered':
        return true;
      default:
        return false;
    }
  }

  String _normalizeVerificationStatus(dynamic status) {
    final normalized = (status?.toString() ?? '').trim().toLowerCase();
    if (normalized == 'submitted') return AppConstants.verificationPending;
    if (normalized == AppConstants.verificationApproved ||
        normalized == AppConstants.verificationRejected ||
        normalized == AppConstants.verificationPending) {
      return normalized;
    }
    return AppConstants.verificationPending;
  }

  bool _hasCompanyVerificationSubmission(Map<String, dynamic> data) {
    final rawVerificationData = data['verificationData'];
    final verificationData = rawVerificationData is Map
        ? Map<String, dynamic>.from(rawVerificationData)
        : <String, dynamic>{};

    final businessReg =
        ((verificationData['businessRegNumber'] as String?) ?? '').trim();
    final gst = ((verificationData['gstNumber'] as String?) ?? '').trim();
    final submittedAt = verificationData['submittedAt'];
    final hasSubmittedAt = submittedAt is Timestamp ||
        (submittedAt is String && submittedAt.trim().isNotEmpty);

    return businessReg.isNotEmpty || gst.isNotEmpty || hasSubmittedAt;
  }

  Timestamp _companyVerificationRequestedAt(Map<String, dynamic> data) {
    final rawVerificationData = data['verificationData'];
    final verificationData = rawVerificationData is Map
        ? Map<String, dynamic>.from(rawVerificationData)
        : <String, dynamic>{};

    final submittedAt = verificationData['submittedAt'];
    if (submittedAt is Timestamp) {
      return submittedAt;
    }
    if (submittedAt is String && submittedAt.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(submittedAt.trim());
      if (parsed != null) {
        return Timestamp.fromDate(parsed);
      }
    }

    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) {
      return updatedAt;
    }

    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt;
    }

    return Timestamp.now();
  }

  List<Map<String, dynamic>> _sortReportsByCreatedAtDesc(
    List<Map<String, dynamic>> reports,
  ) {
    reports.sort((a, b) {
      final aTime = a['createdAt'];
      final bTime = b['createdAt'];
      if (aTime is Timestamp && bTime is Timestamp) {
        return bTime.compareTo(aTime);
      }
      return 0;
    });
    return reports;
  }

  Map<String, dynamic> _buildCompanyVerificationReport(
    String companyUserId,
    Map<String, dynamic> data,
  ) {
    final verificationData = data['verificationData'] is Map
        ? Map<String, dynamic>.from(data['verificationData'] as Map)
        : <String, dynamic>{};

    final companyName = ((data['companyName'] as String?) ?? '').trim();
    final businessReg =
        ((verificationData['businessRegNumber'] as String?) ?? '').trim();
    final gst = ((verificationData['gstNumber'] as String?) ?? '').trim();
    final website = ((data['website'] as String?) ?? '').trim();
    final headOffice = ((data['headOfficeLocation'] as String?) ?? '').trim();

    final requestedApprovals = <String>[
      'Business registration verification',
      if (gst.isNotEmpty) 'GST verification',
    ];
    final missingInfo = <String>[
      if (businessReg.isEmpty) 'Business registration number',
    ];

    final detailLines = <String>[
      'Approvals requested: ${requestedApprovals.join(', ')}',
      if (businessReg.isNotEmpty) 'Business Registration Number: $businessReg',
      if (gst.isNotEmpty) 'GST Number: $gst',
      if (headOffice.isNotEmpty) 'Head Office: $headOffice',
      if (website.isNotEmpty) 'Website: $website',
      if (missingInfo.isNotEmpty)
        'Missing information: ${missingInfo.join(', ')}',
    ];

    return {
      'id': 'company_verification_$companyUserId',
      'type': _companyVerificationReportType,
      'companyUserId': companyUserId,
      'reporterId': companyUserId,
      'reportedUserId': companyUserId,
      'companyName': companyName,
      'reason': 'Business verification approval request',
      'details': detailLines.join('\n'),
      'status': 'pending',
      'source': 'company_profile',
      'createdAt': _companyVerificationRequestedAt(data),
      'updatedAt': _companyVerificationRequestedAt(data),
    };
  }

  List<Map<String, dynamic>> _mergeReportLists({
    required List<Map<String, dynamic>> reports,
    required List<Map<String, dynamic>> companyVerificationReports,
    required int limit,
  }) {
    final merged = <Map<String, dynamic>>[
      ...reports,
      ...companyVerificationReports,
    ];
    _sortReportsByCreatedAtDesc(merged);
    if (merged.length > limit) {
      return merged.sublist(0, limit);
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _getCompanyVerificationReports({
    int limit = 100,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.companyProfilesCollection)
          .limit(limit * 3)
          .get();

      final reports = snapshot.docs
          .map((doc) => {'userId': doc.id, ...doc.data()})
          .where((data) => _hasCompanyVerificationSubmission(data))
          .where((data) =>
              _normalizeVerificationStatus(data['verificationStatus']) ==
              AppConstants.verificationPending)
          .map((data) => _buildCompanyVerificationReport(
                data['userId'] as String,
                data,
              ))
          .toList();

      return _sortReportsByCreatedAtDesc(reports);
    } catch (e) {
      debugPrint('getCompanyVerificationReports error: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _buildCompanyVerificationReportsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final reports = snapshot.docs
        .map((doc) => {'userId': doc.id, ...doc.data()})
        .where((data) => _hasCompanyVerificationSubmission(data))
        .where((data) =>
            _normalizeVerificationStatus(data['verificationStatus']) ==
            AppConstants.verificationPending)
        .map((data) => _buildCompanyVerificationReport(
              data['userId'] as String,
              data,
            ))
        .toList();

    return _sortReportsByCreatedAtDesc(reports);
  }

  Future<void> reviewCompanyVerificationRequest({
    required String companyUserId,
    required bool approve,
    String? adminId,
    String? adminNotes,
  }) async {
    final status = approve
        ? AppConstants.verificationApproved
        : AppConstants.verificationRejected;

    final update = <String, dynamic>{
      'verificationStatus': status,
      'isVerified': approve,
      'updatedAt': FieldValue.serverTimestamp(),
      'verificationReviewedAt': FieldValue.serverTimestamp(),
      if (approve) 'verifiedAt': FieldValue.serverTimestamp(),
      if (!approve) 'verifiedAt': null,
      if (adminId != null && adminId.trim().isNotEmpty)
        'verificationReviewedBy': adminId.trim(),
      if (adminNotes != null && adminNotes.trim().isNotEmpty)
        'verificationNotes': adminNotes.trim(),
    };

    await _firestore
        .collection(AppConstants.companyProfilesCollection)
        .doc(companyUserId)
        .set(update, SetOptions(merge: true));
  }

  Future<bool> canCompanyHireSkilledPersons(String companyUserId) async {
    final profile = await getCompanyProfile(companyUserId);
    return _isCompanyProfileVerified(profile);
  }

  Stream<bool> companyHireEligibilityStream(String companyUserId) {
    return companyProfileStream(companyUserId).map(_isCompanyProfileVerified);
  }

  // ===== Users =====

  Future<UserModel?> getUserById(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .get();

    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!, userId);
  }

  bool _isWorkRequestLike(ServiceRequestModel request) {
    final normalizedType = request.type.toLowerCase().trim();
    final normalizedServiceId = request.serviceId.toLowerCase().trim();
    return normalizedType == _chatWorkRequestType ||
        normalizedServiceId == _legacyDirectHireServiceId;
  }

  Map<String, dynamic> _participantDetailsFromUser(UserModel? user) {
    final safeName = (user?.name ?? '').trim();
    final safePhoto = (user?.profilePhoto ?? '').trim();
    final safeRole = (user?.role ?? '').trim();
    return {
      'name': safeName.isEmpty ? 'User' : safeName,
      'photo': safePhoto,
      if (safeRole.isNotEmpty) 'role': safeRole,
      if (user?.avatarConfig != null) 'avatarConfig': user!.avatarConfig,
    };
  }

  String _chatCategoryForRole(String? role) {
    final normalized = UserRoles.normalizeRole(role ?? '');
    if (normalized == UserRoles.company) return 'company';
    if (normalized == UserRoles.customer) return 'customer';
    if (normalized == UserRoles.skilledPerson) return 'skilled';
    if (normalized == UserRoles.deliveryPartner) return 'delivery';
    return 'general';
  }

  String _deriveDirectChatCategory(UserModel? userA, UserModel? userB) {
    final roleA = UserRoles.normalizeRole(userA?.role ?? '');
    final roleB = UserRoles.normalizeRole(userB?.role ?? '');

    if (roleA == UserRoles.skilledPerson && roleB != null) {
      return _chatCategoryForRole(roleB);
    }
    if (roleB == UserRoles.skilledPerson && roleA != null) {
      return _chatCategoryForRole(roleA);
    }
    if (roleA == UserRoles.company || roleB == UserRoles.company) {
      return 'company';
    }
    if (roleA == UserRoles.customer || roleB == UserRoles.customer) {
      return 'customer';
    }
    if (roleA == UserRoles.skilledPerson || roleB == UserRoles.skilledPerson) {
      return 'skilled';
    }
    return 'general';
  }

  Future<String> _ensureDirectChatBetweenUsers({
    required UserModel? userA,
    required UserModel? userB,
    required String userAId,
    required String userBId,
  }) async {
    final participants = [userAId, userBId]..sort();
    final chatId = '${participants[0]}__${participants[1]}';
    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);
    final chatData = {
      'participants': participants,
      'participantDetails': {
        userAId: _participantDetailsFromUser(userA),
        userBId: _participantDetailsFromUser(userB),
      },
      'isWorkChat': false,
      'isJobChat': false,
      'chatCategory': _deriveDirectChatCategory(userA, userB),
      'jobId': null,
      'workRequestId': null,
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': {
        for (final id in participants) id: 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final existingChat = await chatRef.get();
      if (existingChat.exists) {
        await chatRef.set({
          'participantDetails': {
            userAId: _participantDetailsFromUser(userA),
            userBId: _participantDetailsFromUser(userB),
          },
          'isWorkChat': false,
          'isJobChat': false,
          'chatCategory': _deriveDirectChatCategory(userA, userB),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return chatId;
      }
      await chatRef.set(chatData, SetOptions(merge: true));
      return chatId;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      final fallbackRef = await _firestore
          .collection(AppConstants.chatsCollection)
          .add(chatData);
      return fallbackRef.id;
    }
  }

  Future<String> ensureDeliverySellerChat({
    required String orderId,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
  }) async {
    final orderRef =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw Exception('Order not found.');
    }

    final data = orderSnap.data() ?? <String, dynamic>{};
    final assignedId = (data['deliveryPartnerId'] as String?)?.trim() ?? '';
    if (assignedId != deliveryPartnerId) {
      throw Exception('You are not assigned to this delivery.');
    }
    return _ensureDeliverySellerChatFromOrderData(
      orderId: orderId,
      orderData: data,
      deliveryPartnerId: deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName,
    );
  }

  Future<String> _ensureDeliverySellerChatFromOrderData({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
  }) async {
    final sellerId = (orderData['sellerId'] as String?)?.trim() ?? '';
    if (sellerId.isEmpty) {
      throw Exception('Seller details are missing for this delivery.');
    }

    final now = DateTime.now();
    final seller = await getUserById(sellerId);
    final deliveryPartner = await getUserById(deliveryPartnerId) ??
        UserModel(
          uid: deliveryPartnerId,
          email: '',
          name: deliveryPartnerName.trim().isEmpty
              ? 'Delivery Partner'
              : deliveryPartnerName.trim(),
          role: UserRoles.deliveryPartner,
          createdAt: now,
          updatedAt: now,
        );

    final chatId = await _ensureDirectChatBetweenUsers(
      userA: deliveryPartner,
      userB: seller,
      userAId: deliveryPartnerId,
      userBId: sellerId,
    );

    final productName =
        (orderData['productName'] as String?)?.trim() ?? 'this delivery';
    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);
    final chatSnap = await chatRef.get();
    final currentLastMessage =
        (chatSnap.data()?['lastMessage'] as String?)?.trim() ?? '';
    final updateData = <String, dynamic>{
      'deliveryOrderIds': FieldValue.arrayUnion([orderId]),
      'chatCategory': 'delivery',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (currentLastMessage.isEmpty ||
        currentLastMessage.startsWith('Delivery chat opened for ')) {
      updateData.addAll({
        'lastMessage': 'Delivery chat opened for $productName',
        'lastMessageType': 'delivery_update',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
    await chatRef.set(updateData, SetOptions(merge: true));

    return chatId;
  }

  Future<String> ensureDeliveryBuyerChat({
    required String orderId,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
  }) async {
    final orderRef =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw Exception('Order not found.');
    }

    final data = orderSnap.data() ?? <String, dynamic>{};
    final assignedId = (data['deliveryPartnerId'] as String?)?.trim() ?? '';
    if (assignedId != deliveryPartnerId) {
      throw Exception('You are not assigned to this delivery.');
    }
    return _ensureDeliveryBuyerChatFromOrderData(
      orderId: orderId,
      orderData: data,
      deliveryPartnerId: deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName,
    );
  }

  Future<String> _ensureDeliveryBuyerChatFromOrderData({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
  }) async {
    final buyerId = (orderData['buyerId'] as String?)?.trim() ?? '';
    if (buyerId.isEmpty) {
      throw Exception('Customer details are missing for this delivery.');
    }

    final now = DateTime.now();
    final buyer = await getUserById(buyerId);
    final deliveryPartner = await getUserById(deliveryPartnerId) ??
        UserModel(
          uid: deliveryPartnerId,
          email: '',
          name: deliveryPartnerName.trim().isEmpty
              ? 'Delivery Partner'
              : deliveryPartnerName.trim(),
          role: UserRoles.deliveryPartner,
          createdAt: now,
          updatedAt: now,
        );

    final chatId = await _ensureDirectChatBetweenUsers(
      userA: deliveryPartner,
      userB: buyer,
      userAId: deliveryPartnerId,
      userBId: buyerId,
    );

    final productName =
        (orderData['productName'] as String?)?.trim() ?? 'this delivery';
    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);
    final chatSnap = await chatRef.get();
    final currentLastMessage =
        (chatSnap.data()?['lastMessage'] as String?)?.trim() ?? '';
    final updateData = <String, dynamic>{
      'deliveryOrderIds': FieldValue.arrayUnion([orderId]),
      'chatCategory': 'delivery',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (currentLastMessage.isEmpty ||
        currentLastMessage.startsWith('Delivery chat opened for ')) {
      updateData.addAll({
        'lastMessage': 'Delivery chat opened for $productName',
        'lastMessageType': 'delivery_update',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
    await chatRef.set(updateData, SetOptions(merge: true));

    return chatId;
  }

  Future<String> _ensureWorkProjectChat({
    required String requestId,
    required String customerId,
    required String skilledUserId,
    String? originChatId,
    String? requestTitle,
  }) async {
    final customer = await getUserById(customerId);
    final skilled = await getUserById(skilledUserId);
    final participants = [customerId, skilledUserId]..sort();
    final workChatId = 'work_$requestId';
    final workChatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(workChatId);

    await workChatRef.set({
      'participants': participants,
      'participantDetails': {
        customerId: _participantDetailsFromUser(customer),
        skilledUserId: _participantDetailsFromUser(skilled),
      },
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': {
        for (final id in participants) id: 0,
      },
      'isWorkChat': true,
      'chatCategory': _chatCategoryForRole(customer?.role),
      'workRequestId': requestId,
      if (originChatId != null && originChatId.trim().isNotEmpty)
        'originChatId': originChatId.trim(),
      if (requestTitle != null && requestTitle.trim().isNotEmpty)
        'workTitle': requestTitle.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return workChatId;
  }

  Future<String> ensureJobApplicationChat({
    required String jobId,
    required String companyId,
    required String skilledUserId,
    String? jobTitle,
    // Skip the Firestore status check when the caller already verified
    // acceptance (e.g. inside acceptJobApplicant after a transaction).
    bool skipStatusCheck = false,
    // Only the company owner should write applicationChatIds back to the job.
    // Skilled-person callers must pass false to avoid a permission error.
    bool updateJobRecord = true,
  }) async {
    final jobRef =
        _firestore.collection(AppConstants.jobsCollection).doc(jobId);
    final jobDoc = await jobRef.get();
    if (!jobDoc.exists || jobDoc.data() == null) {
      throw Exception('Job not found.');
    }

    final data = jobDoc.data()!;

    // Only enforce owner + status checks when the caller requests it
    if (!skipStatusCheck) {
      final ownerId = ((data['companyId'] as String?) ??
              (data['postedBy'] as String?) ??
              '')
          .trim();
      if (ownerId.isEmpty) throw Exception('Job owner information missing.');
      if (ownerId != companyId) {
        throw Exception('Invalid company for this job.');
      }

      final statusMap =
          Map<String, dynamic>.from(data['applicationStatus'] ?? const {});
      final applicantStatus = (statusMap[skilledUserId] as String?)?.trim();
      if (applicantStatus != 'accepted') {
        throw Exception(
            'Job chat is available only for accepted applications.');
      }
    }

    final safeJobTitle = (jobTitle?.trim().isNotEmpty == true
            ? jobTitle!.trim()
            : (data['title'] as String?)?.trim()) ??
        'Job Discussion';

    final company = await getUserById(companyId);
    final skilled = await getUserById(skilledUserId);
    final participants = [companyId, skilledUserId]..sort();
    final chatId = 'jobchat_${jobId}_${participants[0]}__${participants[1]}';
    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);

    await chatRef.set({
      'participants': participants,
      'participantDetails': {
        companyId: _participantDetailsFromUser(company),
        skilledUserId: _participantDetailsFromUser(skilled),
      },
      'isJobChat': true,
      'chatCategory': 'company',
      'jobId': jobId,
      'jobTitle': safeJobTitle,
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': {
        for (final id in participants) id: 0,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Only the company owner updates the job record (skilled person lacks
    // the Firestore permission to write applicationChatIds).
    if (updateJobRecord) {
      try {
        await jobRef.update({
          'applicationChatIds.$skilledUserId': chatId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Best-effort; the chatId is already deterministic so this is safe
        // to skip if the caller lacks write permission on the job document.
      }
    }

    return chatId;
  }

  Future<List<UserModel>> getCompanyUsers({
    String? excludeUserId,
    int limit = 20,
  }) async {
    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .where('role', isEqualTo: AppConstants.roleCompany)
        .get();

    final companies = snapshot.docs
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .where((user) => user.isActive)
        .where((user) => excludeUserId == null || user.uid != excludeUserId)
        .toList();

    companies.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (companies.length > limit) {
      return companies.sublist(0, limit);
    }
    return companies;
  }

  Future<List<UserModel>> getDeliveryPartners({
    String? excludeUserId,
    int limit = 20,
  }) async {
    final snapshot = await _firestore
        .collection(AppConstants.usersCollection)
        .limit(1000)
        .get();

    bool hasExplicitVerificationSignal(Map<String, dynamic> data) {
      return data.containsKey('isVerified') ||
          data.containsKey('verificationStatus') ||
          data.containsKey('approvalStatus') ||
          data.containsKey('verifiedAt');
    }

    bool isApprovedUser(Map<String, dynamic> data) {
      final verificationStatus = _normalizeVerificationStatus(
        data['verificationStatus'] ?? data['approvalStatus'],
      );
      return data['isVerified'] == true ||
          verificationStatus == AppConstants.verificationApproved ||
          verificationStatus == AppConstants.approvalApproved ||
          verificationStatus == 'verified' ||
          verificationStatus == 'approved' ||
          data['verifiedAt'] != null;
    }

    final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final doc in snapshot.docs) doc.id: doc,
    };

    final partners = snapshot.docs
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .where((user) => user.role == UserRoles.deliveryPartner)
        .where((user) => user.isActive)
        .where((user) => excludeUserId == null || user.uid != excludeUserId)
        .where((user) {
          final data = docsById[user.uid]?.data();
          if (data == null) return false;

          if (!hasExplicitVerificationSignal(data)) return true;
          return isApprovedUser(data);
        })
        .where((user) =>
            user.name.trim().isNotEmpty || user.email.trim().isNotEmpty)
        .toList();

    partners.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (partners.length > limit) {
      return partners.sublist(0, limit);
    }
    return partners;
  }

  // Update user profile photo in users collection
  Future<void> updateUserProfilePhoto(String userId, String? photoUrl) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
        'profilePhoto': (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('User profile photo updated successfully');
    } catch (e) {
      debugPrint('Error updating user profile photo: $e');
      rethrow;
    }
  }

  // Update user role
  Future<void> updateUserRole(String userId, String role) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('User role updated to: $role');
    } catch (e) {
      debugPrint('Error updating user role: $e');
      rethrow;
    }
  }

  Future<void> updateUserByAdmin({
    required String userId,
    String? name,
    String? email,
    String? phone,
    String? role,
    bool? isActive,
    bool? isSuspended,
  }) async {
    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      final normalized = name.trim();
      if (normalized.isNotEmpty) {
        payload['name'] = normalized;
      }
    }

    if (email != null) {
      final normalizedEmail = email.trim();
      if (normalizedEmail.isNotEmpty) {
        payload['email'] = normalizedEmail;
      }
    }

    if (phone != null) {
      final normalizedPhone = phone.trim();
      payload['phone'] = normalizedPhone.isEmpty ? null : normalizedPhone;
    }

    if (role != null) {
      final normalizedRole = UserRoles.normalizeRole(role);
      if (normalizedRole != null && UserRoles.isValidRole(normalizedRole)) {
        payload['role'] = normalizedRole;
      }
    }

    if (isActive != null) {
      payload['isActive'] = isActive;
    }
    if (isSuspended != null) {
      payload['isSuspended'] = isSuspended;
      payload['suspendedAt'] =
          isSuspended ? FieldValue.serverTimestamp() : null;
    }

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .set(payload, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getUserSettings(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .get();
    if (!doc.exists) return <String, dynamic>{};
    final data = doc.data();
    final settings = data?['settings'];
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
    return <String, dynamic>{};
  }

  Stream<Map<String, dynamic>> userSettingsStream(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <String, dynamic>{};
      final settings = doc.data()?['settings'];
      if (settings is Map) {
        return Map<String, dynamic>.from(settings);
      }
      return <String, dynamic>{};
    });
  }

  Future<void> updateUserSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    await _firestore.collection(AppConstants.usersCollection).doc(userId).set({
      'settings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateUserSettingField(
    String userId, {
    required String key,
    required dynamic value,
  }) async {
    await _firestore.collection(AppConstants.usersCollection).doc(userId).set({
      'settings': {key: value},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ===== Notification Seen Tracking =====

  /// Stamps the user document with the current server timestamp so the badge
  /// count resets once all current notifications are considered "seen".
  Future<void> markNotificationsSeen(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(normalizedUserId)
        .set(
      {'lastNotificationSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    final snapshot = await _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: normalizedUserId)
        .get();

    if (snapshot.docs.isEmpty) return;

    var batch = _firestore.batch();
    var operationCount = 0;

    Future<void> commitBatch() async {
      if (operationCount == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      operationCount = 0;
    }

    for (final doc in snapshot.docs) {
      batch.set(
        doc.reference,
        {
          'read': true,
          'seen': true,
          'readAt': FieldValue.serverTimestamp(),
          'seenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      operationCount++;
      if (operationCount >= 400) {
        await commitBatch();
      }
    }

    await commitBatch();
  }

  /// Returns a stream that emits the `lastNotificationSeenAt` timestamp for
  /// [userId] every time the user document changes.
  Stream<DateTime?> lastNotificationSeenStream(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final ts = doc.data()?['lastNotificationSeenAt'];
      if (ts == null) return null;
      return (ts as Timestamp).toDate();
    });
  }

  Future<void> _createNotificationRecord({
    required String toUserId,
    required String type,
    required String title,
    required String body,
    String? fromUserId,
    String? orderId,
    String? productId,
    String? productName,
    String? status,
  }) async {
    final targetUserId = toUserId.trim();
    if (targetUserId.isEmpty) return;

    await _firestore.collection('notifications').add({
      'toUserId': targetUserId,
      if (fromUserId != null && fromUserId.trim().isNotEmpty)
        'fromUserId': fromUserId.trim(),
      'type': type,
      'title': title,
      'body': body,
      if (orderId != null && orderId.trim().isNotEmpty)
        'orderId': orderId.trim(),
      if (productId != null && productId.trim().isNotEmpty)
        'productId': productId.trim(),
      if (productName != null && productName.trim().isNotEmpty)
        'productName': productName.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'seen': false,
    });
  }

  // ===== Banner Data =====

  /// Saves [bannerData] for a user into both the users collection and the
  /// role-specific profile collection (customers or skilled_users).
  Future<void> saveBannerData({
    required String userId,
    required String role,
    required Map<String, dynamic> bannerData,
  }) async {
    final batch = _firestore.batch();

    String collection;
    if (role == AppConstants.roleCustomer) {
      collection = AppConstants.customerProfilesCollection;
    } else if (role == AppConstants.roleCompany) {
      collection = AppConstants.companyProfilesCollection;
    } else {
      collection = AppConstants.skilledUsersCollection;
    }

    batch.set(
        _firestore.collection(collection).doc(userId),
        {'bannerData': bannerData, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));

    await batch.commit();
  }

  Future<String> submitSupportTicket({
    required String userId,
    required String subject,
    required String message,
    String priority = 'normal',
  }) async {
    final normalizedSubject = subject.trim();
    final normalizedMessage = message.trim();
    if (normalizedSubject.isEmpty || normalizedMessage.isEmpty) {
      throw Exception('Subject and message are required.');
    }

    final docRef =
        _firestore.collection(AppConstants.supportTicketsCollection).doc();
    await docRef.set({
      'userId': userId,
      'subject': normalizedSubject,
      'message': normalizedMessage,
      'priority': priority,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<String> submitProfileReport({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    if (reporterId == reportedUserId) {
      throw Exception('You cannot report yourself.');
    }

    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw Exception('Please provide a report reason.');
    }

    final docRef = _firestore.collection(AppConstants.reportsCollection).doc();
    await docRef.set({
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': normalizedReason,
      'details': details?.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> blockUser({
    required String blockerId,
    required String blockedUserId,
    String? reason,
  }) async {
    if (blockerId == blockedUserId) {
      throw Exception('You cannot block yourself.');
    }

    final docId = '${blockerId}_$blockedUserId';
    await _firestore
        .collection(AppConstants.blockedUsersCollection)
        .doc(docId)
        .set({
      'blockerId': blockerId,
      'blockedUserId': blockedUserId,
      'reason': reason?.trim(),
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unblockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    final docId = '${blockerId}_$blockedUserId';
    await _firestore
        .collection(AppConstants.blockedUsersCollection)
        .doc(docId)
        .set({
      'blockerId': blockerId,
      'blockedUserId': blockedUserId,
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Set<String>> getBlockedUserIds(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.blockedUsersCollection)
          .where('blockerId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => (doc.data()['blockedUserId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } on FirebaseException catch (e) {
      // Existing projects may still have strict blocked_users rules.
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        debugPrint('getBlockedUserIds permission fallback: ${e.message}');
        return <String>{};
      }
      rethrow;
    }
  }

  Future<Set<String>> getUsersWhoBlocked(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.blockedUsersCollection)
          .where('blockedUserId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => (doc.data()['blockerId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } on FirebaseException catch (e) {
      // Existing projects may still have strict blocked_users rules.
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        debugPrint('getUsersWhoBlocked permission fallback: ${e.message}');
        return <String>{};
      }
      rethrow;
    }
  }

  Future<bool> isUserBlockedEitherWay({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      final checks = await Future.wait([
        _firestore
            .collection(AppConstants.blockedUsersCollection)
            .where('blockerId', isEqualTo: currentUserId)
            .where('blockedUserId', isEqualTo: otherUserId)
            .limit(5)
            .get(),
        _firestore
            .collection(AppConstants.blockedUsersCollection)
            .where('blockerId', isEqualTo: otherUserId)
            .where('blockedUserId', isEqualTo: currentUserId)
            .limit(5)
            .get(),
      ]);

      return checks.any(
        (snapshot) =>
            snapshot.docs.any((doc) => doc.data()['isActive'] == true),
      );
    } on FirebaseException catch (e) {
      // Keep core profile/chat flows working even when rules are not yet updated.
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        debugPrint('isUserBlockedEitherWay permission fallback: ${e.message}');
        return false;
      }
      rethrow;
    }
  }

  // ===== Skilled User Profile =====

  Future<void> updateSkilledUserProfile(SkilledUserProfile profile) async {
    await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(profile.userId)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  Future<SkilledUserProfile?> getSkilledUserProfile(String userId) async {
    final collection =
        _firestore.collection(AppConstants.skilledUsersCollection);

    final doc = await collection.doc(userId).get();
    if (doc.exists) {
      final canonicalData = Map<String, dynamic>.from(doc.data()!);
      canonicalData['userId'] = userId;
      return SkilledUserProfile.fromMap(canonicalData, userId);
    }

    // Backward compatibility for legacy docs saved with auto IDs and userId field.
    final legacySnapshot =
        await collection.where('userId', isEqualTo: userId).limit(1).get();
    if (legacySnapshot.docs.isEmpty) return null;

    final legacyData =
        Map<String, dynamic>.from(legacySnapshot.docs.first.data());
    legacyData['userId'] = userId;

    // Opportunistic migration to canonical /skilled_users/{uid}.
    try {
      await collection.doc(userId).set({
        ...legacyData,
        'userId': userId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Legacy skilled profile migration skipped for $userId: $e');
    }

    return SkilledUserProfile.fromMap(legacyData, userId);
  }

  Stream<SkilledUserProfile?> skilledUserProfileStream(String userId) {
    return _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return SkilledUserProfile.fromMap(doc.data()!, userId);
    });
  }

  Future<List<String>> getPrivateSkilledCredentialLinks(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.skilledVerificationPrivateCollection)
        .doc(userId)
        .get();
    if (!doc.exists) return const <String>[];
    final data = doc.data();
    final links = data?['links'];
    if (links is! List) return const <String>[];
    return links
        .map((link) => link?.toString().trim() ?? '')
        .where((link) => link.isNotEmpty)
        .toList();
  }

  Future<List<String>> savePrivateSkilledCredentialLinks({
    required String userId,
    required List<String> rawLinks,
  }) async {
    final normalizedUniqueLinks = rawLinks
        .map((link) => link.trim())
        .where((link) => link.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final validLinks = <String>[];
    final hosts = <String>{};
    for (final link in normalizedUniqueLinks) {
      final uri = _parseCredentialUri(link);
      if (uri == null) continue;
      final reachable = await _isCredentialUrlReachable(uri);
      if (!reachable) continue;
      validLinks.add(uri.toString());
      final host = uri.host.trim().toLowerCase();
      if (host.isNotEmpty) hosts.add(host);
    }

    final privateRef = _firestore
        .collection(AppConstants.skilledVerificationPrivateCollection)
        .doc(userId);
    final profileRef =
        _firestore.collection(AppConstants.skilledUsersCollection).doc(userId);
    final publicSummary = <String, dynamic>{
      'hasConfidentialCredentials': validLinks.isNotEmpty,
      'verifiedCredentialCount': validLinks.length,
      'status':
          validLinks.isNotEmpty ? 'credentials_on_file' : 'no_credentials',
      'lastCheckedAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    if (validLinks.isEmpty) {
      batch.delete(privateRef);
    } else {
      batch.set(
        privateRef,
        {
          'userId': userId,
          'links': validLinks,
          'hostCount': hosts.length,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    batch.set(
      profileRef,
      {
        'verificationData': {
          'credentialSummary': publicSummary,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return validLinks;
  }

  Future<SkilledCompanySocialProof> getSkilledCompanySocialProof(
    String skilledUserId,
  ) async {
    final snapshot = await _firestore
        .collection(AppConstants.ordersCollection)
        .where('sellerId', isEqualTo: skilledUserId)
        .get();

    final relevantOrders = snapshot.docs
        .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
        .where((order) => _isSuccessfulOrderStatus(order.status))
        .toList();
    if (relevantOrders.isEmpty) {
      return const SkilledCompanySocialProof();
    }

    final buyerIds = relevantOrders
        .map((order) => order.buyerId.trim())
        .where((buyerId) => buyerId.isNotEmpty)
        .toSet()
        .toList();

    final users = await Future.wait(
      buyerIds.map(getUserById),
    );
    final companyUsersById = <String, UserModel>{};
    for (final user in users) {
      if (user == null) continue;
      if (UserRoles.normalizeRole(user.role) == UserRoles.company) {
        companyUsersById[user.uid] = user;
      }
    }
    if (companyUsersById.isEmpty) {
      return const SkilledCompanySocialProof();
    }

    final companyProfiles = await Future.wait(
      companyUsersById.keys.map(getCompanyProfile),
    );
    final companyNamesById = <String, String>{};
    for (var i = 0; i < companyProfiles.length; i++) {
      final companyId = companyUsersById.keys.elementAt(i);
      final companyProfile = companyProfiles[i];
      final fallbackUser = companyUsersById[companyId];
      final companyName =
          (companyProfile?.companyName ?? fallbackUser?.name ?? '').trim();
      companyNamesById[companyId] =
          companyName.isEmpty ? 'Company buyer' : companyName;
    }

    final ordersByCompany = <String, List<OrderModel>>{};
    for (final order in relevantOrders) {
      if (!companyUsersById.containsKey(order.buyerId)) continue;
      ordersByCompany
          .putIfAbsent(order.buyerId, () => <OrderModel>[])
          .add(order);
    }
    if (ordersByCompany.isEmpty) {
      return const SkilledCompanySocialProof();
    }

    final highlights = ordersByCompany.entries.map((entry) {
      final companyOrders = entry.value;
      companyOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final totalUnits =
          companyOrders.fold<int>(0, (total, order) => total + order.quantity);
      final totalSpend = companyOrders.fold<double>(
          0, (total, order) => total + order.totalPrice);
      return CompanyBuyerHighlight(
        companyId: entry.key,
        companyName: companyNamesById[entry.key] ?? 'Company buyer',
        totalOrders: companyOrders.length,
        totalUnits: totalUnits,
        totalSpend: totalSpend,
        latestOrderAt: companyOrders.first.createdAt,
      );
    }).toList()
      ..sort((a, b) {
        final unitCompare = b.totalUnits.compareTo(a.totalUnits);
        if (unitCompare != 0) return unitCompare;
        return b.latestOrderAt.compareTo(a.latestOrderAt);
      });

    return SkilledCompanySocialProof(
      uniqueCompanyBuyers: highlights.length,
      companyOrdersCount: highlights.fold<int>(
        0,
        (total, item) => total + item.totalOrders,
      ),
      companyUnitsBought: highlights.fold<int>(
        0,
        (total, item) => total + item.totalUnits,
      ),
      companyRevenue: highlights.fold<double>(
        0,
        (total, item) => total + item.totalSpend,
      ),
      topCompanyBuyers: highlights.take(3).toList(),
    );
  }

  /// Counts a skilled profile view only once per viewer.
  Future<void> trackUniqueSkilledProfileView({
    required String skilledUserId,
    required String viewerUserId,
  }) async {
    if (skilledUserId.trim().isEmpty || viewerUserId.trim().isEmpty) return;
    if (skilledUserId == viewerUserId) return;

    final profileRef = _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(skilledUserId);
    final viewerRef =
        profileRef.collection('profile_viewers').doc(viewerUserId);

    try {
      await _firestore.runTransaction((transaction) async {
        final viewerSnap = await transaction.get(viewerRef);
        if (viewerSnap.exists) return;

        transaction.set(viewerRef, {
          'viewerId': viewerUserId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(profileRef, {
          'profileViews': FieldValue.increment(1),
        });
      });
    } catch (e) {
      debugPrint('Failed to track unique profile view: $e');
    }
  }

  /// Realtime stream of profile view count for a skilled user.
  Stream<int> skilledProfileViewCountStream(String skilledUserId) {
    return _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(skilledUserId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0;
      final value = doc.data()?['profileViews'];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    });
  }

  Future<bool> isAadhaarAlreadyUsed(String aadhaarNumber,
      {String? excludeUserId}) async {
    final cleanAadhaar = _normalizeAadhaar(aadhaarNumber);
    if (cleanAadhaar.length != 12 || int.tryParse(cleanAadhaar) == null) {
      throw Exception('Invalid Aadhaar number format');
    }

    final doc = await _firestore
        .collection(_aadhaarRegistryCollection)
        .doc(cleanAadhaar)
        .get();

    if (!doc.exists) return false;
    final ownerUserId = doc.data()?['userId'] as String?;
    return ownerUserId != null && ownerUserId != excludeUserId;
  }

  Future<bool> isSkilledUserAadhaarVerified(String userId) async {
    final profile = await getSkilledUserProfile(userId);
    if (profile == null) return false;
    return _isSkilledProfileAadhaarVerified(profile);
  }

  Future<SkilledUserProfile?> verifyAndLockAadhaar({
    required String userId,
    required String aadhaarNumber,
  }) async {
    final cleanAadhaar = _normalizeAadhaar(aadhaarNumber);
    if (cleanAadhaar.length != 12 || int.tryParse(cleanAadhaar) == null) {
      throw Exception(
          'Invalid Aadhaar number. Aadhaar must contain exactly 12 digits.');
    }

    final profileRef =
        _firestore.collection(AppConstants.skilledUsersCollection).doc(userId);
    final aadhaarRef =
        _firestore.collection(_aadhaarRegistryCollection).doc(cleanAadhaar);

    await _firestore.runTransaction((transaction) async {
      final profileSnap = await transaction.get(profileRef);
      final profileData = profileSnap.data() ?? <String, dynamic>{};
      final rawVerificationData = profileData['verificationData'];
      final verificationData = rawVerificationData is Map
          ? Map<String, dynamic>.from(rawVerificationData)
          : <String, dynamic>{};

      final existingAadhaar =
          (verificationData['aadhaarNumber'] as String?)?.trim();
      final aadhaarLocked = verificationData['aadhaarLocked'] == true;

      if (aadhaarLocked &&
          existingAadhaar != null &&
          existingAadhaar.isNotEmpty &&
          existingAadhaar != cleanAadhaar) {
        throw Exception(
          'Aadhaar is locked for this profile. Submit a request to admin with valid proofs to change it.',
        );
      }

      final aadhaarSnap = await transaction.get(aadhaarRef);
      if (aadhaarSnap.exists) {
        final ownerUserId = aadhaarSnap.data()?['userId'] as String?;
        if (ownerUserId != null && ownerUserId != userId) {
          throw Exception(
              'This Aadhaar number is already linked to another account.');
        }
      }

      final maskedAadhaar = _maskAadhaar(cleanAadhaar);

      transaction.set(
        aadhaarRef,
        {
          'userId': userId,
          'maskedAadhaar': maskedAadhaar,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!aadhaarSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // Cleanup old registry entry if user is linking a new Aadhaar for the first time.
      if (existingAadhaar != null &&
          existingAadhaar.isNotEmpty &&
          existingAadhaar != cleanAadhaar &&
          !aadhaarLocked) {
        final oldAadhaarRef = _firestore
            .collection(_aadhaarRegistryCollection)
            .doc(existingAadhaar);
        transaction.delete(oldAadhaarRef);
      }

      transaction.set(
        profileRef,
        {
          'verificationStatus': AppConstants.verificationApproved,
          'visibility': AppConstants.visibilityPublic,
          'isVerified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'verificationData': {
            ...verificationData,
            'aadhaarNumber': cleanAadhaar,
            'maskedAadhaar': maskedAadhaar,
            'aadhaarLocked': true,
            'aadhaarLockedAt': verificationData['aadhaarLockedAt'] ??
                FieldValue.serverTimestamp(),
            'aadhaarChangeRequested': false,
            'aadhaarChangeRequestId': null,
            'verifiedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
    });

    return getSkilledUserProfile(userId);
  }

  Future<bool> hasPendingAadhaarChangeRequest(String userId) async {
    final snapshot = await _firestore
        .collection(AppConstants.appealsCollection)
        .where('userId', isEqualTo: userId)
        .limit(25)
        .get();

    return snapshot.docs.any((doc) {
      final data = doc.data();
      return data['type'] == _aadhaarChangeRequestType &&
          data['status'] == 'pending';
    });
  }

  Future<String> requestAadhaarChange({
    required String userId,
    required String reason,
    List<String> proofLinks = const [],
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw Exception(
          'Please provide a valid reason and proof details for Aadhaar change.');
    }

    final profile = await getSkilledUserProfile(userId);
    if (profile == null || !_isSkilledProfileAadhaarVerified(profile)) {
      throw Exception('Aadhaar must be verified before requesting a change.');
    }

    final alreadyPending = await hasPendingAadhaarChangeRequest(userId);
    if (alreadyPending) {
      throw Exception('You already have a pending Aadhaar change request.');
    }

    final cleanProofLinks =
        proofLinks.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final requestId = await createAppeal(
      AppealModel(
        id: '',
        userId: userId,
        type: _aadhaarChangeRequestType,
        title: 'Aadhaar Change Request',
        description: trimmedReason,
        attachments: cleanProofLinks,
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .set({
      'updatedAt': FieldValue.serverTimestamp(),
      'verificationData': {
        ...(profile.verificationData ?? <String, dynamic>{}),
        'aadhaarChangeRequested': true,
        'aadhaarChangeRequestedAt': FieldValue.serverTimestamp(),
        'aadhaarChangeRequestId': requestId,
      },
    }, SetOptions(merge: true));

    return requestId;
  }

  Future<List<SkilledUserProfile>> getVerifiedSkilledUsers({
    String? category,
    List<String>? skills,
    int limit = 20,
  }) async {
    if (_auth.currentUser == null) return [];

    try {
      Query query = _firestore
          .collection(AppConstants.skilledUsersCollection)
          .where('isVerified', isEqualTo: true)
          .where('visibility', isEqualTo: AppConstants.visibilityPublic);

      if (category != null) {
        query = query.where('category', isEqualTo: category);
      }

      final fetchLimit = (limit * 3).clamp(20, 120).toInt();
      query = query.limit(fetchLimit);

      final snapshot = await query.get();
      final dedupedProfiles = <String, SkilledUserProfile>{};

      for (final doc in snapshot.docs) {
        final profile = SkilledUserProfile.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
        if (!_isSkilledProfileAadhaarVerified(profile)) continue;
        if (profile.userId.trim().isEmpty) continue;
        if (doc.id != profile.userId) {
          // Legacy compatibility: move auto-id profile docs to /skilled_users/{uid}.
          try {
            final legacyData = Map<String, dynamic>.from(
              doc.data() as Map<String, dynamic>,
            );
            legacyData['userId'] = profile.userId;
            await _firestore
                .collection(AppConstants.skilledUsersCollection)
                .doc(profile.userId)
                .set(legacyData, SetOptions(merge: true));
          } catch (e) {
            debugPrint(
              'Verified profile migration skipped (${profile.userId}): $e',
            );
          }
        }

        final existing = dedupedProfiles[profile.userId];
        if (existing == null || profile.updatedAt.isAfter(existing.updatedAt)) {
          dedupedProfiles[profile.userId] = profile;
        }
      }

      var profiles = dedupedProfiles.values.toList();

      if (skills != null && skills.isNotEmpty) {
        final normalizedSkills = skills
            .map((skill) => skill.toLowerCase().trim())
            .where((skill) => skill.isNotEmpty)
            .toSet();
        if (normalizedSkills.isNotEmpty) {
          profiles = profiles.where((profile) {
            final profileSkills =
                profile.skills.map((skill) => skill.toLowerCase().trim());
            return profileSkills.any(normalizedSkills.contains);
          }).toList();
        }
      }

      if (profiles.isEmpty) return profiles;

      // Dynamic privacy guard: hide profiles where users.settings.profileVisible is false.
      final userDocs = await Future.wait(
        profiles.map((p) => _firestore
            .collection(AppConstants.usersCollection)
            .doc(p.userId)
            .get()),
      );
      final hiddenUserIds = <String>{};
      for (final doc in userDocs) {
        final settings = doc.data()?['settings'];
        final visible = settings is Map
            ? (settings['profileVisible'] as bool? ?? true)
            : true;
        if (!visible) hiddenUserIds.add(doc.id);
      }

      profiles =
          profiles.where((p) => !hiddenUserIds.contains(p.userId)).toList();

      if (profiles.length > limit) {
        return profiles.sublist(0, limit);
      }
      return profiles;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        return [];
      }
      rethrow;
    }
  }

  // ===== Customer Profile =====

  Future<void> updateCustomerProfile(CustomerProfile profile) async {
    await _firestore
        .collection(AppConstants.customerProfilesCollection)
        .doc(profile.userId)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  Future<CustomerProfile?> getCustomerProfile(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.customerProfilesCollection)
        .doc(userId)
        .get();

    if (!doc.exists) return null;
    return CustomerProfile.fromMap(doc.data()!, userId);
  }

  Stream<CustomerProfile?> customerProfileStream(String userId) {
    return _firestore
        .collection(AppConstants.customerProfilesCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return CustomerProfile.fromMap(doc.data()!, userId);
    });
  }

  // ===== Company Profile =====

  Future<void> updateCompanyProfile(CompanyProfile profile) async {
    await _firestore
        .collection(AppConstants.companyProfilesCollection)
        .doc(profile.userId)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  Future<CompanyProfile?> getCompanyProfile(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.companyProfilesCollection)
        .doc(userId)
        .get();

    if (!doc.exists) return null;
    return CompanyProfile.fromMap(doc.data()!, userId);
  }

  Stream<CompanyProfile?> companyProfileStream(String userId) {
    return _firestore
        .collection(AppConstants.companyProfilesCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return CompanyProfile.fromMap(doc.data()!, userId);
    });
  }

  // ===== Services =====

  List<ServiceModel> _sortServicesByNewest(List<ServiceModel> services) {
    services.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return services;
  }

  double _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  List<ServiceModel> _buildServicesFromProfileData(
    Map<String, dynamic> profileData,
    String userId,
  ) {
    final now = DateTime.now();
    final bio = (profileData['bio'] as String?)?.trim() ?? '';
    final fallbackDescription =
        bio.isNotEmpty ? bio : 'Service details are available on request.';
    final fallbackCategory =
        ((profileData['category'] as String?)?.trim().isNotEmpty == true)
            ? (profileData['category'] as String).trim()
            : 'General';

    final rawServices = profileData['services'] ??
        profileData['serviceList'] ??
        profileData['servicesOffered'];
    final services = <ServiceModel>[];

    if (rawServices is List) {
      for (var i = 0; i < rawServices.length; i++) {
        final rawItem = rawServices[i];
        if (rawItem is Map) {
          final item = Map<String, dynamic>.from(rawItem);
          final title = ((item['title'] ??
                      item['name'] ??
                      item['service'] ??
                      item['label'])
                  ?.toString()
                  .trim() ??
              '');
          if (title.isEmpty) continue;

          services.add(
            ServiceModel(
              id: 'profile_service_${userId}_$i',
              userId: userId,
              title: title,
              description: ((item['description'] ?? item['details'])
                              ?.toString()
                              .trim() ??
                          '')
                      .isNotEmpty
                  ? (item['description'] ?? item['details']).toString().trim()
                  : fallbackDescription,
              priceMin: _safeDouble(item['priceMin'] ?? item['minPrice']),
              priceMax: _safeDouble(item['priceMax'] ?? item['maxPrice']),
              priceUnit: ((item['priceUnit'] ?? item['unit'])?.toString() ??
                      'on request')
                  .trim(),
              images: item['images'] is List
                  ? List<String>.from(
                      (item['images'] as List)
                          .map((e) => e.toString().trim())
                          .where((e) => e.isNotEmpty),
                    )
                  : const [],
              category:
                  ((item['category'] as String?)?.trim().isNotEmpty == true)
                      ? (item['category'] as String).trim()
                      : fallbackCategory,
              isActive: item['isActive'] != false,
              createdAt: (item['createdAt'] as Timestamp?)?.toDate() ?? now,
              updatedAt: (item['updatedAt'] as Timestamp?)?.toDate() ?? now,
            ),
          );
          continue;
        }

        final title = rawItem.toString().trim();
        if (title.isEmpty) continue;
        services.add(
          ServiceModel(
            id: 'profile_service_${userId}_$i',
            userId: userId,
            title: title,
            description: fallbackDescription,
            priceMin: 0,
            priceMax: 0,
            priceUnit: 'on request',
            category: fallbackCategory,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    return _sortServicesByNewest(services);
  }

  Future<List<ServiceModel>> _getFallbackServicesFromProfile(
      String userId) async {
    try {
      final profileByDocId = await _firestore
          .collection(AppConstants.skilledUsersCollection)
          .doc(userId)
          .get();
      if (profileByDocId.exists) {
        final data = Map<String, dynamic>.from(profileByDocId.data()!);
        final derived = _buildServicesFromProfileData(data, userId);
        if (derived.isNotEmpty) return derived;
      }

      final legacyProfile = await _firestore
          .collection(AppConstants.skilledUsersCollection)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
      if (legacyProfile.docs.isNotEmpty) {
        final data = Map<String, dynamic>.from(legacyProfile.docs.first.data());
        final derived = _buildServicesFromProfileData(data, userId);
        if (derived.isNotEmpty) return derived;
      }
    } catch (e) {
      debugPrint('Service profile fallback lookup failed: $e');
    }

    final profile = await getSkilledUserProfile(userId);
    if (profile == null || profile.skills.isEmpty) return [];

    final fallbackDescription = profile.bio.trim().isNotEmpty
        ? profile.bio.trim()
        : 'Service details are available on request.';
    final fallbackCategory = (profile.category?.trim().isNotEmpty == true)
        ? profile.category!
        : 'General';
    final fallbackServices = <ServiceModel>[];
    var index = 0;

    for (final rawSkill in profile.skills) {
      final skill = rawSkill.trim();
      if (skill.isEmpty) continue;
      fallbackServices.add(
        ServiceModel(
          id: 'profile_skill_${userId}_$index',
          userId: userId,
          title: skill,
          description: fallbackDescription,
          priceMin: 0,
          priceMax: 0,
          priceUnit: 'on request',
          category: fallbackCategory,
          isActive: true,
          createdAt: profile.createdAt,
          updatedAt: profile.updatedAt,
        ),
      );
      index += 1;
      if (index >= 6) break;
    }

    return _sortServicesByNewest(fallbackServices);
  }

  Future<String> createService(ServiceModel service) async {
    final docRef = await _firestore.collection('services').add(service.toMap());
    return docRef.id;
  }

  Future<List<ServiceModel>> getUserServices(String userId) async {
    final servicesCollection = _firestore.collection('services');
    try {
      final snapshot = await servicesCollection
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs
          .map((doc) => ServiceModel.fromMap(doc.data(), doc.id))
          .toList();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        try {
          // Fallback query for projects that don't have this composite index yet.
          final snapshot =
              await servicesCollection.where('userId', isEqualTo: userId).get();
          final services = snapshot.docs
              .map((doc) => ServiceModel.fromMap(doc.data(), doc.id))
              .toList();
          return _sortServicesByNewest(services);
        } on FirebaseException catch (_) {
          // Continue to profile fallback below.
        }
      }

      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        debugPrint('getUserServices fallback for user $userId: ${e.message}');
        return _getFallbackServicesFromProfile(userId);
      }
      rethrow;
    }
  }

  Future<void> updateService(ServiceModel service) async {
    await _firestore
        .collection('services')
        .doc(service.id)
        .update(service.toMap());
  }

  Future<void> deleteService(String serviceId) async {
    await _firestore.collection('services').doc(serviceId).delete();
  }

  // ===== Custom Skills (global suggestions) =====

  Future<void> addCustomSkill(String skill) async {
    final normalized = skill.trim();
    if (normalized.isEmpty) return;
    // Use skill as doc ID (lowercase) to avoid duplicates
    await _firestore
        .collection('custom_skills')
        .doc(normalized.toLowerCase())
        .set({
      'name': normalized,
      'addedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<String>> getCustomSkills() async {
    final snapshot =
        await _firestore.collection('custom_skills').orderBy('name').get();
    return snapshot.docs
        .map((doc) => doc.data()['name'] as String? ?? doc.id)
        .toList();
  }

  // ===== Products =====

  Future<String> createProduct(
    ProductModel product, {
    bool bypassSellerVerification = false,
  }) async {
    if (!bypassSellerVerification && product.sourceType != 'skillshare') {
      final canSell = await isSkilledUserAadhaarVerified(product.userId);
      if (!canSell) {
        throw Exception(
            'Aadhaar verification is required before publishing products.');
      }
    }

    final docRef = await _firestore
        .collection(AppConstants.productsCollection)
        .add(product.toMap());
    return docRef.id;
  }

  Future<List<ProductModel>> getUserProducts(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.productsCollection)
          .where('userId', isEqualTo: userId)
          .get();

      // Show ALL products for the owner (including unavailable ones)
      final products = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .toList();

      // Sort by createdAt descending
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return products;
    } catch (e) {
      debugPrint('Error getting user products: $e');
      return [];
    }
  }

  Stream<List<ProductModel>> streamUserProducts(String userId) {
    return _firestore
        .collection(AppConstants.productsCollection)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return products;
    });
  }

  Future<List<ProductModel>> getAllProducts({int limit = 50}) async {
    if (_auth.currentUser == null) return [];

    try {
      final snapshot = await _firestore
          .collection(AppConstants.productsCollection)
          .limit(limit)
          .get();

      // Filter in memory to avoid index requirement
      final products = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .where((product) => product.isAvailable)
          .toList();

      if (products.isEmpty) return [];

      // Enforce strict visibility: only products from Aadhaar-verified skilled users are public
      final sellerIds = products
          .map((product) => product.userId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final verifiedSellerIds = <String>{};
      for (var i = 0; i < sellerIds.length; i += 10) {
        final end = (i + 10 > sellerIds.length) ? sellerIds.length : i + 10;
        final batchIds = sellerIds.sublist(i, end);

        final docsByUserId = <String, Map<String, dynamic>>{};

        final byDocIdSnapshot = await _firestore
            .collection(AppConstants.skilledUsersCollection)
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();

        for (final doc in byDocIdSnapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final mappedUserId = (data['userId'] as String?)?.trim();
          final resolvedUserId =
              (mappedUserId != null && mappedUserId.isNotEmpty)
                  ? mappedUserId
                  : doc.id;
          docsByUserId[resolvedUserId] = data;
        }

        // Legacy compatibility: some profiles were saved with auto doc IDs.
        final byUserIdFieldSnapshot = await _firestore
            .collection(AppConstants.skilledUsersCollection)
            .where('userId', whereIn: batchIds)
            .get();

        for (final doc in byUserIdFieldSnapshot.docs) {
          final data = Map<String, dynamic>.from(doc.data());
          final mappedUserId = (data['userId'] as String?)?.trim();
          if (mappedUserId == null || mappedUserId.isEmpty) continue;
          docsByUserId[mappedUserId] = data;
        }

        for (final entry in docsByUserId.entries) {
          if (_isSkilledUserDataAadhaarVerified(entry.value)) {
            verifiedSellerIds.add(entry.key);
          }
        }
      }

      final visibleProducts = products.where((product) {
        if (product.sourceType == 'skillshare') return true;
        return verifiedSellerIds.contains(product.userId);
      }).toList();

      // Sort by createdAt descending
      visibleProducts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return visibleProducts;
    } catch (e) {
      debugPrint('Error getting products: $e');
      return []; // Return empty list on error
    }
  }

  /// Emits a fresh product list whenever the products collection changes.
  Stream<List<ProductModel>> streamAllProducts({int limit = 50}) {
    return _firestore
        .collection(AppConstants.productsCollection)
        .limit(limit)
        .snapshots()
        .asyncMap((_) => getAllProducts(limit: limit));
  }

  /// Admin stream with no public-visibility filtering.
  Stream<List<ProductModel>> streamAllProductsForAdmin({int limit = 300}) {
    return _firestore
        .collection(AppConstants.productsCollection)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final products = snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), doc.id))
          .toList();
      products.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return products;
    });
  }

  /// Real-time stream of the base [UserModel] for a given uid.
  Stream<UserModel?> streamUserModel(String userId) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((snap) =>
            snap.exists ? UserModel.fromMap(snap.data()!, snap.id) : null);
  }

  Future<void> deleteProduct(String productId) async {
    await _firestore
        .collection(AppConstants.productsCollection)
        .doc(productId)
        .delete();
  }

  Future<void> updateProduct(ProductModel product) async {
    await _firestore
        .collection(AppConstants.productsCollection)
        .doc(product.id)
        .update(product.toMap());
  }

  // ===== Cart & Orders =====

  Future<void> addToCart({
    required String userId,
    required ProductModel product,
    int quantity = 1,
  }) async {
    if (quantity <= 0) {
      throw Exception('Quantity must be at least 1.');
    }
    if (userId == product.userId) {
      throw Exception('You cannot add your own product to cart.');
    }

    final productRef =
        _firestore.collection(AppConstants.productsCollection).doc(product.id);
    final cartItemRef = _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .doc(product.id);

    await _firestore.runTransaction((transaction) async {
      final productSnap = await transaction.get(productRef);
      if (!productSnap.exists) {
        throw Exception('Product no longer exists.');
      }

      final productData = productSnap.data()!;
      final latestProduct = ProductModel.fromMap(productData, productSnap.id);

      if (!latestProduct.isAvailable || latestProduct.stock <= 0) {
        throw Exception('This product is currently out of stock.');
      }

      final cartSnap = await transaction.get(cartItemRef);
      final existingQuantity =
          cartSnap.exists ? (cartSnap.data()?['quantity'] as int? ?? 0) : 0;
      final newQuantity = existingQuantity + quantity;

      if (newQuantity > latestProduct.stock) {
        throw Exception(
            'Only ${latestProduct.stock} item(s) are available in stock.');
      }

      transaction.set(
        cartItemRef,
        {
          'userId': userId,
          'productId': latestProduct.id,
          'sellerId': latestProduct.userId,
          'productName': latestProduct.name,
          'productImage': latestProduct.images.isNotEmpty
              ? latestProduct.images.first
              : null,
          'price': latestProduct.price,
          'quantity': newQuantity,
          'availableStock': latestProduct.stock,
          'isAvailable': latestProduct.isAvailable,
          'updatedAt': FieldValue.serverTimestamp(),
          if (!cartSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Stream<List<CartItemModel>> streamCartItems(String userId) {
    return _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map((doc) => CartItemModel.fromMap(doc.data(), doc.id))
          .toList();
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    });
  }

  Future<List<CartItemModel>> getCartItems(String userId) async {
    final snapshot = await _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .get();
    final items = snapshot.docs
        .map((doc) => CartItemModel.fromMap(doc.data(), doc.id))
        .toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  Future<void> updateCartItemQuantity({
    required String userId,
    required String productId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      await removeCartItem(userId: userId, productId: productId);
      return;
    }

    final productSnap = await _firestore
        .collection(AppConstants.productsCollection)
        .doc(productId)
        .get();
    if (!productSnap.exists) {
      throw Exception('Product no longer exists.');
    }
    final product = ProductModel.fromMap(productSnap.data()!, productSnap.id);
    if (quantity > product.stock) {
      throw Exception('Only ${product.stock} item(s) are available.');
    }

    await _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .doc(productId)
        .set({
      'quantity': quantity,
      'availableStock': product.stock,
      'isAvailable': product.isAvailable,
      'price': product.price,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeCartItem({
    required String userId,
    required String productId,
  }) async {
    await _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .doc(productId)
        .delete();
  }

  Future<int> getCartItemCount(String userId) async {
    final items = await getCartItems(userId);
    return items.fold<int>(0, (totalItems, item) => totalItems + item.quantity);
  }

  Future<OrderModel> purchaseProductDirect({
    required String userId,
    required ProductModel product,
    int quantity = 1,
    String paymentMethod = 'gpay_simulation',
    String? paymentReference,
    String? deliveryAddress,
    String? deliveryLocation,
  }) async {
    if (quantity <= 0) {
      throw Exception('Quantity must be at least 1.');
    }
    if (userId == product.userId) {
      throw Exception('You cannot buy your own product.');
    }

    final buyer = await getUserById(userId);
    final shopSettings = await getShopSettings(product.userId);
    final userSettings = await getUserSettings(product.userId);

    int parseMaxDeliveryQuantity(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      return 0;
    }

    bool parseAllowDelivery(dynamic value) {
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
      }
      if (value is num) return value != 0;
      return true;
    }

    final profileWorkflowEnabled =
        (userSettings['enableShopDeliveryWorkflow'] as bool?) ?? true;
    final allowDeliveryIfAvailable =
        parseAllowDelivery(shopSettings['enableDeliveryIfAvailable']);
    final configuredMaxDeliveryQty =
        parseMaxDeliveryQuantity(shopSettings['maxDeliveryQuantity']);
    final appliedMaxDeliveryQty =
        configuredMaxDeliveryQty > 0 ? configuredMaxDeliveryQty : 10;
    final deliveryByPartner = profileWorkflowEnabled &&
        allowDeliveryIfAvailable &&
        quantity <= appliedMaxDeliveryQty;
    final deliveryCode = _generateDeliveryVerificationCode();
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'gpay_simulation' : paymentMethod.trim();
    final normalizedReference = paymentReference?.trim();
    final normalizedDeliveryAddress = deliveryAddress?.trim();
    final normalizedDeliveryLocation = deliveryLocation?.trim();

    final productRef =
        _firestore.collection(AppConstants.productsCollection).doc(product.id);
    final cartItemRef = _firestore
        .collection(AppConstants.cartsCollection)
        .doc(userId)
        .collection('items')
        .doc(product.id);
    final orderRef = _firestore.collection(AppConstants.ordersCollection).doc();
    final now = DateTime.now();
    late final OrderModel createdOrder;

    int remainingStockToUpdate = 0;
    await _firestore.runTransaction((transaction) async {
      final productSnap = await transaction.get(productRef);
      if (!productSnap.exists || productSnap.data() == null) {
        throw Exception('Product no longer exists.');
      }

      final latestProduct =
          ProductModel.fromMap(productSnap.data()!, productSnap.id);
      if (!latestProduct.isAvailable || latestProduct.stock <= 0) {
        throw Exception('This product is currently out of stock.');
      }
      if (quantity > latestProduct.stock) {
        throw Exception(
            'Only ${latestProduct.stock} item(s) are available in stock.');
      }

      final remainingStock = latestProduct.stock - quantity;
      remainingStockToUpdate = remainingStock;

      createdOrder = OrderModel(
        id: orderRef.id,
        buyerId: userId,
        sellerId: latestProduct.userId,
        productId: latestProduct.id,
        productName: latestProduct.name,
        productImage:
            latestProduct.images.isNotEmpty ? latestProduct.images.first : null,
        quantity: quantity,
        unitPrice: latestProduct.price,
        totalPrice: latestProduct.price * quantity,
        status: 'pending',
        buyerName: buyer?.name,
        buyerEmail: buyer?.email,
        paymentMethod: normalizedPaymentMethod,
        paymentStatus: 'paid',
        paymentReference:
            (normalizedReference != null && normalizedReference.isNotEmpty)
                ? normalizedReference
                : null,
        paidAt: now,
        sellerTransferStatus: 'credited_simulated',
        sellerTransferAt: now,
        statusTimeline: {'pending': now},
        deliveryAddress: normalizedDeliveryAddress != null &&
                normalizedDeliveryAddress.isNotEmpty
            ? normalizedDeliveryAddress
            : null,
        deliveryLocation: normalizedDeliveryLocation != null &&
                normalizedDeliveryLocation.isNotEmpty
            ? normalizedDeliveryLocation
            : null,
        deliveryVerificationCode: deliveryCode,
        deliveryByPartner: deliveryByPartner,
        deliveryQuantityLimit: appliedMaxDeliveryQty,
        createdAt: now,
        updatedAt: now,
      );

      transaction.set(orderRef, createdOrder.toMap());
      transaction.delete(cartItemRef);

      // Successfully update product stock explicitly within the transaction so that
      // failed stock decrements (e.g. concurrent race condition or rules enforcement) will abort the order.
      transaction.update(productRef, {
        'stock': remainingStockToUpdate,
        'isAvailable': remainingStockToUpdate > 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _createNotificationRecord(
      toUserId: createdOrder.sellerId,
      fromUserId: createdOrder.buyerId,
      type: 'shopOrderPlaced',
      title: 'New shop order received',
      body:
          '${createdOrder.buyerName ?? 'A customer'} placed an order for ${createdOrder.quantity} x ${createdOrder.productName}.',
      orderId: createdOrder.id,
      productId: createdOrder.productId,
      productName: createdOrder.productName,
      status: createdOrder.status,
    );

    await _createNotificationRecord(
      toUserId: createdOrder.buyerId,
      fromUserId: createdOrder.sellerId,
      type: 'shopOrderPlaced',
      title: 'Order placed successfully',
      body: 'Your order for ${createdOrder.productName} has been placed.',
      orderId: createdOrder.id,
      productId: createdOrder.productId,
      productName: createdOrder.productName,
      status: createdOrder.status,
    );

    return createdOrder;
  }

  Future<List<OrderModel>> checkoutCart(
    String userId, {
    String paymentMethod = 'gpay_simulation',
    String? paymentReference,
    String? deliveryAddress,
    String? deliveryLocation,
  }) async {
    final cartItems = await getCartItems(userId);
    if (cartItems.isEmpty) {
      throw Exception('Your cart is empty.');
    }

    if (cartItems.length > 100) {
      throw Exception(
          'Cart has too many items to process at once. Please checkout fewer items.');
    }

    final buyer = await getUserById(userId);
    final batch = _firestore.batch();
    final createdOrders = <OrderModel>[];
    final now = DateTime.now();
    final sellerShopSettingsById = <String, Map<String, dynamic>>{};
    final sellerUserSettingsById = <String, Map<String, dynamic>>{};
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'gpay_simulation' : paymentMethod.trim();
    final normalizedReference = paymentReference?.trim();
    final normalizedDeliveryAddress = deliveryAddress?.trim();
    final normalizedDeliveryLocation = deliveryLocation?.trim();

    int parseMaxDeliveryQuantity(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      return 0;
    }

    bool parseAllowDelivery(dynamic value) {
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
      }
      if (value is num) return value != 0;
      return true;
    }

    for (final item in cartItems) {
      final productRef = _firestore
          .collection(AppConstants.productsCollection)
          .doc(item.productId);
      final productSnap = await productRef.get();
      if (!productSnap.exists) {
        throw Exception('One of the products in cart no longer exists.');
      }

      final latestProduct =
          ProductModel.fromMap(productSnap.data()!, item.productId);
      if (!latestProduct.isAvailable || latestProduct.stock < item.quantity) {
        throw Exception(
            'Insufficient stock for "${latestProduct.name}". Please update cart.');
      }

      if (!sellerShopSettingsById.containsKey(latestProduct.userId)) {
        sellerShopSettingsById[latestProduct.userId] =
            await getShopSettings(latestProduct.userId);
      }
      if (!sellerUserSettingsById.containsKey(latestProduct.userId)) {
        sellerUserSettingsById[latestProduct.userId] =
            await getUserSettings(latestProduct.userId);
      }
      final shopSettings = sellerShopSettingsById[latestProduct.userId]!;
      final userSettings = sellerUserSettingsById[latestProduct.userId]!;
      final profileWorkflowEnabled =
          (userSettings['enableShopDeliveryWorkflow'] as bool?) ?? true;
      final allowDeliveryIfAvailable =
          parseAllowDelivery(shopSettings['enableDeliveryIfAvailable']);
      final configuredMaxDeliveryQty =
          parseMaxDeliveryQuantity(shopSettings['maxDeliveryQuantity']);
      final appliedMaxDeliveryQty =
          configuredMaxDeliveryQty > 0 ? configuredMaxDeliveryQty : 10;
      final deliveryByPartner = profileWorkflowEnabled &&
          allowDeliveryIfAvailable &&
          item.quantity <= appliedMaxDeliveryQty;
      final deliveryCode = _generateDeliveryVerificationCode();

      final orderRef =
          _firestore.collection(AppConstants.ordersCollection).doc();
      final totalPrice = latestProduct.price * item.quantity;
      final order = OrderModel(
        id: orderRef.id,
        buyerId: userId,
        sellerId: latestProduct.userId,
        productId: latestProduct.id,
        productName: latestProduct.name,
        productImage:
            latestProduct.images.isNotEmpty ? latestProduct.images.first : null,
        quantity: item.quantity,
        unitPrice: latestProduct.price,
        totalPrice: totalPrice,
        status: 'pending',
        buyerName: buyer?.name,
        buyerEmail: buyer?.email,
        paymentMethod: normalizedPaymentMethod,
        paymentStatus: 'paid',
        paymentReference:
            (normalizedReference != null && normalizedReference.isNotEmpty)
                ? normalizedReference
                : null,
        paidAt: now,
        sellerTransferStatus: 'credited_simulated',
        sellerTransferAt: now,
        statusTimeline: {'pending': now},
        deliveryAddress: normalizedDeliveryAddress != null &&
                normalizedDeliveryAddress.isNotEmpty
            ? normalizedDeliveryAddress
            : null,
        deliveryLocation: normalizedDeliveryLocation != null &&
                normalizedDeliveryLocation.isNotEmpty
            ? normalizedDeliveryLocation
            : null,
        deliveryVerificationCode: deliveryCode,
        deliveryByPartner: deliveryByPartner,
        deliveryQuantityLimit: appliedMaxDeliveryQty,
        createdAt: now,
        updatedAt: now,
      );
      createdOrders.add(order);
      batch.set(orderRef, order.toMap());
      final remainingStock = latestProduct.stock - item.quantity;

      // Update the product within the batch to ensure consistency.
      batch.update(productRef, {
        'stock': remainingStock,
        'isAvailable': remainingStock > 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final cartItemRef = _firestore
          .collection(AppConstants.cartsCollection)
          .doc(userId)
          .collection('items')
          .doc(item.productId);
      batch.delete(cartItemRef);
    }

    await batch.commit();

    final notificationTasks = <Future<void>>[];
    for (final order in createdOrders) {
      notificationTasks.add(
        _createNotificationRecord(
          toUserId: order.sellerId,
          fromUserId: order.buyerId,
          type: 'shopOrderPlaced',
          title: 'New shop order received',
          body:
              '${order.buyerName ?? 'A customer'} placed an order for ${order.quantity} x ${order.productName}.',
          orderId: order.id,
          productId: order.productId,
          productName: order.productName,
          status: order.status,
        ),
      );
      notificationTasks.add(
        _createNotificationRecord(
          toUserId: order.buyerId,
          fromUserId: order.sellerId,
          type: 'shopOrderPlaced',
          title: 'Order placed successfully',
          body: 'Your order for ${order.productName} has been placed.',
          orderId: order.id,
          productId: order.productId,
          productName: order.productName,
          status: order.status,
        ),
      );
    }
    await Future.wait(notificationTasks);

    return createdOrders;
  }

  Stream<List<OrderModel>> streamSellerOrders(String sellerId) {
    return _firestore
        .collection(AppConstants.ordersCollection)
        .where('sellerId', isEqualTo: sellerId)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  Stream<List<OrderModel>> streamBuyerOrders(String buyerId) {
    return _firestore
        .collection(AppConstants.ordersCollection)
        .where('buyerId', isEqualTo: buyerId)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Stream single order real-time updates for tracking.
  Stream<OrderModel?> streamOrder(String orderId) {
    return _firestore
        .collection(AppConstants.ordersCollection)
        .doc(orderId)
        .snapshots()
        .map((doc) => doc.exists ? OrderModel.fromMap(doc.data()!, doc.id) : null);
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String sellerId,
    required String status,
  }) async {
    const allowedStatuses = {'confirmed', 'shipped', 'delivered', 'cancelled'};
    if (!allowedStatuses.contains(status)) {
      throw Exception('Invalid order status.');
    }

    final orderRef =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw Exception('Order not found.');
    }

    final orderSellerId = orderSnap.data()?['sellerId'] as String?;
    if (orderSellerId != sellerId) {
      throw Exception('You are not authorized to update this order.');
    }

    final data = orderSnap.data() ?? <String, dynamic>{};
    final currentStatus = (data['status'] as String?)?.trim() ?? 'pending';
    final deliveryByPartner = data['deliveryByPartner'] == true;

    bool isAllowedTransition() {
      if (currentStatus == 'pending') {
        return status == 'confirmed' || status == 'cancelled';
      }
      if (currentStatus == 'confirmed') {
        if (deliveryByPartner) {
          return status == 'cancelled';
        }
        return status == 'shipped' || status == 'cancelled';
      }
      if (currentStatus == 'shipped') {
        return status == 'delivered' || status == 'cancelled';
      }
      return false;
    }

    if (!isAllowedTransition()) {
      throw Exception(
          'Invalid transition: $currentStatus -> $status for this order.');
    }

    if (deliveryByPartner && (status == 'shipped' || status == 'delivered')) {
      throw Exception(
          'Seller cannot mark shipped/delivered for delivery-partner orders.');
    }

    final hasDeliveryAddress =
        ((data['deliveryAddress'] as String?) ?? '').trim().isNotEmpty;
    final enablePartnerForThisOrder = deliveryByPartner || hasDeliveryAddress;

    final updatePayload = <String, dynamic>{
      'status': status,
      'statusTimeline.$status': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (status == 'confirmed' && enablePartnerForThisOrder && !deliveryByPartner) {
      updatePayload['deliveryByPartner'] = true;
    }

    await orderRef.update(updatePayload);

    final buyerId = (data['buyerId'] as String?)?.trim() ?? '';
    final productId = (data['productId'] as String?)?.trim() ?? '';
    final productName =
        (data['productName'] as String?)?.trim() ?? 'your order';

    final statusTitle = switch (status) {
      'confirmed' => 'Order confirmed',
      'shipped' => 'Order shipped',
      'delivered' => 'Order delivered',
      'cancelled' => 'Order cancelled',
      _ => 'Order updated',
    };

    if (buyerId.isNotEmpty) {
      await _createNotificationRecord(
        toUserId: buyerId,
        fromUserId: sellerId,
        type: 'shopOrderStatusUpdated',
        title: statusTitle,
        body: 'Your order for $productName is now ${status.toUpperCase()}.',
        orderId: orderId,
        productId: productId,
        productName: productName,
        status: status,
      );
    }
  }

  Future<void> handoverOrderToDeliveryPartner({
    required String orderId,
    required String sellerId,
  }) async {
    final orderRef =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw Exception('Order not found.');
    }
    final data = orderSnap.data() ?? <String, dynamic>{};
    final orderSellerId = data['sellerId'] as String?;
    if (orderSellerId != sellerId) {
      throw Exception('You are not authorized to update this order.');
    }
    await orderRef.update({
      'deliveryByPartner': true,
      'status': 'confirmed',
      'statusTimeline.confirmed': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Delivery Partner =====

  /// Stream all orders assigned to a delivery partner.
  Stream<List<OrderModel>> streamDeliveryPartnerOrders(
      String deliveryPartnerId) {
    return _firestore
        .collection(AppConstants.ordersCollection)
        .where('deliveryPartnerId', isEqualTo: deliveryPartnerId)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Stream orders that are confirmed for partner delivery and unassigned.
  Stream<List<OrderModel>> streamAvailableDeliveries() {
    return _firestore
        .collection(AppConstants.ordersCollection)
        .where('status', isEqualTo: 'confirmed')
        .where('deliveryByPartner', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .where((o) =>
              o.deliveryPartnerId == null || o.deliveryPartnerId!.isEmpty)
          .toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  /// Assign a delivery partner to an order and set estimated delivery.
  Future<void> assignDeliveryPartner({
    required String orderId,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
    DateTime? estimatedDelivery,
  }) async {
    final ref =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);

    // Use a transaction to prevent concurrent assignments
    final data = await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) {
        throw Exception('Order not found.');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final status = (data['status'] as String?)?.trim() ?? '';
      final deliveryByPartner = data['deliveryByPartner'] == true;
      final assignedPartnerId =
          (data['deliveryPartnerId'] as String?)?.trim() ?? '';

      if (!deliveryByPartner) {
        throw Exception(
            'This order is not configured for delivery partner flow.');
      }
      if (status != 'confirmed' && status != 'failed_delivery') {
        throw Exception(
            'Only confirmed or failed orders can be accepted for delivery.');
      }
      if (status == 'confirmed' && assignedPartnerId.isNotEmpty) {
        throw Exception(
            'This order is already assigned to a delivery partner.');
      }

      final existingTimeline =
          (data['statusTimeline'] as Map<String, dynamic>?) ?? {};

      final updateData = <String, dynamic>{
        'deliveryPartnerId': deliveryPartnerId,
        'deliveryPartnerName': deliveryPartnerName,
        'status': 'out_for_delivery',
        'statusTimeline.out_for_delivery': FieldValue.serverTimestamp(),
        if (!existingTimeline.containsKey('shipped'))
          'statusTimeline.shipped': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'failed_delivery') {
        // Clear the failed milestone so the tracking timeline resets for the buyer.
        updateData['statusTimeline.failed_delivery'] = FieldValue.delete();
      }

      if (estimatedDelivery != null) {
        updateData['estimatedDelivery'] = Timestamp.fromDate(estimatedDelivery);
      }
      transaction.update(ref, updateData);

      return data;
    });

    final buyerId = (data['buyerId'] as String?)?.trim() ?? '';
    final sellerId = (data['sellerId'] as String?)?.trim() ?? '';
    final productId = (data['productId'] as String?)?.trim() ?? '';
    final productName =
        (data['productName'] as String?)?.trim() ?? 'your order';

    try {
      await _ensureDeliverySellerChatFromOrderData(
        orderId: orderId,
        orderData: data,
        deliveryPartnerId: deliveryPartnerId,
        deliveryPartnerName: deliveryPartnerName,
      );
    } catch (e) {
      debugPrint('Delivery seller chat creation skipped: $e');
    }

    await _createNotificationRecord(
      toUserId: deliveryPartnerId,
      fromUserId: sellerId,
      type: 'shopDeliveryAssigned',
      title: 'New delivery assigned',
      body: 'You have been assigned to deliver $productName.',
      orderId: orderId,
      productId: productId,
      productName: productName,
      status: 'out_for_delivery',
    );

    if (buyerId.isNotEmpty) {
      await _createNotificationRecord(
        toUserId: buyerId,
        fromUserId: deliveryPartnerId,
        type: 'shopDeliveryAssigned',
        title: 'Delivery partner assigned',
        body: 'A delivery partner is assigned for your order of $productName.',
        orderId: orderId,
        productId: productId,
        productName: productName,
        status: 'out_for_delivery',
      );
    }
  }

  /// Partner cancels their assignment before picking it up.
  Future<void> cancelDeliveryAssignment({
    required String orderId,
    required String deliveryPartnerId,
    required String deliveryPartnerName,
  }) async {
    final ref =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);

    final data = await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) throw Exception('Order not found.');
      final data = snap.data()!;

      final assignedId = data['deliveryPartnerId'] as String?;
      if (assignedId != deliveryPartnerId) {
        throw Exception(
            'You are not the assigned delivery partner for this order.');
      }

      final currentStatus = data['status'] as String?;
      if (currentStatus == 'delivered' || currentStatus == 'out_for_delivery') {
        throw Exception(
            'Cannot cancel a delivery that is already active or delivered.');
      }

      transaction.update(ref, {
        'deliveryPartnerId': FieldValue.delete(),
        'deliveryPartnerName': FieldValue.delete(),
        'estimatedDelivery': FieldValue.delete(),
        // Revert status to confirmed so seller can reassign
        'status': 'confirmed',
        'statusTimeline.partner_cancelled': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return data;
    });

    final sellerId = (data['sellerId'] as String?)?.trim() ?? '';
    final productId = (data['productId'] as String?)?.trim() ?? '';
    final productName =
        (data['productName'] as String?)?.trim() ?? 'your order';

    if (sellerId.isNotEmpty) {
      await _createNotificationRecord(
        toUserId: sellerId,
        fromUserId: deliveryPartnerId,
        type: 'shopDeliveryCancelled',
        title: 'Delivery Partner Cancelled',
        body:
            '$deliveryPartnerName cancelled picking up $productName. Please reassign.',
        orderId: orderId,
        productId: productId,
        productName: productName,
        status: 'cancelled_assignment',
      );
    }
  }

  /// Update order delivery status (only assigned delivery partner can do this).
  Future<void> updateDeliveryStatus({
    required String orderId,
    required String deliveryPartnerId,
    required String status,
    String? deliveryVerificationCode,
  }) async {
    const allowed = {
      'out_for_delivery',
      'delivered',
      'failed_delivery',
    };
    if (!allowed.contains(status)) {
      throw Exception('Invalid delivery status: $status');
    }
    final ref =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);

    final data = await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) throw Exception('Order not found.');
      final data = snap.data()!;
      final assignedId = data['deliveryPartnerId'] as String?;
      final deliveryByPartner = data['deliveryByPartner'] == true;
      final currentStatus = data['status'] as String?;
      if (!deliveryByPartner) {
        throw Exception('This order is not using delivery-partner flow.');
      }
      if (currentStatus == 'cancelled' || currentStatus == 'delivered') {
        throw Exception(
            'This order is already $currentStatus and cannot be updated.');
      }
      if (assignedId != deliveryPartnerId) {
        throw Exception(
            'You are not the assigned delivery partner for this order.');
      }
      final expectedCode =
          (data['deliveryVerificationCode'] as String?)?.trim() ?? '';
      if (status == 'delivered' && expectedCode.isNotEmpty) {
        final enteredCode = deliveryVerificationCode?.trim() ?? '';
        if (enteredCode.isEmpty) {
          throw Exception(
              'Enter the customer delivery code to complete delivery.');
        }
        if (enteredCode != expectedCode) {
          throw Exception('Invalid delivery code. Ask the customer again.');
        }
      }

      final existingTimeline =
          (data['statusTimeline'] as Map<String, dynamic>?) ?? {};

      transaction.update(ref, {
        'status': status,
        'statusTimeline.$status': FieldValue.serverTimestamp(),
        if (!existingTimeline.containsKey('shipped'))
          'statusTimeline.shipped': FieldValue.serverTimestamp(),
        if (status == 'delivered' &&
            !existingTimeline.containsKey('out_for_delivery'))
          'statusTimeline.out_for_delivery': FieldValue.serverTimestamp(),
        if (status == 'delivered')
          'deliveryCodeVerifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return data;
    });

    final buyerId = (data['buyerId'] as String?)?.trim() ?? '';
    final sellerId = (data['sellerId'] as String?)?.trim() ?? '';
    final productId = (data['productId'] as String?)?.trim() ?? '';
    final productName =
        (data['productName'] as String?)?.trim() ?? 'your order';

    final eventTitle = switch (status) {
      'out_for_delivery' => 'Order is out for delivery',
      'delivered' => 'Order delivered',
      'failed_delivery' => 'Delivery attempt failed',
      _ => 'Delivery status updated',
    };

    try {
      if (buyerId.isNotEmpty) {
        await _createNotificationRecord(
          toUserId: buyerId,
          fromUserId: deliveryPartnerId,
          type: 'shopDeliveryStatusUpdated',
          title: eventTitle,
          body: 'Delivery update for $productName: ${status.toUpperCase()}.',
          orderId: orderId,
          productId: productId,
          productName: productName,
          status: status,
        );
      }

      if (sellerId.isNotEmpty) {
        await _createNotificationRecord(
          toUserId: sellerId,
          fromUserId: deliveryPartnerId,
          type: 'shopDeliveryStatusUpdated',
          title: eventTitle,
          body:
              'Delivery update for your order item $productName: ${status.toUpperCase()}.',
          orderId: orderId,
          productId: productId,
          productName: productName,
          status: status,
        );
      }
    } catch (e) {
      debugPrint('Delivery status notification skipped: $e');
    }
  }

  /// Update estimated delivery timeline for the assigned delivery partner.
  Future<void> updateDeliveryEstimate({
    required String orderId,
    required String deliveryPartnerId,
    required DateTime estimatedDelivery,
  }) async {
    final ref =
        _firestore.collection(AppConstants.ordersCollection).doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('Order not found.');
    }
    final data = snap.data() ?? <String, dynamic>{};
    final deliveryByPartner = data['deliveryByPartner'] == true;
    final assignedId = (data['deliveryPartnerId'] as String?)?.trim() ?? '';
    if (!deliveryByPartner) {
      throw Exception('This order is not using delivery-partner flow.');
    }
    if (assignedId != deliveryPartnerId) {
      throw Exception(
          'You are not the assigned delivery partner for this order.');
    }

    await ref.update({
      'estimatedDelivery': Timestamp.fromDate(estimatedDelivery),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Jobs =====

  Future<String> createJob(JobModel job) async {
    final docRef = await _firestore
        .collection(AppConstants.jobsCollection)
        .add(job.toMap());
    return docRef.id;
  }

  Future<List<JobModel>> getOpenJobs({String? skill, int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.jobsCollection)
          .limit(limit * 2) // Get more to filter
          .get();

      // Filter in memory to avoid index requirement
      var jobs = snapshot.docs
          .map((doc) => JobModel.fromMap(doc.data(), doc.id))
          .where((job) => job.status == AppConstants.jobStatusOpen)
          .toList();

      // Filter by skill if provided
      if (skill != null) {
        jobs = jobs.where((job) => job.requiredSkills.contains(skill)).toList();
      }

      // Sort by createdAt descending
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return jobs.take(limit).toList();
    } catch (e) {
      debugPrint('Error getting jobs: $e');
      return []; // Return empty list on error
    }
  }

  Future<void> applyForJob(String jobId, String userId) async {
    final jobRef =
        _firestore.collection(AppConstants.jobsCollection).doc(jobId);
    final userRef =
        _firestore.collection(AppConstants.usersCollection).doc(userId);

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) {
        throw Exception('Job not found.');
      }

      final userSnap = await transaction.get(userRef);
      if (!userSnap.exists) {
        throw Exception('User not found.');
      }

      final jobData = jobSnap.data()!;
      final userData = userSnap.data()!;
      final role = (userData['role'] as String?)?.trim().toLowerCase() ?? '';

      if (role != AppConstants.roleSkilledUser) {
        throw Exception('Only skilled users can apply for jobs.');
      }
      if ((jobData['status'] as String?) != AppConstants.jobStatusOpen) {
        throw Exception('This job is no longer open.');
      }
      if ((jobData['companyId'] as String?) == userId ||
          (jobData['postedBy'] as String?) == userId) {
        throw Exception('You cannot apply to your own job.');
      }

      final existingStatus =
          (jobData['applicationStatus'] as Map<String, dynamic>? ?? {})[userId]
              ?.toString();
      if (existingStatus == 'accepted') {
        throw Exception('You are already accepted for this job.');
      }
      if (existingStatus == 'pending') {
        throw Exception('You have already applied for this job.');
      }

      final bool isReapplication = existingStatus == 'rejected';

      final Map<String, dynamic> updates = {
        'applicants': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
        'applicationStatus.$userId': 'pending',
      };

      transaction.update(jobRef, updates);

      // Notify the company about the new / re-application
      final companyId = (jobData['companyId'] as String?)?.trim() ?? '';
      final applicantName = (userData['name'] as String?)?.trim() ?? 'Someone';
      final jobTitle = (jobData['title'] as String?)?.trim() ?? 'your job';
      if (companyId.isNotEmpty && companyId != userId) {
        final notifRef = _firestore.collection('notifications').doc();
        transaction.set(notifRef, {
          'toUserId': companyId,
          'fromUserId': userId,
          'type': isReapplication ? 'jobReApplication' : 'jobApplication',
          'title': isReapplication
              ? 'Re-application received'
              : 'New job application',
          'body': isReapplication
              ? '$applicantName has re-applied for "$jobTitle"'
              : '$applicantName applied for "$jobTitle"',
          'jobId': jobId,
          'jobTitle': jobTitle,
          'createdAt': FieldValue.serverTimestamp(),
          'seen': false,
        });
      }
    });
  }

  /// Real-time stream of open jobs, re-emits whenever the jobs collection changes.
  Stream<List<JobModel>> streamOpenJobs({int limit = 20}) {
    return _firestore
        .collection(AppConstants.jobsCollection)
        .limit(limit * 2)
        .snapshots()
        .map((snapshot) {
      var jobs = snapshot.docs
          .map((doc) => JobModel.fromMap(doc.data(), doc.id))
          .where((job) => job.status == AppConstants.jobStatusOpen)
          .toList();
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs.take(limit).toList();
    });
  }

  /// Real-time stream of jobs posted by a specific company/user (all statuses).
  Stream<List<JobModel>> streamCompanyJobs(String companyId,
      {int limit = 100}) {
    return _firestore
        .collection(AppConstants.jobsCollection)
        .where('companyId', isEqualTo: companyId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final jobs = snapshot.docs
          .map((doc) => JobModel.fromMap(doc.data(), doc.id))
          .toList();
      jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return jobs;
    });
  }

  /// Fetch a single job by its document id (one-time read).
  Future<JobModel?> getJobById(String jobId) async {
    final doc = await _firestore
        .collection(AppConstants.jobsCollection)
        .doc(jobId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return JobModel.fromMap(doc.data()!, doc.id);
  }

  /// Realtime stream for a single job document.
  Stream<JobModel?> streamJob(String jobId) {
    return _firestore
        .collection(AppConstants.jobsCollection)
        .doc(jobId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return JobModel.fromMap(doc.data()!, doc.id);
    });
  }

  /// Accept one applicant for a job.
  /// Sets selectedApplicant and moves job to in_progress.
  /// Accepts [applicantId] for [jobId], creates the job-offer chat, sends an
  /// offer-letter message and a notification.  Returns the job-chat ID.
  Future<String> acceptJobApplicant({
    required String jobId,
    required String applicantId,
    required String companyId,
  }) async {
    final jobRef =
        _firestore.collection(AppConstants.jobsCollection).doc(jobId);

    // â”€â”€ 1. Transactional acceptance â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');

      final data = jobSnap.data()!;
      final ownerId =
          (data['companyId'] as String?) ?? (data['postedBy'] as String?) ?? '';
      if (ownerId != companyId) {
        throw Exception('Only job owner can accept applicants.');
      }

      final applicants = List<String>.from(data['applicants'] ?? const []);
      if (!applicants.contains(applicantId)) {
        throw Exception('Applicant not found in this job.');
      }

      transaction.update(jobRef, {
        'selectedApplicant': applicantId,
        'status': AppConstants.jobStatusInProgress,
        'updatedAt': FieldValue.serverTimestamp(),
        'applicationStatus.$applicantId': 'accepted',
      });
    });

    // â”€â”€ 2. Re-read job for title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final jobDoc = await jobRef.get();
    final jobTitle = (jobDoc.data()?['title'] as String?)?.trim() ?? 'a job';
    // skipStatusCheck: the transaction already verified acceptance;
    // a fresh Firestore read might return a cached pre-acceptance snapshot.
    final chatId = await ensureJobApplicationChat(
      jobId: jobId,
      companyId: companyId,
      skilledUserId: applicantId,
      jobTitle: jobTitle,
      skipStatusCheck: true,
    );
    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);

    // â”€â”€ 3. Notify the skilled person â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _firestore.collection('notifications').add({
      'toUserId': applicantId,
      'fromUserId': companyId,
      'type': 'jobAccepted',
      'title': 'Application Accepted',
      'body': 'Your application for "$jobTitle" has been accepted. '
          'Open the Jobs > My Jobs tab to view the confirmation message. '
          'The offer letter with full details will be shared soon.',
      'jobId': jobId,
      'jobTitle': jobTitle,
      'chatId': chatId,
      'createdAt': FieldValue.serverTimestamp(),
      'seen': false,
    });

    final companyDoc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(companyId)
        .get();
    final companyName = (companyDoc.data()?['name'] as String?)?.trim() ??
        (companyDoc.data()?['companyName'] as String?)?.trim() ??
        'The company';

    // â”€â”€ 5. Send offer-letter message â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final confirmationText = 'Application Selected\n\n'
        'Congratulations! You have been selected for the "$jobTitle" role at '
        '$companyName.\n\n'
        'We will share the offer letter with the full details soon.';

    final msgRef = chatRef.collection(AppConstants.messagesCollection).doc();
    final batch = _firestore.batch();
    batch.set(msgRef, {
      'chatId': chatId,
      'senderId': companyId,
      'text': confirmationText,
      'type': 'job_confirmation',
      'jobId': jobId,
      'jobTitle': jobTitle,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(chatRef, {
      'lastMessage': 'Application selected - $jobTitle',
      'lastMessageType': 'job_confirmation',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'isJobChat': true,
      'jobId': jobId,
      'jobTitle': jobTitle,
      'unreadCount.$applicantId': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return chatId;
  }

  /// Returns a human-readable conflict description if the applicant's
  /// existing accepted jobs clash with [newJobId], or null if safe to accept.
  Future<String?> checkJobConflicts(String applicantId, String newJobId) async {
    final newDoc = await _firestore
        .collection(AppConstants.jobsCollection)
        .doc(newJobId)
        .get();
    if (!newDoc.exists || newDoc.data() == null) return null;
    final newJob = JobModel.fromMap(newDoc.data()!, newDoc.id);

    // Fetch all jobs already accepted for this applicant
    final snapshot = await _firestore
        .collection(AppConstants.jobsCollection)
        .where('applicationStatus.$applicantId', isEqualTo: 'accepted')
        .get();

    final existing = snapshot.docs
        .map((d) => JobModel.fromMap(d.data(), d.id))
        .where((j) => j.id != newJobId && j.status != 'cancelled')
        .toList();

    if (existing.isEmpty) return null;

    for (final e in existing) {
      // Full-time + full-time = definite conflict regardless of shift
      if (newJob.jobType == 'full-time' && e.jobType == 'full-time') {
        return 'This applicant already has a full-time position at '
            '"${e.title}". Accepting this full-time role would create a '
            'direct schedule conflict.';
      }

      // Shift-time overlap check
      final nShift = newJob.shiftMinutes;
      final eShift = e.shiftMinutes;
      if (nShift != null && eShift != null) {
        final overlapStart = nShift.$1 > eShift.$1 ? nShift.$1 : eShift.$1;
        final overlapEnd = nShift.$2 < eShift.$2 ? nShift.$2 : eShift.$2;
        if (overlapStart < overlapEnd) {
          // Check if same work-day overlap
          final nDays = newJob.workDays;
          final eDays = e.workDays;
          final sameDay = nDays.isEmpty ||
              eDays.isEmpty ||
              nDays.any((d) => eDays.contains(d));
          if (sameDay) {
            return 'Shift conflict: applicant already works '
                '${e.shiftLabel} at "${e.title}" on overlapping days. '
                'Both roles require presence at the same time.';
          }
        }
      }
    }
    return null; // no conflict
  }

  /// Stream of all jobs this [userId] has applied to.
  Stream<List<JobModel>> streamAppliedJobs(String userId) {
    return _firestore
        .collection(AppConstants.jobsCollection)
        .where('applicants', arrayContains: userId)
        .snapshots()
        .map((s) {
      final list = s.docs.map((d) => JobModel.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  /// Reject an applicant for a job.
  /// Keeps applicant history but marks status as rejected.
  /// Also works as a revocation when the applicant was previously accepted.
  Future<void> rejectJobApplicant({
    required String jobId,
    required String applicantId,
    required String companyId,
  }) async {
    final jobRef =
        _firestore.collection(AppConstants.jobsCollection).doc(jobId);

    String jobTitle = 'a job';
    bool wasAccepted = false;

    await _firestore.runTransaction((transaction) async {
      final jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) throw Exception('Job not found.');

      final data = jobSnap.data()!;
      final ownerId =
          (data['companyId'] as String?) ?? (data['postedBy'] as String?) ?? '';
      if (ownerId != companyId) {
        throw Exception('Only job owner can reject applicants.');
      }

      final applicants = List<String>.from(data['applicants'] ?? const []);
      if (!applicants.contains(applicantId)) {
        throw Exception('Applicant not found in this job.');
      }

      jobTitle = ((data['title'] as String?)?.trim().isNotEmpty == true)
          ? data['title'] as String
          : 'a job';

      final currentStatus =
          (data['applicationStatus'] as Map<String, dynamic>? ??
              {})[applicantId] as String?;
      wasAccepted = currentStatus == 'accepted';

      // If revoking an accepted applicant, also reset job status & selectedApplicant
      final Map<String, dynamic> updates = {
        'updatedAt': FieldValue.serverTimestamp(),
        'applicationStatus.$applicantId': 'rejected',
      };
      if (wasAccepted) {
        updates['selectedApplicant'] = '';
        updates['status'] = AppConstants.jobStatusOpen;
      }

      transaction.update(jobRef, updates);
    });

    String? jobChatId;
    try {
      final latest = await jobRef.get();
      final map = latest.data()?['applicationChatIds'];
      if (map is Map) {
        final raw = map[applicantId];
        if (raw is String && raw.trim().isNotEmpty) {
          jobChatId = raw.trim();
        }
      }
    } catch (_) {
      // Ignore chat lookup errors for notifications.
    }

    // Notify the applicant
    await _firestore.collection('notifications').add({
      'toUserId': applicantId,
      'fromUserId': companyId,
      'type': wasAccepted ? 'jobRevoked' : 'jobRejected',
      'title': wasAccepted ? 'Offer Revoked' : 'Application Update',
      'body': wasAccepted
          ? 'The company has revoked your accepted offer for "$jobTitle". '
              'Please check the Jobs tab for other opportunities.'
          : 'Your application for "$jobTitle" was not selected at this time.',
      'jobId': jobId,
      'jobTitle': jobTitle,
      if (jobChatId != null) 'chatId': jobChatId,
      'createdAt': FieldValue.serverTimestamp(),
      'seen': false,
    });
  }

  Future<void> deleteJob(String jobId) async {
    await _firestore
        .collection(AppConstants.jobsCollection)
        .doc(jobId)
        .delete();
  }

  Future<void> updateJob(JobModel job) async {
    await _firestore
        .collection(AppConstants.jobsCollection)
        .doc(job.id)
        .update(job.toMap());
  }

  // ===== Reviews =====

  Future<void> createReview(ReviewModel review,
      {String? reviewerRole, String? reviewerCompanyName}) async {
    if (review.reviewerId == review.skilledUserId) {
      throw Exception('You cannot review your own profile.');
    }

    final existingReview = await _firestore
        .collection(AppConstants.reviewsCollection)
        .where('skilledUserId', isEqualTo: review.skilledUserId)
        .where('reviewerId', isEqualTo: review.reviewerId)
        .limit(1)
        .get();
    if (existingReview.docs.isNotEmpty) {
      throw Exception('You have already reviewed this skilled person.');
    }

    // Build the review with role info (prefer fields already on the model)
    final effectiveRole = review.reviewerRole ?? reviewerRole;
    final effectiveCompanyName =
        review.reviewerCompanyName ?? reviewerCompanyName;
    final reviewWithRole = ReviewModel(
      id: review.id,
      skilledUserId: review.skilledUserId,
      reviewerId: review.reviewerId,
      reviewerName: review.reviewerName,
      reviewerPhoto: review.reviewerPhoto,
      rating: review.rating,
      comment: review.comment,
      images: review.images,
      createdAt: review.createdAt,
      reviewerRole: effectiveRole,
      reviewerCompanyName: effectiveCompanyName,
    );

    final batch = _firestore.batch();

    // Add review
    final reviewRef =
        _firestore.collection(AppConstants.reviewsCollection).doc();
    batch.set(reviewRef, reviewWithRole.toMap());

    // Update skilled user rating
    final profileRef = _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(review.skilledUserId);

    final profileDoc = await profileRef.get();
    if (profileDoc.exists) {
      final data = profileDoc.data()!;
      final currentRating = (data['rating'] ?? 0.0).toDouble();
      final currentCount = (data['reviewCount'] ?? 0);

      final newCount = currentCount + 1;
      final newRating =
          ((currentRating * currentCount) + review.rating) / newCount;

      batch.update(profileRef, {
        'rating': newRating,
        'reviewCount': newCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<List<ReviewModel>> getUserReviews(String userId,
      {int limit = 10}) async {
    final snapshot = await _firestore
        .collection(AppConstants.reviewsCollection)
        .where('skilledUserId', isEqualTo: userId)
        .get();

    final reviews = snapshot.docs
        .map((doc) => ReviewModel.fromMap(doc.data(), doc.id))
        .toList();

    // Sort: company reviews first, then by date descending
    reviews.sort((a, b) {
      if (a.isCompanyReview && !b.isCompanyReview) return -1;
      if (!a.isCompanyReview && b.isCompanyReview) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return reviews.take(limit).toList();
  }

  // ===== Company Endorsements =====

  String _endorsementDocId(String companyId, String skilledUserId) =>
      '${companyId}__$skilledUserId';

  /// Toggle a company's endorsement of a skilled user.
  /// Returns `true` if the endorsement was added, `false` if removed.
  Future<bool> toggleCompanyEndorsement({
    required String companyId,
    required String skilledUserId,
  }) async {
    final docId = _endorsementDocId(companyId, skilledUserId);
    final endorsementRef = _firestore
        .collection(AppConstants.companyEndorsementsCollection)
        .doc(docId);
    final profileRef = _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(skilledUserId);

    final existing = await endorsementRef.get();
    final batch = _firestore.batch();

    if (existing.exists) {
      // Remove endorsement
      batch.delete(endorsementRef);
      batch.update(profileRef, {
        'companyEndorsementCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return false;
    } else {
      // Add endorsement
      batch.set(endorsementRef, {
        'companyId': companyId,
        'skilledUserId': skilledUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(profileRef, {
        'companyEndorsementCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return true;
    }
  }

  /// Check if a company has endorsed a skilled user.
  Future<bool> hasCompanyEndorsed({
    required String companyId,
    required String skilledUserId,
  }) async {
    final docId = _endorsementDocId(companyId, skilledUserId);
    final doc = await _firestore
        .collection(AppConstants.companyEndorsementsCollection)
        .doc(docId)
        .get();
    return doc.exists;
  }

  /// Stream the live endorsement state (endorsed or not) for a company-user pair.
  Stream<bool> streamCompanyEndorsementState({
    required String companyId,
    required String skilledUserId,
  }) {
    final docId = _endorsementDocId(companyId, skilledUserId);
    return _firestore
        .collection(AppConstants.companyEndorsementsCollection)
        .doc(docId)
        .snapshots()
        .map((snap) => snap.exists);
  }

  /// Stream the live company endorsement count of a skilled user.
  Stream<int> streamCompanyEndorsementCount(String skilledUserId) {
    return _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(skilledUserId)
        .snapshots()
        .map((snap) => snap.exists
            ? ((snap.data()?['companyEndorsementCount'] ?? 0) as int)
            : 0);
  }

  // ===== Service Requests =====

  Future<String> createServiceRequest(ServiceRequestModel request) async {
    final docRef = await _firestore
        .collection(AppConstants.requestsCollection)
        .add(request.toMap());
    return docRef.id;
  }

  Future<List<ServiceRequestModel>> getUserRequests(String userId) async {
    final snapshot = await _firestore
        .collection(AppConstants.requestsCollection)
        .where('skilledUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => ServiceRequestModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<void> updateRequestStatus(String requestId, String status,
      {String? rejectionReason}) async {
    await _firestore
        .collection(AppConstants.requestsCollection)
        .doc(requestId)
        .update({
      'status': status,
      'rejectionReason': rejectionReason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Send a silent reminder notification (stored in Firestore notifications collection)
  /// instead of posting a visible chat message.
  Future<void> sendReminderNotification({
    required String requestId,
    required String fromUserId,
    required String toUserId,
    required String requestTitle,
  }) async {
    await _firestore.collection('notifications').add({
      'type': 'work_request_reminder',
      'requestId': requestId,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'title': 'Reminder',
      'body': 'Work request "$requestTitle" is still awaiting your response.',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createHireRequest({
    required String requesterId,
    required String skilledUserId,
    required String title,
    required String description,
    DateTime? scheduledDate,
    String? hireType, // full_time, part_time, project_based
  }) async {
    if (requesterId == skilledUserId) {
      throw Exception('You cannot hire yourself.');
    }

    final requester = await getUserById(requesterId);
    final requesterRole = (requester?.role ?? '').toLowerCase().trim();
    if (requesterRole != AppConstants.roleCompany) {
      throw Exception('Only company accounts can send direct hire requests.');
    }

    final isCompanyVerified = await canCompanyHireSkilledPersons(requesterId);
    if (!isCompanyVerified) {
      throw Exception(
          'Company verification is required before sending hire requests.');
    }

    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    if (normalizedTitle.isEmpty || normalizedDescription.isEmpty) {
      throw Exception('Title and description are required.');
    }

    final existingPending = await _firestore
        .collection(AppConstants.requestsCollection)
        .where('customerId', isEqualTo: requesterId)
        .where('skilledUserId', isEqualTo: skilledUserId)
        .where('status', isEqualTo: AppConstants.requestStatusPending)
        .limit(1)
        .get();
    if (existingPending.docs.isNotEmpty) {
      throw Exception('You already have a pending hire request for this user.');
    }

    final skilledUser = await getUserById(skilledUserId);
    final chatId = await _ensureDirectChatBetweenUsers(
      userA: requester,
      userB: skilledUser,
      userAId: requesterId,
      userBId: skilledUserId,
    );

    final now = DateTime.now();
    final request = ServiceRequestModel(
      id: '',
      type: _chatWorkRequestType,
      chatId: chatId,
      customerId: requesterId,
      skilledUserId: skilledUserId,
      requesterId: requesterId,
      requesterName: requester?.name,
      requesterPhoto: requester?.profilePhoto,
      skilledUserName: skilledUser?.name,
      skilledUserPhoto: skilledUser?.profilePhoto,
      participants: [requesterId, skilledUserId],
      serviceId: 'direct_hire',
      title: normalizedTitle,
      description: normalizedDescription,
      status: AppConstants.requestStatusPending,
      scheduledDate: scheduledDate,
      hireType: hireType,
      requesterRole: (requester?.role ?? '').toLowerCase().trim(),
      createdAt: now,
      updatedAt: now,
    );
    return createServiceRequest(request);
  }

  Future<String> createChatWorkRequest({
    required String chatId,
    required String customerId,
    required String skilledUserId,
    required String title,
    required String description,
  }) async {
    if (customerId == skilledUserId) {
      throw Exception('Invalid participants.');
    }

    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    if (normalizedTitle.isEmpty || normalizedDescription.isEmpty) {
      throw Exception('Title and description are required.');
    }

    final customer = await getUserById(customerId);
    final customerRole = (customer?.role ?? '').toLowerCase().trim();
    if (customerRole != AppConstants.roleCustomer &&
        customerRole != AppConstants.roleCompany) {
      throw Exception(
          'Only customers or companies can create work requests in chat.');
    }

    final skilledProfile = await getSkilledUserProfile(skilledUserId);
    if (skilledProfile == null ||
        !_isSkilledProfileAadhaarVerified(skilledProfile)) {
      throw Exception(
        'This skilled profile is not available for work requests yet.',
      );
    }
    final skilledUser = await getUserById(skilledUserId);

    // No duplicate check â€” customers can submit multiple work requests per chat.
    final docRef = _firestore.collection(AppConstants.requestsCollection).doc();
    await docRef.set({
      'type': _chatWorkRequestType,
      'chatId': chatId,
      'customerId': customerId,
      'requesterId': customerId,
      'requesterName': customer?.name ?? '',
      'requesterPhoto': customer?.profilePhoto ?? '',
      'skilledUserId': skilledUserId,
      'skilledUserName': skilledUser?.name ?? '',
      'skilledUserPhoto': skilledUser?.profilePhoto ?? '',
      'participants': [customerId, skilledUserId],
      'serviceId': 'chat_work',
      'title': normalizedTitle,
      'description': normalizedDescription,
      'status': AppConstants.requestStatusPending,
      'requesterRole': customerRole, // 'company' or 'customer'
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  Stream<List<ServiceRequestModel>> streamChatWorkRequests(
    String chatId, {
    required String currentUserId,
  }) {
    if (currentUserId.trim().isEmpty) {
      return Stream.value(const <ServiceRequestModel>[]);
    }
    return _firestore
        .collection(AppConstants.requestsCollection)
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => ServiceRequestModel.fromMap(doc.data(), doc.id))
          .where((request) => request.chatId == chatId)
          .where(_isWorkRequestLike) // type filter in memory
          .toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  Stream<List<ServiceRequestModel>> streamUserWorkRequests(String userId) {
    return _firestore
        .collection(AppConstants.requestsCollection)
        .where('participants',
            arrayContains: userId) // single-field â€” no composite index
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => ServiceRequestModel.fromMap(doc.data(), doc.id))
          .where(_isWorkRequestLike) // type filter in memory
          .toList();
      requests.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return requests;
    });
  }

  Stream<List<ServiceRequestModel>> streamSkilledRequests(
      String skilledUserId) {
    return _firestore
        .collection(AppConstants.requestsCollection)
        .where('skilledUserId', isEqualTo: skilledUserId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => ServiceRequestModel.fromMap(doc.data(), doc.id))
          .where(_isWorkRequestLike)
          .toList();
      requests.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return requests;
    });
  }

  Future<List<ServiceRequestModel>> getLatestUserWorkRequests(
    String userId, {
    int limit = 20,
  }) async {
    final snapshot = await _firestore
        .collection(AppConstants.requestsCollection)
        .where('participants',
            arrayContains: userId) // single-field â€” no composite index
        .get();

    final requests = snapshot.docs
        .map((doc) => ServiceRequestModel.fromMap(doc.data(), doc.id))
        .where(_isWorkRequestLike) // type filter in memory
        .toList();
    requests.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (requests.length > limit) {
      return requests.sublist(0, limit);
    }
    return requests;
  }

  Future<List<OrderModel>> getLatestOrdersForUser(
    String userId, {
    int limit = 20,
  }) async {
    // Run each query independently so a permission error on one field
    // (e.g. deliveryPartnerId for a non-delivery user) doesn't block others.
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safeDocs(
        Query<Map<String, dynamic>> q) async {
      try {
        return (await q.get()).docs;
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      safeDocs(_firestore
          .collection(AppConstants.ordersCollection)
          .where('buyerId', isEqualTo: userId)),
      safeDocs(_firestore
          .collection(AppConstants.ordersCollection)
          .where('sellerId', isEqualTo: userId)),
      safeDocs(_firestore
          .collection(AppConstants.ordersCollection)
          .where('deliveryPartnerId', isEqualTo: userId)),
    ]);

    final ordersById = <String, OrderModel>{};
    for (final docs in results) {
      for (final doc in docs) {
        ordersById[doc.id] = OrderModel.fromMap(doc.data(), doc.id);
      }
    }

    final orders = ordersById.values.toList();
    orders.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (orders.length > limit) {
      return orders.sublist(0, limit);
    }
    return orders;
  }

  Future<void> respondToChatWorkRequest({
    required String requestId,
    required String skilledUserId,
    required bool approve,
    String? responseMessage,
  }) async {
    final requestRef =
        _firestore.collection(AppConstants.requestsCollection).doc(requestId);
    final skilledProfileRef = _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(skilledUserId);

    String? customerId;
    String? requestTitle;
    String? requestDescription;
    String? originChatId;

    await _firestore.runTransaction((transaction) async {
      final requestSnap = await transaction.get(requestRef);
      if (!requestSnap.exists) {
        throw Exception('Work request not found.');
      }

      final data = requestSnap.data() ?? <String, dynamic>{};
      final requestType =
          ((data['type'] as String?) ?? '').toLowerCase().trim();
      final serviceId =
          ((data['serviceId'] as String?) ?? '').toLowerCase().trim();
      if (requestType != _chatWorkRequestType &&
          serviceId != _legacyDirectHireServiceId) {
        throw Exception('Invalid work request type.');
      }

      final requestSkilledUserId =
          ((data['skilledUserId'] as String?) ?? '').trim();
      if (requestSkilledUserId != skilledUserId) {
        throw Exception('Only the skilled person can respond to this request.');
      }

      final status = ((data['status'] as String?) ?? '').toLowerCase().trim();
      if (status != AppConstants.requestStatusPending) {
        throw Exception('This work request has already been processed.');
      }

      customerId =
          ((data['customerId'] ?? data['requesterId']) as String?)?.trim();
      requestTitle = (data['title'] as String?)?.trim() ?? 'Unnamed Project';
      requestDescription = (data['description'] as String?)?.trim() ?? '';
      originChatId = (data['chatId'] as String?)?.trim();

      final nextStatus = approve
          ? AppConstants.requestStatusAccepted
          : AppConstants.requestStatusRejected;

      transaction.update(requestRef, {
        'status': nextStatus,
        'responseMessage': responseMessage?.trim(),
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (approve) {
        transaction.set(
          skilledProfileRef,
          {
            'projectCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    // After transaction: add to customer/company assignedProjects
    if (approve && customerId != null && customerId!.isNotEmpty) {
      final workChatId = await _ensureWorkProjectChat(
        requestId: requestId,
        customerId: customerId!,
        skilledUserId: skilledUserId,
        originChatId: originChatId,
        requestTitle: requestTitle,
      );
      await requestRef.set({
        'workChatId': workChatId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final projectEntry = {
        'requestId': requestId,
        'title': requestTitle,
        'description': requestDescription,
        'skilledUserId': skilledUserId,
        'workChatId': workChatId,
        'status': 'accepted',
        'assignedAt': DateTime.now().toIso8601String(),
      };
      await _addProjectToUserProfile(customerId!, projectEntry);
    }
  }

  Future<String> ensureWorkChatForRequest({
    required String requestId,
  }) async {
    final requestRef =
        _firestore.collection(AppConstants.requestsCollection).doc(requestId);
    final snap = await requestRef.get();
    if (!snap.exists) {
      throw Exception('Work request not found.');
    }
    final data = snap.data() ?? <String, dynamic>{};
    final type = ((data['type'] as String?) ?? '').toLowerCase().trim();
    final serviceId =
        ((data['serviceId'] as String?) ?? '').toLowerCase().trim();
    if (type != _chatWorkRequestType &&
        serviceId != _legacyDirectHireServiceId) {
      throw Exception('Invalid work request type.');
    }
    final status = ((data['status'] as String?) ?? '').toLowerCase().trim();
    if (status != AppConstants.requestStatusAccepted &&
        status != AppConstants.requestStatusCompleted) {
      throw Exception('Work chat is available only for accepted projects.');
    }

    final existing = (data['workChatId'] as String?)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;

    final customerId =
        ((data['customerId'] ?? data['requesterId']) as String?)?.trim() ?? '';
    final skilledUserId = (data['skilledUserId'] as String?)?.trim() ?? '';
    if (customerId.isEmpty || skilledUserId.isEmpty) {
      throw Exception('Invalid work request participants.');
    }

    final workChatId = await _ensureWorkProjectChat(
      requestId: requestId,
      customerId: customerId,
      skilledUserId: skilledUserId,
      originChatId: (data['chatId'] as String?)?.trim(),
      requestTitle: (data['title'] as String?)?.trim(),
    );
    await requestRef.set({
      'workChatId': workChatId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return workChatId;
  }

  /// Adds a project entry to the customer_profiles or company_profiles assignedProjects array.
  Future<void> _addProjectToUserProfile(
      String userId, Map<String, dynamic> projectEntry) async {
    try {
      final user = await getUserById(userId);
      final role = UserRoles.normalizeRole(user?.role ?? '');

      if (role == UserRoles.customer) {
        await _firestore
            .collection(AppConstants.customerProfilesCollection)
            .doc(userId)
            .set({
          'assignedProjects': FieldValue.arrayUnion([projectEntry]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (role == UserRoles.company) {
        await _firestore
            .collection(AppConstants.companyProfilesCollection)
            .doc(userId)
            .set({
          'assignedProjects': FieldValue.arrayUnion([projectEntry]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Failed to add project to user profile: $e');
    }
  }

  Future<Map<String, dynamic>> getShopSettings(String userId) async {
    final doc = await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .get();
    const defaults = <String, dynamic>{
      'enableDeliveryIfAvailable': true,
      'maxDeliveryQuantity': 10,
    };
    if (!doc.exists) return defaults;
    final data = doc.data();
    final settings = data?['shopSettings'];
    if (settings is Map) {
      return {
        ...defaults,
        ...Map<String, dynamic>.from(settings),
      };
    }
    return defaults;
  }

  /// Real-time stream of shop settings from the skilled user's document.
  /// Emits the merged settings map (with defaults) whenever it changes.
  Stream<Map<String, dynamic>> streamShopSettings(String userId) {
    const defaults = <String, dynamic>{
      'enableDeliveryIfAvailable': true,
      'maxDeliveryQuantity': 10,
    };
    return _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return defaults;
      final settings = doc.data()?['shopSettings'];
      if (settings is Map) {
        return {
          ...defaults,
          ...Map<String, dynamic>.from(settings),
        };
      }
      return defaults;
    });
  }

  Future<void> updateShopSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .set({
      'shopSettings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ===== Appeals =====

  Future<String> createAppeal(AppealModel appeal) async {
    final docRef = await _firestore
        .collection(AppConstants.appealsCollection)
        .add(appeal.toMap());
    return docRef.id;
  }

  Future<List<AppealModel>> getPendingAppeals() async {
    final snapshot = await _firestore
        .collection(AppConstants.appealsCollection)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => AppealModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<void> resolveAppeal(
    String appealId,
    String status,
    String adminResponse,
    String adminId,
  ) async {
    await _firestore
        .collection(AppConstants.appealsCollection)
        .doc(appealId)
        .update({
      'status': status,
      'adminResponse': adminResponse,
      'resolvedBy': adminId,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Admin - Verification =====

  Future<List<SkilledUserProfile>> getPendingVerifications() async {
    final snapshot = await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .limit(1000)
        .get();

    final pending = snapshot.docs
        .map((doc) => SkilledUserProfile.fromMap(doc.data(), doc.id))
        .where((p) =>
            p.verificationStatus.toLowerCase().trim() ==
            AppConstants.verificationPending)
        .toList();

    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  Stream<List<SkilledUserProfile>> streamPendingVerifications() {
    return _firestore
        .collection(AppConstants.skilledUsersCollection)
        .limit(1000)
        .snapshots()
        .map((snapshot) {
      final pending = snapshot.docs
          .map((doc) => SkilledUserProfile.fromMap(doc.data(), doc.id))
          .where((p) =>
              p.verificationStatus.toLowerCase().trim() ==
              AppConstants.verificationPending)
          .toList();

      pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return pending;
    });
  }

  Future<void> approveVerification(String userId) async {
    await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .update({
      'verificationStatus': AppConstants.verificationApproved,
      'visibility': AppConstants.visibilityPublic,
      'isVerified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectVerification(String userId, String reason) async {
    await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .update({
      'verificationStatus': AppConstants.verificationRejected,
      'rejectionReason': reason,
      'visibility': AppConstants.visibilityPrivate,
      'isVerified': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Reports (extra admin methods â€“ submitProfileReport is defined earlier) ======

  Future<void> submitChatReport({
    required String reporterId,
    required String reportedUserId,
    required String chatId,
    required String reason,
    String? details,
  }) async {
    await _firestore.collection(AppConstants.reportsCollection).add({
      'type': 'chat',
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'chatId': chatId,
      'reason': reason,
      'details': details ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllReports({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.reportsCollection)
          .limit(limit)
          .get();
      final reports =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      final companyVerificationReports =
          await _getCompanyVerificationReports(limit: limit);

      return _mergeReportLists(
        reports: reports,
        companyVerificationReports: companyVerificationReports,
        limit: limit,
      );
    } catch (e) {
      debugPrint('getAllReports error: $e');
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> streamAllReports({int limit = 100}) {
    final controller = StreamController<List<Map<String, dynamic>>>();

    List<Map<String, dynamic>> reports = const [];
    List<Map<String, dynamic>> companyVerificationReports = const [];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? reportsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? companySub;

    void emit() {
      if (controller.isClosed) return;
      controller.add(_mergeReportLists(
        reports: reports,
        companyVerificationReports: companyVerificationReports,
        limit: limit,
      ));
    }

    controller.onListen = () {
      emit();

      reportsSub = _firestore
          .collection(AppConstants.reportsCollection)
          .limit(limit)
          .snapshots()
          .listen(
        (snapshot) {
          reports = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('streamAllReports reports stream error: $e');
          reports = const [];
          emit();
        },
      );

      companySub = _firestore
          .collection(AppConstants.companyProfilesCollection)
          .limit(limit * 3)
          .snapshots()
          .listen(
        (snapshot) {
          companyVerificationReports =
              _buildCompanyVerificationReportsFromSnapshot(snapshot);
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('streamAllReports company verification stream error: $e');
          companyVerificationReports = const [];
          emit();
        },
      );
    };

    controller.onCancel = () async {
      await reportsSub?.cancel();
      await companySub?.cancel();
    };

    return controller.stream;
  }

  Future<void> updateReportStatus(
    String reportId,
    String status, {
    String? adminNotes,
    String? adminId,
  }) async {
    await _firestore
        .collection(AppConstants.reportsCollection)
        .doc(reportId)
        .update({
      'status': status,
      if (adminNotes != null) 'adminNotes': adminNotes,
      if (adminId != null) 'resolvedBy': adminId,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Admin - User Management =====

  Future<List<UserModel>> getAllUsers({int limit = 100}) async {
    try {
      final snapshot = await _firestore
          .collection(AppConstants.usersCollection)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('getAllUsers error: $e');
      return [];
    }
  }

  Stream<List<UserModel>> streamAllUsers({int limit = 100}) {
    return _firestore
        .collection(AppConstants.usersCollection)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Stream<AdminDashboardData> streamAdminDashboardData({int limit = 500}) {
    final controller = StreamController<AdminDashboardData>();

    List<UserModel> users = const [];
    List<Map<String, dynamic>> reports = const [];
    List<Map<String, dynamic>> companyVerificationReports = const [];
    List<SkilledUserProfile> pendingVerifications = const [];

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? usersSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? reportsSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? companySub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? pendingSub;

    void emit() {
      if (controller.isClosed) return;

      final mergedReports = _mergeReportLists(
        reports: reports,
        companyVerificationReports: companyVerificationReports,
        limit: limit,
      );

      final activeSkilledUserIds = users
          .where((u) =>
              UserRoles.normalizeRole(u.role) == UserRoles.skilledPerson &&
              u.isActive &&
              u.isSuspended != true)
          .map((u) => u.uid)
          .toSet();

      final validPendingVerifs = pendingVerifications
          .where((p) => activeSkilledUserIds.contains(p.userId))
          .toList();

      controller.add(
        AdminDashboardData(
          users: users,
          reports: mergedReports,
          pendingVerifications: validPendingVerifs,
        ),
      );
    }

    controller.onListen = () {
      // Emit immediately so UI is never blocked waiting for all streams.
      emit();

      usersSub = _firestore
          .collection(AppConstants.usersCollection)
          .limit(limit)
          .snapshots()
          .listen(
        (snapshot) {
          users = snapshot.docs
              .map((doc) => UserModel.fromMap(doc.data(), doc.id))
              .toList();
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('streamAdminDashboardData users stream error: $e');
          users = const [];
          emit();
        },
      );

      reportsSub = _firestore
          .collection(AppConstants.reportsCollection)
          .limit(limit)
          .snapshots()
          .listen(
        (snapshot) {
          reports = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();
          reports.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('streamAdminDashboardData reports stream error: $e');
          reports = const [];
          emit();
        },
      );

      companySub = _firestore
          .collection(AppConstants.companyProfilesCollection)
          .limit(limit * 3)
          .snapshots()
          .listen(
        (snapshot) {
          companyVerificationReports =
              _buildCompanyVerificationReportsFromSnapshot(snapshot);
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint(
              'streamAdminDashboardData company verification stream error: $e');
          companyVerificationReports = const [];
          emit();
        },
      );

      pendingSub = _firestore
          .collection(AppConstants.skilledUsersCollection)
          .limit(limit * 3)
          .snapshots()
          .listen(
        (snapshot) {
          pendingVerifications = snapshot.docs
              .map((doc) => SkilledUserProfile.fromMap(doc.data(), doc.id))
              .where((p) =>
                  p.verificationStatus.toLowerCase().trim() ==
                  AppConstants.verificationPending)
              .toList();
          pendingVerifications
              .sort((a, b) => a.createdAt.compareTo(b.createdAt));
          emit();
        },
        onError: (Object e, StackTrace st) {
          debugPrint(
              'streamAdminDashboardData pending verification stream error: $e');
          pendingVerifications = const [];
          emit();
        },
      );
    };

    controller.onCancel = () async {
      await usersSub?.cancel();
      await reportsSub?.cancel();
      await companySub?.cancel();
      await pendingSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> suspendUser(String userId, {required bool suspend}) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .update({
      'isSuspended': suspend,
      'suspendedAt': suspend ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> adminDeleteUserAccount(String userId) async {
    final batch = _firestore.batch();

    // Fetch the skilled user profile to check for a registered Aadhaar and free it
    final skilledDoc = await _firestore
        .collection(AppConstants.skilledUsersCollection)
        .doc(userId)
        .get();

    if (skilledDoc.exists) {
      final data = skilledDoc.data();
      if (data != null && data['verificationData'] != null) {
        final verificationData =
            data['verificationData'] as Map<String, dynamic>;
        final aadhaarNumber = verificationData['aadhaarNumber'] as String?;
        if (aadhaarNumber != null && aadhaarNumber.isNotEmpty) {
          final cleanAadhaar = _normalizeAadhaar(aadhaarNumber);
          // Free the Aadhaar from the registry so they can use it again later
          batch.delete(_firestore
              .collection(_aadhaarRegistryCollection)
              .doc(cleanAadhaar));
        }
      }
    }

    // Delete user doc
    batch.delete(
        _firestore.collection(AppConstants.usersCollection).doc(userId));

    // Delete profile docs (skilled/customer/company/managed)
    batch.delete(
        _firestore.collection(AppConstants.skilledUsersCollection).doc(userId));
    batch.delete(_firestore
        .collection(AppConstants.customerProfilesCollection)
        .doc(userId));
    batch.delete(_firestore
        .collection(AppConstants.companyProfilesCollection)
        .doc(userId));
    batch.delete(_firestore
        .collection(AppConstants.managedMembersCollection)
        .doc(userId));

    // Delete private verification data to prevent leaks (like Aadhar images)
    batch.delete(_firestore
        .collection(AppConstants.skilledVerificationPrivateCollection)
        .doc(userId));

    await batch.commit();
  }

  /// Cancel a pending chat work request (customer only).
  Future<void> cancelChatWorkRequest({
    required String requestId,
    required String customerId,
  }) async {
    final ref =
        _firestore.collection(AppConstants.requestsCollection).doc(requestId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Request not found.');
    final data = snap.data()!;
    if ((data['customerId'] ?? data['requesterId']) != customerId) {
      throw Exception('Not authorized to cancel this request.');
    }
    if (data['status'] != AppConstants.requestStatusPending) {
      throw Exception('Only pending requests can be cancelled.');
    }
    await ref.update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently delete a chat work request owned by the customer/requester.
  ///
  /// This is intended for stale or noisy requests that no longer need to stay
  /// in Firestore. Accepted requests are preserved so active work history does
  /// not disappear unexpectedly.
  Future<void> deleteChatWorkRequest({
    required String requestId,
    required String customerId,
  }) async {
    final ref =
        _firestore.collection(AppConstants.requestsCollection).doc(requestId);
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Request not found.');

    final data = snap.data() ?? <String, dynamic>{};
    final ownerId =
        ((data['customerId'] ?? data['requesterId']) as String?)?.trim() ?? '';
    if (ownerId != customerId) {
      throw Exception('Not authorized to delete this request.');
    }

    final status = ((data['status'] as String?) ?? '').toLowerCase().trim();
    if (status == AppConstants.requestStatusAccepted) {
      throw Exception('Accepted work requests cannot be deleted.');
    }

    await ref.delete();
  }

  // ===== Managed Members (Admin) =====

  Map<String, dynamic> _sanitizeManagedMemberPayload(
    Map<String, dynamic> payload, {
    required bool isCreate,
  }) {
    String normalizeString(dynamic value) => value?.toString().trim() ?? '';

    List<String> normalizeStringList(dynamic value) {
      if (value is List) {
        return value
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
      }
      if (value is String) {
        return value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();
      }
      return const <String>[];
    }

    num normalizeExperience(dynamic value) {
      if (value is num) return value;
      return num.tryParse(value?.toString() ?? '') ?? 0;
    }

    final memberTypeRaw = normalizeString(payload['memberType']);
    final memberType = memberTypeRaw == AppConstants.memberTypeSkilled
        ? AppConstants.memberTypeSkilled
        : AppConstants.memberTypeCompany;

    final statusRaw = normalizeString(payload['status']).toLowerCase();
    final status = statusRaw == 'inactive' ? 'inactive' : 'active';

    final approvalRaw =
        normalizeString(payload['approvalStatus']).toLowerCase();
    final approvalStatus = approvalRaw == AppConstants.approvalApproved
        ? AppConstants.approvalApproved
        : approvalRaw == AppConstants.approvalRejected
            ? AppConstants.approvalRejected
            : AppConstants.approvalPending;

    final normalized = <String, dynamic>{
      'name': normalizeString(payload['name']),
      'email': normalizeString(payload['email']).toLowerCase(),
      'phone': normalizeString(payload['phone']),
      'memberType': memberType,
      'parentUserId': normalizeString(payload['parentUserId']),
      'parentName': normalizeString(payload['parentName']),
      'designation': normalizeString(payload['designation']),
      'skillCategory': normalizeString(payload['skillCategory']),
      'experienceYears': normalizeExperience(payload['experienceYears']),
      'address': normalizeString(payload['address']),
      'idProofUrls': normalizeStringList(payload['idProofUrls']),
      'permissions': normalizeStringList(payload['permissions']),
      'status': status,
      'approvalStatus': approvalStatus,
      'verificationNotes': normalizeString(payload['verificationNotes']),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isCreate) {
      normalized['createdAt'] = FieldValue.serverTimestamp();
    }

    return normalized;
  }

  Future<String> createManagedMember(
    Map<String, dynamic> payload, {
    required String adminId,
  }) async {
    final normalized = _sanitizeManagedMemberPayload(payload, isCreate: true);
    if ((normalized['name'] as String).isEmpty) {
      throw Exception('Member name is required.');
    }

    normalized['createdByAdminId'] = adminId;
    final docRef = await _firestore
        .collection(AppConstants.managedMembersCollection)
        .add(normalized);
    return docRef.id;
  }

  Future<void> updateManagedMember(
    String memberId,
    Map<String, dynamic> payload,
  ) async {
    final normalized = _sanitizeManagedMemberPayload(payload, isCreate: false);
    await _firestore
        .collection(AppConstants.managedMembersCollection)
        .doc(memberId)
        .set(normalized, SetOptions(merge: true));
  }

  Future<void> deleteManagedMember(String memberId) async {
    await _firestore
        .collection(AppConstants.managedMembersCollection)
        .doc(memberId)
        .delete();
  }

  Future<List<Map<String, dynamic>>> getManagedMembers({
    String? memberType,
    String? approvalStatus,
    int limit = 500,
  }) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection(AppConstants.managedMembersCollection);

    if (memberType != null && memberType.trim().isNotEmpty) {
      query = query.where('memberType', isEqualTo: memberType.trim());
    }
    if (approvalStatus != null && approvalStatus.trim().isNotEmpty) {
      query = query.where('approvalStatus', isEqualTo: approvalStatus.trim());
    }

    final snapshot = await query.limit(limit).get();
    final items = snapshot.docs
        .map((doc) => {
              ...doc.data(),
              'id': doc.id,
            })
        .toList();

    items.sort((a, b) {
      DateTime asDate(dynamic value) {
        if (value is Timestamp) return value.toDate();
        if (value is DateTime) return value;
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      return asDate(b['updatedAt']).compareTo(asDate(a['updatedAt']));
    });

    return items;
  }

  Stream<List<Map<String, dynamic>>> streamManagedMembers({
    String? memberType,
    String? approvalStatus,
    int limit = 500,
  }) {
    Query<Map<String, dynamic>> query =
        _firestore.collection(AppConstants.managedMembersCollection);

    if (memberType != null && memberType.trim().isNotEmpty) {
      query = query.where('memberType', isEqualTo: memberType.trim());
    }
    if (approvalStatus != null && approvalStatus.trim().isNotEmpty) {
      query = query.where('approvalStatus', isEqualTo: approvalStatus.trim());
    }

    return query.limit(limit).snapshots().map(
      (snapshot) {
        final items = snapshot.docs
            .map((doc) => {
                  ...doc.data(),
                  'id': doc.id,
                })
            .toList();

        items.sort((a, b) {
          DateTime asDate(dynamic value) {
            if (value is Timestamp) return value.toDate();
            if (value is DateTime) return value;
            return DateTime.fromMillisecondsSinceEpoch(0);
          }

          return asDate(b['updatedAt']).compareTo(asDate(a['updatedAt']));
        });

        return items;
      },
    );
  }

  // ===== Animated Avatar Config =====

  /// Save custom animated avatar configuration for any user role.
  /// Stores in the `users` collection so it's universally accessible.
  Future<void> saveAvatarConfig(String userId, dynamic avatarConfig) async {
    if (avatarConfig == null) {
      await removeAvatarConfig(userId);
      return;
    }
    final configMap = avatarConfig is Map<String, dynamic>
        ? avatarConfig
        : (avatarConfig as dynamic).toMap() as Map<String, dynamic>;
    await _firestore.collection(AppConstants.usersCollection).doc(userId).set(
      {
        'avatarConfig': configMap,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Remove the custom animated avatar (revert to photo / emoji / letter).
  Future<void> removeAvatarConfig(String userId) async {
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .update(
      {
        'avatarConfig': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }
}
