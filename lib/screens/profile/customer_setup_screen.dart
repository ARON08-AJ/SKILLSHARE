import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/customer_profile.dart';
import '../../services/cloudinary_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/universal_avatar.dart';
import '../../screens/avatar/avatar_builder_screen.dart';
import '../main_navigation.dart';

class CustomerSetupScreen extends StatefulWidget {
  final String userId;
  final bool isEditing;

  const CustomerSetupScreen({
    super.key,
    required this.userId,
    this.isEditing = false,
  });

  @override
  State<CustomerSetupScreen> createState() => _CustomerSetupScreenState();
}

class _CustomerSetupScreenState extends State<CustomerSetupScreen> {
  static const Color _accent = Color(0xFF2563EB);
  static const Color _accentEnd = Color(0xFF7C3AED);
  static const Color _accentSoft = Color(0xFFEAF2FF);
  static const Color _accentBorder = Color(0xFFBFDBFE);
  static const Color _neutralBorder = Color(0xFFD1D9E6);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestController = TextEditingController();
  final _locationController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();

  List<String> _interests = [];
  List<String> _lookingFor = [];
  bool _isLoading = true;
  bool _isUploading = false;

  // Image variables
  File? _profileImage;
  Uint8List? _profileImageBytes; // For web
  String? _profileImageUrl;
  String? _avatarKey; // WhatsApp-style emoji avatar
  Map<String, dynamic>? _avatarConfig; // Animated avatar config

  final List<String> _serviceCategories = [
    'Home Baking',
    'Handicrafts',
    'Carpentry',
    'Plumbing',
    'Electrical',
    'Painting',
    'Tailoring',
    'Beauty & Wellness',
    'Photography',
    'Videography',
    'Content Creation',
    'Home Cleaning',
    'Gardening',
    'Tutoring',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await userProvider.loadCustomerProfile(widget.userId);

    final user = await FirestoreService().getUserById(widget.userId) ??
        authProvider.currentUser;
    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone ?? '';
    }

    if (userProvider.customerProfile != null) {
      final profile = userProvider.customerProfile!;
      _bioController.text = profile.bio;
      _interests = List.from(profile.interests);
      _lookingFor = List.from(profile.lookingFor);
      _profileImageUrl = (profile.profilePicture != null &&
              profile.profilePicture!.trim().isNotEmpty)
          ? profile.profilePicture
          : null;
      _locationController.text = profile.location ?? '';
      _avatarKey = profile.avatarKey;
      _avatarConfig = profile.avatarConfig;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _interestController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _addInterest() {
    if (_interestController.text.isNotEmpty) {
      setState(() {
        _interests.add(_interestController.text.trim());
        _interestController.clear();
      });
    }
  }

  void _removeInterest(String interest) {
    setState(() {
      _interests.remove(interest);
    });
  }

  void _toggleLookingFor(String category) {
    setState(() {
      if (_lookingFor.contains(category)) {
        _lookingFor.remove(category);
      } else {
        _lookingFor.add(category);
      }
    });
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        if (kIsWeb) {
          // For web, read as bytes
          final bytes = await image.readAsBytes();
          if (!mounted) return;
          setState(() {
            _profileImageBytes = bytes;
          });
        } else {
          // For mobile, use File
          setState(() {
            _profileImage = File(image.path);
          });
        }
      }
    } catch (e) {
      // Handle web-specific errors gracefully
      if (mounted) {
        AppDialog.success(context, 'Image selected! Click Save to upload.');
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final currentProfile = userProvider.customerProfile;

      // Upload profile picture if selected
      String? finalProfileUrl = _profileImageUrl;
      if (_profileImage != null || _profileImageBytes != null) {
        // Create temp file for web bytes
        if (kIsWeb && _profileImageBytes != null) {
          finalProfileUrl = await _cloudinaryService.uploadImageBytes(
            _profileImageBytes!,
            folder: 'customer_profiles',
          );
        } else if (_profileImage != null) {
          finalProfileUrl = await _cloudinaryService.uploadImage(
            _profileImage!,
            folder: 'customer_profiles',
          );
        }
      }

      // Determine profile picture URL - never write empty string to Firestore
      final String? effectiveProfileUrl;
      if (finalProfileUrl != null && finalProfileUrl.isNotEmpty) {
        effectiveProfileUrl = finalProfileUrl;
      } else if (currentProfile?.profilePicture != null &&
          currentProfile!.profilePicture!.isNotEmpty) {
        effectiveProfileUrl = currentProfile.profilePicture;
      } else {
        effectiveProfileUrl = null;
      }

      final profile = CustomerProfile(
        userId: widget.userId,
        bio: _bioController.text.trim(),
        interests: _interests,
        lookingFor: _lookingFor,
        profilePicture: effectiveProfileUrl,
        location: _locationController.text.trim(),
        preferredCategories: _lookingFor,
        avatarKey: _avatarKey,
        avatarConfig: _avatarConfig,
        createdAt: currentProfile?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await userProvider.updateCustomerProfile(profile);

      // Save animated avatar config to users collection
      if (_avatarConfig != null) {
        await FirestoreService().saveAvatarConfig(widget.userId, _avatarConfig);
      }

      final newName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim();
      try {
        await FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .doc(widget.userId)
            .set({
          if (newName.isNotEmpty) 'name': newName,
          'phone': newPhone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (authProvider.currentUser != null) {
          final updatedUser = authProvider.currentUser!.copyWith(
            name: newName.isNotEmpty ? newName : authProvider.currentUser!.name,
            phone: newPhone,
          );
          await authProvider.updateProfile(updatedUser);
        }
      } catch (e) {
        debugPrint('Failed to sync customer name and phone: $e');
      }

      if (effectiveProfileUrl != null) {
        try {
          await FirestoreService()
              .updateUserProfilePhoto(widget.userId, effectiveProfileUrl);

          if (authProvider.currentUser != null) {
            final updatedUser = authProvider.currentUser!.copyWith(
              profilePhoto: effectiveProfileUrl,
            );
            await authProvider.updateProfile(updatedUser);
          }
        } catch (e) {
          debugPrint('Failed to sync customer profile photo: $e');
        }
      }

      if (!mounted) return;

      AppDialog.success(context, 'Profile saved successfully!', onDismiss: () {
        if (widget.isEditing) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const MainNavigation(),
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;

      AppDialog.error(context, 'Error saving profile', detail: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bottomPad = MediaQuery.of(context).padding.bottom + 96;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            // Gradient app bar with avatar
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              stretch: true,
              backgroundColor: _accent,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_accent, _accentEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _pickProfileImage,
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: UniversalAvatar(
                                    avatarConfig: _avatarConfig,
                                    avatarKey: _avatarKey,
                                    photoUrl: _profileImageUrl,
                                    fallbackName: _bioController.text.isNotEmpty
                                        ? _bioController.text
                                        : 'U',
                                    radius: 52,
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        color: Colors.white, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final key = await AvatarPickerSheet.show(
                                    context,
                                    currentAvatar: _avatarKey,
                                  );
                                  if (key == null) return;
                                  setState(() {
                                    if (key == 'remove_avatar') {
                                      _avatarKey = null;
                                    } else {
                                      _avatarKey = key;
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.48),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.face_rounded,
                                          color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _avatarKey != null
                                            ? 'Change Emoji'
                                            : 'Use Emoji',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final config = await Navigator.push<dynamic>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AvatarBuilderScreen(
                                        initialConfig: _avatarConfig,
                                      ),
                                    ),
                                  );
                                  if (config != null) {
                                    setState(() {
                                      _avatarConfig =
                                          config as Map<String, dynamic>;
                                      _avatarKey = null;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.48),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.face_retouching_natural,
                                          color: Colors.white, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        _avatarConfig != null
                                            ? 'Edit Avatar'
                                            : 'Create Avatar',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPad + 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // About section card
                    _sectionCard(
                      title: 'About You',
                      icon: Icons.person_outline_rounded,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: _inputDeco(
                              label: 'Full Name',
                              hint: 'Enter your name',
                              icon: Icons.badge_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDeco(
                              label: 'Phone Number',
                              hint: 'Contact mobile number',
                              icon: Icons.phone_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationController,
                            decoration: _inputDeco(
                              label: 'Delivery Address / Location',
                              hint: 'House, street, area, city',
                              icon: Icons.location_on_outlined,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _bioController,
                            decoration: _inputDeco(
                              label: 'Bio',
                              hint: 'Tell us a bit about yourself...',
                              icon: Icons.info_outline,
                            ),
                            maxLines: 3,
                            maxLength: 500,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please tell us about yourself';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Interests section card
                    _sectionCard(
                      title: 'Your Interests',
                      icon: Icons.favorite_outline_rounded,
                      subtitle: 'What are you passionate about?',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _interestController,
                                  decoration: _inputDeco(
                                    label: 'Add an interest',
                                    hint: 'e.g. Cooking, Art...',
                                    icon: Icons.add_circle_outline,
                                  ),
                                  onSubmitted: (_) => _addInterest(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Material(
                                color: _accent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _addInterest,
                                  child: const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: Icon(Icons.add, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_interests.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _interests.map((interest) {
                                return Chip(
                                  label: Text(interest,
                                      style: const TextStyle(color: _accent)),
                                  deleteIcon: const Icon(Icons.close,
                                      size: 16, color: _accent),
                                  onDeleted: () => _removeInterest(interest),
                                  backgroundColor: _accentSoft,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side:
                                        const BorderSide(color: _accentBorder),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Services section card
                    _sectionCard(
                      title: 'Services You Need',
                      icon: Icons.build_outlined,
                      subtitle: 'Select the categories you\'re interested in',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _serviceCategories.map((category) {
                          final isSelected = _lookingFor.contains(category);
                          return GestureDetector(
                            onTap: () => _toggleLookingFor(category),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? _accent : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? _accent : _neutralBorder,
                                  width: 1.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: _accent.withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) ...[
                                    const Icon(Icons.check,
                                        color: Colors.white, size: 14),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    category,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF455A64),
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accent, _accentEnd],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Complete Profile',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
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

  Widget _sectionCard({
    required String title,
    required IconData icon,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _accent, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _accent),
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _neutralBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _neutralBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF5B6472)),
    );
  }
}
