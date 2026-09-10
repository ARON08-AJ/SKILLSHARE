import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/firestore_service.dart';
import '../../services/chat_service.dart';
import '../../models/skilled_user_profile.dart';
import '../../models/customer_profile.dart';
import '../../models/company_profile.dart';
import '../../models/product_model.dart';
import '../../models/review_model.dart';

import '../../models/service_request_model.dart';
import '../../models/user_model.dart';
import '../../models/order_model.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../utils/user_roles.dart';
import '../../utils/web_image_loader.dart';
import 'skilled_user_setup_screen.dart';
import 'customer_setup_screen.dart';
import 'company_setup_screen.dart';
import '../shop/add_product_screen.dart';
import '../chat/chat_detail_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../shop/shop_storefront_screen.dart';
import '../../widgets/banner_display.dart';
import '../../widgets/universal_avatar.dart';
import 'banner_editor_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ChatService _chatService = ChatService();
  final ScrollController _profileScrollController = ScrollController();

  SkilledUserProfile? _profile;
  CustomerProfile? _customerProfile;
  CompanyProfile? _companyProfile;
  List<ReviewModel> _reviews = [];
  UserModel? _userData;
  String? _userRole;
  bool _isLoading = true;
  StreamSubscription? _profileSub;
  StreamSubscription<UserModel?>? _userDataSub;
  StreamSubscription<Map<String, dynamic>>? _userSettingsSub;
  Future<SkilledCompanySocialProof>? _companySocialProofFuture;

  bool _targetProfileVisible = true;
  bool _targetShowEmail = false;
  bool _targetShowPhone = false;

  int _companyEndorsementCount = 0;
  bool _hasCurrentCompanyEndorsed = false;
  StreamSubscription? _endorsementCountSub;
  StreamSubscription? _endorsementStateSub;

  bool get isOwnProfile =>
      FirebaseAuth.instance.currentUser?.uid == widget.userId;

  void _resetProfileScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_profileScrollController.hasClients) return;
      _profileScrollController.jumpTo(0);
    });
  }

  String? get _currentViewerRole {
    final auth = Provider.of<app_auth.AuthProvider>(context, listen: false);
    return UserRoles.normalizeRole(auth.userRole ?? '');
  }

  bool get _canCurrentUserReview {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return currentUser.uid != widget.userId;
  }

  bool get _isCurrentUserCompany => _currentViewerRole == UserRoles.company;

  bool _isCompanyVerifiedForHiring(CompanyProfile? profile) {
    if (profile == null) return false;
    final status = profile.verificationStatus.toLowerCase().trim();
    return profile.isVerified ||
        status == AppConstants.verificationApproved ||
        status == 'verified';
  }

  String _displayNameUpper(String? name, {String fallback = 'USER'}) {
    final value = (name ?? '').trim();
    if (value.isEmpty) return fallback.toUpperCase();
    return value.toUpperCase();
  }

  Map<String, dynamic>? _normalizedBannerData(
    Map<String, dynamic>? bannerData, {
    required String? fallbackName,
  }) {
    if (bannerData == null) return null;
    final normalized = Map<String, dynamic>.from(bannerData);
    final type = (normalized['type'] as String?)?.trim().toLowerCase();
    if (type != 'text') return normalized;

    final currentText = (normalized['text'] as String?)?.trim() ?? '';
    final rawName = (fallbackName ?? '').trim();
    if (currentText.isEmpty ||
        (rawName.isNotEmpty &&
            currentText.toLowerCase() == rawName.toLowerCase())) {
      normalized['text'] = _displayNameUpper(fallbackName);
    }
    return normalized;
  }

  void _showReportDialog() {
    final reasonController = TextEditingController();
    final reasons = [
      'Spam or misleading',
      'Inappropriate content',
      'Fake profile',
      'Harassment',
      'Other',
    ];
    String? selectedReason;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.flag, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Report User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Why are you reporting this user?'),
                const SizedBox(height: 12),
                ...reasons.map((r) => RadioListTile<String>(
                      title: Text(r),
                      value: r,
                      groupValue: selectedReason,
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                      dense: true,
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
              onPressed: (isSending || selectedReason == null)
                  ? null
                  : () async {
                      final currentUid = FirebaseAuth.instance.currentUser?.uid;
                      if (currentUid == null) return;
                      setDialogState(() => isSending = true);
                      try {
                        await _firestoreService.submitProfileReport(
                          reporterId: currentUid,
                          reportedUserId: widget.userId,
                          reason: selectedReason!,
                          details: reasonController.text.trim().isEmpty
                              ? null
                              : reasonController.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        AppDialog.success(context, 'User reported. Thank you.');
                      } catch (e) {
                        setDialogState(() => isSending = false);
                        // ignore: use_build_context_synchronously
                        AppDialog.error(context, 'Error submitting report',
                            detail: e.toString());
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Report', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Block User',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'This user will no longer be able to send you messages or view your profile. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              if (currentUid == null) return;
              Navigator.pop(ctx);
              try {
                await _firestoreService.blockUser(
                  blockerId: currentUid,
                  blockedUserId: widget.userId,
                );
                if (!mounted) return;
                AppDialog.success(context, 'User blocked successfully.',
                    onDismiss: () => Navigator.of(context).pop());
              } catch (e) {
                if (!mounted) return;
                AppDialog.error(context, 'Error blocking user',
                    detail: e.toString());
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Block', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCompanyVerificationRequired() async {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null) return;

    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Company Verification Required'),
        content: const Text(
          'Only verified companies can send hire requests. '
          'Complete verification to unlock hiring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Verify Now'),
          ),
        ],
      ),
    );

    if (shouldOpen != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompanySetupScreen(userId: viewerId)),
    );
  }

  Future<void> _showHireRequestDialog() async {
    if (!_isCurrentUserCompany) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final isVerifiedCompany =
        await _firestoreService.canCompanyHireSkilledPersons(currentUser.uid);
    if (!isVerifiedCompany) {
      if (!mounted) return;
      await _promptCompanyVerificationRequired();
      return;
    }

    final titleController = TextEditingController();
    final descController = TextEditingController();
    String selectedHireType = 'full_time';

    const hireTypes = [
      {'value': 'full_time', 'label': 'Full-time Employee', 'icon': Icons.work},
      {
        'value': 'part_time',
        'label': 'Part-time / Freelance',
        'icon': Icons.access_time
      },
      {
        'value': 'project_based',
        'label': 'Project-based',
        'icon': Icons.task_alt
      },
    ];

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Send Hire Request'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Project / position title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      minLines: 3,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'Describe the work requirement',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Hire Type',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(hireTypes.length, (i) {
                      final ht = hireTypes[i];
                      final isSelected =
                          selectedHireType == ht['value'] as String;
                      return GestureDetector(
                        onTap: () => setDialogState(
                            () => selectedHireType = ht['value'] as String),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF3F51B5)
                                    .withValues(alpha: 0.08)
                                : Colors.grey[50],
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF3F51B5)
                                  : Colors.grey[300]!,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                ht['icon'] as IconData,
                                size: 18,
                                color: isSelected
                                    ? const Color(0xFF3F51B5)
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 10),
                              Text(
                                ht['label'] as String,
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF3F51B5)
                                      : Colors.black87,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                              if (isSelected) const Spacer(),
                              if (isSelected)
                                const Icon(Icons.check_circle,
                                    color: Color(0xFF3F51B5), size: 18),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F51B5),
                      foregroundColor: Colors.white),
                  child: const Text('Send Request'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      titleController.dispose();
      descController.dispose();
      return;
    }

    try {
      await _firestoreService.createHireRequest(
        requesterId: currentUser.uid,
        skilledUserId: widget.userId,
        title: titleController.text.trim(),
        description: descController.text.trim(),
        hireType: selectedHireType,
      );
      if (!mounted) return;
      AppDialog.success(context, 'Hire request sent successfully!');
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(context, 'Failed to send hire request',
          detail: e.toString());
    } finally {
      titleController.dispose();
      descController.dispose();
    }
  }

  @override
  void initState() {
    super.initState();
    _resetProfileScrollPosition();
    _subscribeToUserSettingsStream();
    _loadProfile().then((_) {
      _subscribeToProfileStream();
      _subscribeToEndorsementStreams();
    });
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId) return;

    _resetProfileScrollPosition();
    _profileSub?.cancel();
    _userDataSub?.cancel();
    _endorsementCountSub?.cancel();
    _endorsementStateSub?.cancel();

    _profile = null;
    _customerProfile = null;
    _companyProfile = null;
    _reviews = [];
    _userData = null;
    _userRole = null;
    _companySocialProofFuture = null;
    _targetProfileVisible = true;
    _targetShowEmail = false;
    _targetShowPhone = false;
    _companyEndorsementCount = 0;
    _hasCurrentCompanyEndorsed = false;

    _subscribeToUserSettingsStream();
    _loadProfile().then((_) {
      _subscribeToProfileStream();
      _subscribeToEndorsementStreams();
    });
  }

  @override
  void dispose() {
    _profileScrollController.dispose();
    _profileSub?.cancel();
    _userDataSub?.cancel();
    _userSettingsSub?.cancel();
    _endorsementCountSub?.cancel();
    _endorsementStateSub?.cancel();
    super.dispose();
  }

  void _subscribeToUserSettingsStream() {
    _userSettingsSub?.cancel();
    _userSettingsSub =
        _firestoreService.userSettingsStream(widget.userId).listen((settings) {
      if (!mounted) return;
      setState(() {
        _targetProfileVisible = settings['profileVisible'] as bool? ?? true;
        _targetShowEmail = settings['showEmail'] as bool? ?? false;
        _targetShowPhone = settings['showPhone'] as bool? ?? false;
      });
    }, onError: (_) {
      if (!mounted) return;
      setState(() {
        _targetProfileVisible = true;
        _targetShowEmail = false;
        _targetShowPhone = false;
      });
    });
  }

  String? get _publicEmail {
    final email = _userData?.email.trim();
    if (email == null || email.isEmpty) return null;
    if (isOwnProfile) return email;
    return _targetShowEmail ? email : null;
  }

  String? get _publicPhone {
    final phone = _userData?.phone?.trim();
    if (phone == null || phone.isEmpty) return null;
    if (isOwnProfile) return phone;
    return _targetShowPhone ? phone : null;
  }

  Widget _buildContactVisibilitySection(List<Color> colors) {
    final email = _publicEmail;
    final phone = _publicPhone;
    if (email == null && phone == null) {
      return const SizedBox.shrink();
    }

    Widget chip({
      required IconData icon,
      required String text,
      required Color color,
    }) {
      return Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              colors.first.withValues(alpha: 0.06),
              colors.last.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.first.withValues(alpha: 0.2)),
        ),
        child: Wrap(
          children: [
            if (email != null)
              chip(
                icon: Icons.alternate_email_rounded,
                text: email,
                color: const Color(0xFF1565C0),
              ),
            if (phone != null)
              chip(
                icon: Icons.phone_rounded,
                text: phone,
                color: const Color(0xFF2E7D32),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHiddenView() {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_rounded,
                  size: 58, color: Color(0xFF8E24AA)),
              SizedBox(height: 12),
              Text(
                'This profile is private',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'The user has disabled profile visibility in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _subscribeToEndorsementStreams() {
    // Only relevant when a company is viewing a skilled person's profile
    if (isOwnProfile) return;
    if (_userRole != AppConstants.roleSkilledUser &&
        _userRole != 'skilled_person') {
      return;
    }

    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final viewerRole = _currentViewerRole;

    // Always stream the endorsement count for the skilled profile
    _endorsementCountSub?.cancel();
    _endorsementCountSub = _firestoreService
        .streamCompanyEndorsementCount(widget.userId)
        .listen((count) {
      if (mounted) setState(() => _companyEndorsementCount = count);
    });

    // Only stream the viewer's own endorsement state when viewer is a company
    if (viewerRole == UserRoles.company && viewerId != null) {
      _endorsementStateSub?.cancel();
      _endorsementStateSub = _firestoreService
          .streamCompanyEndorsementState(
              companyId: viewerId, skilledUserId: widget.userId)
          .listen((hasEndorsed) {
        if (mounted) setState(() => _hasCurrentCompanyEndorsed = hasEndorsed);
      });
    }
  }

  Future<void> _toggleEndorsement() async {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null) return;
    try {
      final added = await _firestoreService.toggleCompanyEndorsement(
          companyId: viewerId, skilledUserId: widget.userId);
      // Optimistic update reflected via stream, but also update locally instantly
      if (mounted) {
        setState(() {
          _hasCurrentCompanyEndorsed = added;
          _companyEndorsementCount += added ? 1 : -1;
          if (_companyEndorsementCount < 0) _companyEndorsementCount = 0;
        });
      }
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(context, 'Could not update endorsement',
          detail: e.toString());
    }
  }

  void _subscribeToProfileStream() {
    // Keep _userData always fresh via stream
    _userDataSub?.cancel();
    _userDataSub =
        _firestoreService.streamUserModel(widget.userId).listen((user) {
      if (mounted && user != null) {
        setState(() => _userData = user);
      }
    });

    _profileSub?.cancel();
    if (_userRole == AppConstants.roleCustomer) {
      _profileSub = _firestoreService
          .customerProfileStream(widget.userId)
          .listen((profile) {
        if (mounted && profile != null) {
          setState(() => _customerProfile = profile);
        }
      });
    } else if (_userRole == AppConstants.roleCompany) {
      _profileSub = _firestoreService
          .companyProfileStream(widget.userId)
          .listen((profile) {
        if (mounted && profile != null) {
          setState(() => _companyProfile = profile);
        }
      });
    } else {
      _profileSub = _firestoreService
          .skilledUserProfileStream(widget.userId)
          .listen((profile) {
        if (mounted && profile != null) {
          setState(() => _profile = profile);
        }
      });
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Load user basic info
      try {
        _userData = await _firestoreService.getUserById(widget.userId);
        _userRole =
            UserRoles.normalizeRole(_userData?.role ?? '') ?? _userData?.role;
      } catch (e) {
        debugPrint('Could not load user data: $e');
      }

      if (_userRole == AppConstants.roleCustomer) {
        _customerProfile =
            await _firestoreService.getCustomerProfile(widget.userId);

        // Guard: if role says 'customer' but no customer profile exists,
        // the users-doc role may have been corrupted. Try skilled_users.
        if (_customerProfile == null) {
          final maybeSkilledProfile =
              await _firestoreService.getSkilledUserProfile(widget.userId);
          if (maybeSkilledProfile != null) {
            _profile = maybeSkilledProfile;
            _userRole = AppConstants.roleSkilledUser;
            _companySocialProofFuture =
                _firestoreService.getSkilledCompanySocialProof(widget.userId);
            // Fix the corrupted role in Firestore so this doesn't repeat
            try {
              await _firestoreService.updateUserRole(
                  widget.userId, AppConstants.roleSkilledUser);
            } catch (_) {}
            await _trackSkilledProfileViewIfEligible();
            try {
              _reviews = await _firestoreService.getUserReviews(widget.userId);
            } catch (_) {
              _reviews = [];
            }
          }
        }

        // Sync: if customer_profiles has a photo but users doc doesn't, update users doc
        if (_customerProfile != null &&
            isOwnProfile &&
            _customerProfile?.profilePicture != null &&
            _customerProfile!.profilePicture!.isNotEmpty &&
            (_userData?.profilePhoto == null ||
                _userData!.profilePhoto!.isEmpty)) {
          try {
            await _firestoreService.updateUserProfilePhoto(
                widget.userId, _customerProfile!.profilePicture!);
          } catch (_) {}
        }
      } else if (_userRole == AppConstants.roleCompany) {
        _companyProfile =
            await _firestoreService.getCompanyProfile(widget.userId);
      } else {
        _profile = await _firestoreService.getSkilledUserProfile(widget.userId);
        _companySocialProofFuture =
            _firestoreService.getSkilledCompanySocialProof(widget.userId);
        await _trackSkilledProfileViewIfEligible();

        // Try to load reviews, but don't fail if reviews collection doesn't exist or has permission issues
        try {
          _reviews = await _firestoreService.getUserReviews(widget.userId);
        } catch (reviewError) {
          debugPrint('Could not load reviews: $reviewError');
          _reviews = []; // Set empty list if reviews fail
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _profile = null;
        });
      }
    }
  }

  Future<void> _trackSkilledProfileViewIfEligible() async {
    if (_profile == null || isOwnProfile) return;
    final viewerRole = _currentViewerRole;
    if (viewerRole != UserRoles.customer && viewerRole != UserRoles.company) {
      return;
    }
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (viewerId == null) return;

    await _firestoreService.trackUniqueSkilledProfileView(
      skilledUserId: widget.userId,
      viewerUserId: viewerId,
    );
  }

  void _openPortfolioViewer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PortfolioScreen(portfolioUserId: widget.userId),
      ),
    );
  }

  Future<void> _openBannerEditor() async {
    final existing = _profile?.bannerData ??
        _customerProfile?.bannerData ??
        _companyProfile?.bannerData;
    final List<Color> defaultColors = _profile != null
        ? _getCoverGradient(_profile!.category)
        : _companyProfile != null
            ? const [Color(0xFF1565C0), Color(0xFF42A5F5)]
            : const [Color(0xFF9C27B0), Color(0xFFE91E63)];

    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => BannerEditorScreen(
          initialData: existing,
          defaultColors: defaultColors,
        ),
      ),
    );

    if (result == null || !mounted) return;

    // Immediately update local state for instant visual feedback (no loading spinner)
    setState(() {
      if (_userRole == AppConstants.roleCustomer && _customerProfile != null) {
        _customerProfile = _customerProfile!.copyWith(bannerData: result);
      } else if (_userRole == AppConstants.roleCompany &&
          _companyProfile != null) {
        _companyProfile = _companyProfile!.copyWith(bannerData: result);
      } else if (_profile != null) {
        _profile = _profile!.copyWith(bannerData: result);
      }
    });

    // Persist to Firestore â€” the active stream subscription will also
    // confirm the update on all other screens viewing this profile.
    await FirestoreService().saveBannerData(
      userId: widget.userId,
      role: _userRole ?? '',
      bannerData: result,
    );
  }

  Future<void> _showAddReviewDialog() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _userData == null) return;

    // Unfocus before opening dialog to avoid Flutter web pointer assertion.
    FocusManager.instance.primaryFocus?.unfocus();

    double rating = 5.0;
    final commentController = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Write a Review'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rate this skilled person'),
                  const SizedBox(height: 8),
                  RatingBar.builder(
                    initialRating: rating,
                    minRating: 1,
                    allowHalfRating: true,
                    itemSize: 30,
                    itemBuilder: (context, _) =>
                        const Icon(Icons.star, color: Colors.amber),
                    onRatingUpdate: (value) => setStateDialog(() {
                      rating = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    autofocus: false,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Comment',
                      hintText: 'Share your experience',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submitted != true) {
      commentController.dispose();
      return;
    }

    final normalizedComment = commentController.text.trim();
    commentController.dispose();

    try {
      final reviewerData = await _firestoreService.getUserById(currentUser.uid);
      final reviewerName = reviewerData?.name.trim().isNotEmpty == true
          ? reviewerData!.name
          : 'User';
      final reviewerPhoto = reviewerData?.profilePhoto;

      // Determine reviewer role and company name for enterprise endorsement badge
      final viewerRole = _currentViewerRole; // 'company', 'customer', etc.
      String? companyDisplayName;
      if (viewerRole == UserRoles.company) {
        try {
          final companyData =
              await _firestoreService.getCompanyProfile(currentUser.uid);
          companyDisplayName =
              (companyData?.companyName.trim().isNotEmpty == true)
                  ? companyData!.companyName
                  : reviewerName;
        } catch (_) {}
      }

      await _firestoreService.createReview(
        ReviewModel(
          id: '',
          skilledUserId: widget.userId,
          reviewerId: currentUser.uid,
          reviewerName: reviewerName,
          reviewerPhoto: reviewerPhoto,
          rating: rating,
          comment: normalizedComment,
          createdAt: DateTime.now(),
          reviewerRole: viewerRole,
          reviewerCompanyName: companyDisplayName,
        ),
      );

      await _loadProfile();
      if (!mounted) return;
      AppDialog.success(context, 'Review submitted successfully!');
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(context, 'Failed to submit review', detail: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!isOwnProfile && !_targetProfileVisible) {
      return _buildProfileHiddenView();
    }

    if (_userRole == AppConstants.roleCustomer) {
      if (_customerProfile == null) {
        if (isOwnProfile) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => CustomerSetupScreen(userId: widget.userId)),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildProfileNotFound(
          message: 'This customer has not set up their profile yet',
        );
      }

      return _buildCustomerProfileView();
    }

    if (_userRole == AppConstants.roleCompany) {
      if (_companyProfile == null) {
        if (isOwnProfile) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => CompanySetupScreen(userId: widget.userId)),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildProfileNotFound(
          message: 'This company has not set up their profile yet',
        );
      }

      return _buildCompanyProfileView();
    }

    if (_profile == null) {
      // Delivery partner and admin get a simple editable profile view
      if (_userRole == AppConstants.roleDeliveryPartner ||
          _userRole == AppConstants.roleAdmin) {
        return _buildBasicProfileView();
      }

      // If it's own profile, redirect to role-specific setup
      // Use _userRole (loaded from Firestore 'users' doc) â€” NOT
      // authProvider.currentUser.role which may be a stale fallback.
      if (isOwnProfile) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Widget setupScreen;

          if (_userRole == AppConstants.roleSkilledUser) {
            setupScreen = SkilledUserSetupScreen(userId: widget.userId);
          } else if (_userRole == AppConstants.roleCustomer) {
            setupScreen = CustomerSetupScreen(userId: widget.userId);
          } else if (_userRole == AppConstants.roleCompany) {
            setupScreen = CompanySetupScreen(userId: widget.userId);
          } else {
            // Fallback to skilled setup
            setupScreen = SkilledUserSetupScreen(userId: widget.userId);
          }

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => setupScreen),
          );
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      // For other users or error case
      return _buildProfileNotFound(
        message: isOwnProfile
            ? 'Complete your profile to get started'
            : 'This user has not set up their profile yet',
      );
    }

    return _buildSkilledPersonProfile();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // LinkedIn / Instagram style skilled-person profile
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSkilledPersonProfile() {
    const coverHeight = 210.0;
    const avatarRadius = 52.0;
    const avatarBorder = 3.0;

    // gradient stops derived from category for a unique feel
    final List<Color> coverColors = _getCoverGradient(_profile!.category);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: _bodyGradient(coverColors),
        child: CustomScrollView(
          controller: _profileScrollController,
          clipBehavior: Clip.none,
          slivers: [
            // â”€â”€ Pinned app-bar â”€â”€
            SliverAppBar(
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: coverHeight,
              backgroundColor: coverColors.first,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (!isOwnProfile) ...[
                  _appBarIcon(Icons.share_rounded, () {
                    Share.share(
                      'Check out ${_userData?.name ?? 'this profile'} on SkillShare!\n'
                      'Category: ${_profile!.category}\n'
                      'Rating: ${_profile!.rating.toStringAsFixed(1)} â­',
                      subject: 'SkillShare Profile',
                    );
                  }),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'report',
                          child: Row(children: [
                            Icon(Icons.report, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Report')
                          ])),
                      PopupMenuItem(
                          value: 'block',
                          child: Row(children: [
                            Icon(Icons.block, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Block')
                          ])),
                    ],
                    onSelected: (v) {
                      if (v == 'report') _showReportDialog();
                      if (v == 'block') _showBlockDialog();
                    },
                  ),
                ],
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final top = MediaQuery.of(context).padding.top;
                  final t =
                      ((constraints.biggest.height - kToolbarHeight - top) /
                              (coverHeight - kToolbarHeight))
                          .clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      FlexibleSpaceBar(
                        background: BannerDisplay(
                          enableAnimations: true,
                          bannerData: _normalizedBannerData(
                                _profile?.bannerData,
                                fallbackName: _userData?.name,
                              ) ??
                              {
                                'type': 'text',
                                'text': _displayNameUpper(_userData?.name,
                                    fallback: 'User'),
                                'fontKey': 'default',
                                'textColor': 0xFFFFFFFF,
                                'fontSize': 28.0,
                                'animation': 'none',
                              },
                          defaultColors: coverColors,
                          height: coverHeight,
                        ),
                      ),
                      // Edit banner button (own profile only)
                      if (isOwnProfile)
                        Positioned(
                          top: top + 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: _openBannerEditor,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      // Avatar overflowing below the banner
                      if (t > 0.05)
                        Positioned(
                          bottom: -(avatarRadius + avatarBorder),
                          left: 20,
                          child: Opacity(
                            opacity: t,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: coverColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: coverColors.last
                                        .withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(avatarBorder),
                              child: CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: Colors.white,
                                child: UniversalAvatar(
                                  avatarConfig: _profile?.avatarConfig ??
                                      _userData?.avatarConfig,
                                  photoUrl: _profile!.profilePicture,
                                  fallbackName:
                                      _userData?.name ?? _profile!.name,
                                  radius: avatarRadius - 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // â”€â”€ Name + stats card â”€â”€
            SliverToBoxAdapter(
              child: _buildProfileIdentitySection(avatarRadius, coverColors),
            ),

            SliverToBoxAdapter(
              child: _buildContactVisibilitySection(coverColors),
            ),

            // â”€â”€ Action buttons â”€â”€
            if (!isOwnProfile)
              SliverToBoxAdapter(
                child: _buildActionButtons(coverColors),
              ),
            SliverToBoxAdapter(
              child: _buildTrustAndBulkSection(),
            ),
            if (!isOwnProfile && _isCurrentUserCompany)
              SliverToBoxAdapter(
                child: _buildCompanyHiringInsightsSection(),
              ),

            // â”€â”€ Own-profile controls â”€â”€
            if (isOwnProfile)
              SliverToBoxAdapter(
                child: _buildOwnProfileControls(),
              ),

            // â”€â”€ Bio â”€â”€
            SliverToBoxAdapter(child: _buildBioSection()),

            // â”€â”€ Skills â”€â”€
            if (_profile!.skills.isNotEmpty)
              SliverToBoxAdapter(child: _buildSkillsSection()),

            // â”€â”€ Portfolio â”€â”€
            SliverToBoxAdapter(child: _buildPortfolioSection()),

            // â”€â”€ Reviews â”€â”€
            SliverToBoxAdapter(child: _buildReviewsSection()),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 88,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _getCoverGradient(String? category) {
    const Map<String, List<Color>> palettes = {
      'Baking': [Color(0xFFFF6B9D), Color(0xFFC44FEB)],
      'Photography': [Color(0xFF667EEA), Color(0xFF764BA2)],
      'Tailoring': [Color(0xFFf093fb), Color(0xFFf5576c)],
      'Carpentry': [Color(0xFF4facfe), Color(0xFF00f2fe)],
      'Electrician': [Color(0xFF43e97b), Color(0xFF38f9d7)],
      'Plumbing': [Color(0xFF0ba360), Color(0xFF3cba92)],
      'Web Dev': [Color(0xFF30cfd0), Color(0xFF667eea)],
      'Painting': [Color(0xFFfa709a), Color(0xFFfee140)],
    };
    for (final entry in palettes.entries) {
      if (category?.toLowerCase().contains(entry.key.toLowerCase()) == true) {
        return entry.value;
      }
    }
    return const [Color(0xFF6A11CB), Color(0xFF2575FC)];
  }

  /// Generates a unique gradient color pair derived from the userId hash,
  /// so each user gets their own distinct color theme.
  List<Color> _getUserColorGradient(String userId) {
    const palettes = [
      [Color(0xFF9C27B0), Color(0xFFE91E63)], // purple -> pink
      [Color(0xFF006064), Color(0xFF26C6DA)], // dark teal -> cyan
      [Color(0xFF1B5E20), Color(0xFF66BB6A)], // deep green -> mint
      [Color(0xFFE65100), Color(0xFFFFB74D)], // deep orange -> amber
      [Color(0xFF880E4F), Color(0xFFEC407A)], // wine -> rose
      [Color(0xFF4A148C), Color(0xFFAB47BC)], // deep purple -> lilac
      [Color(0xFF01579B), Color(0xFF29B6F6)], // ocean -> sky
      [Color(0xFF37474F), Color(0xFF78909C)], // slate -> steel
      [Color(0xFF33691E), Color(0xFFAED581)], // forest -> lime
      [Color(0xFF3E2723), Color(0xFF8D6E63)], // espresso -> latte
      [Color(0xFFB71C1C), Color(0xFFEF9A9A)], // crimson -> blush
      [Color(0xFF0D47A1), Color(0xFF64B5F6)], // cobalt -> periwinkle
      [Color(0xFF1A237E), Color(0xFF7986CB)], // indigo -> lavender
      [Color(0xFF004D40), Color(0xFF4DB6AC)], // emerald -> seafoam
      [Color(0xFF827717), Color(0xFFFFF176)], // olive -> butter
      [Color(0xFF212121), Color(0xFF757575)], // charcoal -> smoke
    ];
    int hash = 0;
    for (int i = 0; i < userId.length; i++) {
      hash = (hash * 31 + userId.codeUnitAt(i)) & 0xFFFFFF;
    }
    final pair = palettes[hash % palettes.length];
    return [pair[0], pair[1]];
  }

  Widget _appBarIcon(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      );

  /// Keeps profile body clean and neutral.
  BoxDecoration _bodyGradient(List<Color> coverColors) {
    return const BoxDecoration(color: Colors.white);
  }

  // â”€â”€â”€ Minimal profile view for delivery partner / admin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBasicProfileView() {
    const coverHeight = 200.0;
    const avatarRadius = 48.0;
    const avatarBorder = 3.0;
    final coverColors = _getUserColorGradient(widget.userId);
    final imageUrl = _userData?.profilePhoto;
    final isDelivery = _userRole == AppConstants.roleDeliveryPartner;
    final roleLabel = isDelivery ? 'Delivery Partner' : 'Administrator';
    final roleIcon = isDelivery
        ? Icons.delivery_dining_rounded
        : Icons.admin_panel_settings_rounded;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Container(
        decoration: _bodyGradient(coverColors),
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverAppBar(
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: coverHeight,
              backgroundColor: coverColors.first,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              // title intentionally omitted to avoid duplicate name display
              actions: [
                if (!isOwnProfile)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_rounded,
                        color: Colors.white),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      try {
                        final cu = FirebaseAuth.instance.currentUser;
                        if (cu == null) return;
                        final cuData =
                            await _firestoreService.getUserById(cu.uid);
                        if (cuData == null || _userData == null) return;
                        if (!mounted) return;
                        showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                                child: CircularProgressIndicator()));
                        final chatId = await _chatService.getOrCreateChat(
                          cu.uid,
                          widget.userId,
                          {
                            'name': cuData.name,
                            'profilePhoto': cuData.profilePhoto
                          },
                          {
                            'name': _userData!.name,
                            'profilePhoto': _userData!.profilePhoto
                          },
                        );
                        final safeChatId =
                            await _chatService.resolveAccessibleDirectChatId(
                          preferredChatId: chatId,
                          currentUserId: cu.uid,
                          otherUserId: widget.userId,
                        );
                        if (!mounted) return;
                        nav.pop();
                        nav.push(MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(
                                chatId: safeChatId,
                                otherUserId: widget.userId,
                                otherUserName: _userData!.name,
                                otherUserPhoto: _userData!.profilePhoto)));
                      } catch (e) {
                        if (!mounted) return;
                        nav.pop();
                        AppDialog.error(context, 'Error starting chat',
                            detail: e.toString());
                      }
                    },
                  ),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final top = MediaQuery.of(context).padding.top;
                  final t =
                      ((constraints.biggest.height - kToolbarHeight - top) /
                              (coverHeight - kToolbarHeight))
                          .clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      FlexibleSpaceBar(
                        background: BannerDisplay(
                          enableAnimations: true,
                          bannerData: _normalizedBannerData(
                                _profile?.bannerData,
                                fallbackName: _userData?.name,
                              ) ??
                              {
                                'type': 'text',
                                'text': _displayNameUpper(_userData?.name,
                                    fallback: 'User'),
                                'fontKey': 'default',
                                'textColor': 0xFFFFFFFF,
                                'fontSize': 28.0,
                                'animation': 'none',
                              },
                          defaultColors: coverColors,
                          height: coverHeight,
                        ),
                      ),
                      if (isOwnProfile)
                        Positioned(
                          top: top + 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: _openBannerEditor,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      if (t > 0.05)
                        Positioned(
                          bottom: -(avatarRadius + avatarBorder),
                          left: 20,
                          child: Opacity(
                            opacity: t,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: coverColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: coverColors.last
                                        .withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(avatarBorder),
                              child: CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: Colors.white,
                                child: UniversalAvatar(
                                  avatarConfig: _profile?.avatarConfig ??
                                      _customerProfile?.avatarConfig ??
                                      _companyProfile?.avatarConfig ??
                                      _userData?.avatarConfig,
                                  photoUrl: imageUrl,
                                  fallbackName: _userData?.name,
                                  radius: avatarRadius - 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // â”€â”€ Identity: name + role badge â”€â”€
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    16, avatarRadius + avatarBorder + 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: SizedBox(
                        width: 2 * (avatarRadius + avatarBorder),
                        child: Text(
                          _displayNameUpper(_userData?.name, fallback: 'User'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1A1A2E),
                              letterSpacing: 1.2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: coverColors),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(roleIcon, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(roleLabel,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _buildContactVisibilitySection(coverColors),
            ),

            // â”€â”€ Own-profile edit button â”€â”€
            if (isOwnProfile)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: _gradientButton(
                    label: 'Edit Profile',
                    icon: Icons.edit_rounded,
                    colors: coverColors,
                    onTap: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => SkilledUserSetupScreen(
                                  userId: widget.userId)));
                      _loadProfile();
                    },
                  ),
                ),
              ),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 88,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileIdentitySection(
      double avatarRadius, List<Color> coverColors) {
    const avatarBorder = 3.0;
    final rawDisplayName = (_userData?.name ?? '').trim();
    final displayName = rawDisplayName.isEmpty ? 'User' : rawDisplayName;

    // Content below â€” top padding leaves room for the overflowing avatar
    return Padding(
      padding: EdgeInsets.fromLTRB(20, avatarRadius + avatarBorder + 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Name centered under avatar circle â”€â”€
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 40,
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // â”€â”€ Category badge â”€â”€
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_profile!.category?.isNotEmpty == true) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: coverColors),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _profile!.category ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // — Location —
          if (_profile!.city != null || _profile!.address != null)
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 14, color: Color(0xFF9E9E9E)),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _profile!.city ?? _profile!.address ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 10),

          // â”€â”€ Star rating bar â”€â”€
          InkWell(
            onTap: () {
              if (_canCurrentUserReview) {
                _showAddReviewDialog();
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RatingBarIndicator(
                    rating: _profile!.rating,
                    itemBuilder: (_, __) =>
                        const Icon(Icons.star_rounded, color: Colors.amber),
                    itemCount: 5,
                    itemSize: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_profile!.rating.toStringAsFixed(1)} • ${_profile!.reviewCount} reviews',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600),
                  ),
                  if (_canCurrentUserReview) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.amber.shade700, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rate_rounded,
                              size: 14, color: Colors.amber),
                          SizedBox(width: 2),
                          Text('Rate 5 Stars',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE65100))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // â”€â”€ Stats row â€” compact, left-aligned â”€â”€
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniStat(_profile!.rating.toStringAsFixed(1), 'Rating',
                  Icons.star_rounded, Colors.amber),
              const SizedBox(width: 24),
              _miniStat(_profile!.reviewCount.toString(), 'Reviews',
                  Icons.reviews_rounded, const Color(0xFF2196F3)),
              const SizedBox(width: 24),
              _miniStat(_profile!.projectCount.toString(), 'Projects',
                  Icons.work_rounded, const Color(0xFF4CAF50)),
            ],
          ),

          const SizedBox(height: 4),

          // â”€â”€ Company endorsement banner â”€â”€
          if (_companyEndorsementCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.business_center_rounded,
                        color: Color(0xFFE65100), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$_companyEndorsementCount ${_companyEndorsementCount == 1 ? 'Company Endorses' : 'Companies Endorse'} This Professional',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // â”€â”€ Company endorsement button (visible to company viewers only) â”€â”€
          if (_profile!.hasConfidentialCredentials)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE8F5E9), Color(0xFFD7F4E3)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        color: Color(0xFF1B5E20), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      _profile!.confidentialCredentialCount > 0
                          ? '${_profile!.confidentialCredentialCount} validated credential ${_profile!.confidentialCredentialCount == 1 ? 'link' : 'links'} on file'
                          : 'Validated credentials on file',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isCurrentUserCompany && !isOwnProfile)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: GestureDetector(
                onTap: _toggleEndorsement,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: _hasCurrentCompanyEndorsed
                        ? const LinearGradient(
                            colors: [Color(0xFFE53935), Color(0xFFE91E63)])
                        : const LinearGradient(
                            colors: [Color(0xFFF5F5F5), Color(0xFFEEEEEE)]),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: _hasCurrentCompanyEndorsed
                            ? Colors.transparent
                            : const Color(0xFFBDBDBD)),
                    boxShadow: _hasCurrentCompanyEndorsed
                        ? [
                            BoxShadow(
                              color: const Color(0xFFE91E63)
                                  .withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hasCurrentCompanyEndorsed
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: _hasCurrentCompanyEndorsed
                            ? Colors.white
                            : const Color(0xFF9E9E9E),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _hasCurrentCompanyEndorsed
                            ? 'Endorsed'
                            : 'Endorse Professional',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _hasCurrentCompanyEndorsed
                              ? Colors.white
                              : const Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label, IconData icon, Color color) {
    return GestureDetector(
      onTap: () {
        if (_canCurrentUserReview &&
            (label == 'Rating' || label == 'Reviews')) {
          _showAddReviewDialog();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800])),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }

  Widget _buildActionButtons(List<Color> coverColors) {
    final secondaryActionColors = [coverColors.last, coverColors.first];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        children: [
          // Message button
          Expanded(
            child: _gradientButton(
              label: 'Message',
              icon: Icons.chat_bubble_rounded,
              colors: coverColors,
              onTap: () async {
                final nav = Navigator.of(context);
                try {
                  final currentUser = FirebaseAuth.instance.currentUser;
                  if (currentUser == null) return;
                  final currentUserData =
                      await _firestoreService.getUserById(currentUser.uid);
                  if (currentUserData == null || _userData == null) return;
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                  );
                  final chatId = await _chatService.getOrCreateChat(
                    currentUser.uid,
                    widget.userId,
                    {
                      'name': currentUserData.name,
                      'profilePhoto': currentUserData.profilePhoto
                    },
                    {
                      'name': _userData!.name,
                      'profilePhoto': _userData!.profilePhoto
                    },
                  );
                  final safeChatId =
                      await _chatService.resolveAccessibleDirectChatId(
                    preferredChatId: chatId,
                    currentUserId: currentUser.uid,
                    otherUserId: widget.userId,
                  );
                  if (!mounted) return;
                  nav.pop();
                  nav.push(MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(
                      chatId: safeChatId,
                      otherUserId: widget.userId,
                      otherUserName: _userData!.name,
                      otherUserPhoto: _userData!.profilePhoto,
                    ),
                  ));
                } catch (e) {
                  if (!mounted) return;
                  nav.pop();
                  AppDialog.error(context, 'Failed to start chat',
                      detail: e.toString());
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          // Hire / Review button
          if (_canCurrentUserReview)
            Expanded(
              child: _gradientButton(
                label: 'Rating',
                icon: Icons.star_rate_rounded,
                colors: const [Color(0xFFFF9800), Color(0xFFF4511E)],
                onTap: _showAddReviewDialog,
              ),
            ),
          if (_isCurrentUserCompany)
            Expanded(
              child: Builder(
                builder: (context) {
                  final viewerId = FirebaseAuth.instance.currentUser?.uid;
                  if (viewerId == null || viewerId.isEmpty) {
                    return _gradientButton(
                      label: 'Verify to Hire',
                      icon: Icons.verified_user_rounded,
                      colors: const [Color(0xFFB0BEC5), Color(0xFF90A4AE)],
                      onTap: _promptCompanyVerificationRequired,
                    );
                  }

                  return StreamBuilder<CompanyProfile?>(
                    stream: _firestoreService.companyProfileStream(viewerId),
                    builder: (context, snapshot) {
                      final canHire =
                          _isCompanyVerifiedForHiring(snapshot.data);
                      return _gradientButton(
                        label: canHire ? 'Hire' : 'Verify to Hire',
                        icon: canHire
                            ? Icons.handshake_rounded
                            : Icons.verified_user_rounded,
                        colors: canHire
                            ? secondaryActionColors
                            : const [Color(0xFFB0BEC5), Color(0xFF90A4AE)],
                        onTap: canHire
                            ? _showHireRequestDialog
                            : _promptCompanyVerificationRequired,
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrustAndBulkSection() {
    if (_profile == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: StreamBuilder<List<ProductModel>>(
        stream: _firestoreService.streamUserProducts(widget.userId),
        builder: (context, productSnapshot) {
          final availableProducts =
              (productSnapshot.data ?? const <ProductModel>[])
                  .where((product) => product.isAvailable)
                  .toList();
          final hasShopProducts = availableProducts.isNotEmpty;

          return FutureBuilder<SkilledCompanySocialProof>(
            future: _companySocialProofFuture,
            builder: (context, snapshot) {
              final socialProof =
                  snapshot.data ?? const SkilledCompanySocialProof();
              final showSection = _profile!.hasConfidentialCredentials ||
                  hasShopProducts ||
                  socialProof.companyOrdersCount > 0;
              if (!showSection) {
                return const SizedBox.shrink();
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6E9F2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_rounded, color: Color(0xFF1565C0)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Trust, Verification and Bulk Orders',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (_profile!.hasConfidentialCredentials)
                          _insightChip(
                            value: _profile!.confidentialCredentialCount > 0
                                ? _profile!.confidentialCredentialCount
                                    .toString()
                                : 'Yes',
                            label: 'Credential Checks',
                            icon: Icons.fact_check_rounded,
                            color: const Color(0xFF2E7D32),
                          ),
                        if (socialProof.uniqueCompanyBuyers > 0)
                          _insightChip(
                            value: socialProof.uniqueCompanyBuyers.toString(),
                            label: 'Company Buyers',
                            icon: Icons.apartment_rounded,
                            color: const Color(0xFF6A1B9A),
                          ),
                        if (socialProof.companyUnitsBought > 0)
                          _insightChip(
                            value: socialProof.companyUnitsBought.toString(),
                            label: 'Units Bought by Companies',
                            icon: Icons.inventory_2_rounded,
                            color: const Color(0xFFEF6C00),
                          ),
                        if (hasShopProducts)
                          _insightChip(
                            value: availableProducts.length.toString(),
                            label: 'Bulk-ready Products',
                            icon: Icons.storefront_rounded,
                            color: const Color(0xFF1565C0),
                          ),
                      ],
                    ),
                    if (_profile!.hasConfidentialCredentials) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Confidential verification evidence is on file for this skilled person. Viewers see the trust status, but the actual credential URLs remain private.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (socialProof.topCompanyBuyers.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Highlighted company buyers',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E2E2E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...socialProof.topCompanyBuyers.map((buyer) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFB300)
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.business_center_rounded,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        buyer.companyName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      Text(
                                        '${buyer.totalUnits} units across ${buyer.totalOrders} order${buyer.totalOrders == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF616161),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Rs ${buyer.totalSpend.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                    if (hasShopProducts) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isCurrentUserCompany
                                  ? 'Bulk product buying is available for company users.'
                                  : 'Bulk product buying is available from this skilled person.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D47A1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Use the shop quantity selector or cart checkout to place larger orders. Company reviews stay highlighted first in the profile below.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _openSellerShopStorefront,
                            icon: Icon(_isCurrentUserCompany
                                ? Icons.shopping_bag_rounded
                                : Icons.storefront_rounded),
                            label: Text(_isCurrentUserCompany
                                ? 'Buy in Bulk'
                                : 'Open Shop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Future<void> _openSellerShopStorefront() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopStorefrontScreen(
          sellerId: widget.userId,
          initialShopName: _userData?.name,
        ),
      ),
    );
  }

  Widget _buildCompanyHiringInsightsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: StreamBuilder<List<ProductModel>>(
        stream: _firestoreService.streamUserProducts(widget.userId),
        builder: (context, productSnapshot) {
          final products = productSnapshot.data ?? const <ProductModel>[];
          final availableProducts = products.where((p) => p.isAvailable).length;
          final totalProducts = products.length;
          final hasShop = totalProducts > 0;

          return StreamBuilder<List<OrderModel>>(
            stream: _firestoreService.streamSellerOrders(widget.userId),
            builder: (context, orderSnapshot) {
              final orders = orderSnapshot.data ?? const <OrderModel>[];
              final deliveredOrders = orders
                  .where((o) => o.status.toLowerCase().trim() == 'delivered')
                  .toList();
              final deliveredCount = deliveredOrders.length;
              final totalUnitsSold = deliveredOrders.fold<int>(
                0,
                (sum, o) => sum + o.quantity,
              );
              final totalSales = deliveredOrders.fold<double>(
                0,
                (sum, o) => sum + o.totalPrice,
              );

              return StreamBuilder<List<ServiceRequestModel>>(
                stream: _firestoreService.streamSkilledRequests(widget.userId),
                builder: (context, requestSnapshot) {
                  final requests =
                      requestSnapshot.data ?? const <ServiceRequestModel>[];
                  // Projects = accepted + completed (projectCount increments on acceptance)
                  final doneProjects = requests.where((r) {
                    final s = r.status.toLowerCase().trim();
                    return s == AppConstants.requestStatusCompleted;
                  }).toList();
                  final activeProjects = requests
                      .where((r) =>
                          r.status.toLowerCase().trim() ==
                          AppConstants.requestStatusAccepted)
                      .toList();
                  // All projects ever worked on = accepted + completed
                  final allProjects = [...doneProjects, ...activeProjects]
                    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  final hireProjects = requests
                      .where((r) =>
                          r.serviceId.toLowerCase().trim() == 'direct_hire')
                      .toList();
                  // Split all projects by client type (for project history)
                  final companyProjects =
                      allProjects.where((r) => r.isCompanyProject).toList();
                  final customerProjects =
                      allProjects.where((r) => !r.isCompanyProject).toList();
                  final portfolioCount = _profile?.portfolioImages.length ?? 0;
                  final topSkills = _profile?.skills.length ?? 0;
                  final profileViews = _profile?.profileViews ?? 0;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE6E9F2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.insights_rounded,
                                color: Color(0xFF3949AB)),
                            SizedBox(width: 8),
                            Text(
                              'Hiring Insights',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _insightChip(
                              value: '$totalProducts',
                              label: 'Products',
                              icon: Icons.inventory_2_rounded,
                              color: const Color(0xFF1976D2),
                            ),
                            _insightChip(
                              value: '$availableProducts',
                              label: 'Available',
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF2E7D32),
                            ),
                            _insightChip(
                              value: '$deliveredCount',
                              label: 'Delivered',
                              icon: Icons.local_shipping_rounded,
                              color: const Color(0xFF6A1B9A),
                            ),
                            _insightChip(
                              value: '$totalUnitsSold',
                              label: 'Units Sold',
                              icon: Icons.shopping_bag_rounded,
                              color: const Color(0xFFEF6C00),
                            ),
                            _insightChip(
                              value: '${_profile?.projectCount ?? 0}',
                              label: 'Completed Projects',
                              icon: Icons.assignment_turned_in_rounded,
                              color: const Color(0xFF00897B),
                            ),
                            _insightChip(
                              value: '${activeProjects.length}',
                              label: 'Active Projects',
                              icon: Icons.work_history_rounded,
                              color: const Color(0xFF1E88E5),
                            ),
                            _insightChip(
                              value: '${hireProjects.length}',
                              label: 'Hires Completed',
                              icon: Icons.handshake_rounded,
                              color: const Color(0xFF3949AB),
                            ),
                            _insightChip(
                              value: '$portfolioCount',
                              label: 'Portfolio Items',
                              icon: Icons.collections_rounded,
                              color: const Color(0xFF8E24AA),
                            ),
                            _insightChip(
                              value: '$topSkills',
                              label: 'Skills',
                              icon: Icons.workspace_premium_rounded,
                              color: const Color(0xFFF57C00),
                            ),
                            _insightChip(
                              value: '$profileViews',
                              label: 'Profile Views',
                              icon: Icons.visibility_rounded,
                              color: const Color(0xFF546E7A),
                            ),
                            _insightChip(
                              value:
                                  _profile?.rating.toStringAsFixed(1) ?? '0.0',
                              label: 'Rating',
                              icon: Icons.star_rounded,
                              color: const Color(0xFFF9A825),
                            ),
                            _insightChip(
                              value: (_profile?.reviewCount ?? 0).toString(),
                              label: 'Reviews',
                              icon: Icons.rate_review_rounded,
                              color: const Color(0xFF5E35B1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Estimated sales: Rs ${totalSales.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF616161),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // â”€â”€ Project History â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        Row(
                          children: [
                            const Icon(Icons.work_history_rounded,
                                size: 16, color: Color(0xFF2196F3)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                allProjects.isEmpty
                                    ? 'Project History (${_profile?.projectCount ?? 0} total)'
                                    : 'Project History (${allProjects.length} with you Â· ${_profile?.projectCount ?? 0} total)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E2E2E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (allProjects.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 15, color: Color(0xFF9E9E9E)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (_profile?.projectCount ?? 0) > 0
                                        ? 'No joint projects with your company yet. This person has completed ${_profile!.projectCount} project${_profile!.projectCount == 1 ? '' : 's'} overall.'
                                        : 'No projects completed yet.',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(0xFF9E9E9E)),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          // Company projects first, then customer projects
                          ...[...companyProjects, ...customerProjects].map((r) {
                            final isCompany = r.isCompanyProject;
                            final badgeColor = isCompany
                                ? const Color(0xFF1A237E)
                                : const Color(0xFF00695C);
                            final badgeLabel =
                                isCompany ? 'ðŸ¢ Company' : 'ðŸ‘¤ Customer';
                            final isActive = r.status.toLowerCase().trim() ==
                                AppConstants.requestStatusAccepted;
                            final dateStr =
                                '${r.updatedAt.day}/${r.updatedAt.month}/${r.updatedAt.year}';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCompany
                                      ? const Color(0xFFBBDEFB)
                                      : const Color(0xFFB2DFDB),
                                  width: 1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.04),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          badgeLabel,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (isActive ||
                                          (r.hireType != null &&
                                              r.hireType!.isNotEmpty)) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isActive
                                                ? const Color(0xFFFF8F00)
                                                : const Color(0xFF37474F),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            isActive
                                                ? 'â³ In Progress'
                                                : r.hireType!
                                                    .replaceAll('_', ' '),
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        dateStr,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF9E9E9E),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    r.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2E2E2E),
                                    ),
                                  ),
                                  if (r.description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      r.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF757575),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        if (_reviews.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Recent customer feedback',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E2E2E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._reviews.take(2).map(
                                (review) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '"${review.comment}" - ${review.reviewerName}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF616161),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (hasShop)
                              OutlinedButton.icon(
                                onPressed: _openSellerShopStorefront,
                                icon: const Icon(Icons.storefront_rounded),
                                label: const Text('View Shop Products'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _openPortfolioViewer,
                              icon: const Icon(Icons.collections_bookmark),
                              label: const Text('View Portfolio'),
                            ),
                          ],
                        ),
                        if (!hasShop)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No shop products published yet.',
                              style: TextStyle(
                                color: Color(0xFF757575),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _insightChip({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnProfileControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AddProductScreen()));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFE91E63), Color(0xFFFF6B9D)]),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFE91E63).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_shopping_cart_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Add Product to Shop',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Visibility badge
          Row(
            children: [
              _infoBadge(
                icon: _profile!.visibility == AppConstants.visibilityPublic
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                label: _profile!.visibility == AppConstants.visibilityPublic
                    ? 'Public'
                    : 'Private',
                color: _profile!.visibility == AppConstants.visibilityPublic
                    ? const Color(0xFF4CAF50)
                    : Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.4)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E))),
        ],
      ),
    );
  }

  Widget _buildBioSection() {
    if (_profile!.bio.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              'Bio', Icons.info_outline_rounded, const Color(0xFF6A11CB)),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Text(
              _profile!.bio,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, color: Color(0xFF444466)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsSection() {
    final skillColors = [
      const Color(0xFF6A11CB),
      const Color(0xFF2575FC),
      const Color(0xFFE91E63),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF00BCD4),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              'Skills', Icons.auto_awesome_rounded, const Color(0xFFE91E63)),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_profile!.skills.length, (i) {
                final color = skillColors[i % skillColors.length];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _profile!.skills[i],
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioSection() {
    if (_profile!.portfolioImages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionHeader('Portfolio',
                      Icons.photo_library_rounded, const Color(0xFF4CAF50)),
                ),
                if (!isOwnProfile && _canCurrentUserReview)
                  TextButton.icon(
                    onPressed: _openPortfolioViewer,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View'),
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Icon(Icons.photo_library, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('No portfolio yet',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionHeader('Portfolio', Icons.photo_library_rounded,
                    const Color(0xFF4CAF50)),
              ),
              if (!isOwnProfile && _canCurrentUserReview)
                TextButton.icon(
                  onPressed: _openPortfolioViewer,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View'),
                ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 600 ? 4 : 3;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemCount: _profile!.portfolioImages.length,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => _showFullScreenImage(context, i),
                  child: Hero(
                    tag: 'portfolio_$i',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: WebImageLoader.loadImage(
                        imageUrl: _profile!.portfolioImages[i],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _sectionHeader(
                    'Reviews', Icons.reviews_rounded, Colors.amber),
              ),
              if (!isOwnProfile && _canCurrentUserReview)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _showAddReviewDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Colors.amber, Color(0xFFFF9800)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Add Review',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_reviews.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Icon(Icons.rate_review, size: 44, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('No reviews yet',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500)),
                  if (_canCurrentUserReview) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _showAddReviewDialog,
                      icon: const Icon(Icons.star_rate_rounded, color: Colors.white, size: 18),
                      label: const Text('Rating & Review',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Builder(builder: (context) {
              final companyReviews =
                  _reviews.where((r) => r.isCompanyReview).take(5).toList();
              final otherReviews =
                  _reviews.where((r) => !r.isCompanyReview).take(5).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (companyReviews.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFFF8F00),
                                Color(0xFFE65100),
                              ]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.business_center_rounded,
                                    size: 12, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Company Endorsements',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...companyReviews.map((r) => _buildReviewCard(r)),
                    if (otherReviews.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: 6, left: 2, bottom: 6),
                        child: Text(
                          'Customer Reviews',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600]),
                        ),
                      ),
                  ],
                  ...otherReviews.map((r) => _buildReviewCard(r)),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ReviewModel review) {
    final isCompany = review.isCompanyReview;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCompany ? const Color(0xFFFFFDE7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isCompany
            ? Border.all(
                color: const Color(0xFFFFB300).withValues(alpha: 0.7),
                width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: isCompany
                  ? const Color(0xFFFFB300).withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompany)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        Color(0xFFFF8F00),
                        Color(0xFFE65100),
                      ]),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.business_center_rounded,
                            size: 11, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'COMPANY ENDORSEMENT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UniversalAvatar(
                photoUrl: review.reviewerPhoto,
                fallbackName: review.reviewerName,
                radius: 22,
                animate: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                review.reviewerName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF1A1A2E)),
                              ),
                              if (isCompany &&
                                  review.reviewerCompanyName != null &&
                                  review.reviewerCompanyName!.isNotEmpty)
                                Text(
                                  review.reviewerCompanyName!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFE65100),
                                      fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                        RatingBarIndicator(
                          rating: review.rating,
                          itemBuilder: (_, __) => const Icon(Icons.star_rounded,
                              color: Colors.amber),
                          itemCount: 5,
                          itemSize: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(review.comment,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileNotFound({required String message}) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Profile not found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerProfileView() {
    final profile = _customerProfile!;
    final imageUrl = profile.profilePicture?.isNotEmpty == true
        ? profile.profilePicture
        : _userData?.profilePhoto;
    final coverColors = _getUserColorGradient(widget.userId);
    const coverHeight = 200.0;
    const avatarRadius = 52.0;
    const avatarBorder = 3.0;

    // Build location string cleanly â€“ filter out blanks / single chars
    String locationText = '';
    if (profile.city != null && profile.city!.trim().length > 1) {
      locationText = profile.city!.trim();
    }
    if (profile.state != null && profile.state!.trim().length > 1) {
      locationText = locationText.isEmpty
          ? profile.state!.trim()
          : '$locationText, ${profile.state!.trim()}';
    }
    if (locationText.isEmpty &&
        profile.location != null &&
        profile.location!.trim().length > 2) {
      locationText = profile.location!.trim();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: _bodyGradient(coverColors),
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverAppBar(
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: coverHeight,
              backgroundColor: coverColors.first,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              // title intentionally omitted to avoid duplicate name display
              actions: [
                if (!isOwnProfile)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_rounded,
                        color: Colors.white),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      try {
                        final cu = FirebaseAuth.instance.currentUser;
                        if (cu == null) return;
                        final cuData =
                            await _firestoreService.getUserById(cu.uid);
                        if (cuData == null || _userData == null) return;
                        if (!mounted) return;
                        showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                                child: CircularProgressIndicator()));
                        final chatId = await _chatService.getOrCreateChat(
                          cu.uid,
                          widget.userId,
                          {
                            'name': cuData.name,
                            'profilePhoto': cuData.profilePhoto
                          },
                          {
                            'name': _userData!.name,
                            'profilePhoto': _userData!.profilePhoto
                          },
                        );
                        final safeChatId =
                            await _chatService.resolveAccessibleDirectChatId(
                          preferredChatId: chatId,
                          currentUserId: cu.uid,
                          otherUserId: widget.userId,
                        );
                        if (!mounted) return;
                        nav.pop();
                        nav.push(MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(
                                chatId: safeChatId,
                                otherUserId: widget.userId,
                                otherUserName: _userData!.name,
                                otherUserPhoto: _userData!.profilePhoto)));
                      } catch (e) {
                        if (!mounted) return;
                        nav.pop();
                        AppDialog.error(context, 'Error starting chat',
                            detail: e.toString());
                      }
                    },
                  ),
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final top = MediaQuery.of(context).padding.top;
                  final t =
                      ((constraints.biggest.height - kToolbarHeight - top) /
                              (coverHeight - kToolbarHeight))
                          .clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      FlexibleSpaceBar(
                        background: BannerDisplay(
                          enableAnimations: true,
                          bannerData: _normalizedBannerData(
                                _customerProfile?.bannerData,
                                fallbackName: _userData?.name,
                              ) ??
                              {
                                'type': 'text',
                                'text': _displayNameUpper(_userData?.name,
                                    fallback: 'Customer'),
                                'fontKey': 'default',
                                'textColor': 0xFFFFFFFF,
                                'fontSize': 28.0,
                                'animation': 'none',
                              },
                          defaultColors: coverColors,
                          height: coverHeight,
                        ),
                      ),
                      if (isOwnProfile)
                        Positioned(
                          top: top + 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: _openBannerEditor,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      if (t > 0.05)
                        Positioned(
                          bottom: -(avatarRadius + avatarBorder),
                          left: 20,
                          child: Opacity(
                            opacity: t,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: coverColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: coverColors.last
                                        .withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(avatarBorder),
                              child: CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: Colors.white,
                                child: UniversalAvatar(
                                  avatarConfig: _profile?.avatarConfig ??
                                      _customerProfile?.avatarConfig ??
                                      _companyProfile?.avatarConfig ??
                                      _userData?.avatarConfig,
                                  photoUrl: imageUrl,
                                  fallbackName: _userData?.name,
                                  radius: avatarRadius - 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // â”€â”€ Identity: name + location + action â”€â”€
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    20, avatarRadius + avatarBorder + 12, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 2 * (avatarRadius + avatarBorder),
                            child: Text(
                              _displayNameUpper(_userData?.name,
                                  fallback: 'Customer'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1A2E),
                                  letterSpacing: 1.2),
                            ),
                          ),
                          if (locationText.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded,
                                    size: 14, color: Color(0xFFAA44BB)),
                                const SizedBox(width: 3),
                                Text(locationText,
                                    style: const TextStyle(
                                        color: Color(0xFF777788),
                                        fontSize: 13)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Action button
                    if (isOwnProfile)
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CustomerSetupScreen(
                                      userId: widget.userId)));
                          _loadProfile();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: coverColors),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      coverColors.last.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Edit Profile',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () async {
                          final nav = Navigator.of(context);
                          try {
                            final cu = FirebaseAuth.instance.currentUser;
                            if (cu == null) return;
                            final cuData =
                                await _firestoreService.getUserById(cu.uid);
                            if (cuData == null || _userData == null) return;
                            if (!mounted) return;
                            showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(
                                    child: CircularProgressIndicator()));
                            final chatId = await _chatService.getOrCreateChat(
                              cu.uid,
                              widget.userId,
                              {
                                'name': cuData.name,
                                'profilePhoto': cuData.profilePhoto
                              },
                              {
                                'name': _userData!.name,
                                'profilePhoto': _userData!.profilePhoto
                              },
                            );
                            final safeChatId = await _chatService
                                .resolveAccessibleDirectChatId(
                              preferredChatId: chatId,
                              currentUserId: cu.uid,
                              otherUserId: widget.userId,
                            );
                            if (!mounted) return;
                            nav.pop();
                            nav.push(MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                    chatId: safeChatId,
                                    otherUserId: widget.userId,
                                    otherUserName: _userData!.name,
                                    otherUserPhoto: _userData!.profilePhoto)));
                          } catch (e) {
                            if (!mounted) return;
                            nav.pop();
                            AppDialog.error(context, 'Error starting chat',
                                detail: e.toString());
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF2979FF), Color(0xFF00B0FF)]),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFF2979FF)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Message',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _buildContactVisibilitySection(coverColors),
            ),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 72,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Bio
            if (profile.bio.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('About', Icons.info_outline_rounded,
                          const Color(0xFF9C27B0)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Text(profile.bio,
                            style: const TextStyle(
                                fontSize: 14,
                                height: 1.65,
                                color: Color(0xFF444466))),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            // Interests
            if (profile.interests.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('Interests', Icons.favorite_rounded,
                          const Color(0xFFE91E63)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: profile.interests.map((i) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE91E63)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFE91E63)
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(i,
                                  style: const TextStyle(
                                      color: Color(0xFFE91E63),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            // Looking For
            if (profile.lookingFor.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('Looking For', Icons.search_rounded,
                          const Color(0xFF9C27B0)),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: profile.lookingFor.map((c) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFF9C27B0)
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(c,
                                  style: const TextStyle(
                                      color: Color(0xFF9C27B0),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            // Assigned Projects
            if (profile.assignedProjects.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('Projects', Icons.folder_rounded,
                          const Color(0xFF4CAF50)),
                      ...profile.assignedProjects
                          .map((p) => _buildProjectCard(p)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 88,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyProfileView() {
    final profile = _companyProfile!;
    final imageUrl = profile.logoUrl?.isNotEmpty == true
        ? profile.logoUrl
        : _userData?.profilePhoto;
    final coverColors = _getUserColorGradient(widget.userId);
    const coverHeight = 200.0;
    const avatarRadius = 52.0;
    const avatarBorder = 3.0;

    // Clean location
    String locationText = '';
    if (profile.city != null && profile.city!.trim().length > 1) {
      locationText = profile.city!.trim();
    }
    if (profile.state != null && profile.state!.trim().length > 1) {
      locationText = locationText.isEmpty
          ? profile.state!.trim()
          : '$locationText, ${profile.state!.trim()}';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              coverColors.first.withValues(alpha: 0.08),
              const Color(0xFFF6F7FB),
              coverColors.last.withValues(alpha: 0.04),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverAppBar(
              clipBehavior: Clip.none,
              pinned: true,
              expandedHeight: coverHeight,
              backgroundColor: coverColors.first,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              // title intentionally omitted to avoid duplicate name display
              actions: [
                if (!isOwnProfile) ...[
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white),
                    onPressed: () => Share.share(
                        'Check out ${profile.companyName} on SkillShare!\nIndustry: ${profile.industry}',
                        subject: 'SkillShare Company'),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'report',
                          child: Row(children: [
                            Icon(Icons.report, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Report')
                          ])),
                    ],
                    onSelected: (v) {
                      if (v == 'report') _showReportDialog();
                    },
                  ),
                ],
              ],
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final top = MediaQuery.of(context).padding.top;
                  final t =
                      ((constraints.biggest.height - kToolbarHeight - top) /
                              (coverHeight - kToolbarHeight))
                          .clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      FlexibleSpaceBar(
                        background: BannerDisplay(
                          enableAnimations: true,
                          bannerData: _normalizedBannerData(
                                profile.bannerData,
                                fallbackName: profile.companyName,
                              ) ??
                              {
                                'type': 'text',
                                'text': _displayNameUpper(
                                  profile.companyName,
                                  fallback: 'Company',
                                ),
                                'fontKey': 'default',
                                'textColor': 0xFFFFFFFF,
                                'fontSize': 28.0,
                                'animation': 'none',
                              },
                          defaultColors: coverColors,
                          height: coverHeight,
                        ),
                      ),
                      if (isOwnProfile)
                        Positioned(
                          top: top + 4,
                          right: 12,
                          child: GestureDetector(
                            onTap: _openBannerEditor,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      if (t > 0.05)
                        Positioned(
                          bottom: -(avatarRadius + avatarBorder),
                          left: 20,
                          child: Opacity(
                            opacity: t,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: coverColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: coverColors.last
                                        .withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(avatarBorder),
                              child: CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: Colors.white,
                                child: UniversalAvatar(
                                  avatarConfig: _profile?.avatarConfig ??
                                      _customerProfile?.avatarConfig ??
                                      _companyProfile?.avatarConfig ??
                                      _userData?.avatarConfig,
                                  photoUrl: imageUrl,
                                  fallbackName: profile.companyName,
                                  radius: avatarRadius - 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // â”€â”€ Identity: company name + details â”€â”€
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    20, avatarRadius + avatarBorder + 12, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name centered under avatar
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 2 * (avatarRadius + avatarBorder),
                            child: Text(
                              _displayNameUpper(
                                profile.companyName,
                                fallback: 'Company',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1A2E),
                                  letterSpacing: 1.2),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: coverColors),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.business_rounded,
                                    size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  profile.industry.isNotEmpty
                                      ? profile.industry
                                      : 'Company',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (locationText.isNotEmpty) ...[
                                const Icon(Icons.location_on_rounded,
                                    size: 14, color: Color(0xFF1E88E5)),
                                const SizedBox(width: 3),
                                Text(locationText,
                                    style: const TextStyle(
                                        color: Color(0xFF777788),
                                        fontSize: 13)),
                                const SizedBox(width: 8),
                              ],
                              if (profile.isVerified)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient:
                                        LinearGradient(colors: coverColors),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded,
                                          size: 11, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Verified',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Stats row
                          Row(
                            children: [
                              _miniStat(profile.rating.toStringAsFixed(1),
                                  'Rating', Icons.star_rounded, Colors.amber),
                              const SizedBox(width: 16),
                              _miniStat(
                                  profile.reviewCount.toString(),
                                  'Reviews',
                                  Icons.reviews_rounded,
                                  const Color(0xFF2196F3)),
                              const SizedBox(width: 16),
                              _miniStat(
                                  profile.assignedProjects.length.toString(),
                                  'Projects',
                                  Icons.work_rounded,
                                  const Color(0xFF4CAF50)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action button
                    if (isOwnProfile)
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CompanySetupScreen(
                                      userId: widget.userId)));
                          _loadProfile();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: coverColors),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      coverColors.last.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Edit',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () async {
                          final nav = Navigator.of(context);
                          try {
                            final cu = FirebaseAuth.instance.currentUser;
                            if (cu == null) return;
                            final cuData =
                                await _firestoreService.getUserById(cu.uid);
                            if (cuData == null || _userData == null) return;
                            if (!mounted) return;
                            showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(
                                    child: CircularProgressIndicator()));
                            final chatId = await _chatService.getOrCreateChat(
                              cu.uid,
                              widget.userId,
                              {
                                'name': cuData.name,
                                'profilePhoto': cuData.profilePhoto
                              },
                              {
                                'name': _userData!.name,
                                'profilePhoto': _userData!.profilePhoto
                              },
                            );
                            final safeChatId = await _chatService
                                .resolveAccessibleDirectChatId(
                              preferredChatId: chatId,
                              currentUserId: cu.uid,
                              otherUserId: widget.userId,
                            );
                            if (!mounted) return;
                            nav.pop();
                            nav.push(MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                    chatId: safeChatId,
                                    otherUserId: widget.userId,
                                    otherUserName: _userData!.name,
                                    otherUserPhoto: _userData!.profilePhoto)));
                          } catch (e) {
                            if (!mounted) return;
                            nav.pop();
                            AppDialog.error(context, 'Error starting chat',
                                detail: e.toString());
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF2979FF), Color(0xFF00B0FF)]),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFF2979FF)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_rounded,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Text('Message',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _buildContactVisibilitySection(coverColors),
            ),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 72,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // About
            if (profile.description.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('About', Icons.info_outline_rounded,
                          coverColors.first),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Text(profile.description,
                            style: const TextStyle(
                                fontSize: 14,
                                height: 1.65,
                                color: Color(0xFF444466))),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            // Company details info cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('Company Details', Icons.business_rounded,
                        coverColors.last),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: Column(
                        children: [
                          if (profile.website != null &&
                              profile.website!.isNotEmpty)
                            _companyDetailRow(Icons.language_rounded, 'Website',
                                profile.website!, const Color(0xFF2196F3)),
                          if (profile.headOfficeLocation != null &&
                              profile.headOfficeLocation!.isNotEmpty)
                            _companyDetailRow(
                                Icons.location_city_rounded,
                                'Head Office',
                                profile.headOfficeLocation!,
                                const Color(0xFF9C27B0)),
                          if (profile.employeeCount != null &&
                              profile.employeeCount!.isNotEmpty)
                            _companyDetailRow(
                                Icons.people_rounded,
                                'Team Size',
                                '${profile.employeeCount} employees',
                                const Color(0xFF4CAF50)),
                          if (profile.gstNumber != null &&
                              profile.gstNumber!.isNotEmpty)
                            _companyDetailRow(Icons.badge_rounded, 'GST Number',
                                profile.gstNumber!, Colors.orange),
                          if (profile.website == null &&
                              profile.headOfficeLocation == null &&
                              profile.employeeCount == null &&
                              profile.gstNumber == null)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No details added yet',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Assigned Projects
            if (profile.assignedProjects.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(
                          'Projects', Icons.folder_rounded, coverColors.first),
                      ...profile.assignedProjects
                          .map((p) => _buildProjectCard(p)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 88,
              ),
              sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _companyDetailRow(
      IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w500)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    final title = (project['title'] as String?) ?? 'Unnamed Project';
    final description = (project['description'] as String?) ?? '';
    final status = (project['status'] as String?) ?? 'accepted';
    final assignedAt = (project['assignedAt'] as String?) ?? '';

    List<Color> statusGradient;
    IconData statusIcon;
    switch (status) {
      case 'completed':
        statusGradient = [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'accepted':
        statusGradient = [const Color(0xFF2E7D32), const Color(0xFF66BB6A)];
        statusIcon = Icons.assignment_turned_in_rounded;
        break;
      default:
        statusGradient = [const Color(0xFFE65100), const Color(0xFFFFB74D)];
        statusIcon = Icons.pending_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.trim().isEmpty
                        ? 'Pending'
                        : status.trim()[0].toUpperCase() +
                            status.trim().substring(1),
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF777799), height: 1.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (assignedAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 11, color: Color(0xFFBBBBCC)),
                  const SizedBox(width: 4),
                  Text(
                    'Assigned: $assignedAt',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFFBBBBCC)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          images: _profile!.portfolioImages,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// Fullscreen Image Viewer
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / ${widget.images.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              // Share the image URL (opens system share sheet which includes save option)
              Share.share(
                widget.images[_currentIndex],
                subject: 'Portfolio Image',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Share.share(widget.images[_currentIndex]);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return Center(
            child: index == _currentIndex
                ? Hero(
                    tag: 'portfolio_$index',
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: WebImageLoader.loadImage(
                        imageUrl: widget.images[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: WebImageLoader.loadImage(
                      imageUrl: widget.images[index],
                      fit: BoxFit.contain,
                    ),
                  ),
          );
        },
      ),
      bottomNavigationBar: widget.images.length > 1
          ? Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
