import 'package:flutter/material.dart';

import '../screens/profile/profile_tab_screen.dart';
import '../screens/profile/skilled_user_setup_screen.dart';
import '../screens/profile/customer_setup_screen.dart';
import '../screens/profile/company_setup_screen.dart';
import '../screens/profile/delivery_profile_screen.dart';
import '../utils/user_roles.dart';

Widget buildOwnProfileScreen({
  required String role,
  required String userId,
}) {
  return const ProfileTabScreen();
}

Widget buildSkilledEditScreen({required String userId}) {
  return SkilledUserSetupScreen(userId: userId, isEditing: true);
}

Widget buildRoleBasedEditProfileScreen({
  required String role,
  required String userId,
}) {
  final normalized = UserRoles.normalizeRole(role);
  if (normalized == UserRoles.customer) {
    return CustomerSetupScreen(userId: userId, isEditing: true);
  } else if (normalized == UserRoles.company) {
    return CompanySetupScreen(userId: userId, isEditing: true);
  } else if (normalized == UserRoles.deliveryPartner) {
    return DeliveryProfileScreen(userId: userId, isEditing: true);
  } else {
    return SkilledUserSetupScreen(userId: userId, isEditing: true);
  }
}
