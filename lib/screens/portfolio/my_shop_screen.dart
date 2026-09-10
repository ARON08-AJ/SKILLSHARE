import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../providers/user_provider.dart';
import '../../models/product_model.dart';
import '../../models/order_model.dart';
import '../../models/customer_profile.dart';
import '../../services/firestore_service.dart';
import '../../utils/web_image_loader.dart';
import '../../utils/app_dialog.dart';
import '../profile/settings_screen.dart';
import '../shop/add_product_screen.dart';
import '../shop/product_detail_screen.dart';
import '../shop/order_tracking_screen.dart';
import '../../utils/app_helpers.dart';

/// My Shop Screen - For Skilled Persons Only
/// Skilled persons can manage their online shop here
/// They can add, edit, and manage products they want to sell
class MyShopScreen extends StatefulWidget {
  const MyShopScreen({super.key});

  @override
  State<MyShopScreen> createState() => _MyShopScreenState();
}

class _MyShopScreenState extends State<MyShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final products = await _firestoreService.getUserProducts(userId);
        if (!mounted) return;
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading products: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app_auth.AuthProvider>(context);

    // CRITICAL: Only skilled persons can manage shop
    if (!authProvider.isSkilledPerson) {
      return _buildAccessDenied();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Shop', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE91E63),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openShopSettings(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Products', icon: Icon(Icons.inventory_2)),
            Tab(text: 'Orders', icon: Icon(Icons.list_alt)),
            Tab(text: 'My Orders', icon: Icon(Icons.shopping_bag_outlined)),
            Tab(text: 'Analytics', icon: Icon(Icons.analytics)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductsTab(),
          _buildOrdersTab(),
          _buildMyOrdersTab(),
          _buildAnalyticsTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _addProduct(context),
              backgroundColor: const Color(0xFFE91E63),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Product',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildAccessDenied() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Shop'),
        backgroundColor: Colors.red,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 80, color: Colors.red),
              SizedBox(height: 20),
              Text(
                'Access Denied',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                'Only skilled persons can manage their shop. Customers and companies can browse the shop instead.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE91E63)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProducts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No products in your shop yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to add your first product',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      color: const Color(0xFFE91E63),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _products.length,
        itemBuilder: (context, index) => _buildProductCard(_products[index]),
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: product.images.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WebImageLoader.loadImage(
                  imageUrl: product.images.first,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              )
            : Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image, color: Colors.grey[600]),
              ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('₹${product.price.toStringAsFixed(2)}'),
            const SizedBox(height: 2),
            Text(
              'Stock: ${product.stock}',
              style: TextStyle(
                color: product.stock > 0 ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _editProduct(product),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteProduct(product),
            ),
          ],
        ),
        onTap: () => _viewProduct(product),
      ),
    );
  }

  Widget _buildOrdersTab() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Please sign in'));
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _firestoreService.streamSellerOrders(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE91E63)));
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No Orders Yet',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700])),
                const SizedBox(height: 8),
                Text('Orders from your shop will appear here',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500])),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _buildOrderCard(order);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final statusColors = {
      'pending': Colors.orange,
      'confirmed': Colors.blue,
      'shipped': Colors.purple,
      'out_for_delivery': const Color(0xFFEF6C00),
      'delivered': Colors.green,
      'failed_delivery': Colors.red,
      'cancelled': Colors.red,
    };
    final color = statusColors[order.status] ?? Colors.grey;
    final usesDeliveryPartner = order.deliveryByPartner;
    final canCancel = order.status == 'pending' || order.status == 'confirmed';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(order.productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color),
                  ),
                  child: Text(order.status.toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Qty: ${order.quantity}  -  Rs ${order.totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.grey),
            ),
            if (order.buyerName != null)
              Text('Buyer: ${order.buyerName}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            _buildOrderAddress(order),
            Text(
              usesDeliveryPartner
                  ? 'Fulfillment: Delivery Partner'
                  : 'Fulfillment: Seller Delivery',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (order.status != 'delivered' &&
                order.status != 'cancelled' &&
                order.status != 'failed_delivery')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (order.status == 'pending')
                    TextButton(
                      onPressed: () => _updateOrderStatus(order, 'confirmed'),
                      child: const Text('Confirm Availability'),
                    ),
                  if (order.status == 'confirmed' && !usesDeliveryPartner) ...[
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final sellerId =
                              FirebaseAuth.instance.currentUser?.uid ??
                                  order.sellerId;
                          await _firestoreService.handoverOrderToDeliveryPartner(
                            orderId: order.id,
                            sellerId: sellerId,
                          );
                          if (mounted) {
                            AppDialog.success(
                                context, 'Assigned to delivery partner!');
                          }
                        } catch (e) {
                          if (mounted) {
                            AppDialog.error(context,
                                'Failed to assign delivery',
                                detail: e.toString());
                          }
                        }
                      },
                      icon: const Icon(Icons.delivery_dining, size: 16),
                      label: const Text('Assign Delivery Partner'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE65100),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _updateOrderStatus(order, 'shipped'),
                      child: const Text('Mark Shipped'),
                    ),
                  ],
                  if (order.status == 'confirmed' && usesDeliveryPartner)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text(
                        'Awaiting delivery pickup',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFEF6C00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (order.status == 'shipped' && !usesDeliveryPartner)
                    TextButton(
                      onPressed: () => _updateOrderStatus(order, 'delivered'),
                      child: const Text('Mark Delivered'),
                    ),
                  if (canCancel)
                    TextButton(
                      onPressed: () => _updateOrderStatus(order, 'cancelled'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderAddress(OrderModel order) {
    final directAddress =
        order.deliveryAddress?.trim() ?? order.deliveryLocation?.trim();
    if (directAddress != null && directAddress.isNotEmpty) {
      return Text(
        'Address: $directAddress',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }

    return FutureBuilder<CustomerProfile?>(
      future: _firestoreService.getCustomerProfile(order.buyerId),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final loc = profile?.location?.trim();
        final city = profile?.city?.trim();
        String display;
        if (loc != null && loc.isNotEmpty) {
          display = (city != null && city.isNotEmpty && !loc.contains(city))
              ? '$loc, $city'
              : loc;
        } else if (city != null && city.isNotEmpty) {
          display = city;
        } else {
          display = 'Not provided';
        }

        return Text(
          'Address: $display',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        );
      },
    );
  }

  Future<void> _updateOrderStatus(OrderModel order, String status) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      await _firestoreService.updateOrderStatus(
        orderId: order.id,
        sellerId: userId,
        status: status,
      );
      if (mounted) {
        AppDialog.success(context, 'Order marked as $status');
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Error updating order', detail: e.toString());
      }
    }
  }

  Widget _buildMyOrdersTab() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Center(child: Text('Please sign in'));
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _firestoreService.streamBuyerOrders(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE91E63)),
          );
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag_outlined,
                    size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No Orders Placed Yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Orders you place as a buyer will appear here',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _buildPurchasedOrderCard(order);
          },
        );
      },
    );
  }

  Color _purchasedOrderStatusColor(String s) {
    switch (s) {
      case 'delivered':
        return Colors.green;
      case 'out_for_delivery':
        return Colors.orange;
      case 'shipped':
        return const Color(0xFF2196F3);
      case 'confirmed':
        return Colors.blue;
      case 'cancelled':
      case 'failed_delivery':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _purchasedOrderStatusLabel(String s) {
    switch (s) {
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'failed_delivery':
        return 'Failed';
      default:
        if (s.isEmpty) return 'Pending';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  Widget _buildPurchasedOrderCard(OrderModel order) {
    final statusColor = _purchasedOrderStatusColor(order.status);
    final statusLabel = _purchasedOrderStatusLabel(order.status);
    final orderCode = order.id.length >= 8
        ? order.id.substring(0, 8).toUpperCase()
        : order.id.toUpperCase();
    final address =
        order.deliveryAddress?.trim() ?? order.deliveryLocation?.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(order: order),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      order.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Order #$orderCode  •  ₹${order.totalPrice.toStringAsFixed(2)}  •  Qty: ${order.quantity}',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                AppHelpers.formatDateTime(order.createdAt),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              if (address != null && address.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Address: $address',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if ((order.deliveryVerificationCode ?? '').trim().isNotEmpty &&
                  order.status != 'delivered') ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_outlined,
                          size: 18, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      Text(
                        'Delivery Code: ${order.deliveryVerificationCode}',
                        style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (order.status != 'cancelled') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(order: order),
                      ),
                    ),
                    icon: const Icon(Icons.timeline, size: 16),
                    label: const Text('Track Order'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE91E63),
                      side: const BorderSide(color: Color(0xFFE91E63)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final totalProducts = _products.length;
    final totalStock =
        _products.fold<int>(0, (sum, product) => sum + product.stock);
    final averagePrice = _products.isEmpty
        ? 0.0
        : _products.fold<double>(0, (sum, product) => sum + product.price) /
            _products.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAnalyticsCard(
          'Total Products',
          '$totalProducts',
          Icons.inventory,
          const Color(0xFFE91E63),
        ),
        const SizedBox(height: 12),
        _buildAnalyticsCard(
          'Total Stock',
          '$totalStock',
          Icons.store,
          Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildAnalyticsCard(
          'Average Price',
          '₹${averagePrice.toStringAsFixed(2)}',
          Icons.currency_rupee,
          Colors.green,
        ),
        const SizedBox(height: 12),
        _buildAnalyticsCard(
          'Products Out of Stock',
          '${_products.where((p) => p.stock == 0).length}',
          Icons.warning,
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  void _addProduct(BuildContext context) async {
    // SECURITY: Check if user is verified before allowing shop/product creation
    final authProvider =
        Provider.of<app_auth.AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final nav = Navigator.of(context);

    // Load profile if not already loaded
    if (userProvider.currentProfile == null &&
        authProvider.currentUser != null) {
      await userProvider.loadProfile(authProvider.currentUser!.uid);
    }

    // Check verification status
    if (userProvider.currentProfile?.isVerified != true) {
      if (!context.mounted) return;
      final shouldVerify = await AppDialog.confirm(
        context,
        title: 'Verification Required',
        message:
            'You must verify your Aadhaar to open a shop and sell products. This keeps buyer trust and platform safety intact.\n\nPlease complete identity verification from your profile setup.',
        confirmText: 'Verify Now',
        gradientColors: const [Color(0xFFFF9800), Color(0xFFE91E63)],
        icon: Icons.security_rounded,
      );
      if (shouldVerify == true && context.mounted) {
        Navigator.pushNamed(context, '/skilled-setup');
      }
      return;
    }

    // Verified - proceed to add product
    final result = await nav.push(
      MaterialPageRoute(
        builder: (context) => const AddProductScreen(),
      ),
    );

    if (result == true && mounted) {
      _loadProducts(); // Refresh the list
    }
  }

  void _viewProduct(ProductModel product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: product),
      ),
    );
  }

  void _editProduct(ProductModel product) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductScreen(existingProduct: product),
      ),
    );
    if (result == true && mounted) {
      _loadProducts();
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirm = await AppDialog.confirm(
      context,
      title: 'Delete Product',
      message: 'Are you sure you want to delete "${product.name}"?',
      confirmText: 'Delete',
      gradientColors: const [Color(0xFFE53935), Color(0xFFFF7043)],
      icon: Icons.delete_forever_rounded,
    );

    if (confirm == true) {
      try {
        await _firestoreService.deleteProduct(product.id);
        _loadProducts();
        if (mounted) {
          AppDialog.success(context, 'Product deleted successfully');
        }
      } catch (e) {
        if (mounted) {
          AppDialog.error(context, 'Error deleting product',
              detail: e.toString());
        }
      }
    }
  }

  void _openShopSettings(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    _openShopSettingsGuarded(context, userId);
  }

  Future<void> _openShopSettingsGuarded(
      BuildContext context, String userId) async {
    final userSettings = await _firestoreService.getUserSettings(userId);
    final isDeliveryWorkflowEnabled =
        userSettings['enableShopDeliveryWorkflow'] as bool? ?? false;

    if (!isDeliveryWorkflowEnabled) {
      if (!context.mounted) return;
      final shouldEnable = await AppDialog.confirm(
        context,
        title: 'Enable Delivery Workflow',
        message:
            'Shop delivery settings are disabled in your profile settings.\n\nEnable them now to manage delivery controls in My Shop.',
        confirmText: 'Enable Now',
        gradientColors: const [Color(0xFFE91E63), Color(0xFFFF9800)],
        icon: Icons.settings_suggest_rounded,
      );

      if (shouldEnable == true) {
        await _firestoreService.updateUserSettings(userId, {
          ...userSettings,
          'enableShopDeliveryWorkflow': true,
        });
        if (context.mounted) {
          AppDialog.success(context,
              'Delivery workflow enabled. Opening profile settings...');
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }
      } else {
        return;
      }
    }

    if (!context.mounted) return;
    final shopNameController = TextEditingController();
    final shopDescController = TextEditingController();
    final maxDeliveryQtyController = TextEditingController(text: '10');
    bool enableDeliveryIfAvailable = true;
    bool hasLoadedSettings = false;
    bool isLoading = false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!isLoading && !hasLoadedSettings) {
            isLoading = true;
            _firestoreService.getShopSettings(userId).then((settings) {
              setDialogState(() {
                shopNameController.text = settings['shopName'] as String? ?? '';
                shopDescController.text =
                    settings['shopDescription'] as String? ?? '';
                enableDeliveryIfAvailable =
                    settings['enableDeliveryIfAvailable'] != false;
                final configuredLimit = settings['maxDeliveryQuantity'];
                final maxLimit = configuredLimit is int
                    ? configuredLimit
                    : int.tryParse('${configuredLimit ?? ''}') ?? 10;
                maxDeliveryQtyController.text =
                    (maxLimit > 0 ? maxLimit : 10).toString();
                hasLoadedSettings = true;
                isLoading = false;
              });
            });
          }
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.store, color: Color(0xFFE91E63)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shop Settings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: isLoading
                ? const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: shopNameController,
                          decoration: const InputDecoration(
                            labelText: 'Shop Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.storefront),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: shopDescController,
                          decoration: const InputDecoration(
                            labelText: 'Shop Description',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: enableDeliveryIfAvailable,
                          onChanged: (value) => setDialogState(
                              () => enableDeliveryIfAvailable = value),
                          title: const Text('Allow Delivery Partner'),
                          subtitle: const Text(
                            'Enable delivery-partner flow when stock is available.',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: maxDeliveryQtyController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Delivery Quantity',
                            hintText: 'Example: 10',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.numbers),
                          ),
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
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final parsedMaxQty = int.tryParse(
                                maxDeliveryQtyController.text.trim()) ??
                            10;
                        final maxDeliveryQty =
                            parsedMaxQty > 0 ? parsedMaxQty : 10;
                        try {
                          await _firestoreService.updateShopSettings(userId, {
                            'shopName': shopNameController.text.trim(),
                            'shopDescription': shopDescController.text.trim(),
                            'enableDeliveryIfAvailable':
                                enableDeliveryIfAvailable,
                            'maxDeliveryQuantity': maxDeliveryQty,
                          });
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          // ignore: use_build_context_synchronously
                          AppDialog.success(context, 'Shop settings saved!');
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          AppDialog.error(
                              context, 'Could not save shop settings',
                              detail: e.toString());
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE91E63)),
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
}
