import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/skilled_user_profile.dart';
import '../models/customer_profile.dart';
import '../models/company_profile.dart';
import '../models/review_model.dart';
import '../services/firestore_service.dart';

class UserProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  // Role-specific profiles
  SkilledUserProfile? _skilledProfile;
  CustomerProfile? _customerProfile;
  CompanyProfile? _companyProfile;

  List<SkilledUserProfile> _verifiedUsers = [];
  List<ReviewModel> _reviews = [];
  bool _isLoading = false;
  String? _error;

  // Getters for role-specific profiles
  SkilledUserProfile? get skilledProfile => _skilledProfile;
  CustomerProfile? get customerProfile => _customerProfile;
  CompanyProfile? get companyProfile => _companyProfile;

  // Legacy getter for backward compatibility
  SkilledUserProfile? get currentProfile => _skilledProfile;

  List<SkilledUserProfile> get verifiedUsers => _verifiedUsers;
  List<ReviewModel> get reviews => _reviews;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load skilled user profile
  Future<void> loadProfile(String userId) async {
    try {
      _isLoading = true;
      _error = null;
      _customerProfile = null;
      _companyProfile = null;
      notifyListeners();

      _skilledProfile = await _firestoreService.getSkilledUserProfile(userId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update skilled user profile
  Future<bool> updateProfile(SkilledUserProfile profile) async {
    try {
      _isLoading = true;
      _error = null;
      _customerProfile = null;
      _companyProfile = null;
      notifyListeners();

      await _firestoreService.updateSkilledUserProfile(profile);
      _skilledProfile = profile;
      final idx = _verifiedUsers.indexWhere((u) => u.userId == profile.userId);
      if (idx != -1) {
        _verifiedUsers[idx] = profile;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load customer profile
  Future<void> loadCustomerProfile(String userId) async {
    try {
      _isLoading = true;
      _error = null;
      _skilledProfile = null;
      _companyProfile = null;
      notifyListeners();

      _customerProfile = await _firestoreService.getCustomerProfile(userId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update customer profile
  Future<bool> updateCustomerProfile(CustomerProfile profile) async {
    try {
      _isLoading = true;
      _error = null;
      _skilledProfile = null;
      _companyProfile = null;
      notifyListeners();

      await _firestoreService.updateCustomerProfile(profile);
      _customerProfile = profile;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load company profile
  Future<void> loadCompanyProfile(String userId) async {
    try {
      _isLoading = true;
      _error = null;
      _skilledProfile = null;
      _customerProfile = null;
      notifyListeners();

      _companyProfile = await _firestoreService.getCompanyProfile(userId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update company profile
  Future<bool> updateCompanyProfile(CompanyProfile profile) async {
    try {
      _isLoading = true;
      _error = null;
      _skilledProfile = null;
      _customerProfile = null;
      notifyListeners();

      await _firestoreService.updateCompanyProfile(profile);
      _companyProfile = profile;

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load verified skilled users
  Future<void> loadVerifiedUsers(
      {String? category, List<String>? skills}) async {
    if (FirebaseAuth.instance.currentUser == null) {
      _verifiedUsers = [];
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      _verifiedUsers = await _firestoreService.getVerifiedSkilledUsers(
        category: category,
        skills: skills,
      );

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading verified users: $e');
      _error = e.toString();
      _verifiedUsers = []; // Set empty list on error
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load user reviews
  Future<void> loadReviews(String userId) async {
    try {
      _reviews = await _firestoreService.getUserReviews(userId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Add review
  Future<bool> addReview(ReviewModel review) async {
    try {
      await _firestoreService.createReview(review);
      await loadReviews(review.skilledUserId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearRoleProfiles() {
    _skilledProfile = null;
    _customerProfile = null;
    _companyProfile = null;
    _error = null;
    notifyListeners();
  }

  void clearAllData() {
    _skilledProfile = null;
    _customerProfile = null;
    _companyProfile = null;
    _verifiedUsers = [];
    _reviews = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
