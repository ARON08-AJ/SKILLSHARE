import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/product_model.dart';
import '../../models/skilled_user_profile.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_helpers.dart';
import '../../utils/app_theme.dart';
import '../../widgets/product_card.dart';
import '../../widgets/universal_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/profile_screen.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';
import '../../models/cart_item_model.dart';

class ShopStorefrontScreen extends StatefulWidget {
  const ShopStorefrontScreen({
    super.key,
    required this.sellerId,
    this.initialShopName,
  });

  final String sellerId;
  final String? initialShopName;

  @override
  State<ShopStorefrontScreen> createState() => _ShopStorefrontScreenState();
}

class _ShopStorefrontScreenState extends State<ShopStorefrontScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = true;
  String? _error;

  UserModel? _seller;
  SkilledUserProfile? _profile;
  List<ProductModel> _products = [];
  Map<String, dynamic> _shopSettings = const {};

  StreamSubscription? _sellerSub;
  StreamSubscription? _profileSub;
  StreamSubscription? _productsSub;
  StreamSubscription? _shopSettingsSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sellerSub?.cancel();
    _profileSub?.cancel();
    _productsSub?.cancel();
    _shopSettingsSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // One-time Aadhaar verification gate
    try {
      final isVerified =
          await _firestoreService.isSkilledUserAadhaarVerified(widget.sellerId);
      if (!mounted) return;
      if (!isVerified) {
        setState(() {
          _error = 'This shop is not publicly available.';
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load shop: $e';
        _isLoading = false;
      });
      return;
    }

    // Live streams — all viewers see changes the moment they happen
    _sellerSub =
        _firestoreService.streamUserModel(widget.sellerId).listen((seller) {
      if (mounted) setState(() => _seller = seller);
    }, onError: (_) {});

    _profileSub = _firestoreService
        .skilledUserProfileStream(widget.sellerId)
        .listen((profile) {
      if (mounted) setState(() => _profile = profile);
    }, onError: (_) {});

    _shopSettingsSub = _firestoreService
        .streamShopSettings(widget.sellerId)
        .listen((settings) {
      if (mounted) setState(() => _shopSettings = settings);
    }, onError: (_) {});

    _productsSub =
        _firestoreService.streamUserProducts(widget.sellerId).listen((all) {
      if (mounted) {
        setState(() {
          _products = all.where((p) => p.isAvailable).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _isLoading = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load products: $e';
          _isLoading = false;
        });
      }
    });
  }

  /// Resolved shop name with first-letter capitalisation.
  /// Priority: configured shopName → "[SellerName] Shop"
  String get _resolvedShopName {
    final configured = (_shopSettings['shopName'] as String?)?.trim() ?? '';
    if (configured.isNotEmpty) {
      return AppHelpers.capitalize(configured);
    }
    final sellerName = (_seller?.name.trim().isNotEmpty == true)
        ? _seller!.name.trim()
        : (_profile?.name?.trim().isNotEmpty == true
            ? _profile!.name!.trim()
            : '');
    if (sellerName.isNotEmpty) {
      return '${AppHelpers.capitalize(sellerName)} Shop';
    }
    return widget.initialShopName?.trim().isNotEmpty == true
        ? AppHelpers.capitalize(widget.initialShopName!.trim())
        : 'Shop';
  }

  Future<void> _openProduct(ProductModel product) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
    // No manual reload needed — products stream auto-refreshes
  }

  @override
  Widget build(BuildContext context) {
    final shopName = _resolvedShopName;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(shopName, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return const SizedBox.shrink();
              return StreamBuilder<List<CartItemModel>>(
                stream: _firestoreService.streamCartItems(uid),
                builder: (context, snapshot) {
                  final count = snapshot.data?.fold<int>(
                          0, (sum, item) => sum + item.quantity) ??
                      0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shopping_cart_outlined,
                            color: Colors.white),
                        tooltip: 'View Cart',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CartScreen()),
                          );
                        },
                      ),
                      if (count > 0)
                        Positioned(
                          right: 4,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primaryPurple, AppTheme.primaryPink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildShopHeader(shopName),
                    const SizedBox(height: 12),
                    Text(
                      '${_products.length} product${_products.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_products.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child:
                            const Text('No products available in this shop.'),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final columns = (width / 220).floor().clamp(2, 7);
                          final ratio = columns >= 6
                              ? 0.82
                              : columns >= 4
                                  ? 0.78
                                  : columns == 3
                                      ? 0.74
                                      : 0.72;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              childAspectRatio: ratio,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              return ProductCard(
                                product: product,
                                onTap: () => _openProduct(product),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
    );
  }

  Widget _buildShopHeader(String shopName) {
    final sellerName = (_seller?.name.trim().isNotEmpty == true)
        ? _seller!.name.trim()
        : (_profile?.name?.trim().isNotEmpty == true
            ? _profile!.name!.trim()
            : 'Skilled Person');
    final bio = (_profile?.bio ?? '').trim();
    final skills = _profile?.skills ?? const <String>[];
    final hasCredentialBadge = _profile?.hasConfidentialCredentials == true;
    final credentialCount = _profile?.confidentialCredentialCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UniversalAvatar(
                avatarConfig: _seller?.avatarConfig,
                photoUrl: _seller?.profilePhoto,
                fallbackName: sellerName,
                radius: 24,
                animate: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'By $sellerName',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _seller == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(userId: _seller!.uid),
                          ),
                        ),
                icon: const Icon(Icons.person, size: 16),
                label: const Text('View Profile'),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ],
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skills
                  .take(6)
                  .map(
                    (skill) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        skill,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (hasCredentialBadge || _products.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasCredentialBadge)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      credentialCount > 0
                          ? '$credentialCount validated credential ${credentialCount == 1 ? 'link' : 'links'} on file'
                          : 'Validated credentials on file',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1B5E20),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_products.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Bulk orders supported from product pages and cart',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.primaryPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
