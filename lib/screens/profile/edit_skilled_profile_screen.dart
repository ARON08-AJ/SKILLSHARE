import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/skilled_user_profile.dart';
import '../../models/service_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/web_image_loader.dart';
import '../../widgets/universal_avatar.dart';
import '../../utils/app_dialog.dart';
import 'skilled_user_setup_screen.dart';

class EditSkilledProfileScreen extends StatefulWidget {
  const EditSkilledProfileScreen({super.key});

  @override
  State<EditSkilledProfileScreen> createState() =>
      _EditSkilledProfileScreenState();
}

class _EditSkilledProfileScreenState extends State<EditSkilledProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  SkilledUserProfile? _profile;
  List<ServiceModel> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      await userProvider.loadProfile(authProvider.currentUser!.uid);
      try {
        _services = await _firestoreService.getUserServices(authProvider.currentUser!.uid);
      } catch (e) {
        debugPrint('Error loading services: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _profile = userProvider.currentProfile;
      _isLoading = false;
    });
  }

  void _showVerificationDialog() {
    AppDialog.warning(
      context,
      'Complete Aadhaar verification from Edit Full Profile to upload portfolio images and add services.',
      title: 'Verification Required',
      buttonText: 'OK',
    );
  }

  Future<void> _toggleVisibility() async {
    if (_profile == null) return;
    final newVisibility = _profile!.visibility == 'public' ? 'private' : 'public';
    final updatedProfile = SkilledUserProfile(
      userId: _profile!.userId,
      name: _profile!.name,
      bio: _profile!.bio,
      skills: _profile!.skills,
      category: _profile!.category,
      profilePicture: _profile!.profilePicture,
      verificationStatus: _profile!.verificationStatus,
      visibility: newVisibility,
      portfolioImages: _profile!.portfolioImages,
      portfolioVideos: _profile!.portfolioVideos,
      verificationData: _profile!.verificationData,
      address: _profile!.address,
      city: _profile!.city,
      state: _profile!.state,
      rating: _profile!.rating,
      reviewCount: _profile!.reviewCount,
      projectCount: _profile!.projectCount,
      isVerified: _profile!.isVerified,
      verifiedAt: _profile!.verifiedAt,
      createdAt: _profile!.createdAt,
      updatedAt: DateTime.now(),
    );
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final success = await userProvider.updateProfile(updatedProfile);
    if (success && mounted) {
      setState(() => _profile = updatedProfile);
      if (newVisibility == 'public') {
        AppDialog.success(context, 'Profile is now PUBLIC');
      } else {
        AppDialog.info(context, 'Profile is now PRIVATE');
      }
    }
  }

  void _navigateToFullEdit() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SkilledUserSetupScreen(userId: authProvider.currentUser!.uid)),
    );
    _loadProfile();
  }

  void _showAddServiceDialog({ServiceModel? existing}) {
    if (_profile?.isVerified != true) {
      _showVerificationDialog();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _ServiceDialog(
        existing: existing,
        category: _profile?.category ?? '',
        onSaved: (service) async {
          try {
            if (existing != null) {
              await _firestoreService.updateService(service);
            } else {
              await _firestoreService.createService(service);
            }
            _loadProfile();
            if (mounted) {
              AppDialog.success(
                  context, existing != null ? 'Service updated!' : 'Service added!');
            }
          } catch (e) {
            if (mounted) {
              AppDialog.error(context, 'Error saving service', detail: e.toString());
            }
          }
        },
      ),
    );
  }

  Future<void> _deleteService(ServiceModel service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service'),
        content: Text('Delete "${service.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _firestoreService.deleteService(service.id);
      _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;
    final isVerified = _profile?.isVerified ?? false;
    final isPublic = _profile?.visibility == 'public';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton.icon(
            onPressed: _navigateToFullEdit,
            icon: const Icon(Icons.edit, color: Colors.white, size: 18),
            label: const Text('Full Edit', style: TextStyle(color: Colors.white)),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Column(children: [
                  Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                    child: UniversalAvatar(
                      avatarConfig: currentUser?.avatarConfig,
                      photoUrl: _profile?.profilePicture ?? currentUser?.profilePhoto,
                      fallbackName: currentUser?.name,
                      radius: 50,
                      borderColor: Colors.white,
                      borderWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(currentUser?.name ?? 'User', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(_profile?.category ?? 'No Category', style: const TextStyle(fontSize: 15, color: Colors.white70)),
                  if (_profile?.address != null && _profile!.address!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.location_on, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(_profile!.address!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ]),
                  ],
                ]),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Visibility Toggle
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(isPublic ? Icons.visibility : Icons.visibility_off, color: isPublic ? Colors.green : Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Profile Visibility', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          Text(isPublic ? 'Visible to everyone' : 'Hidden from search', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ])),
                        Switch(value: isPublic, onChanged: (_) => _toggleVisibility(), activeColor: Colors.green),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Verification Status
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Icon(isVerified ? Icons.verified : Icons.pending, color: isVerified ? Colors.green : Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Verification', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          Text(isVerified ? 'Aadhaar verified' : 'Complete verification to unlock features', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ])),
                        if (!isVerified) TextButton(onPressed: _navigateToFullEdit, child: const Text('Verify Now')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Portfolio
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Portfolio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_profile?.portfolioImages.length ?? 0} images', style: TextStyle(color: Colors.grey[600])),
                  ]),
                  const SizedBox(height: 12),
                  if (_profile?.portfolioImages.isNotEmpty == true)
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _profile!.portfolioImages.length,
                        itemBuilder: (context, index) => Container(
                          width: 100,
                          margin: const EdgeInsets.only(right: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WebImageLoader.loadImage(imageUrl: _profile!.portfolioImages[index], fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                      child: Column(children: [
                        Icon(Icons.photo_library, size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('No portfolio images yet', style: TextStyle(color: Colors.grey[600])),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _navigateToFullEdit,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Manage Portfolio'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF6A11CB), side: const BorderSide(color: Color(0xFF6A11CB)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Services
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Services & Pricing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('${_services.length} services', style: TextStyle(color: Colors.grey[600])),
                  ]),
                  const SizedBox(height: 12),
                  if (_services.isNotEmpty)
                    ..._services.map((service) => Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(service.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SizedBox(height: 4),
                          Text(service.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(
                            '${service.priceMin.toStringAsFixed(0)} - ${service.priceMax.toStringAsFixed(0)} ${service.priceUnit}',
                            style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold),
                          ),
                        ]),
                        trailing: PopupMenuButton(
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                          onSelected: (v) {
                            if (v == 'edit') { _showAddServiceDialog(existing: service); }
                            else if (v == 'delete') { _deleteService(service); }
                          },
                        ),
                      ),
                    ))
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
                      child: Column(children: [
                        Icon(Icons.miscellaneous_services, size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text('No services added yet', style: TextStyle(color: Colors.grey[600])),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showAddServiceDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Service'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  final ServiceModel? existing;
  final String category;
  final ValueChanged<ServiceModel> onSaved;

  const _ServiceDialog({
    this.existing,
    required this.category,
    required this.onSaved,
  });

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _minPriceController;
  late TextEditingController _maxPriceController;
  late String _selectedUnit;

  static const List<String> _priceUnits = [
    'per hour',
    'per day',
    'per session',
    'per project',
    'fixed',
  ];

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.existing?.title ?? '');
    _descController =
        TextEditingController(text: widget.existing?.description ?? '');
    _minPriceController = TextEditingController(
        text: widget.existing != null
            ? widget.existing!.priceMin.toStringAsFixed(0)
            : '');
    _maxPriceController = TextEditingController(
        text: widget.existing != null
            ? widget.existing!.priceMax.toStringAsFixed(0)
            : '');
    _selectedUnit = widget.existing?.priceUnit ?? 'per session';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(existing != null ? 'Edit Service' : 'Add Service'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                    labelText: 'Service Title',
                    hintText: 'e.g., Wedding Photography',
                    prefixIcon: Icon(Icons.work)),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe what you offer...',
                    alignLabelWithHint: true),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _minPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Min Price', prefixText: '₹ '),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Max Price', prefixText: '₹ '),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedUnit,
                decoration: const InputDecoration(
                    labelText: 'Pricing Unit', prefixIcon: Icon(Icons.schedule)),
                items: _priceUnits
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedUnit = v);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context);
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            final now = DateTime.now();
            final service = ServiceModel(
              id: existing?.id ?? '',
              userId: authProvider.currentUser!.uid,
              title: _titleController.text.trim(),
              description: _descController.text.trim(),
              priceMin: double.parse(_minPriceController.text),
              priceMax: double.parse(_maxPriceController.text),
              priceUnit: _selectedUnit,
              images: existing?.images ?? [],
              category: widget.category,
              isActive: true,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            );
            widget.onSaved(service);
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white),
          child: Text(existing != null ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
