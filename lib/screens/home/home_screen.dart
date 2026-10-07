import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/skilled_user_profile.dart';
import '../../models/service_request_model.dart';
import '../../utils/app_constants.dart';
import '../../utils/user_roles.dart';
import '../../utils/add_dummy_profiles.dart';
import '../../widgets/universal_avatar.dart';
import '../../widgets/expert_card.dart';
import '../../services/firestore_service.dart';
import '../../services/chat_service.dart';
import '../profile/profile_screen.dart';
import 'explore_screen.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/filter_bottom_sheet.dart';
import '../../utils/app_dialog.dart';
import '../../utils/app_helpers.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FirestoreService _firestoreService = FirestoreService();
  String _searchQuery = '';
  String? _selectedCategory;
  String _sortBy = 'rating'; // rating, reviews, projects
  bool _isGridView = false;
  bool _showFilters = false;
  bool _searchFocused = false;

  // Animated search hints
  int _hintIndex = 0;
  Timer? _hintTimer;
  static const _searchHints = [
    'Search Plumbers...',
    'Search Electricians...',
    'Search Carpenters...',
    'Search Tailors...',
    'Search Painters...',
    'Search Web Developers...',
    'Search Photographers...',
    'Search Tutors...',
  ];

  final List<String> _categories = [
    'All',
    ...AppConstants.categories,
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    });
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
        setState(() => _hintIndex = (_hintIndex + 1) % _searchHints.length);
      }
    });
    // Use addPostFrameCallback to ensure widget tree is built before loading data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await FilterBottomSheet.show(
      context,
      mode: 'experts',
      initialCategory: _selectedCategory,
      initialSortBy: _sortBy,
      initialMinRating: 0,
      initialViewMode: _isGridView ? 'grid' : 'list',
    );
    if (result == null) return;
    setState(() {
      _selectedCategory = result.category;
      _sortBy = result.sortBy ?? 'rating';
      _isGridView = result.viewMode == 'grid';
      _showFilters = false; // close inline filter if open
    });
  }

  Future<void> _loadData() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await userProvider.loadVerifiedUsers();

      // Load current user's role-specific profile to get profile photo
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        final role = currentUser.role;
        if (role == UserRoles.skilledPerson || role == 'skilled_user') {
          await userProvider.loadProfile(currentUser.uid);
        } else if (role == UserRoles.customer) {
          await userProvider.loadCustomerProfile(currentUser.uid);
        } else if (role == UserRoles.company) {
          await userProvider.loadCompanyProfile(currentUser.uid);
        }

        // Auto-sync: if users collection has no photo but role profile does, sync it
        if (currentUser.profilePhoto == null ||
            currentUser.profilePhoto!.isEmpty) {
          String? rolePhoto;
          if (userProvider.skilledProfile?.profilePicture != null &&
              userProvider.skilledProfile!.profilePicture!.isNotEmpty) {
            rolePhoto = userProvider.skilledProfile!.profilePicture;
          } else if (userProvider.customerProfile?.profilePicture != null &&
              userProvider.customerProfile!.profilePicture!.isNotEmpty) {
            rolePhoto = userProvider.customerProfile!.profilePicture;
          } else if (userProvider.companyProfile?.logoUrl != null &&
              userProvider.companyProfile!.logoUrl!.isNotEmpty) {
            rolePhoto = userProvider.companyProfile!.logoUrl;
          }

          // Last resort: try to recover photo from chat participantDetails
          if (rolePhoto == null) {
            try {
              final chatService = ChatService();
              final chatSnap = await chatService.getUserChats(currentUser.uid).first;
              for (final chat in chatSnap) {
                final details = chat.participantDetails[currentUser.uid];
                if (details != null) {
                  final p = (details['photo'] ?? '').toString().trim();
                  if (p.isNotEmpty) {
                    rolePhoto = p;
                    break;
                  }
                }
              }
            } catch (_) {}
          }

          if (rolePhoto != null) {
            try {
              await _firestoreService.updateUserProfilePhoto(
                  currentUser.uid, rolePhoto);
              final updatedUser = currentUser.copyWith(profilePhoto: rolePhoto);
              await authProvider.updateProfile(updatedUser);
              // Also sync back to role profile if missing
              if (currentUser.role == UserRoles.customer &&
                  (userProvider.customerProfile?.profilePicture == null ||
                      userProvider.customerProfile!.profilePicture!.isEmpty)) {
                try {
                  final cp = userProvider.customerProfile;
                  if (cp != null) {
                    await userProvider.updateCustomerProfile(
                        cp.copyWith(profilePicture: rolePhoto));
                  }
                } catch (_) {}
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  List<SkilledUserProfile> _getFilteredAndSortedUsers(
    List<SkilledUserProfile> users,
    String? currentUserId,
  ) {
    var filtered = users.where((profile) {
      if (currentUserId != null && profile.userId == currentUserId) {
        return false;
      }

      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          (profile.category?.toLowerCase().contains(_searchQuery) ?? false) ||
          profile.skills
              .any((skill) => skill.toLowerCase().contains(_searchQuery)) ||
          (profile.bio.toLowerCase().contains(_searchQuery));

      // Category filter
      final matchesCategory = _selectedCategory == null ||
          _selectedCategory == 'All' ||
          profile.category == _selectedCategory;

      return matchesSearch && matchesCategory;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'reviews':
          return b.reviewCount.compareTo(a.reviewCount);
        case 'projects':
          return b.projectCount.compareTo(a.projectCount);
        case 'rating':
        default:
          return b.rating.compareTo(a.rating);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);
    final currentUser = authProvider.currentUser;
    final userRole = authProvider.userRole ?? UserRoles.customer;

    // Resolve profile photo & avatar config: role-specific profile → users collection
    final rolePhoto = userProvider.skilledProfile?.profilePicture ??
        userProvider.customerProfile?.profilePicture ??
        userProvider.companyProfile?.logoUrl;
    final String? profilePhotoUrl = (rolePhoto != null && rolePhoto.isNotEmpty)
        ? rolePhoto
        : currentUser?.profilePhoto;

    final effectiveAvatarConfig = userProvider.skilledProfile?.avatarConfig ??
        userProvider.customerProfile?.avatarConfig ??
        currentUser?.avatarConfig;

    // Role-based greeting
    String greeting = 'Welcome';
    final hour = DateTime.now().hour;
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }

    // Resolve display name with multi-tier fallback:
    // 1. Firestore UserModel name (non-empty)
    // 2. FirebaseAuth displayName (non-empty)
    // 3. Email prefix from FirebaseAuth
    // 4. 'there'
    final firestoreName = (currentUser?.name ?? '').trim();
    final firebaseAuthUser = FirebaseAuth.instance.currentUser;
    final authDisplayName = (firebaseAuthUser?.displayName ?? '').trim();
    final authEmailPrefix =
        (firebaseAuthUser?.email ?? '').split('@').first.trim();
    final resolvedName = firestoreName.isNotEmpty
        ? firestoreName
        : authDisplayName.isNotEmpty
            ? authDisplayName
            : authEmailPrefix.isNotEmpty
                ? authEmailPrefix
                : 'there';

    return Scaffold(
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            slivers: [
              // Compact App Bar — title + avatar only
              SliverAppBar(
                expandedHeight: 0,
                floating: true,
                pinned: true,
                toolbarHeight: 56,
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                title: const Text(
                  'SkillShare',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20),
                ),
                actions: [
                  if (currentUser != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: NotificationBell(
                        userId: currentUser.uid,
                        color: Colors.white,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () {
                        if (currentUser != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProfileScreen(userId: currentUser.uid),
                            ),
                          );
                        }
                      },
                      child: UniversalAvatar(
                        avatarConfig: effectiveAvatarConfig,
                        photoUrl: profilePhotoUrl,
                        fallbackName: currentUser?.name ?? 'U',
                        radius: 18,
                        animate: false,
                      ),
                    ),
                  ),
                ],
              ),

              // Welcome + Search Section (always visible)
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting, ${AppHelpers.capitalize(resolvedName.split(' ').first)}!',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userRole == UserRoles.skilledPerson
                              ? 'Manage your profile and connect with clients'
                              : 'Find skilled professionals near you',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        // Animated search bar with gradient focus border + cycling hints
                        GestureDetector(
                          onTap: () => _searchFocusNode.requestFocus(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: EdgeInsets.all(_searchFocused ? 2 : 0),
                            decoration: BoxDecoration(
                              gradient: _searchFocused
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B6B),
                                        Color(0xFFFFE66D),
                                        Color(0xFF4ECDC4),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color:
                                  _searchFocused ? null : Colors.transparent,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: _searchFocused
                                      ? const Color(0xFF4ECDC4)
                                          .withValues(alpha: 0.5)
                                      : Colors.black.withValues(alpha: 0.15),
                                  blurRadius: _searchFocused ? 18 : 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                    _searchFocused ? 28 : 30),
                              ),
                              child: Row(
                                children: [
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 300),
                                    child: Icon(
                                      _searchFocused
                                          ? Icons.search
                                          : Icons.search_rounded,
                                      key: ValueKey(_searchFocused),
                                      color: _searchFocused
                                          ? const Color(0xFF6A11CB)
                                          : Colors.grey[500],
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            errorBorder: InputBorder.none,
                                            disabledBorder: InputBorder.none,
                                            filled: false,
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 14),
                                            hintText: _searchFocused
                                                ? 'Type to search...'
                                                : null,
                                            hintStyle: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        // Animated cycling hints (only when empty & unfocused)
                                        if (!_searchFocused &&
                                            _searchQuery.isEmpty)
                                          IgnorePointer(
                                            child: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 400),
                                              transitionBuilder:
                                                  (child, anim) =>
                                                      FadeTransition(
                                                opacity: anim,
                                                child: SlideTransition(
                                                  position: Tween<Offset>(
                                                    begin: const Offset(
                                                        0, 0.4),
                                                    end: Offset.zero,
                                                  ).animate(
                                                    CurvedAnimation(
                                                      parent: anim,
                                                      curve: Curves
                                                          .easeOutCubic,
                                                    ),
                                                  ),
                                                  child: child,
                                                ),
                                              ),
                                              child: Text(
                                                _searchHints[_hintIndex],
                                                key: ValueKey(_hintIndex),
                                                style: TextStyle(
                                                  color: Colors.grey[400],
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Right icon: clear or filter
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    child: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            key: const ValueKey('clear'),
                                            icon: const Icon(Icons.close,
                                                color: Colors.grey, size: 20),
                                            onPressed: () {
                                              _searchController.clear();
                                              _searchFocusNode.unfocus();
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                          )
                                        : GestureDetector(
                                            key: const ValueKey('filter'),
                                            onTap: () => _openFilterSheet(),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                gradient:
                                                    const LinearGradient(
                                                  colors: [
                                                    Color(0xFF6A11CB),
                                                    Color(0xFF2575FC),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                  Icons.tune_rounded,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Skilled Person Quick Stats Dashboard
              if (userRole == UserRoles.skilledPerson &&
                  userProvider.skilledProfile != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your Dashboard',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildStatChip(
                                Icons.star,
                                userProvider.skilledProfile!.rating
                                    .toStringAsFixed(1),
                                'Rating',
                                Colors.amber),
                            const SizedBox(width: 8),
                            _buildStatChip(
                                Icons.rate_review,
                                '${userProvider.skilledProfile!.reviewCount}',
                                'Reviews',
                                const Color(0xFF2196F3)),
                            const SizedBox(width: 8),
                            _buildStatChip(
                                Icons.work,
                                '${userProvider.skilledProfile!.projectCount}',
                                'Projects',
                                const Color(0xFF4CAF50)),
                            const SizedBox(width: 8),
                            _buildStatChip(
                                Icons.photo_library,
                                '${userProvider.skilledProfile!.portfolioImages.length}',
                                'Portfolio',
                                const Color(0xFF9C27B0)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              userProvider.skilledProfile!.visibility ==
                                      'public'
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 14,
                              color: userProvider.skilledProfile!.visibility ==
                                      'public'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Profile: ${userProvider.skilledProfile!.visibility == 'public' ? 'Public' : 'Private'}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              userProvider.skilledProfile!.isVerified
                                  ? Icons.verified
                                  : Icons.pending,
                              size: 14,
                              color: userProvider.skilledProfile!.isVerified
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              userProvider.skilledProfile!.isVerified
                                  ? 'Verified'
                                  : 'Not Verified',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                      ],
                    ),
                  ),
                ),

              // Work Requests Dashboard (Customer / Company)
              if ((userRole == UserRoles.customer ||
                      userRole == UserRoles.company) &&
                  currentUser != null)
                SliverToBoxAdapter(
                  child: StreamBuilder<List<ServiceRequestModel>>(
                    stream: _firestoreService
                        .streamUserWorkRequests(currentUser.uid),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        debugPrint(
                            'Home work requests error: ${snapshot.error}');
                        return const SizedBox.shrink();
                      }
                      final requests = snapshot.data ?? [];
                      if (requests.isEmpty) return const SizedBox.shrink();

                      final pending =
                          requests.where((r) => r.status == 'pending').length;
                      final accepted =
                          requests.where((r) => r.status == 'accepted').length;

                      return Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Work Requests',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildStatChip(
                                    Icons.hourglass_empty,
                                    '$pending',
                                    'Pending',
                                    Colors.orange),
                                const SizedBox(width: 8),
                                _buildStatChip(
                                    Icons.check_circle_outline,
                                    '$accepted',
                                    'Approved',
                                    Colors.green),
                                const SizedBox(width: 8),
                                _buildStatChip(
                                    Icons.list_alt,
                                    '${requests.length}',
                                    'Total',
                                    const Color(0xFF6A11CB)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...requests.take(2).map((req) {
                              Color statusColor;
                              switch (req.status) {
                                case 'accepted':
                                  statusColor = Colors.green;
                                  break;
                                case 'rejected':
                                  statusColor = Colors.red;
                                  break;
                                case 'completed':
                                  statusColor = Colors.blue;
                                  break;
                                default:
                                  statusColor = Colors.orange;
                              }
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: statusColor
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.work_outline,
                                        color: statusColor, size: 18),
                                  ),
                                  title: Text(
                                    req.title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    req.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      req.status.trim().isEmpty
                                          ? 'Pending'
                                          : req.status.trim()[0].toUpperCase() +
                                              req.status.trim().substring(1),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: statusColor,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 4),
                            const Divider(),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // Categories with Filter
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Categories',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ExploreScreen(
                                      initialCategory: _selectedCategory,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.explore, size: 18),
                                label: const Text('Explore All'),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  _openFilterSheet();
                                },
                                icon: Icon(
                                  _showFilters
                                      ? Icons.filter_alt
                                      : Icons.filter_alt_outlined,
                                  size: 18,
                                ),
                                label: const Text('Filters'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected = _selectedCategory == category ||
                                (_selectedCategory == null &&
                                    category == 'All');
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedCategory =
                                        category == 'All' ? null : category;
                                  });
                                },
                                selectedColor: const Color(0xFF2196F3)
                                    .withValues(alpha: 0.2),
                                checkmarkColor: const Color(0xFF2196F3),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF2196F3)
                                      : Colors.grey[700],
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Filter Options
                      if (_showFilters) ...[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sort By',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Rating'),
                                      selected: _sortBy == 'rating',
                                      onSelected: (selected) {
                                        setState(() {
                                          _sortBy = 'rating';
                                        });
                                      },
                                    ),
                                    ChoiceChip(
                                      label: const Text('Reviews'),
                                      selected: _sortBy == 'reviews',
                                      onSelected: (selected) {
                                        setState(() {
                                          _sortBy = 'reviews';
                                        });
                                      },
                                    ),
                                    ChoiceChip(
                                      label: const Text('Projects'),
                                      selected: _sortBy == 'projects',
                                      onSelected: (selected) {
                                        setState(() {
                                          _sortBy = 'projects';
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Text(
                                      'View Mode',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: Icon(
                                        Icons.view_list,
                                        color: !_isGridView
                                            ? const Color(0xFF2196F3)
                                            : Colors.grey,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isGridView = false;
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.grid_view,
                                        color: _isGridView
                                            ? const Color(0xFF2196F3)
                                            : Colors.grey,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _isGridView = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Top Rated Experts Header
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedCategory != null && _selectedCategory != 'All'
                            ? '$_selectedCategory Experts'
                            : 'Skilled Professionals',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_searchQuery.isNotEmpty || _selectedCategory != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _selectedCategory = null;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                ),
              ),

              // Experts Grid/List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: userProvider.isLoading
                    ? SliverToBoxAdapter(
                        child: Column(
                          children: List.generate(
                            3,
                            (index) => _buildShimmerCard(),
                          ),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final filteredUsers = _getFilteredAndSortedUsers(
                            userProvider.verifiedUsers,
                            currentUser?.uid,
                          );

                          if (filteredUsers.isEmpty) {
                            return SliverToBoxAdapter(
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(48),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 80,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'No results found for "$_searchQuery"'
                                            : 'No experts available',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Try adjusting your search or filters',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          if (_isGridView) {
                            return SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.75,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final profile = filteredUsers[index];
                                  return _buildGridCard(profile);
                                },
                                childCount: filteredUsers.length,
                              ),
                            );
                          } else {
                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final profile = filteredUsers[index];
                                  return ExpertCard(profile: profile);
                                },
                                childCount: filteredUsers.length,
                              ),
                            );
                          }
                        },
                      ),
              ),

              // Bottom spacing
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
      // Admin Debug Button - Remove in production
      floatingActionButton: (currentUser?.role == AppConstants.roleAdmin)
          ? FloatingActionButton.extended(
              onPressed: () async {
                final nav = Navigator.of(context);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
                await DummyDataSeeder.seedDatabase();
                if (!context.mounted) return;
                nav.pop();
                AppDialog.success(context, 'Dummy profiles added successfully!');
                _loadData(); // Reload data
              },
              icon: const Icon(Icons.add_circle),
              label: const Text('Add Dummy Data'),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }

  Widget _buildStatChip(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(SkilledUserProfile profile) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: profile.userId),
          ),
        );
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Image
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      gradient: LinearGradient(
                        colors: [Colors.blue[400]!, Colors.purple[400]!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: UniversalAvatar(
                        avatarConfig: profile.avatarConfig,
                        photoUrl: profile.profilePicture,
                        fallbackName: profile.name,
                        radius: 42,
                        animate: false,
                        borderColor: Colors.white,
                        borderWidth: 3,
                      ),
                    ),
                  ),
                  if (profile.isVerified)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(
                        Icons.verified,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppHelpers.capitalize(profile.name ?? 'Professional'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (profile.category != null)
                      Text(
                        profile.category!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          profile.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '(${profile.reviewCount})',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.work_outline,
                            size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.projectCount} projects',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
