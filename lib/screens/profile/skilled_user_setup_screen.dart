import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/skilled_user_profile.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../utils/user_roles.dart';
import '../../services/cloudinary_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_popup.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/universal_avatar.dart';
import '../../utils/web_image_loader.dart';
import '../../screens/avatar/avatar_builder_screen.dart';
import '../../services/biometric_service.dart';
import '../main_navigation.dart';

class SkilledUserSetupScreen extends StatefulWidget {
  final String userId;
  final bool isEditing;

  const SkilledUserSetupScreen({
    super.key,
    required this.userId,
    this.isEditing = false,
  });

  @override
  State<SkilledUserSetupScreen> createState() => _SkilledUserSetupScreenState();
}

class _SkilledUserSetupScreenState extends State<SkilledUserSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _skillController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _customCategoryController = TextEditingController();
  final _locationController = TextEditingController();
  final _shopNameController = TextEditingController();
  final List<TextEditingController> _credentialLinkControllers =
      <TextEditingController>[TextEditingController()];
  final ImagePicker _picker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final FirestoreService _firestoreService = FirestoreService();

  String? _selectedCategory;
  List<String> _skills = [];
  List<String> _skillSuggestions = []; // Global skill suggestions
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isVerified = false;
  bool _isVerifying = false; // Separate flag for verification
  String _verificationStatus = 'pending';
  String _uploadStatusMessage = 'Saving profile...';
  String _visibility = 'private';

  // Image variables
  File? _profileImage;
  Uint8List? _profileImageBytes;
  String? _profileImageUrl;
  Map<String, dynamic>? _avatarConfig;
  final List<File> _portfolioImages = [];
  final List<Uint8List> _portfolioImageBytes = [];
  List<String> _portfolioImageUrls = [];

  final List<String> _categories = [
    'Home Baking',
    'Handicrafts',
    'Content Creation',
    'Beauty & Wellness',
    'Carpentry',
    'Tailoring',
    'Photography',
    'Videography',
    'Editing',
    ...AppConstants.categories.where((c) => ![
          'Home Baking',
          'Handicrafts',
          'Content Creation',
          'Beauty & Wellness',
          'Carpentry',
          'Tailoring',
          'Photography',
          'Videography',
          'Editing',
          'Other'
        ].contains(c)),
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    await userProvider.loadProfile(widget.userId);

    if (userProvider.currentProfile != null) {
      final profile = userProvider.currentProfile!;
      _bioController.text = profile.bio;
      _locationController.text = profile.address ?? '';

      // Handle custom category - if not in list, set as Other + custom
      if (profile.category != null && !_categories.contains(profile.category)) {
        _selectedCategory = 'Other';
        _customCategoryController.text = profile.category!;
      } else {
        _selectedCategory = profile.category;
      }

      _skills = List.from(profile.skills);
      _visibility = profile.visibility;
      _profileImageUrl = profile.profilePicture;
      _avatarConfig = profile.avatarConfig;
      _portfolioImageUrls = List.from(profile.portfolioImages);
      _isVerified = profile.isVerified;
      _verificationStatus = profile.verificationStatus;

      // Load Aadhaar if exists
      if (profile.verificationData != null &&
          profile.verificationData!['aadhaarNumber'] != null) {
        _aadhaarController.text = profile.verificationData!['aadhaarNumber'];
      }
    }

    try {
      final credentialLinks = await _firestoreService
          .getPrivateSkilledCredentialLinks(widget.userId);
      _seedCredentialControllers(credentialLinks);
    } catch (e) {
      debugPrint('Error loading private credential links: $e');
    }

    // Load global skill suggestions
    try {
      _skillSuggestions = await _firestoreService.getCustomSkills();
    } catch (e) {
      debugPrint('Error loading skill suggestions: $e');
    }

    // Load shop name (only relevant when editing)
    if (widget.isEditing) {
      try {
        final shopSettings =
            await _firestoreService.getShopSettings(widget.userId);
        _shopNameController.text = shopSettings['shopName'] as String? ?? '';
      } catch (e) {
        debugPrint('Error loading shop settings: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _bioController.dispose();
    _skillController.dispose();
    _aadhaarController.dispose();
    _customCategoryController.dispose();
    _locationController.dispose();
    _shopNameController.dispose();
    for (final controller in _credentialLinkControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedCredentialControllers(List<String> links) {
    for (final controller in _credentialLinkControllers) {
      controller.dispose();
    }
    _credentialLinkControllers
      ..clear()
      ..addAll(
        (links.isEmpty ? const <String>[''] : links)
            .map((link) => TextEditingController(text: link)),
      );
  }

  List<String> _readCredentialLinks() {
    return _credentialLinkControllers
        .map((controller) => controller.text.trim())
        .where((link) => link.isNotEmpty)
        .toList();
  }

  void _addCredentialField() {
    setState(() {
      _credentialLinkControllers.add(TextEditingController());
    });
  }

  void _removeCredentialField(int index) {
    if (_credentialLinkControllers.length == 1) {
      _credentialLinkControllers.first.clear();
      setState(() {});
      return;
    }
    final controller = _credentialLinkControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  void _addSkill([String? skillName]) {
    final skill = (skillName ?? _skillController.text).trim();
    if (skill.isNotEmpty && !_skills.contains(skill)) {
      setState(() {
        _skills.add(skill);
        _skillController.clear();
      });
      // Add to global suggestions in background
      _firestoreService.addCustomSkill(skill);
      // Add to local suggestions list so it appears immediately
      if (!_skillSuggestions
          .any((s) => s.toLowerCase() == skill.toLowerCase())) {
        _skillSuggestions.add(skill);
      }
    }
  }

  void _removeSkill(String skill) {
    setState(() {
      _skills.remove(skill);
    });
  }

  // Image picking methods
  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      // User cancelled - do nothing
      if (image == null) return;

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _profileImageBytes = bytes;
          _profileImage = null;
          _avatarConfig = null;
        });
      } else {
        setState(() {
          _profileImage = File(image.path);
          _profileImageBytes = null;
          _avatarConfig = null;
        });
      }
    } on Exception catch (e) {
      // Only show error for actual errors, not cancellations
      if (mounted &&
          e.toString().isNotEmpty &&
          !e.toString().contains('cancel')) {
        AppDialog.error(context, 'Error picking image', detail: e.toString());
      }
    }
  }

  Future<void> _pickPortfolioImages() async {
    try {
      if ((kIsWeb ? _portfolioImageBytes.length : _portfolioImages.length) +
              _portfolioImageUrls.length >=
          10) {
        AppDialog.info(context, 'Maximum 10 portfolio images allowed',
            title: 'Limit Reached');
        return;
      }

      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      // User cancelled - do nothing
      if (images.isEmpty) return;

      final remaining =
          10 - (_portfolioImages.length + _portfolioImageUrls.length);
      if (kIsWeb) {
        final selected = images.take(remaining).toList();
        final bytesList = <Uint8List>[];
        for (final img in selected) {
          bytesList.add(await img.readAsBytes());
        }
        setState(() {
          _portfolioImageBytes.addAll(bytesList);
        });
      } else {
        setState(() {
          _portfolioImages.addAll(
            images.take(remaining).map((img) => File(img.path)),
          );
        });
      }
    } on Exception catch (e) {
      // Only show error for actual errors, not cancellations
      if (mounted &&
          e.toString().isNotEmpty &&
          !e.toString().contains('cancel')) {
        AppDialog.error(context, 'Error picking images', detail: e.toString());
      }
    }
  }

  void _removePortfolioImage(int index) {
    setState(() {
      if (kIsWeb) {
        _portfolioImageBytes.removeAt(index);
      } else {
        _portfolioImages.removeAt(index);
      }
    });
  }

  void _removePortfolioUrl(int index) {
    setState(() {
      _portfolioImageUrls.removeAt(index);
    });
  }

  bool _isDiceBearAvatarConfig(Map<String, dynamic>? config) {
    return config?['type']?.toString() == 'dicebear';
  }

  bool _isEmojiAvatarConfig(Map<String, dynamic>? config) {
    return config?['type']?.toString() == 'emoji';
  }

  Future<void> _pickEmojiAvatar() async {
    final currentAvatar = _isEmojiAvatarConfig(_avatarConfig)
        ? _avatarConfig!['avatarKey']?.toString()
        : null;
    final avatarKey = await AvatarPickerSheet.show(
      context,
      currentAvatar: currentAvatar,
    );
    if (!mounted || avatarKey == null) return;

    setState(() {
      if (avatarKey == 'remove_avatar') {
        _avatarConfig = null;
      } else {
        _avatarConfig = {
          'type': 'emoji',
          'avatarKey': avatarKey,
        };
        _profileImage = null;
        _profileImageBytes = null;
        _profileImageUrl = null;
      }
    });
  }

  Future<void> _pickAnimatedAvatar() async {
    final config = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarBuilderScreen(
          initialConfig:
              _isDiceBearAvatarConfig(_avatarConfig) ? _avatarConfig : null,
        ),
      ),
    );
    if (!mounted || config == null) return;

    setState(() {
      _avatarConfig = config as Map<String, dynamic>;
      _profileImage = null;
      _profileImageBytes = null;
      _profileImageUrl = null;
    });
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                _pickProfileImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickProfileImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _maskAadhaar(String aadhaar) {
    if (aadhaar.length < 4) return aadhaar;
    return 'XXXX XXXX ${aadhaar.substring(aadhaar.length - 4)}';
  }

  bool _validateAadhaar(String aadhaar) {
    // Remove spaces and check if it’s 12 digits
    final cleanAadhaar = aadhaar.replaceAll(' ', '');
    return cleanAadhaar.length == 12 && int.tryParse(cleanAadhaar) != null;
  }

  /// Step 1 — validate Aadhaar, generate random OTP, show dialog
  Future<void> _verifyAadhaar() async {
    final aadhaar = _aadhaarController.text.trim().replaceAll(' ', '');

    if (aadhaar.isEmpty) {
      AppDialog.info(context, 'Please enter your Aadhaar number');
      return;
    }

    if (!_validateAadhaar(aadhaar)) {
      AppDialog.info(context, 'Invalid Aadhaar number. Must be 12 digits');
      return;
    }

    setState(() => _isVerifying = true);

    // Simulate network call to send OTP
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _isVerifying = false);

    // Generate a random 6-digit OTP
    final generatedOtp = (100000 + Random().nextInt(900000)).toString();

    _showOtpDialog(aadhaar, generatedOtp);
  }

  /// Step 2 — OTP dialog with simulated SMS auto-fill
  void _showOtpDialog(String aadhaar, String generatedOtp) {
    final maskedAadhaar = _maskAadhaar(aadhaar);
    final otpController = TextEditingController();
    bool isVerifying = false;
    bool isAutoFilling = true; // starts in "reading SMS" state
    bool autoFilled = false;
    String? otpError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Kick off auto-fill simulation once
          if (isAutoFilling && !autoFilled) {
            autoFilled = true;
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (ctx.mounted) {
                // Type OTP character by character
                int i = 0;
                void typeNext() {
                  if (i <= generatedOtp.length && ctx.mounted) {
                    setDialogState(() {
                      otpController.text = generatedOtp.substring(0, i);
                      if (i == generatedOtp.length) isAutoFilling = false;
                    });
                    if (i < generatedOtp.length) {
                      i++;
                      Future.delayed(
                          const Duration(milliseconds: 80), typeNext);
                    }
                  }
                }

                i = 1;
                typeNext();
              }
            });
          }

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9C27B0).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.message_rounded,
                      color: Color(0xFF9C27B0), size: 30),
                ),
                const SizedBox(height: 10),
                const Text('OTP Verification',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                    children: [
                      const TextSpan(
                          text:
                              'An OTP has been sent to the mobile\nnumber linked with Aadhaar '),
                      TextSpan(
                        text: maskedAadhaar,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // SMS auto-fill status banner
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isAutoFilling
                      ? Container(
                          key: const ValueKey('reading'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Reading SMS...',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.blue)),
                            ],
                          ),
                        )
                      : Container(
                          key: const ValueKey('filled'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 14, color: Colors.green.shade600),
                              const SizedBox(width: 6),
                              Text('OTP auto-filled from SMS',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  readOnly: isAutoFilling,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '------',
                    counterText: '',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF9C27B0), width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: !isAutoFilling
                            ? const Color(0xFF9C27B0)
                            : Colors.grey.shade300,
                        width: !isAutoFilling ? 2 : 1,
                      ),
                    ),
                    errorText: otpError,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isVerifying ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (isVerifying || isAutoFilling)
                    ? null
                    : () async {
                        final otp = otpController.text.trim();
                        if (otp != generatedOtp) {
                          setDialogState(() => otpError = 'Incorrect OTP');
                          return;
                        }
                        setDialogState(() {
                          isVerifying = true;
                          otpError = null;
                        });
                        Navigator.pop(ctx);
                        await _runBiometricStep(aadhaar);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C27B0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : isAutoFilling
                        ? const Text('Please wait...',
                            style: TextStyle(color: Colors.white70))
                        : const Text('Verify & Continue',
                            style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Step 3 — biometric scan, then mark verification submitted for review
  Future<void> _runBiometricStep(String aadhaar) async {
    // Show biometric prompt dialog while waiting
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _BiometricWaitDialog(),
      );
    }

    final result = await BiometricService.authenticate(
      reason: 'Scan your fingerprint to complete Aadhaar verification',
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close wait dialog
    }
    if (!mounted) return;

    if (result == BiometricResult.success) {
      setState(() {
        _isVerified = false;
        _verificationStatus = 'submitted';
      });
      AppDialog.success(
        context,
        'Identity checks completed. Your verification request is submitted for admin approval.',
      );
    } else {
      AppDialog.error(context, BiometricService.resultMessage(result));
    }
  }

  Future<void> _saveProfile() async {
    if (_isUploading) return;

    if (!_formKey.currentState!.validate()) {
      AppPopup.show(
        context,
        message: 'Please complete all required fields before saving.',
        type: PopupType.warning,
      );
      return;
    }

    if (_selectedCategory == null) {
      AppDialog.info(context, 'Please select a category');
      return;
    }

    // Resolve actual category name (handle "Other" → custom text)
    String finalCategory = _selectedCategory!;
    if (_selectedCategory == 'Other') {
      final custom = _customCategoryController.text.trim();
      if (custom.isEmpty) {
        AppDialog.info(context, 'Please enter your custom category');
        return;
      }
      finalCategory = custom;
    }

    if (_skills.isEmpty) {
      AppDialog.info(context, 'Please add at least one skill');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatusMessage = 'Saving profile...';
    });

    final nav = Navigator.of(context);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentProfile = userProvider.currentProfile;
      final requestedCredentialLinks = _readCredentialLinks();

      String? finalProfileUrl = _profileImageUrl;
      List<String> finalPortfolioUrls = List.from(_portfolioImageUrls);

      // Upload profile image if selected
      if (_profileImage != null || _profileImageBytes != null) {
        if (mounted) {
          setState(() => _uploadStatusMessage = 'Uploading profile photo...');
        }
        if (kIsWeb && _profileImageBytes != null) {
          finalProfileUrl = await _cloudinaryService.uploadImageBytes(
            _profileImageBytes!,
            folder: 'profiles',
          );
        } else if (_profileImage != null) {
          finalProfileUrl = await _cloudinaryService.uploadImage(
            _profileImage!,
            folder: 'profiles',
          );
        }
      }

      // Upload portfolio images if selected
      if (_portfolioImages.isNotEmpty || _portfolioImageBytes.isNotEmpty) {
        if (mounted) {
          setState(
              () => _uploadStatusMessage = 'Uploading portfolio images...');
        }
        if (kIsWeb) {
          for (final bytes in _portfolioImageBytes) {
            final url = await _cloudinaryService.uploadImageBytes(
              bytes,
              folder: 'portfolios',
            );
            if (url != null) {
              finalPortfolioUrls.add(url);
            }
          }
        } else {
          for (var image in _portfolioImages) {
            final url = await _cloudinaryService.uploadImage(
              image,
              folder: 'portfolios',
            );
            if (url != null) {
              finalPortfolioUrls.add(url);
            }
          }
        }
      }

      // Prepare verification data
      final verificationData = Map<String, dynamic>.from(
        currentProfile?.verificationData ?? const <String, dynamic>{},
      );
      if (_aadhaarController.text.isNotEmpty) {
        verificationData.addAll({
          'aadhaarNumber': _aadhaarController.text.trim().replaceAll(' ', ''),
          'maskedAadhaar': _maskAadhaar(_aadhaarController.text.trim()),
          'verifiedAt': _isVerified ? DateTime.now().toIso8601String() : null,
        });
      }

      if (mounted) {
        setState(() => _uploadStatusMessage = 'Saving to database...');
      }

      // Get user name to denormalize into skilled_users collection
      final userName = authProvider.currentUser?.name;

      // Determine effective profile picture URL - never write empty string
      final String? effectiveProfileUrl;
      if (_avatarConfig != null) {
        effectiveProfileUrl = null;
      } else if (finalProfileUrl != null && finalProfileUrl.isNotEmpty) {
        effectiveProfileUrl = finalProfileUrl;
      } else if (_profileImage == null &&
          _profileImageBytes == null &&
          currentProfile?.profilePicture != null &&
          currentProfile!.profilePicture!.isNotEmpty) {
        effectiveProfileUrl = currentProfile.profilePicture;
      } else {
        effectiveProfileUrl = null;
      }

      final profile = SkilledUserProfile(
        userId: widget.userId,
        name: userName,
        bio: _bioController.text.trim(),
        skills: _skills,
        category: finalCategory,
        profilePicture: effectiveProfileUrl,
        verificationStatus: _verificationStatus,
        visibility: widget.isEditing
            ? _visibility
            : (_isVerified
                ? AppConstants.visibilityPublic
                : AppConstants.visibilityPrivate),
        portfolioImages: finalPortfolioUrls,
        portfolioVideos: currentProfile?.portfolioVideos ?? [],
        verificationData: verificationData.isEmpty ? null : verificationData,
        address: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        rating: currentProfile?.rating ?? 0.0,
        reviewCount: currentProfile?.reviewCount ?? 0,
        projectCount: currentProfile?.projectCount ?? 0,
        companyEndorsementCount: currentProfile?.companyEndorsementCount ?? 0,
        isVerified: _isVerified,
        verifiedAt: _isVerified ? (currentProfile?.verifiedAt ?? DateTime.now()) : null,
        avatarConfig: _avatarConfig,
        createdAt: currentProfile?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final success = await userProvider.updateProfile(profile);
      List<String> validCredentialLinks = const <String>[];
      if (success) {
        if (requestedCredentialLinks.isNotEmpty) {
          if (mounted) {
            setState(
                () => _uploadStatusMessage = 'Checking certification links...');
          }
          try {
            validCredentialLinks =
                await _firestoreService.savePrivateSkilledCredentialLinks(
              userId: widget.userId,
              rawLinks: requestedCredentialLinks,
            );
          } catch (e) {
            debugPrint('Warning: Could not save credential links: $e');
          }
        }
        await userProvider.loadProfile(widget.userId);
      }

      if (!mounted) return;

      if (success) {
        // Save animated avatar config to users collection (or remove if cleared)
        try {
          await FirestoreService().saveAvatarConfig(widget.userId, _avatarConfig);
        } catch (e) {
          debugPrint('Warning: Could not save avatar config: $e');
        }

        // Also update user basic profile with profile photo in Firestore directly
        try {
          await FirestoreService()
              .updateUserProfilePhoto(widget.userId, effectiveProfileUrl);
          debugPrint('Profile photo saved: $effectiveProfileUrl');
        } catch (e) {
          debugPrint('Error updating user profile photo: $e');
        }

        // Refresh AuthProvider immediately so all screens re-render with new profile data
        try {
          await authProvider.refreshUserData();
        } catch (e) {
          debugPrint('Warning: Could not refresh auth profile: $e');
        }

        // Save shop name when editing
        if (widget.isEditing && _shopNameController.text.trim().isNotEmpty) {
          try {
            await _firestoreService.updateShopSettings(widget.userId, {
              'shopName': _shopNameController.text.trim(),
            });
          } catch (e) {
            debugPrint('Error saving shop name: $e');
          }
        }

        if (!mounted) return;
        if (widget.isEditing) {
          AppPopup.show(
            context,
            message: requestedCredentialLinks.length ==
                    validCredentialLinks.length
                ? 'Profile updated successfully!'
                : 'Profile updated. Only valid certification links were saved.',
            type: PopupType.success,
          );
          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) nav.pop();
        } else {
          AppPopup.show(
            context,
            message: requestedCredentialLinks.length ==
                    validCredentialLinks.length
                ? 'Profile saved successfully!'
                : 'Profile saved. Only valid certification links were kept.',
            type: PopupType.success,
          );
          await Future.delayed(const Duration(milliseconds: 900));
          if (mounted) {
            nav.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainNavigation()),
              (route) => false,
            );
          }
        }
      } else {
        throw Exception(userProvider.error ?? 'Failed to save profile');
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Error saving profile', detail: e.toString());
      }
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
    final authProvider = Provider.of<AuthProvider>(context);
    final canUseEmojiAvatar = authProvider.userRole != UserRoles.company;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 96;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Profile' : 'Setup Profile',
            style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text(
              'Save',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF9C27B0), Color(0xFFE91E63)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Photo Section
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _showImageSourceDialog,
                          child: Stack(
                            children: [
                              _avatarConfig != null
                                  ? UniversalAvatar(
                                      avatarConfig: _avatarConfig,
                                      photoUrl: _profileImageUrl,
                                      fallbackName:
                                          _bioController.text.isNotEmpty
                                              ? _bioController.text
                                              : 'U',
                                      radius: 60,
                                    )
                                  : CircleAvatar(
                                      radius: 60,
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage: ((kIsWeb &&
                                              _profileImageBytes != null)
                                          ? MemoryImage(_profileImageBytes!)
                                          : (_profileImage != null
                                              ? FileImage(_profileImage!)
                                              : (_profileImageUrl != null &&
                                                      _profileImageUrl!
                                                          .isNotEmpty
                                                  ? WebImageLoader
                                                      .getImageProvider(
                                                          _profileImageUrl)
                                                  : null))),
                                      child: (_profileImage == null &&
                                              _profileImageBytes == null &&
                                              (_profileImageUrl == null ||
                                                  _profileImageUrl!.isEmpty))
                                          ? const Icon(Icons.person,
                                              size: 60, color: Colors.grey)
                                          : null,
                                    ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF9C27B0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to ${_profileImage != null || (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) ? 'change' : 'add'} photo',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (canUseEmojiAvatar)
                              GestureDetector(
                                onTap: _pickEmojiAvatar,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: const Color(0xFF2563EB)
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isEmojiAvatarConfig(_avatarConfig)
                                            ? Icons.emoji_emotions
                                            : Icons.emoji_emotions_outlined,
                                        color: const Color(0xFF2563EB),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isEmojiAvatarConfig(_avatarConfig)
                                            ? 'Change Emoji'
                                            : 'Choose Emoji',
                                        style: const TextStyle(
                                          color: Color(0xFF2563EB),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            GestureDetector(
                              onTap: _pickAnimatedAvatar,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9C27B0)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFF9C27B0)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.face_retouching_natural,
                                        color: Color(0xFF9C27B0), size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isDiceBearAvatarConfig(_avatarConfig)
                                          ? 'Edit Avatar'
                                          : 'Create Avatar',
                                      style: const TextStyle(
                                        color: Color(0xFF9C27B0),
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
                  const SizedBox(height: 24),

                  // ── Edit-only: Visibility + Shop Name ─────────────────
                  if (widget.isEditing) ...[
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              _visibility == 'public'
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: _visibility == 'public'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Profile Visibility',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15)),
                                  Text(
                                    _visibility == 'public'
                                        ? 'Visible to everyone'
                                        : 'Hidden from search',
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _visibility == 'public',
                              onChanged: (v) => setState(
                                  () => _visibility = v ? 'public' : 'private'),
                              activeColor: Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _shopNameController,
                      decoration: const InputDecoration(
                        labelText: 'Shop Name',
                        hintText: 'e.g., Ravi\'s Handicrafts, Priya Studio...',
                        prefixIcon: Icon(Icons.storefront),
                        helperText: 'Displayed on your product listings',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Category Selection
                  DropdownButtonFormField<String>(
                    value: _categories.contains(_selectedCategory)
                        ? _selectedCategory
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCategory = value;
                        if (value != 'Other') {
                          _customCategoryController.clear();
                        }
                      });
                    },
                    validator: (value) {
                      if (value == null) return 'Please select a category';
                      return null;
                    },
                  ),
                  // Custom category input when "Other" is selected
                  if (_selectedCategory == 'Other') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customCategoryController,
                      decoration: const InputDecoration(
                        labelText: 'Your Custom Category',
                        hintText: 'e.g., Mehndi Design, Pottery, etc.',
                        prefixIcon: Icon(Icons.edit),
                      ),
                      validator: (value) {
                        if (_selectedCategory == 'Other' &&
                            (value == null || value.trim().isEmpty)) {
                          return 'Please enter your category';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Location
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'City, State',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bio
                  TextFormField(
                    controller: _bioController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'Tell people about yourself and your skills...',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your bio';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Skills with suggestions
                  const Text(
                    'Skills',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Type a skill or pick from suggestions below',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<String>.empty();
                            }
                            return _skillSuggestions.where((s) =>
                                s.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase()) &&
                                !_skills.contains(s));
                          },
                          onSelected: (String selection) {
                            _addSkill(selection);
                            _skillController.clear();
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            // Sync custom controller reference
                            controller.addListener(() {
                              if (_skillController.text != controller.text) {
                                _skillController.text = controller.text;
                              }
                            });
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                hintText: 'Add a skill',
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    _addSkill(controller.text);
                                    controller.clear();
                                  },
                                  icon: const Icon(Icons.add_circle,
                                      color: Color(0xFF2196F3)),
                                ),
                              ),
                              onSubmitted: (_) {
                                _addSkill(controller.text);
                                controller.clear();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _skills.map((skill) {
                      return Chip(
                        label: Text(skill),
                        onDeleted: () => _removeSkill(skill),
                        backgroundColor:
                            const Color(0xFF2196F3).withValues(alpha: 0.1),
                        labelStyle: const TextStyle(color: Color(0xFF2196F3)),
                        deleteIconColor: const Color(0xFF2196F3),
                      );
                    }).toList(),
                  ),
                  // Show suggested skills from global list
                  if (_skillSuggestions
                      .where((s) => !_skills.contains(s))
                      .isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Suggested skills:',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _skillSuggestions
                          .where((s) => !_skills.contains(s))
                          .take(10)
                          .map((skill) => ActionChip(
                                label: Text(skill,
                                    style: const TextStyle(fontSize: 12)),
                                onPressed: () {
                                  setState(() => _skills.add(skill));
                                },
                                backgroundColor: Colors.grey[100],
                                side: BorderSide(color: Colors.grey[300]!),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Portfolio Images Section
                  const Text(
                    'Portfolio Images',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Showcase your work (Max 10 images)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Display existing portfolio images
                  if (_portfolioImageUrls.isNotEmpty ||
                      _portfolioImages.isNotEmpty ||
                      _portfolioImageBytes.isNotEmpty)
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _portfolioImageUrls.length +
                            (kIsWeb
                                ? _portfolioImageBytes.length
                                : _portfolioImages.length),
                        itemBuilder: (context, index) {
                          if (index < _portfolioImageUrls.length) {
                            // Display existing URL images
                            return Stack(
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    image: DecorationImage(
                                      image: WebImageLoader.getImageProvider(
                                          _portfolioImageUrls[index])!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 16,
                                  child: GestureDetector(
                                    onTap: () => _removePortfolioUrl(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // Display newly selected images
                            final fileIndex =
                                index - _portfolioImageUrls.length;
                            return Stack(
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    image: DecorationImage(
                                      image: kIsWeb
                                          ? MemoryImage(
                                              _portfolioImageBytes[fileIndex])
                                          : FileImage(
                                                  _portfolioImages[fileIndex])
                                              as ImageProvider,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 16,
                                  child: GestureDetector(
                                    onTap: () =>
                                        _removePortfolioImage(fileIndex),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Add Portfolio Images Button
                  OutlinedButton.icon(
                    onPressed: ((kIsWeb
                                    ? _portfolioImageBytes.length
                                    : _portfolioImages.length) +
                                _portfolioImageUrls.length <
                            10)
                        ? _pickPortfolioImages
                        : null,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: Text(
                      'Add Portfolio Images (${(kIsWeb ? _portfolioImageBytes.length : _portfolioImages.length) + _portfolioImageUrls.length}/10)',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2196F3),
                      side: const BorderSide(color: Color(0xFF2196F3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Professional Credentials',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add certification or portfolio proof links if you have them. The raw links stay confidential, and viewers only see that valid credentials are on file.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 14),
                          ...List.generate(_credentialLinkControllers.length,
                              (index) {
                            final controller =
                                _credentialLinkControllers[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index ==
                                        _credentialLinkControllers.length - 1
                                    ? 0
                                    : 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: controller,
                                      keyboardType: TextInputType.url,
                                      decoration: InputDecoration(
                                        labelText:
                                            'Certification Link ${index + 1}',
                                        hintText:
                                            'https://example.com/certificate',
                                        prefixIcon:
                                            const Icon(Icons.verified_outlined),
                                      ),
                                      validator: (value) {
                                        final link = (value ?? '').trim();
                                        if (link.isEmpty) return null;
                                        final uri = Uri.tryParse(link);
                                        if (uri == null ||
                                            !uri.hasScheme ||
                                            !uri.hasAuthority ||
                                            !(uri.scheme == 'http' ||
                                                uri.scheme == 'https')) {
                                          return 'Enter a valid http/https link';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    onPressed: () =>
                                        _removeCredentialField(index),
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    color: Colors.redAccent,
                                    tooltip: 'Remove link',
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _addCredentialField,
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('Add Another Credential Link'),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lock_outline_rounded,
                                    color: Color(0xFF2E7D32), size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Only working links are saved. Customers and companies see only a trusted credential badge, not your private URLs.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1B5E20),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Verification Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Identity Verification',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Complete identity verification to make your profile visible to customers',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),

                          // Verification Status
                          if (_isVerified)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.green.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.verified,
                                          color: Colors.green, size: 22),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Identity Verified ✓',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_aadhaarController.text.trim().isNotEmpty)
                                    Text(
                                      'Aadhaar: ${_maskAadhaar(_aadhaarController.text.trim().replaceAll(' ', ''))}',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 13,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Your profile is public and visible to customers.',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            TextFormField(
                              controller: _aadhaarController,
                              decoration: InputDecoration(
                                labelText: 'Aadhaar Number',
                                hintText: '1234 5678 9012',
                                prefixIcon: const Icon(Icons.credit_card),
                                helperText: 'Enter 12-digit Aadhaar number',
                                suffixIcon: _isVerified
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green)
                                    : null,
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 14, // 12 digits + 2 spaces
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return null; // Optional field
                                }
                                if (!_validateAadhaar(value)) {
                                  return 'Invalid Aadhaar number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isVerifying ? null : _verifyAadhaar,
                                icon: _isVerifying
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.fingerprint),
                                label: Text(_isVerifying
                                    ? 'Sending OTP...'
                                    : 'Verify Identity'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Steps explanation
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0)
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Verification steps:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Color(0xFF9C27B0))),
                                  SizedBox(height: 6),
                                  _StepRow(
                                      step: '1',
                                      text: 'Enter 12-digit Aadhaar number'),
                                  SizedBox(height: 4),
                                  _StepRow(
                                      step: '2',
                                      text:
                                          'OTP auto-fills via SMS (just like real apps)'),
                                  SizedBox(height: 4),
                                  _StepRow(
                                      step: '3',
                                      text: 'Scan fingerprint / Face ID'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '✔ After verification: profile becomes public, shop & products unlocked',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading overlay
          if (_isUploading || _isVerifying)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_isVerifying
                            ? 'Verifying Aadhaar...'
                            : _uploadStatusMessage),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────
// Helper widgets
// ────────────────────────────────────────────────────────────────

class _BiometricWaitDialog extends StatelessWidget {
  const _BiometricWaitDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fingerprint,
                color: Color(0xFF4CAF50), size: 56),
          ),
          const SizedBox(height: 16),
          const Text(
            'Fingerprint Scan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Place your finger on the\nsensor to verify identity',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;

  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(right: 8, top: 1),
          decoration: const BoxDecoration(
            color: Color(0xFF9C27B0),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      ],
    );
  }
}
