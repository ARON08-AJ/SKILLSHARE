import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../screens/avatar/avatar_builder_screen.dart';
import '../../services/cloudinary_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../utils/app_helpers.dart';
import '../../utils/user_roles.dart';
import '../../utils/web_image_loader.dart';
import '../../widgets/universal_avatar.dart';
import '../delivery/delivery_screen.dart';
import '../main_navigation.dart';

class DeliveryProfileScreen extends StatefulWidget {
  final String userId;
  final bool isEditing;

  const DeliveryProfileScreen({
    super.key,
    required this.userId,
    this.isEditing = true,
  });

  @override
  State<DeliveryProfileScreen> createState() => _DeliveryProfileScreenState();
}

class _DeliveryProfileScreenState extends State<DeliveryProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _licenseNumberController = TextEditingController();

  String _vehicleType = 'Motorcycle';
  final List<String> _vehicleTypes = [
    'Motorcycle',
    'Scooter',
    'Bicycle',
    'Car',
    'Van',
    'Auto-Rickshaw',
  ];

  StreamSubscription<UserModel?>? _userSub;
  UserModel? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasSeededForm = false;

  File? _profileImage;
  Uint8List? _profileImageBytes;
  String? _profilePhotoUrl;
  Map<String, dynamic>? _avatarConfig;

  // Verification ID Document
  File? _docImage;
  Uint8List? _docImageBytes;
  String? _documentUrl;

  bool get _isCurrentUser =>
      FirebaseAuth.instance.currentUser?.uid == widget.userId;

  @override
  void initState() {
    super.initState();
    _userSub = _firestoreService.streamUserModel(widget.userId).listen(
      (user) {
        if (!mounted) return;
        setState(() {
          _user = user;
          if (user != null && !_hasSeededForm) {
            _seedForm(user);
          }
          _isLoading = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      },
    );
  }

  void _seedForm(UserModel user) {
    final verifData = user.verificationData ?? const {};
    _nameController.text = user.name;
    _phoneController.text = user.phone ?? '';
    _profilePhotoUrl = user.profilePhoto;
    _avatarConfig = user.avatarConfig;

    _cityController.text = user.operatingCity ??
        (verifData['operatingCity'] as String?) ??
        '';
    _vehicleNumberController.text = user.vehicleNumber ??
        (verifData['vehicleNumber'] as String?) ??
        '';
    _licenseNumberController.text = user.licenseNumber ??
        (verifData['licenseNumber'] as String?) ??
        '';
    final vType = user.vehicleType ?? (verifData['vehicleType'] as String?);
    if (vType != null && _vehicleTypes.contains(vType)) {
      _vehicleType = vType;
    }
    _documentUrl = user.documentUrl ?? (verifData['documentUrl'] as String?);

    _hasSeededForm = true;
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _vehicleNumberController.dispose();
    _licenseNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _profileImageBytes = bytes;
          _profileImage = null;
        });
      } else {
        setState(() {
          _profileImage = File(image.path);
          _profileImageBytes = null;
        });
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Image selection failed',
            detail: e.toString());
      }
    }
  }

  Future<void> _pickDocumentImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        if (!mounted) return;
        setState(() {
          _docImageBytes = bytes;
          _docImage = null;
        });
      } else {
        setState(() {
          _docImage = File(image.path);
          _docImageBytes = null;
        });
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Document selection failed',
            detail: e.toString());
      }
    }
  }

  Future<void> _openAvatarBuilder() async {
    if (_user == null) return;

    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarBuilderScreen(initialConfig: _avatarConfig),
      ),
    );

    if (!mounted || result == null) return;
    setState(() {
      _avatarConfig = Map<String, dynamic>.from(result as Map);
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_user == null) return;

    // If not verified, make sure ID document is provided
    if (!_user!.isFullyVerified &&
        (_documentUrl == null || _documentUrl!.isEmpty) &&
        _docImage == null &&
        _docImageBytes == null) {
      AppDialog.info(
        context,
        'Please upload a photo of your Driving License or Government ID document to complete verification.',
        title: 'ID Document Required',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authProvider = context.read<app_auth.AuthProvider>();
      String? finalProfileUrl = _profilePhotoUrl;
      String? finalDocUrl = _documentUrl;

      // Upload profile image if picked
      if (_profileImageBytes != null || _profileImage != null) {
        if (kIsWeb && _profileImageBytes != null) {
          finalProfileUrl = await _cloudinaryService.uploadImageBytes(
            _profileImageBytes!,
            folder: 'delivery_profiles',
          );
        } else if (_profileImage != null) {
          finalProfileUrl = await _cloudinaryService.uploadImage(
            _profileImage!,
            folder: 'delivery_profiles',
          );
        }
      }

      // Upload ID document if picked
      if (_docImageBytes != null || _docImage != null) {
        if (kIsWeb && _docImageBytes != null) {
          finalDocUrl = await _cloudinaryService.uploadImageBytes(
            _docImageBytes!,
            folder: 'delivery_verification',
          );
        } else if (_docImage != null) {
          finalDocUrl = await _cloudinaryService.uploadImage(
            _docImage!,
            folder: 'delivery_verification',
          );
        }
      }

      final isAlreadyVerified = _user!.isFullyVerified;
      final newVerifStatus = isAlreadyVerified ? 'approved' : 'submitted';

      final verificationPayload = <String, dynamic>{
        'vehicleType': _vehicleType,
        'vehicleNumber': _vehicleNumberController.text.trim(),
        'licenseNumber': _licenseNumberController.text.trim(),
        'operatingCity': _cityController.text.trim(),
        if (finalDocUrl != null) 'documentUrl': finalDocUrl,
        'submittedAt': DateTime.now().toIso8601String(),
        'status': newVerifStatus,
      };

      final updateMap = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'operatingCity': _cityController.text.trim(),
        'vehicleType': _vehicleType,
        'vehicleNumber': _vehicleNumberController.text.trim(),
        'licenseNumber': _licenseNumberController.text.trim(),
        if (finalProfileUrl != null) 'profilePhoto': finalProfileUrl,
        if (finalDocUrl != null) 'documentUrl': finalDocUrl,
        'verificationData': verificationPayload,
        'verificationStatus': newVerifStatus,
        'isVerified': isAlreadyVerified,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(widget.userId)
          .set(updateMap, SetOptions(merge: true));

      if (_avatarConfig != null) {
        await _firestoreService.saveAvatarConfig(widget.userId, _avatarConfig!);
      }

      // Update AuthProvider current user model
      final currentUser = authProvider.currentUser ?? _user!;
      final updatedUser = currentUser.copyWith(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        profilePhoto: finalProfileUrl,
        avatarConfig: _avatarConfig,
        operatingCity: _cityController.text.trim(),
        vehicleType: _vehicleType,
        vehicleNumber: _vehicleNumberController.text.trim(),
        licenseNumber: _licenseNumberController.text.trim(),
        documentUrl: finalDocUrl,
        verificationStatus: newVerifStatus,
        isVerified: isAlreadyVerified,
        verificationData: verificationPayload,
      );
      await authProvider.updateProfile(updatedUser);

      if (!mounted) return;

      setState(() {
        _profilePhotoUrl = finalProfileUrl;
        _documentUrl = finalDocUrl;
        _profileImage = null;
        _profileImageBytes = null;
        _docImage = null;
        _docImageBytes = null;
      });

      if (!widget.isEditing) {
        await AppDialog.success(
          context,
          'Your profile and verification documents have been submitted to Admin for review. You can now explore the app while verification is pending.',
          title: 'Verification Submitted',
          buttonText: 'Continue to App',
          onDismiss: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainNavigation()),
            );
          },
        );
      } else {
        AppDialog.success(
          context,
          isAlreadyVerified
              ? 'Delivery profile saved successfully.'
              : 'Profile and verification documents submitted for Admin review.',
          title: isAlreadyVerified ? 'Profile Updated' : 'Verification Submitted',
          onDismiss: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(context, 'Could not save delivery profile',
          detail: e.toString());
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildHeader() {
    final user = _user;
    final displayName = AppHelpers.capitalize(user?.name ?? 'Delivery Partner');
    final roleLabel =
        UserRoles.getDisplayName(user?.role ?? UserRoles.deliveryPartner);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFFFF6B35), Color(0xFFFF8E53)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white),
                ),
              const Spacer(),
              if (_isCurrentUser)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeliveryScreen(),
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.local_shipping_rounded, size: 18),
                  label: const Text('Delivery Console'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _user?.email ?? '',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delivery_dining_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            roleLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const radius = 48.0;
    final imageWidget = _profileImageBytes != null
        ? Image.memory(
            _profileImageBytes!,
            fit: BoxFit.cover,
            width: radius * 2,
            height: radius * 2,
          )
        : _profileImage != null
            ? Image.file(
                _profileImage!,
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2,
              )
            : UniversalAvatar(
                avatarConfig: _avatarConfig,
                photoUrl: _profilePhotoUrl,
                fallbackName: _user?.name,
                radius: radius,
              );

    return GestureDetector(
      onTap: _isSaving ? null : _pickProfileImage,
      child: Container(
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ClipOval(child: imageWidget),
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF6B35),
                ),
                child: const Icon(Icons.photo_camera_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationStatusBanner() {
    final user = _user;
    final isVerified = user?.isFullyVerified == true;
    final status = (user?.verificationStatus ?? '').toLowerCase().trim();
    final isPending = !isVerified && (status == 'submitted' || status == 'pending');
    final isRejected = !isVerified && status == 'rejected';

    Color bannerColor;
    Color borderColor;
    IconData icon;
    String title;
    String subtitle;

    if (isVerified) {
      bannerColor = const Color(0xFFE8F5E9);
      borderColor = const Color(0xFFA5D6A7);
      icon = Icons.verified_rounded;
      title = 'Verified Delivery Partner';
      subtitle =
          'Your profile and documents are approved. You have full access to accept and deliver orders.';
    } else if (isPending) {
      bannerColor = const Color(0xFFE3F2FD);
      borderColor = const Color(0xFF90CAF9);
      icon = Icons.hourglass_top_rounded;
      title = 'Verification Pending Review';
      subtitle =
          'Your application is under review by our Admin team. Deliveries will be unlocked once approved.';
    } else if (isRejected) {
      bannerColor = const Color(0xFFFFEBEE);
      borderColor = const Color(0xFFEF9A9A);
      icon = Icons.cancel_rounded;
      title = 'Verification Declined';
      subtitle =
          'Reason: ${user?.rejectionReason ?? "Information or documents did not meet requirements."}\nPlease update your details and re-upload valid documents below.';
    } else {
      bannerColor = const Color(0xFFFFF3E0);
      borderColor = const Color(0xFFFFCC80);
      icon = Icons.security_rounded;
      title = 'Verification Required';
      subtitle =
          'Please submit your vehicle information and government ID/driving license below to get verified and start delivering.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: borderColor == const Color(0xFFA5D6A7) ? Colors.green[700] : (isRejected ? Colors.red[700] : const Color(0xFFE65100)), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isRejected
                        ? Colors.red[900]
                        : (isVerified ? Colors.green[900] : const Color(0xFF1A1A2E)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return StreamBuilder<List<OrderModel>>(
      stream: _firestoreService.streamDeliveryPartnerOrders(widget.userId),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <OrderModel>[];
        final total = orders.length;
        final active = orders
            .where((order) => order.status == 'out_for_delivery')
            .length;
        final delivered =
            orders.where((order) => order.status == 'delivered').length;

        return Row(
          children: [
            Expanded(child: _buildStatTile('Total Assigned', '$total')),
            const SizedBox(width: 12),
            Expanded(child: _buildStatTile('In Transit', '$active')),
            const SizedBox(width: 12),
            Expanded(child: _buildStatTile('Delivered', '$delivered')),
          ],
        );
      },
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_pin_rounded,
                    color: Color(0xFFFF6B35), size: 22),
                SizedBox(width: 8),
                Text(
                  'Personal & Contact Details',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              enabled: !_isSaving,
              decoration: _fieldDecoration(
                label: 'Full Name',
                icon: Icons.badge_rounded,
                hint: 'Your official name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your full name';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              enabled: !_isSaving,
              keyboardType: TextInputType.phone,
              decoration: _fieldDecoration(
                label: 'Phone Number',
                icon: Icons.phone_rounded,
                hint: '10-digit mobile number',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your contact phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cityController,
              enabled: !_isSaving,
              decoration: _fieldDecoration(
                label: 'Operating City / Service Area',
                icon: Icons.location_city_rounded,
                hint: 'e.g. Chennai, Bangalore, Coimbatore',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your operating city';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickProfileImage,
                  icon: const Icon(Icons.image_rounded, size: 18),
                  label: const Text('Change Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFFCCBC)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _openAvatarBuilder,
                  icon: const Icon(Icons.face_retouching_natural_rounded,
                      size: 18),
                  label: const Text('Avatar Builder'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFFCCBC)),
                  ),
                ),
              ],
            ),

            const Divider(height: 36, color: Color(0xFFF1F5F9)),

            // Vehicle Information Section
            const Row(
              children: [
                Icon(Icons.two_wheeler_rounded,
                    color: Color(0xFFFF6B35), size: 22),
                SizedBox(width: 8),
                Text(
                  'Vehicle Information',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _vehicleType,
              decoration: _fieldDecoration(
                label: 'Vehicle Type',
                icon: Icons.directions_bike_rounded,
              ),
              items: _vehicleTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: _isSaving
                  ? null
                  : (v) {
                      if (v != null) setState(() => _vehicleType = v);
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _vehicleNumberController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              decoration: _fieldDecoration(
                label: 'Vehicle Registration Number',
                icon: Icons.pin_rounded,
                hint: 'e.g. TN-07-AB-1234',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter vehicle registration number';
                }
                return null;
              },
            ),

            const Divider(height: 36, color: Color(0xFFF1F5F9)),

            // Identification & Verification Document Section
            const Row(
              children: [
                Icon(Icons.badge_outlined,
                    color: Color(0xFFFF6B35), size: 22),
                SizedBox(width: 8),
                Text(
                  'Government ID / Driving License',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Required for verification. Admin will inspect this before activating your delivery privileges.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _licenseNumberController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.characters,
              decoration: _fieldDecoration(
                label: 'Driving License / ID Number',
                icon: Icons.credit_card_rounded,
                hint: 'e.g. DL-0420110012345 or Govt ID Number',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your license or ID number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Document upload container
            _buildDocumentUploadBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentUploadBox() {
    final hasDocImage = _docImage != null || _docImageBytes != null;
    final hasExistingUrl = _documentUrl != null && _documentUrl!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (hasDocImage || hasExistingUrl)
              ? const Color(0xFFFF6B35)
              : const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file_rounded,
                  color: Color(0xFFFF6B35), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ID Document Photo (Driving License / Govt ID)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (hasDocImage || hasExistingUrl)
                const Icon(Icons.check_circle_rounded,
                    color: Colors.green, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          if (hasDocImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _docImageBytes != null
                  ? Image.memory(
                      _docImageBytes!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Image.file(
                      _docImage!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickDocumentImage,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Change Document'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() {
                            _docImage = null;
                            _docImageBytes = null;
                          }),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ] else if (hasExistingUrl) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: WebImageLoader.loadImage(
                imageUrl: _documentUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _pickDocumentImage,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('Upload New Document Photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B35),
              ),
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 44, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'No document photo uploaded yet',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _pickDocumentImage,
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: const Text('Upload Document Image'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFFFF6B35)),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.4),
      ),
    );
  }

  Widget _buildActionBar() {
    final isAlreadyVerified = _user?.isFullyVerified == true;
    final buttonLabel = _isSaving
        ? 'Saving...'
        : (isAlreadyVerified
            ? 'Save Delivery Profile'
            : (widget.isEditing
                ? 'Submit Verification & Profile'
                : 'Submit Verification & Continue'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveProfile,
          icon: _isSaving
              ? Container(
                  width: 18,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.verified_user_rounded),
          label: Text(buttonLabel),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: const Color(0xFFFF6B35),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (isAlreadyVerified) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSaving
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeliveryScreen(),
                      ),
                    ),
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Open Delivery Console'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              foregroundColor: const Color(0xFFFF6B35),
              side: const BorderSide(color: Color(0xFFFFCCBC)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildVerificationStatusBanner(),
              const SizedBox(height: 16),
              _buildStatsCard(),
              const SizedBox(height: 18),
              _buildFormCard(),
              const SizedBox(height: 20),
              _buildActionBar(),
            ],
          ),
        ),
      ),
    );
  }
}
