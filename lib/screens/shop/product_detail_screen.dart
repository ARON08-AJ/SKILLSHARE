import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/chat_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_helpers.dart';
import '../../utils/web_image_loader.dart';
import '../../widgets/universal_avatar.dart';
import '../../widgets/app_popup.dart';
import '../profile/profile_screen.dart';
import '../chat/chat_detail_screen.dart';
import '../../widgets/gpay_simulation_dialog.dart';
import 'shop_storefront_screen.dart';
import 'cart_screen.dart';
import 'order_tracking_screen.dart';
import '../../models/cart_item_model.dart';
import '../../utils/app_dialog.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ChatService _chatService = ChatService();
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;
  UserModel? _seller;
  String _shopName = 'Shop';
  List<ProductModel> _sellerProducts = [];
  List<ProductModel> _recommended = [];
  int _qty = 1;

  StreamSubscription<UserModel?>? _sellerUserSub;
  StreamSubscription<Map<String, dynamic>>? _sellerShopSub;

  @override
  void initState() {
    super.initState();
    _subscribeToSeller();
    _loadSellerProducts();
    _loadRecommended();
  }

  void _subscribeToSeller() {
    if (widget.product.sourceType == 'skillshare') {
      _shopName = (widget.product.displayShopName != null &&
              widget.product.displayShopName!.trim().isNotEmpty)
          ? widget.product.displayShopName!.trim()
          : 'SkillShare Official';
    }

    final sellerId = widget.product.userId;
    _sellerUserSub = _firestoreService.streamUserModel(sellerId).listen((user) {
      if (!mounted) return;
      setState(() {
        _seller = user;
        _resolveShopName();
      });
    });
    _sellerShopSub =
        _firestoreService.streamShopSettings(sellerId).listen((settings) {
      if (!mounted) return;
      final configuredName = (settings['shopName'] as String?)?.trim() ?? '';
      if (configuredName.isNotEmpty) {
        setState(() => _shopName = configuredName);
      } else {
        _resolveShopName();
      }
    });
  }

  void _resolveShopName() {
    final sellerName = _seller?.name.trim() ?? '';
    if (_shopName == 'Shop' || _shopName.endsWith(' Shop')) {
      setState(() {
        _shopName = sellerName.isNotEmpty ? '$sellerName Shop' : 'Shop';
      });
    }
  }

  Future<void> _openSellerShop() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShopStorefrontScreen(
          sellerId: widget.product.userId,
          initialShopName: _shopName,
        ),
      ),
    );
  }

  Future<void> _loadSellerProducts() async {
    try {
      final all = await _firestoreService.getAllProducts(limit: 30);
      if (mounted) {
        setState(() {
          _sellerProducts = all
              .where((p) =>
                  p.userId == widget.product.userId &&
                  p.id != widget.product.id &&
                  p.isAvailable)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading seller products: $e');
    }
  }

  Future<void> _loadRecommended() async {
    try {
      final all = await _firestoreService.getAllProducts(limit: 20);
      if (mounted) {
        setState(() {
          _recommended = all
              .where((p) =>
                  p.id != widget.product.id &&
                  p.userId != widget.product.userId &&
                  p.isAvailable &&
                  p.category == widget.product.category)
              .take(8)
              .toList();
          if (_recommended.isEmpty) {
            _recommended = all
                .where((p) =>
                    p.id != widget.product.id &&
                    p.userId != widget.product.userId &&
                    p.isAvailable)
                .take(8)
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading recommended: $e');
    }
  }

  Future<void> _shareProduct() async {
    await Share.share(
      '${widget.product.name}\n\n'
      '${widget.product.description}\n\n'
      'Price: ${AppHelpers.formatCurrency(widget.product.price)}\n\n'
      'Check it out on SkillShare!',
      subject: widget.product.name,
    );
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text(
            'Are you sure you want to delete this product? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _firestoreService.deleteProduct(widget.product.id);
        if (mounted) {
          Navigator.pop(context, true);
          AppPopup.show(context,
              message: 'Product deleted successfully', type: PopupType.success);
        }
      } catch (e) {
        if (mounted) {
          AppPopup.show(context,
              message: 'Error deleting product: $e', type: PopupType.error);
        }
      }
    }
  }

  Future<void> _contactSeller() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppPopup.show(context,
          message: 'Please sign in to contact the seller',
          type: PopupType.warning);
      return;
    }
    if (currentUser.uid == widget.product.userId) {
      AppPopup.show(context,
          message: 'This is your own product', type: PopupType.info);
      return;
    }
    try {
      final myUser = await _firestoreService.getUserById(currentUser.uid);
      if (myUser == null) return;
      final chatId = await _chatService.getOrCreateChat(
        currentUser.uid,
        widget.product.userId,
        {'name': myUser.name, 'photo': myUser.profilePhoto ?? ''},
        {
          'name': _seller?.name ?? 'Seller',
          'photo': _seller?.profilePhoto ?? ''
        },
      );
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: chatId,
              otherUserId: widget.product.userId,
              otherUserName: _seller?.name ?? 'Seller',
              otherUserPhoto: _seller?.profilePhoto,
            ),
          ));
    } catch (e) {
      if (!mounted) return;
      AppPopup.show(context, message: 'Error: $e', type: PopupType.error);
    }
  }

  Future<void> _addToCart() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppPopup.show(context,
          message: 'Please sign in to add to cart', type: PopupType.warning);
      return;
    }
    if (currentUser.uid == widget.product.userId) {
      AppPopup.show(context,
          message: 'You cannot add your own product to cart',
          type: PopupType.info);
      return;
    }
    try {
      for (int i = 0; i < _qty; i++) {
        await _firestoreService.addToCart(
            userId: currentUser.uid, product: widget.product);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      AppPopup.show(
        context,
        message:
            '${widget.product.name}${_qty > 1 ? ' x$_qty' : ''} added to cart!',
        type: PopupType.success,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      AppPopup.show(context,
          message: 'Error adding to cart: $e', type: PopupType.error);
    }
  }

  Future<void> _buyNow() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppPopup.show(context,
          message: 'Please sign in to purchase', type: PopupType.warning);
      return;
    }
    if (currentUser.uid == widget.product.userId) {
      AppPopup.show(context,
          message: 'You cannot buy your own product', type: PopupType.info);
      return;
    }

    final checkoutDetails = await _collectCheckoutDetails(currentUser.uid);
    if (!mounted || checkoutDetails == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    final transactionId = await GPaySimulationDialog.show(
      context,
      amount: widget.product.price * _qty,
      recipientName: _seller?.name ?? 'Seller',
      description: '${widget.product.name}${_qty > 1 ? ' x$_qty' : ''}',
    );

    if (transactionId != null && mounted) {
      try {
        final order = await _firestoreService.purchaseProductDirect(
          userId: currentUser.uid,
          product: widget.product,
          quantity: _qty,
          paymentMethod: 'gpay_simulation',
          paymentReference: transactionId,
          deliveryAddress: checkoutDetails.address,
        );

        if (!mounted) return;
        await AppDialog.success(
          context,
          'Payment successful!\n'
          'Order placed for ${order.productName}${order.quantity > 1 ? ' x${order.quantity}' : ''}.\n\n'
          'Ref: $transactionId\n'
          'Delivery code: ${order.deliveryVerificationCode ?? 'N/A'}',
          title: 'Order Placed',
          buttonText: 'OK',
        );
      } catch (e) {
        if (!mounted) return;
        AppPopup.show(context,
            message: 'Error placing order: $e', type: PopupType.error);
      }
    }
  }

  Future<_CheckoutDetails?> _collectCheckoutDetails(String userId) async {
    final addressSnapshot =
        await _firestoreService.resolveUserAddressSnapshot(userId);
    if (!mounted) return null;

    final defaultAddress =
        (addressSnapshot['formattedAddress'] as String? ?? '').trim();

    return showDialog<_CheckoutDetails>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DeliveryAddressDialog(savedAddress: defaultAddress),
    );
  }

  Future<void> _requestService() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppPopup.show(
        context,
        message: 'Please sign in to request this service',
        type: PopupType.warning,
      );
      return;
    }
    if (currentUser.uid == widget.product.userId) {
      AppPopup.show(
        context,
        message: 'You cannot request your own service',
        type: PopupType.info,
      );
      return;
    }

    final notesController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.handshake_outlined,
                  color: Color(0xFF9C27B0)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Request Service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Service Fee: ${AppHelpers.formatCurrency(widget.product.price)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Color(0xFFE91E63),
                ),
              ),
              if (_seller != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Skilled Person: ${_seller!.name}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Project Requirements & Notes:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: notesController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Describe your requirements, goals, deadline expectations, and any specifics...',
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Color(0xFF7B1FA2)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The skilled person will review your request. Once accepted, requirement gathering and project milestones will begin.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF4A148C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9C27B0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final order = await _firestoreService.createServiceOrderRequest(
        userId: currentUser.uid,
        product: widget.product,
        notes: notesController.text.trim(),
      );

      if (!mounted) return;
      await AppDialog.success(
        context,
        'Your service request for "${widget.product.name}" has been sent!\n\n'
        'The skilled person has been notified and will review your request shortly.',
        title: 'Request Sent',
        buttonText: 'View Request Status',
        onDismiss: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(order: order),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        AppPopup.show(
          context,
          message: 'Error submitting service request: $e',
          type: PopupType.error,
        );
      }
    }
  }

  void _viewFullscreenImage(int initialIndex) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _FullScreenImageViewer(
          images: widget.product.images, initialIndex: initialIndex),
    ));
  }

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid == widget.product.userId;

  // ─── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final inStock = product.isAvailable && product.stock > 0;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 700;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: _buildAppBar(product),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main product section: image + info/actions ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Product Image
                        Expanded(flex: 5, child: _buildImageSection(product)),
                        const SizedBox(width: 24),
                        // Right: Info + Actions
                        Expanded(
                            flex: 4,
                            child: _buildInfoAndActions(product, inStock)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildImageSection(product),
                        const SizedBox(height: 16),
                        _buildInfoAndActions(product, inStock),
                      ],
                    ),
            ),

            const SizedBox(height: 8),

            // ── Seller section ──
            if (_seller != null) _buildSellerCard(),

            const SizedBox(height: 8),

            // ── Description ──
            _buildDescriptionCard(product),

            // ── Seller's Other Products (grid) ──
            if (_sellerProducts.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildSellerProductsGrid(),
            ],

            // ── Recommended Products (grid) ──
            if (_recommended.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildRecommendedGrid(),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ─── APP BAR ────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(ProductModel product) {
    return AppBar(
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryPurple, AppTheme.primaryPink],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      elevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
      ),
      actions: [
        Builder(
          builder: (context) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart,
                      color: Colors.white, size: 24),
                  tooltip: 'View Cart',
                  onPressed: () {
                    if (uid == null) {
                      AppPopup.show(
                        context,
                        message: 'Please sign in to view your cart',
                        type: PopupType.info,
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CartScreen()),
                      );
                    }
                  },
                ),
                if (uid != null)
                  StreamBuilder<List<CartItemModel>>(
                    stream: _firestoreService.streamCartItems(uid),
                    builder: (context, snapshot) {
                      final itemCount = snapshot.data?.fold<int>(
                              0, (sum, item) => sum + item.quantity) ??
                          0;
                      if (itemCount == 0) return const SizedBox.shrink();
                      return Positioned(
                        right: 4,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 18, minHeight: 18),
                          child: Text(
                            '$itemCount',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: _shareProduct),
        if (_isOwner)
          PopupMenuButton<String>(
            iconColor: Colors.white,
            onSelected: (value) {
              if (value == 'delete') _deleteProduct();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete Product', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ],
          ),
      ],
    );
  }

  // ─── IMAGE SECTION ──────────────────────────────────────────────────────
  Widget _buildImageSection(ProductModel product) {
    return Column(
      children: [
        // Main image viewer
        GestureDetector(
          onTap: () => _viewFullscreenImage(_currentImageIndex),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[50],
              border: Border.all(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: product.images.isNotEmpty
                ? Stack(
                    children: [
                      PageView.builder(
                        controller: _imagePageController,
                        onPageChanged: (i) =>
                            setState(() => _currentImageIndex = i),
                        itemCount: product.images.length,
                        itemBuilder: (_, i) => Hero(
                          tag: 'product_${product.id}_$i',
                          child: WebImageLoader.loadImage(
                              imageUrl: product.images[i], fit: BoxFit.contain),
                        ),
                      ),
                      // Page dots
                      if (product.images.length > 1)
                        Positioned(
                          bottom: 10,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              product.images.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: _currentImageIndex == i ? 22 : 8,
                                height: 8,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: _currentImageIndex == i
                                      ? AppTheme.primaryPink
                                      : Colors.grey[400],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Zoom icon
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.zoom_in,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Icon(Icons.image_not_supported,
                        size: 48, color: Colors.grey)),
          ),
        ),
        // Thumbnail strip
        if (product.images.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: product.images.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _imagePageController.animateToPage(i,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut),
                child: Container(
                  width: 56,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _currentImageIndex == i
                          ? AppTheme.primaryPink
                          : Colors.grey.shade300,
                      width: _currentImageIndex == i ? 2.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: WebImageLoader.loadImage(
                      imageUrl: product.images[i], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─── INFO + ACTION BUTTONS (right side on wide, below on mobile) ──────
  Widget _buildInfoAndActions(ProductModel product, bool inStock) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product name
        Text(product.name,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                height: 1.3)),
        const SizedBox(height: 8),

        // Rating row
        if (product.reviewCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                ...List.generate(
                  5,
                  (i) => Icon(
                    i < product.rating.round()
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: Colors.amber,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  product.rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${product.reviewCount} review${product.reviewCount != 1 ? 's' : ''})',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),

        // Price
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              AppHelpers.formatCurrency(product.price),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryPink,
              ),
            ),
            if (_qty > 1) ...[
              const SizedBox(width: 8),
              Text(
                'Total: ${AppHelpers.formatCurrency(product.price * _qty)}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),

        // Stock or Service status
        if (product.isService) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFF9C27B0).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.design_services,
                    color: Color(0xFF9C27B0), size: 14),
                SizedBox(width: 5),
                Text(
                  'Skilled Service',
                  style: TextStyle(
                    color: Color(0xFF9C27B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: inStock
                      ? AppTheme.accentGreen.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(inStock ? Icons.check_circle : Icons.cancel,
                        color: inStock ? AppTheme.accentGreen : Colors.red,
                        size: 14),
                    const SizedBox(width: 4),
                    Text(
                      inStock ? 'In Stock' : 'Out of Stock',
                      style: TextStyle(
                          color: inStock ? Colors.green[700] : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (inStock && product.stock <= 10) ...[
                const SizedBox(width: 8),
                Text('${product.stock} left',
                    style: TextStyle(
                        fontSize: 12,
                        color: product.stock <= 3
                            ? Colors.red
                            : Colors.grey[600])),
              ],
            ],
          ),
        ],
        const SizedBox(height: 6),

        // Category chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.primaryPurple.withValues(alpha: 0.3)),
          ),
          child: Text(product.category,
              style: const TextStyle(
                  color: AppTheme.primaryPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ),

        const SizedBox(height: 16),

        // ── Quantity selector (Only for physical products) ──
        if (!_isOwner && product.isPhysicalProduct && inStock) ...[
          Row(
            children: [
              const Text('Qty:',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(width: 10),
              _buildQtyButton(Icons.remove, () {
                if (_qty > 1) setState(() => _qty--);
              }),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text('$_qty',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              _buildQtyButton(Icons.add, () {
                if (_qty < product.stock) setState(() => _qty++);
              }),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Action Buttons ──
        if (!_isOwner) ...[
          if (product.isService) ...[
            // Request Service button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _requestService,
                icon: const Icon(Icons.assignment_turned_in_outlined,
                    size: 20),
                label: const Text(
                  'Request Service',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C27B0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            // Add to Cart
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: inStock ? _addToCart : null,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                label: Text(
                  inStock ? 'Add to Cart' : 'Out of Stock',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Buy Now (GPay)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: inStock ? _buyNow : null,
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text(
                  'Buy Now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPink,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // View Cart
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    AppPopup.show(context,
                        message: 'Please sign in to view your cart',
                        type: PopupType.info);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CartScreen()),
                    );
                  }
                },
                icon: const Icon(Icons.shopping_cart_rounded,
                    size: 20, color: AppTheme.primaryOrange),
                label: const Text(
                  'View My Cart 🛒',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: AppTheme.primaryOrange, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],

          // Chat with Seller
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _contactSeller,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text(
                'Chat with Seller',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryPurple,
                side: BorderSide(
                    color: AppTheme.primaryPurple.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Icon(icon, size: 16, color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  // ─── SELLER CARD ────────────────────────────────────────────────────────
  Widget _buildSellerCard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sold by',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_rounded,
                        size: 14, color: AppTheme.primaryPurple),
                    const SizedBox(width: 4),
                    Text(
                      _shopName,
                      style: const TextStyle(
                        color: AppTheme.primaryPurple,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openSellerShop,
                icon: const Icon(Icons.store_mall_directory, size: 16),
                label: const Text('Visit Shop'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: _seller!.uid))),
            child: Row(
              children: [
                UniversalAvatar(
                  avatarConfig: _seller!.avatarConfig,
                  photoUrl: _seller!.profilePhoto,
                  fallbackName: _seller!.name,
                  radius: 22,
                  animate: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_seller!.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(_seller!.role,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      AppTheme.primaryPurple,
                      AppTheme.primaryPink,
                    ]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('View Profile',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── DESCRIPTION ────────────────────────────────────────────────────────
  Widget _buildDescriptionCard(ProductModel product) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                    color: AppTheme.primaryPurple,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              const Text('Product Details',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(product.description,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[700], height: 1.6)),
        ],
      ),
    );
  }

  // ─── SELLER'S OTHER PRODUCTS (GRID) ─────────────────────────────────────
  Widget _buildSellerProductsGrid() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                    color: AppTheme.primaryOrange,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'More from ${_shopName.isNotEmpty ? _shopName : (_seller?.name ?? 'this seller')}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = (width / 220).floor().clamp(2, 6);
              final ratio = columns >= 5
                  ? 0.82
                  : columns >= 4
                      ? 0.78
                      : columns == 3
                          ? 0.74
                          : 0.72;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: ratio,
                ),
                itemCount:
                    _sellerProducts.length > 6 ? 6 : _sellerProducts.length,
                itemBuilder: (_, i) =>
                    _ProductGridCard(product: _sellerProducts[i]),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── RECOMMENDED PRODUCTS (GRID) ────────────────────────────────────────
  Widget _buildRecommendedGrid() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                    color: AppTheme.primaryBlue,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              const Text('You may also like',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = (width / 220).floor().clamp(2, 6);
              final ratio = columns >= 5
                  ? 0.82
                  : columns >= 4
                      ? 0.78
                      : columns == 3
                          ? 0.74
                          : 0.72;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: ratio,
                ),
                itemCount: _recommended.length,
                itemBuilder: (_, i) =>
                    _ProductGridCard(product: _recommended[i]),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sellerUserSub?.cancel();
    _sellerShopSub?.cancel();
    _imagePageController.dispose();
    super.dispose();
  }
}

// ─── PRODUCT GRID CARD (styled for the product detail page grids) ──────────
class _ProductGridCard extends StatelessWidget {
  final ProductModel product;
  const _ProductGridCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final validImage =
        product.images.where((url) => url.trim().isNotEmpty).toList();
    final bool inStock = product.isAvailable && product.stock > 0;

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  validImage.isNotEmpty
                      ? WebImageLoader.loadImage(
                          imageUrl: validImage.first,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: Colors.grey[50],
                            child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryPink)),
                          ),
                          errorWidget: Container(
                            color: Colors.grey[50],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey, size: 28),
                          ),
                        )
                      : Container(
                          color: Colors.grey[50],
                          child: const Icon(Icons.shopping_bag_outlined,
                              size: 30, color: Colors.grey),
                        ),
                  // Out of stock overlay
                  if (!inStock)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: const Center(
                        child: Text('Out of Stock',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                            height: 1.3)),
                    const SizedBox(height: 3),
                    if (product.reviewCount > 0)
                      Row(
                        children: [
                          ...List.generate(
                            5,
                            (i) => Icon(
                              i < product.rating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: Colors.amber,
                              size: 11,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text('(${product.reviewCount})',
                              style: TextStyle(
                                  fontSize: 9, color: Colors.grey[500])),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      AppHelpers.formatCurrency(product.price),
                      style: const TextStyle(
                        color: AppTheme.primaryPink,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
}

// ─── FULLSCREEN IMAGE VIEWER ──────────────────────────────────────────────
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer(
      {required this.images, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _CheckoutDetails {
  final String address;

  const _CheckoutDetails({required this.address});
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('${_currentIndex + 1} / ${widget.images.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemCount: widget.images.length,
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Hero(
              tag: 'product_fullscreen_$index',
              child: WebImageLoader.loadImage(
                  imageUrl: widget.images[index], fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class _DeliveryAddressDialog extends StatefulWidget {
  final String savedAddress;

  const _DeliveryAddressDialog({required this.savedAddress});

  @override
  State<_DeliveryAddressDialog> createState() => _DeliveryAddressDialogState();
}

class _DeliveryAddressDialogState extends State<_DeliveryAddressDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.savedAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Confirm Delivery Address',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter or edit your delivery address for this order.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Delivery Address',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Door no, Street, Area, City, State, PIN',
                  hintMaxLines: 2,
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(Icons.home_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (widget.savedAddress.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _controller.text = widget.savedAddress;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_added_outlined,
                            size: 15, color: Color(0xFF1976D2)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Reset to saved: ${widget.savedAddress}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1976D2),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            final address = _controller.text.trim();
            if (address.isEmpty) {
              AppPopup.show(
                context,
                message: 'Please enter a delivery address',
                type: PopupType.warning,
              );
              return;
            }
            Navigator.of(context).pop(
              _CheckoutDetails(address: address),
            );
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
