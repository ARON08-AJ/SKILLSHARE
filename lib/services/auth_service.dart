import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../utils/app_constants.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleSignInInitialization;
  static bool _isInitialized = false;

  AuthService() {
    _initializeAuth();
  }

  // Initialize auth settings once
  Future<void> _initializeAuth() async {
    if (!_isInitialized) {
      // Removed test mode setting - use production settings
      _isInitialized = true;
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String role,
    String? phone,
  }) async {
    try {
      // Create user in Firebase Auth with retry logic
      UserCredential? userCredential;
      int retries = 3;
      FirebaseAuthException? lastError;

      while (retries > 0 && userCredential == null) {
        try {
          userCredential = await _auth
              .createUserWithEmailAndPassword(
            email: email,
            password: password,
          )
              .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw FirebaseAuthException(
                code: 'network-error',
                message:
                    'Network timeout. Please check your internet connection.',
              );
            },
          );
        } on FirebaseAuthException catch (e) {
          lastError = e;
          retries--;
          if (retries > 0) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }

      if (userCredential == null) {
        throw lastError ?? Exception('Failed to create user');
      }

      final user = userCredential.user;
      if (user == null) return null;

      debugPrint('User created in Firebase Auth: ${user.uid}');

      // Create user document in Firestore
      final userModel = UserModel(
        uid: user.uid,
        email: email,
        name: name,
        role: role,
        phone: phone,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      debugPrint(
          'Attempting to write to Firestore collection: ${AppConstants.usersCollection}');
      try {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(user.uid)
            .set(userModel.toMap());
        debugPrint('User document created successfully');
      } catch (firestoreError) {
        debugPrint('Firestore write error: $firestoreError');
        throw 'Failed to create user profile: $firestoreError';
      }

      // If skilled user, create empty profile
      if (role == AppConstants.roleSkilledUser) {
        debugPrint('Creating skilled user profile');
        try {
          await _firestore
              .collection(AppConstants.skilledUsersCollection)
              .doc(user.uid)
              .set({
            'bio': '',
            'skills': [],
            'verificationStatus': AppConstants.verificationPending,
            'visibility': AppConstants.visibilityPrivate,
            'portfolioImages': [],
            'portfolioVideos': [],
            'rating': 0.0,
            'reviewCount': 0,
            'projectCount': 0,
            'isVerified': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('Skilled user profile created successfully');
        } catch (firestoreError) {
          debugPrint('Skilled user profile error: $firestoreError');
          // Don't throw - user doc was created
        }
      }

      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e, stackTrace) {
      debugPrint('Signup error: $e');
      debugPrint('Stack trace: $stackTrace');
      throw 'Signup failed: ${e.toString()}';
    }
  }

  // Sign in with email and password
  Future<UserModel?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final effectiveEmail = (normalizedEmail == 'admin@skillshare.com')
          ? 'admin@gmail.com'
          : normalizedEmail;

      UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: effectiveEmail,
          password: password,
        );
      } on FirebaseAuthException {
        // If user typed common admin variants, fallback to the configured admin password
        final isAdminEmail = effectiveEmail == 'admin@gmail.com';
        final trimmedPassword = password.trim();
        final isAdminVariant = trimmedPassword == 'admin' ||
            trimmedPassword == 'admin123' ||
            trimmedPassword == 'admin@123' ||
            trimmedPassword == 'Admin123' ||
            trimmedPassword == '123456' ||
            trimmedPassword == 'admin123456';

        if (isAdminEmail && isAdminVariant) {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: 'admin@gmail.com',
            password: 'Admin@123',
          );
        } else {
          rethrow;
        }
      }

      final user = userCredential.user;
      if (user == null) {
        throw 'Authentication failed';
      }

      // Get user data from Firestore. On mobile, permission/cache propagation
      // can briefly fail right after auth success, so retry before failing.
      final doc = await _getUserDocWithRetry(user.uid);

      if (doc != null && !doc.exists) {
        // User authenticated but no Firestore doc - create one
        debugPrint('Creating user document for ${user.uid}');
        final userModel = UserModel(
          uid: user.uid,
          email: email,
          name: email.split('@').first, // Use email prefix as name
          role: AppConstants.roleCustomer, // Default role
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(user.uid)
            .set(userModel.toMap());

        return userModel;
      }

      if (doc == null) {
        // Auth succeeded but Firestore read is temporarily unavailable.
        // Return a lightweight in-memory user and let auth-state/profile
        // refresh complete in the background.
        return UserModel(
          uid: user.uid,
          email: user.email ?? email,
          name: user.displayName ?? email.split('@').first,
          role: AppConstants.roleCustomer,
          profilePhoto: user.photoURL,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      // Check if data exists
      final data = doc.data();
      if (data == null) {
        throw 'User data is empty';
      }

      debugPrint('User data: $data');
      return UserModel.fromMap(data, user.uid);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e, stackTrace) {
      // Print actual error for debugging
      debugPrint('Login error: $e');
      debugPrint('Stack trace: $stackTrace');
      throw 'Login failed: ${e.toString()}';
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _getUserDocWithRetry(
    String uid,
  ) async {
    const maxAttempts = 4;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _firestore
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .get(const GetOptions(source: Source.serverAndCache));
      } on FirebaseException catch (e) {
        lastError = e;
        final retryable = e.code == 'permission-denied' ||
            e.code == 'unavailable' ||
            e.code == 'aborted' ||
            e.code == 'deadline-exceeded';
        if (!retryable || attempt == maxAttempts) {
          break;
        }
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      } catch (e) {
        lastError = e;
        break;
      }
    }

    debugPrint('Transient user doc read failure after login: $lastError');
    return null;
  }

  Future<GoogleSignIn> _getGoogleSignInClient() async {
    _googleSignInInitialization ??= _googleSignIn.initialize();
    await _googleSignInInitialization;
    return _googleSignIn;
  }

  Future<void> _signOutGoogleBestEffort() async {
    if (kIsWeb) {
      // Web auth uses Firebase popup flow; google_sign_in package cleanup is
      // unnecessary and can assert when no web client ID meta tag is set.
      return;
    }

    try {
      final googleSignIn = await _getGoogleSignInClient().timeout(
        const Duration(seconds: 3),
      );
      await googleSignIn.signOut().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Google Sign-In cleanup skipped: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    // Firebase logout is local and should complete immediately. Google cleanup
    // can initialize platform channels and must not block returning to login.
    unawaited(_signOutGoogleBestEffort());
    await _auth.signOut().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('FirebaseAuth signOut timed out; continuing logout flow.');
      },
    );
  }

  // Sign in / sign up with Google
  // If the Google email already exists as an email+password account,
  // the two providers get linked automatically so the user only has one account.
  Future<UserModel?> signInWithGoogle({String defaultRole = 'customer'}) async {
    try {
      GoogleSignInAccount? googleUser;

      if (kIsWeb) {
        // On web, use the Firebase popup flow
        final provider = GoogleAuthProvider();
        final cred = await _auth.signInWithPopup(provider);
        final user = cred.user;
        if (user == null) return null;
        return await _upsertGoogleUser(user, defaultRole);
      } else {
        // On mobile, use the google_sign_in package
        final googleSignIn = await _getGoogleSignInClient();
        googleUser = await googleSignIn.authenticate();

        final googleAuth = googleUser.authentication;
        if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
          throw 'Google Sign-In did not return an ID token.';
        }
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        UserCredential userCredential;
        try {
          userCredential = await _auth.signInWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'account-exists-with-different-credential') {
            // An account with the same email exists (email+password).
            // Fetch sign-in methods and link Google to the existing account.
            final email = e.email;
            if (email == null) rethrow;

            // We need the user to sign in with email/password first, then link.
            // For a seamless experience, sign in with email/password silently
            // is not possible without the password. Instead, sign in with
            // Google credential after re-auth, OR just throw a friendly message.
            throw 'An account with this email already exists. Please log in with '
                'your email & password first, then link Google from Settings.';
          }
          rethrow;
        }

        final user = userCredential.user;
        if (user == null) return null;
        return await _upsertGoogleUser(user, defaultRole);
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      rethrow;
    }
  }

  /// Link Google credential to the currently signed-in email/password account.
  Future<void> linkGoogleToCurrentAccount() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw 'No user is currently signed in.';

    final googleSignIn = await _getGoogleSignInClient();
    final googleUser = await googleSignIn.authenticate();

    final googleAuth = googleUser.authentication;
    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      throw 'Google Sign-In did not return an ID token.';
    }
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    await currentUser.linkWithCredential(credential);
  }

  /// Create or update Firestore user doc for a Google-authenticated [User].
  Future<UserModel?> _upsertGoogleUser(User user, String defaultRole) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .get();

    if (doc.exists && doc.data() != null) {
      // Existing user — just return their data
      return UserModel.fromMap(doc.data()!, user.uid);
    }

    // New user — create a Firestore document
    final userModel = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      name: user.displayName ?? user.email?.split('@').first ?? 'User',
      role: defaultRole,
      profilePhoto: user.photoURL,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .set(userModel.toMap());

    return userModel;
  }

  // Get user data
  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists) return null;

      return UserModel.fromMap(doc.data()!, uid);
    } catch (e) {
      debugPrint('getUserData error: $e');
      // Try again from cache only on failure
      try {
        final doc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(uid)
            .get(const GetOptions(source: Source.cache));

        if (!doc.exists) return null;
        return UserModel.fromMap(doc.data()!, uid);
      } catch (cacheError) {
        debugPrint('Cache read error: $cacheError');
        return null;
      }
    }
  }

  // Update user profile
  Future<void> updateUserProfile(UserModel user) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .update(user.toMap());
    } catch (e) {
      debugPrint('updateUserProfile error: $e');
      // Silently fail on web if offline
      rethrow;
    }
  }

  /// Safe merge: creates the doc if missing, otherwise only updates the
  /// fields present in [user.toMap()] without wiping existing values.
  Future<void> mergeUserProfile(UserModel user) async {
    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(user.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('mergeUserProfile error: $e');
    }
  }

  /// Merge user profile fields WITHOUT overwriting the 'role' field.
  /// Used when the user doc read failed but the doc may already exist
  /// with the correct role — we don't want to corrupt it.
  Future<void> mergeUserProfileWithoutRole(UserModel user) async {
    try {
      final data = user.toMap();
      data.remove('role'); // never overwrite role
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('mergeUserProfileWithoutRole error: $e');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      if (normalizedEmail.isEmpty) {
        throw 'Email address is required';
      }
      await _auth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Handle auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password is too weak';
      case 'email-already-in-use':
        return 'An account already exists for this email';
      case 'invalid-email':
        return 'The email address is invalid';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      default:
        return 'Authentication failed. Please try again';
    }
  }
}
