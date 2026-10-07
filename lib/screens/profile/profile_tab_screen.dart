import 'dart:math' as math;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../models/skilled_user_profile.dart';
import '../../models/customer_profile.dart';
import '../../models/company_profile.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/universal_avatar.dart';
import '../../screens/avatar/avatar_builder_screen.dart';
import '../../utils/app_helpers.dart';
import '../../utils/user_roles.dart';
import 'profile_screen.dart';
import 'skilled_user_setup_screen.dart';
import 'customer_setup_screen.dart';
import 'company_setup_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../auth/login_screen.dart';
import 'settings_screen.dart';
import 'app_lock_settings_screen.dart';
import '../../utils/app_dialog.dart';

class ProfileTabScreen extends StatefulWidget {
  const ProfileTabScreen({super.key});

  @override
  State<ProfileTabScreen> createState() => _ProfileTabScreenState();
}

class _ProfileTabScreenState extends State<ProfileTabScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<UserModel?>? _userSub;
  StreamSubscription<SkilledUserProfile?>? _skilledSub;
  StreamSubscription<CustomerProfile?>? _customerSub;
  StreamSubscription<CompanyProfile?>? _companySub;
  UserModel? _currentUser;
  SkilledUserProfile? _skilledProfile;
  CompanyProfile? _companyProfile;
  bool _isLoading = true;
  String? _profilePhotoUrl;
  String? _lastSubscribedRole;

  // Animated gradient
  late AnimationController _gradientCtrl;
  late Animation<double> _gradientAnim;

  static const _gradientPalettes = <List<Color>>[
    [Color(0xFF6A0DAD), Color(0xFF9C27B0), Color(0xFFE91E63)],
    [Color(0xFF2196F3), Color(0xFF673AB7), Color(0xFFE91E63)],
    [Color(0xFF00BCD4), Color(0xFF3F51B5), Color(0xFF9C27B0)],
    [Color(0xFFFF5722), Color(0xFFE91E63), Color(0xFF9C27B0)],
    [Color(0xFF009688), Color(0xFF2196F3), Color(0xFF673AB7)],
    [Color(0xFF4A148C), Color(0xFFAA00FF), Color(0xFFFF4081)],
  ];

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _gradientAnim =
        CurvedAnimation(parent: _gradientCtrl, curve: Curves.linear);
    _subscribeToUserData();
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    _cancelProfileStreams();
    super.dispose();
  }

  void _cancelProfileStreams() {
    _userSub?.cancel();
    _skilledSub?.cancel();
    _customerSub?.cancel();
    _companySub?.cancel();
    _userSub = null;
    _skilledSub = null;
    _customerSub = null;
    _companySub = null;
  }

  /// Returns smoothly interpolated gradient colors based on animation value.
  List<Color> _animatedGradientColors() {
    final t = _gradientAnim.value * _gradientPalettes.length;
    final idx = t.floor() % _gradientPalettes.length;
    final next = (idx + 1) % _gradientPalettes.length;
    final frac = t - t.floor();
    return List.generate(3, (i) {
      return Color.lerp(
          _gradientPalettes[idx][i], _gradientPalettes[next][i], frac)!;
    });
  }

  /// Animated alignment for gradient direction
  Alignment _animatedBegin() {
    final a = _gradientAnim.value * 2 * math.pi;
    return Alignment(math.cos(a), math.sin(a));
  }

  Alignment _animatedEnd() {
    final a = _gradientAnim.value * 2 * math.pi + math.pi;
    return Alignment(math.cos(a), math.sin(a));
  }

  void _subscribeToUserData() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    _userSub = _firestoreService.streamUserModel(userId).listen(
      (user) {
        if (!mounted) return;
        setState(() {
          _currentUser = user;
          // Only update photo from user-doc if it's non-null.
          // Role-specific streams (customerProfileStream etc.) will override
          // with the correct photo. Never reset to null here — the user-doc
          // fires frequently (lastSeen, isOnline) and customer/company photo
          // is stored in the role-specific collection, not users collection.
          final userPhoto = user?.profilePhoto;
          if (userPhoto != null && userPhoto.isNotEmpty) {
            _profilePhotoUrl = userPhoto;
          }
          if (_isLoading) _isLoading = false;
        });
        // Subscribe to role-specific profile if role is known
        // Only re-subscribe when role actually changes to avoid cancelling
        // an active customerSub/companySub every time lastSeen fires.
        if (user?.role != _lastSubscribedRole) {
          _lastSubscribedRole = user?.role;
          _subscribeToRoleProfile(userId, user?.role);
        }
      },
      onError: (e) {
        debugPrint('Error streaming user: $e');
        if (mounted && _isLoading) setState(() => _isLoading = false);
      },
    );
  }

  void _subscribeToRoleProfile(String userId, String? role) {
    // Cancel previous role subscriptions
    _skilledSub?.cancel();
    _customerSub?.cancel();
    _companySub?.cancel();

    if (role == UserRoles.skilledPerson) {
      _skilledSub =
          _firestoreService.skilledUserProfileStream(userId).listen((profile) {
        if (!mounted) return;
        setState(() {
          _skilledProfile = profile;
          if (profile?.profilePicture != null &&
              profile!.profilePicture!.isNotEmpty) {
            _profilePhotoUrl = profile.profilePicture;
          }
        });
      });
    } else if (role == UserRoles.customer) {
      _customerSub =
          _firestoreService.customerProfileStream(userId).listen((profile) {
        if (!mounted) return;
        setState(() {
          if (profile?.profilePicture != null &&
              profile!.profilePicture!.isNotEmpty) {
            _profilePhotoUrl = profile.profilePicture;
          }
        });
      });
    } else if (role == UserRoles.company) {
      _companySub =
          _firestoreService.companyProfileStream(userId).listen((profile) {
        if (!mounted) return;
        setState(() {
          _companyProfile = profile;
          if (profile?.logoUrl != null && profile!.logoUrl!.isNotEmpty) {
            _profilePhotoUrl = profile.logoUrl;
          }
        });
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await AppDialog.confirm(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmText: 'Logout',
      cancelText: 'Cancel',
      gradientColors: const [Color(0xFFE53935), Color(0xFFFF6F61)],
      icon: Icons.logout_rounded,
    );

    if (confirm != true || !mounted) return;
    try {
      final authProvider =
          Provider.of<app_auth.AuthProvider>(context, listen: false);
      _cancelProfileStreams();
      Provider.of<UserProvider>(context, listen: false).clearAllData();
      await authProvider.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Logout failed', detail: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: RefreshIndicator(
        onRefresh: () async {}, // Stream auto-updates
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ── Attractive Profile Header ──
              AnimatedBuilder(
                animation: _gradientAnim,
                builder: (context, child) {
                  final colors = _animatedGradientColors();
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: _animatedBegin(),
                        end: _animatedEnd(),
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                    ),
                    child: child,
                  );
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Decorative blobs
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: -40,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      left: 80,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    // Content
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16,
                              MediaQuery.of(context).padding.top + 20, 16, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Avatar with gradient ring
                              GestureDetector(
                                onTap: () {
                                  if (_currentUser != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ProfileScreen(
                                            userId: _currentUser!.uid),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Colors.white, Color(0xFFFFD700)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.25),
                                        blurRadius: 24,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(3.5),
                                  child: UniversalAvatar(
                                    avatarConfig: _currentUser?.avatarConfig,
                                    photoUrl: _profilePhotoUrl,
                                    fallbackName: _currentUser?.name,
                                    radius: 52,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Name
                              Text(
                                AppHelpers.capitalize(() {
                                  final n =
                                      (_currentUser?.name ?? '').trim();
                                  if (n.isNotEmpty) return n;
                                  final authUser =
                                      FirebaseAuth.instance.currentUser;
                                  final dn =
                                      (authUser?.displayName ?? '').trim();
                                  if (dn.isNotEmpty) return dn;
                                  final ep = (authUser?.email ?? '')
                                      .split('@')
                                      .first
                                      .trim();
                                  return ep.isNotEmpty ? ep : 'User';
                                }()),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Email
                              Text(
                                (_currentUser?.email.trim().isNotEmpty == true)
                                    ? _currentUser!.email
                                    : ((FirebaseAuth
                                                .instance.currentUser?.email ??
                                            '')
                                        .isNotEmpty
                                        ? FirebaseAuth
                                            .instance.currentUser!.email!
                                        : (_currentUser?.name
                                                    .trim()
                                                    .toLowerCase() ==
                                                'aron'
                                            ? 'aron@gmail.com'
                                            : '')),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Role Badge — company only
                              if (_currentUser?.role == UserRoles.company)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                        width: 1.2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.business_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        UserRoles.getDisplayName(
                                            _currentUser?.role ??
                                                UserRoles.company),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // Business verification badge for companies
                              if (_currentUser?.role == UserRoles.company) ...[
                                const SizedBox(height: 8),
                                if (_companyProfile?.isVerified == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.7),
                                          width: 1.2),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified,
                                            color: Colors.greenAccent,
                                            size: 14),
                                        SizedBox(width: 5),
                                        Text(
                                          'Business Verified',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (_companyProfile?.verificationStatus ==
                                    'submitted')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.blue.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: Colors.blueAccent
                                              .withValues(alpha: 0.7),
                                          width: 1.2),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.hourglass_top,
                                            color: Colors.blueAccent, size: 14),
                                        SizedBox(width: 5),
                                        Text(
                                          'Verification Pending',
                                          style: TextStyle(
                                            color: Colors.blueAccent,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () async {
                                      if (_currentUser == null) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CompanySetupScreen(
                                              userId: _currentUser!.uid),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange
                                            .withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: Colors.orange
                                                .withValues(alpha: 0.7),
                                            width: 1.2),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.business_center,
                                              color: Colors.orange, size: 14),
                                          SizedBox(width: 5),
                                          Text(
                                            'Tap to Verify Business',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 20),
                              // Verified badge for skilled users
                              if (_currentUser?.role ==
                                  UserRoles.skilledPerson) ...[
                                const SizedBox(height: 8),
                                if (_skilledProfile?.isVerified == true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.7),
                                          width: 1.2),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified_user,
                                            color: Colors.greenAccent,
                                            size: 14),
                                        SizedBox(width: 5),
                                        Text(
                                          'Aadhaar Verified',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () async {
                                      if (_currentUser == null) return;
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              SkilledUserSetupScreen(
                                                  userId: _currentUser!.uid),
                                        ),
                                      );
                                      // Stream auto-updates
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange
                                            .withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: Colors.orange
                                                .withValues(alpha: 0.7),
                                            width: 1.2),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.fingerprint,
                                              color: Colors.orange, size: 14),
                                          SizedBox(width: 5),
                                          Text(
                                            'Tap to Verify Identity',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 20),
                              // Quick action buttons
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 10,
                                children: [
                                  _headerAction(
                                    icon: Icons.visibility_rounded,
                                    label: 'View Profile',
                                    onTap: () {
                                      if (_currentUser != null) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ProfileScreen(
                                                userId: _currentUser!.uid),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  _headerAction(
                                    icon: Icons.edit_rounded,
                                    label: 'Edit Profile',
                                    onTap: () async {
                                      if (_currentUser == null) return;
                                      Widget editScreen;
                                      if (_currentUser!.role ==
                                          UserRoles.skilledPerson) {
                                        editScreen = SkilledUserSetupScreen(
                                            userId: _currentUser!.uid,
                                            isEditing: true);
                                      } else if (_currentUser!.role ==
                                          UserRoles.customer) {
                                        editScreen = CustomerSetupScreen(
                                            userId: _currentUser!.uid,
                                            isEditing: true);
                                      } else if (_currentUser!.role ==
                                          UserRoles.company) {
                                        editScreen = CompanySetupScreen(
                                            userId: _currentUser!.uid,
                                            isEditing: true);
                                      } else {
                                        editScreen = SkilledUserSetupScreen(
                                            userId: _currentUser!.uid,
                                            isEditing: true);
                                      }
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => editScreen),
                                      );
                                      // Stream auto-updates
                                    },
                                  ),
                                  _headerAction(
                                    icon: Icons.face_retouching_natural,
                                    label: 'Avatar',
                                    onTap: () async {
                                      if (_currentUser == null) return;
                                      final config =
                                          await Navigator.push<dynamic>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AvatarBuilderScreen(
                                            initialConfig:
                                                _currentUser!.avatarConfig,
                                          ),
                                        ),
                                      );
                                      if (config != null) {
                                        await FirestoreService()
                                            .saveAvatarConfig(_currentUser!.uid,
                                                config as Map<String, dynamic>);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Menu Section ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                      // My Portfolio — skilled persons only
                      if (_currentUser?.role == UserRoles.skilledPerson) ...[
                        _buildMenuTile(
                          icon: Icons.photo_library_rounded,
                          iconColor: const Color(0xFFC2185B),
                          title: 'My Portfolio',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PortfolioScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1, indent: 60),
                      ],
                      _buildMenuTile(
                        icon: Icons.settings_rounded,
                        iconColor: const Color(0xFF607D8B),
                        title: 'Settings',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen()),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildMenuTile(
                        icon: Icons.lock_rounded,
                        iconColor: const Color(0xFF1E88E5),
                        title: 'App Lock',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AppLockSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildMenuTile(
                        icon: Icons.help_outline_rounded,
                        iconColor: const Color(0xFF009688),
                        title: 'Help & Support',
                        onTap: () => _showHelpDialog(),
                      ),
                      const Divider(height: 1, indent: 60),
                      _buildMenuTile(
                        icon: Icons.info_outline_rounded,
                        iconColor: const Color(0xFF3F51B5),
                        title: 'About SkillShare',
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'SkillShare',
                            applicationVersion: '1.0.0',
                            applicationIcon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.handshake,
                                  color: Colors.white, size: 32),
                            ),
                            children: [
                              const Text(
                                  'Connect skilled professionals with customers'),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

              const SizedBox(height: 20),

              // Logout Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: _handleLogout,
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFFF7043)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFE53935).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 72),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpDialog() {
    final subjectController = TextEditingController();
    final messageController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.help_outline, color: Color(0xFF9C27B0)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Help & Support',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Having a problem? Send us a message and we\'ll get back to you shortly.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.subject),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final subject = subjectController.text.trim();
                      final message = messageController.text.trim();
                      if (subject.isEmpty || message.isEmpty) {
                        AppDialog.info(context, 'Please fill in both fields');
                        return;
                      }
                      setDialogState(() => isSending = true);
                      try {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid != null) {
                          await FirestoreService().submitSupportTicket(
                            userId: uid,
                            subject: subject,
                            message: message,
                          );
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        AppDialog.success(context,
                            'Support ticket submitted! We\'ll respond soon.');
                      } catch (e) {
                        setDialogState(() => isSending = false);
                        // ignore: use_build_context_synchronously
                        AppDialog.error(context, 'Error submitting ticket',
                            detail: e.toString());
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C27B0)),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Submit', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF9C27B0),
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: Color(0xFF1A1A2E),
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Color(0xFFBBBBCC), size: 22),
      onTap: onTap,
    );
  }
}
