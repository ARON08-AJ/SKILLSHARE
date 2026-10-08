import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../models/product_model.dart';
import '../../models/skilled_user_profile.dart';
import '../../services/firestore_service.dart';
import '../../services/cloudinary_service.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../providers/user_provider.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../utils/web_image_loader.dart';

class AddProductScreen extends StatefulWidget {
  final ProductModel? existingProduct;
  const AddProductScreen({super.key, this.existingProduct});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  static final TextInputFormatter _moneyInputFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
    if (newValue.text.isEmpty ||
        RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  });

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final FocusNode _imagePasteFocusNode = FocusNode();
  final FirestoreService _firestoreService = FirestoreService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ImagePicker _picker = ImagePicker();

  String? _selectedCategory;
  String? _selectedListingType;
  final List<String> _imageUrls = [];
  final List<Uint8List> _pendingImageBytes = [];
  int _stockIncrease = 0;
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isPreparingCategories = true;
  bool get _isEditing => widget.existingProduct != null;
  void Function(ClipboardReadEvent event)? _webPasteListener;

  List<String> _categories = [];

  int get _selectedImageCount => _pendingImageBytes.length;
  int get _totalImageCount => _selectedImageCount + _imageUrls.length;
  int get _remainingImageSlots => 5 - _totalImageCount;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final p = widget.existingProduct!;
      _selectedListingType = p.type;
      _nameController.text = p.name;
      _descriptionController.text = p.description;
      _priceController.text = p.price.toString();
      _stockController.text = p.stock.toString();
      _stockIncrease = 0;
      _selectedCategory = p.category;
      _imageUrls.addAll(p.images);
    } else {
      _selectedListingType = null;
    }
    _configureWebPasteListener();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadAllowedCategories());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _imagePasteFocusNode.dispose();
    final events = ClipboardEvents.instance;
    if (_webPasteListener != null && events != null) {
      events.unregisterPasteEventListener(_webPasteListener!);
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      if (_remainingImageSlots <= 0) {
        AppDialog.info(context, 'Maximum 5 images allowed',
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

      final newImages = images.take(_remainingImageSlots).toList();
      final newBytes = await Future.wait(
        newImages.map((image) => image.readAsBytes()),
      );

      if (!mounted) return;

      setState(() {
        _pendingImageBytes.addAll(newBytes);
      });

      if (images.length > newImages.length && mounted) {
        AppDialog.info(
          context,
          'Only the first $_remainingImageSlots image slots were available.',
          title: 'Image Limit Reached',
        );
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

  void _configureWebPasteListener() {
    final events = ClipboardEvents.instance;
    if (events == null) return;

    _webPasteListener = (event) async {
      if (!mounted || !_imagePasteFocusNode.hasFocus) return;
      try {
        final reader = await event.getClipboardReader();
        await _pasteImageFromClipboard(
            reader: reader, showSuccessDialog: false);
      } catch (e) {
        if (!mounted) return;
        AppDialog.error(
          context,
          'Could not paste image',
          detail: e.toString(),
        );
      }
    };

    events.registerPasteEventListener(_webPasteListener!);
  }

  Future<void> _loadAllowedCategories() async {
    final authProvider =
        Provider.of<app_auth.AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final userId =
        authProvider.currentUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      if (!mounted) return;
      setState(() => _isPreparingCategories = false);
      return;
    }

    if (userProvider.currentProfile?.userId != userId) {
      await userProvider.loadProfile(userId);
    }

    final allowedCategories =
        _buildAllowedCategories(userProvider.currentProfile);

    if (_isEditing &&
        _selectedCategory != null &&
        !_containsIgnoreCase(allowedCategories, _selectedCategory!)) {
      allowedCategories.insert(0, _selectedCategory!);
    }

    if (!mounted) return;

    setState(() {
      _categories = allowedCategories;
      if (_selectedCategory == null && _categories.length == 1) {
        _selectedCategory = _categories.first;
      }
      _isPreparingCategories = false;
    });
  }

  List<String> _buildAllowedCategories(SkilledUserProfile? profile) {
    final allowed = <String>[];

    void addOption(String? value) {
      final normalized = value?.trim() ?? '';
      if (normalized.isEmpty) return;
      if (_containsIgnoreCase(allowed, normalized)) return;
      allowed.add(normalized);
    }

    addOption(profile?.category);
    for (final skill in profile?.skills ?? const <String>[]) {
      addOption(skill);
    }

    return allowed;
  }

  bool _containsIgnoreCase(List<String> values, String candidate) {
    final normalizedCandidate = candidate.trim().toLowerCase();
    return values
        .any((value) => value.trim().toLowerCase() == normalizedCandidate);
  }

  Future<void> _pasteImageFromClipboard({
    ClipboardReader? reader,
    bool showSuccessDialog = true,
    bool silentWhenNoImage = false,
  }) async {
    if (_remainingImageSlots <= 0) {
      if (mounted) {
        AppDialog.info(context, 'Maximum 5 images allowed',
            title: 'Limit Reached');
      }
      return;
    }

    try {
      final clipboardReader = reader ?? await SystemClipboard.instance?.read();
      if (clipboardReader == null) {
        if (mounted) {
          AppDialog.info(
            context,
            'Clipboard image paste is not available on this device.',
            title: 'Clipboard Unavailable',
          );
        }
        return;
      }

      final bytes = await _readImageBytesFromReader(clipboardReader);
      if (bytes == null || bytes.isEmpty) {
        if (silentWhenNoImage) return;
        if (mounted) {
          AppDialog.info(
            context,
            'Copy an image first, then use Paste Image or Ctrl+V in the image area.',
            title: 'No Image Found',
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _pendingImageBytes.add(bytes);
      });

      if (showSuccessDialog && mounted) {
        AppDialog.success(context, 'Image pasted successfully!');
      }
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(
        context,
        'Could not paste image',
        detail: e.toString(),
      );
    }
  }

  bool _isTextInputFocused() {
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    return focusedWidget is EditableText;
  }

  Future<void> _handleGlobalPasteShortcut() async {
    if (_isLoading || _isUploading || _remainingImageSlots <= 0) return;
    if (_isTextInputFocused()) return;
    await _pasteImageFromClipboard(
      showSuccessDialog: false,
      silentWhenNoImage: true,
    );
  }

  Future<Uint8List?> _readImageBytesFromReader(ClipboardReader reader) async {
    const imageFormats = <FileFormat>[
      Formats.png,
      Formats.jpeg,
      Formats.gif,
      Formats.webp,
      Formats.bmp,
      Formats.tiff,
    ];

    for (final format in imageFormats) {
      if (!reader.canProvide(format)) continue;
      final file = await _readClipboardFile(reader, format);
      if (file == null) continue;
      final bytes = await file.readAll();
      file.close();
      if (bytes.isNotEmpty) {
        return bytes;
      }
    }
    return null;
  }

  Future<DataReaderFile?> _readClipboardFile(
      ClipboardReader reader, FileFormat format) async {
    final completer = Completer<DataReaderFile?>();
    final progress = reader.getFile(
      format,
      (file) {
        if (!completer.isCompleted) {
          completer.complete(file);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    if (progress == null) {
      return null;
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }

  void _removeImage(int index) {
    setState(() {
      _pendingImageBytes.removeAt(index);
    });
  }

  void _removeUploadedImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  Future<void> _saveProduct() async {
    if (_selectedListingType == null) {
      AppDialog.info(
        context,
        'Please select a Listing Type (Product / Deliverable or Service).',
        title: 'Listing Type Required',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategory == null) {
      AppDialog.info(context, 'Please select a category');
      return;
    }

    final isService = _selectedListingType == AppConstants.listingTypeService;

    if (_pendingImageBytes.isEmpty && _imageUrls.isEmpty) {
      AppDialog.info(
        context,
        isService
            ? 'Please add at least one service image or banner'
            : 'Please add at least one product image',
      );
      return;
    }

    if (!isService && !_isEditing) {
      final stockVal = int.tryParse(_stockController.text.trim());
      if (stockVal == null || stockVal < 0) {
        AppDialog.info(context, 'Please enter a valid stock quantity for physical products');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _isUploading = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();
      List<String> finalImageUrls = List.from(_imageUrls);
      final baseStock = _isEditing ? widget.existingProduct!.stock : 0;
      final updatedStock = isService
          ? 0
          : (_isEditing
              ? baseStock + _stockIncrease
              : int.parse(_stockController.text.trim()));

      // Upload selected images
      if (_pendingImageBytes.isNotEmpty) {
        for (final bytes in _pendingImageBytes) {
          final url = await _cloudinaryService.uploadImageBytes(
            bytes,
            folder: isService ? 'services' : 'products',
          );
          if (url != null) {
            finalImageUrls.add(url);
          }
        }
      }

      final product = ProductModel(
        id: _isEditing
            ? widget.existingProduct!.id
            : '', // Preserve ID when editing
        userId: userId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        images: finalImageUrls,
        category: _selectedCategory!,
        stock: updatedStock,
        type: _selectedListingType!,
        isAvailable: _isEditing ? widget.existingProduct!.isAvailable : true,
        rating: _isEditing ? widget.existingProduct!.rating : 0.0,
        reviewCount: _isEditing ? widget.existingProduct!.reviewCount : 0,
        createdAt: _isEditing ? widget.existingProduct!.createdAt : now,
        updatedAt: now,
      );

      if (_isEditing) {
        await _firestoreService.updateProduct(product);
      } else {
        await _firestoreService.createProduct(product);
      }

      if (mounted) {
        final typeLabel = isService ? 'Service' : 'Product';
        AppDialog.success(
          context,
          _isEditing
              ? '$typeLabel updated successfully!'
              : '$typeLabel added successfully!',
          onDismiss: () => Navigator.of(context).pop(true),
        );
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Error adding product', detail: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    // CRITICAL: Only skilled persons can sell products
    if (!authProvider.isSkilledPerson) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Add Product'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 80, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  'Access Denied',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Only skilled persons can sell products. Customers and companies can browse and purchase products.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // CRITICAL: Check Aadhaar verification
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    if (userProvider.currentProfile == null &&
        authProvider.currentUser != null) {
      userProvider.loadProfile(authProvider.currentUser!.uid);
    }
    if (userProvider.isLoading || userProvider.currentProfile == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Product' : 'Add Product',
              style: const TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFE91E63), Color(0xFFFF9800)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final isVerified = userProvider.currentProfile?.isVerified ?? false;
    if (!isVerified) {
      return Scaffold(
        appBar: AppBar(
          title:
              const Text('Add Product', style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFE91E63), Color(0xFFFF9800)],
              ),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fingerprint,
                    size: 80, color: Color(0xFF9C27B0)),
                const SizedBox(height: 20),
                const Text(
                  'Verification Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'To list products, complete Aadhaar + fingerprint verification.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Profile \u2192 Edit Profile \u2192 Verify Identity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFF9C27B0)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE91E63)),
                  child: const Text('Go Back',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _PasteImageIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): _PasteImageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PasteImageIntent: CallbackAction<_PasteImageIntent>(
            onInvoke: (intent) {
              unawaited(_handleGlobalPasteShortcut());
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
        title: Text(
            _isEditing
                ? (_selectedListingType == AppConstants.listingTypeService
                    ? 'Edit Service'
                    : 'Edit Product')
                : (_selectedListingType == AppConstants.listingTypeService
                    ? 'Add Service'
                    : 'Add Listing'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE91E63), Color(0xFFFF9800)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
          ),
          body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Listing Type Selection (Product / Deliverable vs Service)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _selectedListingType == null
                      ? Colors.orange.shade300
                      : Colors.transparent,
                  width: _selectedListingType == null ? 1.5 : 0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Listing Type',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE91E63),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (_selectedListingType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _selectedListingType ==
                                      AppConstants.listingTypeService
                                  ? const Color(0xFF9C27B0).withValues(alpha: 0.12)
                                  : const Color(0xFFE91E63).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedListingType ==
                                      AppConstants.listingTypeService
                                  ? 'Service'
                                  : 'Deliverable',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _selectedListingType ==
                                        AppConstants.listingTypeService
                                    ? const Color(0xFF9C27B0)
                                    : const Color(0xFFE91E63),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Select whether you are selling a physical deliverable product with shipping or offering a skilled service with project milestones.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedListingType =
                                    AppConstants.listingTypeProduct;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _selectedListingType ==
                                          AppConstants.listingTypeProduct
                                      ? const Color(0xFFE91E63)
                                      : Colors.grey.shade300,
                                  width: _selectedListingType ==
                                          AppConstants.listingTypeProduct
                                      ? 2
                                      : 1,
                                ),
                                color: _selectedListingType ==
                                        AppConstants.listingTypeProduct
                                    ? const Color(0xFFE91E63)
                                        .withValues(alpha: 0.08)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: AppConstants.listingTypeProduct,
                                    groupValue: _selectedListingType,
                                    activeColor: const Color(0xFFE91E63),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedListingType = val;
                                      });
                                    },
                                  ),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Product / Deliverable',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Physical item & shipping',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedListingType =
                                    AppConstants.listingTypeService;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _selectedListingType ==
                                          AppConstants.listingTypeService
                                      ? const Color(0xFF9C27B0)
                                      : Colors.grey.shade300,
                                  width: _selectedListingType ==
                                          AppConstants.listingTypeService
                                      ? 2
                                      : 1,
                                ),
                                color: _selectedListingType ==
                                        AppConstants.listingTypeService
                                    ? const Color(0xFF9C27B0)
                                        .withValues(alpha: 0.08)
                                    : Colors.grey.shade50,
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: AppConstants.listingTypeService,
                                    groupValue: _selectedListingType,
                                    activeColor: const Color(0xFF9C27B0),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedListingType = val;
                                      });
                                    },
                                  ),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Service',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Project & timeline',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedListingType == null) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Please select one type to continue',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Product / Service Name
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedListingType == AppConstants.listingTypeService
                          ? 'Service Title'
                          : 'Product Name',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE91E63),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        hintText: _selectedListingType ==
                                AppConstants.listingTypeService
                            ? 'e.g. Website Development, Custom Painting...'
                            : 'Enter product name',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: Icon(_selectedListingType ==
                                AppConstants.listingTypeService
                            ? Icons.design_services
                            : Icons.shopping_bag),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _selectedListingType ==
                                  AppConstants.listingTypeService
                              ? 'Please enter service title'
                              : 'Please enter product name';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Category
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Category',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE91E63),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isPreparingCategories)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_categories.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFB74D)),
                        ),
                        child: const Text(
                          'No product categories are available yet. Update your skilled profile category or skills first, then add products.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8D4E00),
                            height: 1.45,
                          ),
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          hintText: 'Select category',
                          helperText:
                              'Shown only from your skilled profile category and skills.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.category),
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
                          });
                        },
                        validator: (value) {
                          if (_categories.isEmpty) {
                            return 'Add categories in your profile first';
                          }
                          if (value == null) {
                            return 'Please select a category';
                          }
                          return null;
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedListingType == AppConstants.listingTypeService
                          ? 'Service Details & Scope'
                          : 'Description',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE91E63),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: _selectedListingType ==
                                AppConstants.listingTypeService
                            ? 'Describe your service scope, deliverables, timeline expectations, etc.'
                            : 'Describe your product',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(
                          14,
                          18,
                          14,
                          16,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 12, right: 8, top: 14),
                          child: Icon(Icons.description),
                        ),
                      ),
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _selectedListingType ==
                                  AppConstants.listingTypeService
                              ? 'Please enter service details'
                              : 'Please enter product description';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Price and Stock
            if (_selectedListingType == AppConstants.listingTypeService) ...[
              // Service Price (Full width, no stock required)
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Service Price / Starting Rate',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE91E63),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Fixed fee or starting cost for this service.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceController,
                        decoration: InputDecoration(
                          hintText: '0.00',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 14, right: 8),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                '₹',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF424242),
                                ),
                              ),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [_moneyInputFormatter],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter service price';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Invalid price';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Physical Product Price & Stock
              Row(
                children: [
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Price',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE91E63),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _priceController,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 16,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(left: 14, right: 8),
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(
                                      '₹',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF424242),
                                      ),
                                    ),
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [_moneyInputFormatter],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Enter price';
                                }
                                if (double.tryParse(value) == null) {
                                  return 'Invalid price';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Stock',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE91E63),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_isEditing) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  color: Colors.grey.shade50,
                                ),
                                child: Text(
                                  'Current: ${widget.existingProduct!.stock}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: _stockIncrease > 0
                                          ? () {
                                              setState(() {
                                                _stockIncrease--;
                                              });
                                            }
                                          : null,
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                    ),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Increase By',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$_stockIncrease',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _stockIncrease++;
                                        });
                                      },
                                      icon:
                                          const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'New Stock: ${widget.existingProduct!.stock + _stockIncrease}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE91E63),
                                ),
                              ),
                            ] else
                              TextFormField(
                                controller: _stockController,
                                decoration: InputDecoration(
                                  hintText: '0',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixIcon: const Icon(Icons.inventory),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Enter stock';
                                  }
                                  if (int.tryParse(value) == null) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Image Upload with Preview
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Product Images',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE91E63),
                          ),
                        ),
                        Text(
                          '$_totalImageCount/5',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Image Preview Grid
                    if (_selectedImageCount > 0 || _imageUrls.isNotEmpty)
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _imageUrls.length + _selectedImageCount,
                          itemBuilder: (context, index) {
                            if (index < _imageUrls.length) {
                              // Display uploaded URLs
                              return Stack(
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                      image: DecorationImage(
                                        image: WebImageLoader.getImageProvider(_imageUrls[index])!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 16,
                                    child: GestureDetector(
                                      onTap: () => _removeUploadedImage(index),
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
                              // Display selected files
                              final fileIndex = index - _imageUrls.length;
                              return Stack(
                                children: [
                                  Container(
                                    width: 120,
                                    height: 120,
                                    margin: const EdgeInsets.only(right: 12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                      image: DecorationImage(
                                        image: MemoryImage(
                                            _pendingImageBytes[fileIndex]),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 16,
                                    child: GestureDetector(
                                      onTap: () => _removeImage(fileIndex),
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

                    if (_selectedImageCount > 0 || _imageUrls.isNotEmpty)
                      const SizedBox(height: 12),

                    FocusableActionDetector(
                      focusNode: _imagePasteFocusNode,
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.keyV, control: true):
                            ActivateIntent(),
                        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                            ActivateIntent(),
                      },
                      actions: <Type, Action<Intent>>{
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (intent) {
                            _pasteImageFromClipboard(showSuccessDialog: false);
                            return null;
                          },
                        ),
                      },
                      child: InkWell(
                        onTap: _remainingImageSlots > 0
                            ? () {
                                _imagePasteFocusNode.requestFocus();
                                _pickImages();
                              }
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 116,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _remainingImageSlots > 0
                                  ? const Color(0xFFE91E63)
                                  : Colors.grey[400]!,
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: _imagePasteFocusNode.hasFocus
                                ? const Color(0xFFFFEBEE)
                                : Colors.grey[50],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate,
                                  size: 40,
                                  color: _remainingImageSlots > 0
                                      ? const Color(0xFFE91E63)
                                      : Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _remainingImageSlots > 0
                                      ? 'Tap to choose files'
                                      : 'Maximum 5 images',
                                  style: TextStyle(
                                    color: _remainingImageSlots > 0
                                        ? const Color(0xFFE91E63)
                                        : Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Or copy an image and press Ctrl+V here',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _remainingImageSlots > 0
                            ? () {
                                _imagePasteFocusNode.requestFocus();
                                _pasteImageFromClipboard();
                              }
                            : null,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Paste Image From Clipboard'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE91E63),
                          side: const BorderSide(color: Color(0xFFE91E63)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveProduct,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                backgroundColor: const Color(0xFFE91E63),
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _isEditing ? 'Update Product' : 'Add Product',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
          ),
          // Upload overlay
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          bottomSheet: _isUploading
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: Colors.black87,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(width: 16),
                  Text(
                    'Uploading images...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            )
          : null,
        ),
      ),
    );
  }
}

class _PasteImageIntent extends Intent {
  const _PasteImageIntent();
}
