import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../utils/app_constants.dart';
import '../utils/user_roles.dart';

class AdminBootstrapService {
  static const String defaultAdminEmail =
      String.fromEnvironment('SKILLSHARE_BOOTSTRAP_ADMIN_EMAIL',
          defaultValue: 'admin@gmail.com');
  static const String defaultAdminPassword =
      String.fromEnvironment('SKILLSHARE_BOOTSTRAP_ADMIN_PASSWORD',
          defaultValue: 'Admin@123');
  static const String defaultAdminName =
      String.fromEnvironment('SKILLSHARE_BOOTSTRAP_ADMIN_NAME',
          defaultValue: 'Admin');

  Future<void> ensureDefaultAdminAccount() async {
    if (defaultAdminEmail.isEmpty || defaultAdminPassword.isEmpty) {
      debugPrint(
        'Admin bootstrap skipped: define '
        'SKILLSHARE_BOOTSTRAP_ADMIN_EMAIL and '
        'SKILLSHARE_BOOTSTRAP_ADMIN_PASSWORD.',
      );
      return;
    }

    if (defaultAdminPassword.length < 6) {
      debugPrint(
        'Admin bootstrap skipped: '
        'SKILLSHARE_BOOTSTRAP_ADMIN_PASSWORD must be at least 6 characters.',
      );
      return;
    }

    final tempAppName =
        'admin-bootstrap-${DateTime.now().microsecondsSinceEpoch}';

    FirebaseApp? tempApp;
    FirebaseAuth? tempAuth;
    User? adminUser;

    try {
      tempApp = await Firebase.initializeApp(
        name: tempAppName,
        options: Firebase.app().options,
      );
      tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final tempFirestore = FirebaseFirestore.instanceFor(app: tempApp);

      try {
        final created = await tempAuth.createUserWithEmailAndPassword(
          email: defaultAdminEmail,
          password: defaultAdminPassword,
        );
        adminUser = created.user;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;

        // If account already exists, sign in with known credentials
        // so we can safely ensure the Firestore role/profile document.
        final signedIn = await tempAuth.signInWithEmailAndPassword(
          email: defaultAdminEmail,
          password: defaultAdminPassword,
        );
        adminUser = signedIn.user;
      }

      if (adminUser == null) {
        throw Exception('Could not provision default admin account.');
      }

      final userModel = UserModel(
        uid: adminUser.uid,
        email: defaultAdminEmail,
        name: defaultAdminName,
        role: UserRoles.admin,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tempFirestore
          .collection(AppConstants.usersCollection)
          .doc(adminUser.uid)
          .set(userModel.toMap(), SetOptions(merge: true));

      // Force admin role in case a legacy profile exists with wrong role.
      await tempFirestore
          .collection(AppConstants.usersCollection)
          .doc(adminUser.uid)
          .set(
        {
          'role': UserRoles.admin,
          'name': defaultAdminName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      debugPrint('Default admin account is ready: $defaultAdminEmail');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        debugPrint(
          'Default admin email exists with a different password. '
          'Please reset it manually in Firebase Auth: $defaultAdminEmail',
        );
        return;
      }
      debugPrint('Default admin bootstrap auth error: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('Default admin bootstrap failed: $e');
    } finally {
      try {
        await tempAuth?.signOut();
      } catch (e) {
        debugPrint('Default admin bootstrap signOut cleanup failed: $e');
      }
      // Do not delete the temporary app immediately. On some Android devices,
      // plugin callbacks can still arrive briefly and then crash with
      // "FirebaseApp was deleted" when any Firestore stream is active.
      tempApp = null;
    }
  }
}
