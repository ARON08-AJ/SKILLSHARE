import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/cart_item_model.dart';
import '../../models/order_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_helpers.dart';
import '../../utils/app_dialog.dart';
import '../../utils/web_image_loader.dart';
import '../../widgets/app_popup.dart';
import '../../widgets/gpay_simulation_dialog.dart';
import 'order_tracking_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  String? _currentUserId;
  bool _isCheckingOut = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _calculateTotal(List<CartItemModel> items) {
    return items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  Future<void> _updateQuantity(CartItemModel item, int newQuantity) async {
    if (_currentUserId == null) return;
    try {
      await _firestoreService.updateCartItemQuantity(
        userId: _currentUserId!,
        productId: item.productId,
        quantity: newQuantity,
      );
    } catch (e) {
      if (mounted) {
        AppPopup.show(context, message: 'Error: $e', type: PopupType.error);
      }
    }
  }

  Future<void> _removeItem(CartItemModel item) async {
    if (_currentUserId == null) return;
    try {
      await _firestoreService.removeCartItem(
        userId: _currentUserId!,
        productId: item.productId,
      );
      if (mounted) {
        AppPopup.show(
          context,
          message: '${item.productName} removed from cart',
          type: PopupType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppPopup.show(context, message: 'Error: $e', type: PopupType.error);
      }
    }
  }

  Future<void> _checkout(List<CartItemModel> items) async {
    if (_currentUserId == null || _isCheckingOut) return;
    if (items.isEmpty) {
      AppPopup.show(context,
          message: 'Your cart is empty', type: PopupType.warning);
      return;
    }

    final total = _calculateTotal(items);
    final checkoutDetails = await _collectCheckoutDetails();
    if (checkoutDetails == null || !mounted) return;

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    final txnId = await GPaySimulationDialog.show(
      context,
      amount: total,
      recipientName: 'SkillShare Shop',
      description: 'Cart Checkout - ${items.length} item(s)',
    );

    if (txnId == null || !mounted) return;

    setState(() => _isCheckingOut = true);
    try {
      final orders = await _firestoreService.checkoutCart(
        _currentUserId!,
        paymentMethod: 'gpay_simulation',
        paymentReference: txnId,
        deliveryAddress: checkoutDetails.address,
      );
      if (mounted) {
        final codeLines = orders
            .map((order) =>
                '${order.productName}: ${order.deliveryVerificationCode ?? 'N/A'}')
            .join('\n');
        await AppDialog.success(
          context,
          '${orders.length} order(s) placed.\n'
          'Total: ₹${total.toStringAsFixed(2)}\n\n'
          'Delivery address:\n'
          '${checkoutDetails.address}\n\n'
          'Share this delivery code with the delivery person only when asked:\n'
          '$codeLines',
          title: 'Order Placed',
          buttonText: 'OK',
        );
      }
    } catch (e) {
      if (mounted) {
        AppPopup.show(context,
            message: 'Checkout failed: $e', type: PopupType.error);
      }
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  Future<_CheckoutDetails?> _collectCheckoutDetails() async {
    if (_currentUserId == null) return null;

    final addressSnapshot =
        await _firestoreService.resolveUserAddressSnapshot(_currentUserId!);
    if (!mounted) return null;

    final defaultAddress =
        (addressSnapshot['formattedAddress'] as String? ?? '').trim();

    return showDialog<_CheckoutDetails>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _CartDeliveryAddressDialog(savedAddress: defaultAddress),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Cart', style: TextStyle(color: Colors.white)),
          flexibleSpace: _buildGradient(),
        ),
        body: const Center(child: Text('Please sign in to view your cart')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart', style: TextStyle(color: Colors.white)),
        flexibleSpace: _buildGradient(),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: EdgeInsets.zero,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.shopping_cart, size: 18),
              iconMargin: EdgeInsets.only(bottom: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Cart', maxLines: 1),
              ),
            ),
            Tab(
              icon: Icon(Icons.list_alt, size: 18),
              iconMargin: EdgeInsets.only(bottom: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('My Orders', maxLines: 1),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCartTabBody(),
          _buildOrdersTabBody(),
        ],
      ),
    );
  }

  Widget _buildCartTabBody() {
    return StreamBuilder<List<CartItemModel>>(
      stream: _firestoreService.streamCartItems(_currentUserId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Your cart is empty',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Browse the shop and add products to your cart',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final total = _calculateTotal(items);

        return Column(
          children: [
            // Item count header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Icon(Icons.shopping_cart, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length} item${items.length == 1 ? '' : 's'} in cart',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),

            // Cart Items
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildCartItemCard(item);
                },
              ),
            ),

            // Bottom summary
            _buildSummarySection(items, total),
          ],
        );
      },
    );
  }

  Widget _buildCartItemCard(CartItemModel item) {
    final isUnavailable = !item.isAvailable || item.availableStock <= 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
                child: item.productImage != null
                    ? WebImageLoader.loadImage(
                        imageUrl: item.productImage,
                        fit: BoxFit.cover,
                        width: 80,
                        height: 80,
                      )
                    : Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.image,
                            size: 40, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 20, color: Colors.red),
                        onPressed: () => _removeItem(item),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${item.price.toStringAsFixed(2)} each',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  if (isUnavailable) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Out of stock',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Quantity controls
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () =>
                                  _updateQuantity(item, item.quantity - 1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  item.quantity <= 1
                                      ? Icons.delete_outline
                                      : Icons.remove,
                                  size: 16,
                                  color: item.quantity <= 1
                                      ? Colors.red
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              color: Colors.grey[100],
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: item.quantity >= item.availableStock
                                  ? null
                                  : () =>
                                      _updateQuantity(item, item.quantity + 1),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.add,
                                  size: 16,
                                  color: item.quantity >= item.availableStock
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Subtotal
                      Text(
                        '₹${item.totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFFE91E63),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(List<CartItemModel> items, double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subtotal (${items.fold<int>(0, (s, i) => s + i.quantity)} items)',
                  style: const TextStyle(fontSize: 16),
                ),
                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Delivery', style: TextStyle(color: Colors.grey[600])),
                const Text('Free', style: TextStyle(color: Colors.green)),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE91E63),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE91E63), Color(0xFFFF9800)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isCheckingOut ? null : () => _checkout(items),
                  icon: _isCheckingOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.payment, color: Colors.white),
                  label: Text(
                    _isCheckingOut
                        ? 'Processing...'
                        : 'Checkout  ₹${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTabBody() {
    if (_currentUserId == null) {
      return const Center(child: Text('Please sign in to view orders'));
    }
    return StreamBuilder<List<OrderModel>>(
      stream: _firestoreService.streamBuyerOrders(_currentUserId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 72, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No orders yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your order history will appear here',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: orders.length,
          itemBuilder: (ctx, i) {
            final order = orders[i];
            return _OrderHistoryCard(order: order);
          },
        );
      },
    );
  }

  Widget _buildGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE91E63), Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});
  final OrderModel order;

  Color _statusColor(String s) {
    switch (s) {
      case 'delivered':
        return Colors.green;
      case 'out_for_delivery':
        return Colors.orange;
      case 'shipped':
        return const Color(0xFF2196F3);
      case 'cancelled':
      case 'failed_delivery':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String s) {
    switch (s.trim().toLowerCase()) {
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'failed_delivery':
        return 'Failed';
      case 'delivered':
        return 'Delivered';
      case 'shipped':
        return 'Shipped';
      case 'confirmed':
        return 'Confirmed';
      case 'cancelled':
        return 'Cancelled';
      default:
        final clean = s.trim();
        if (clean.isEmpty) return 'Pending';
        return clean[0].toUpperCase() + clean.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderIdShort = order.id.length > 8
        ? order.id.substring(0, 8).toUpperCase()
        : order.id.toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.productName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(order.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(order.status),
                    style: TextStyle(
                      color: _statusColor(order.status),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Order #$orderIdShort  •  '
              '₹${order.totalPrice.toStringAsFixed(2)}  •  '
              'Qty: ${order.quantity}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              AppHelpers.formatDateTime(order.createdAt),
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            if ((order.deliveryAddress?.trim() ?? order.deliveryLocation?.trim() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Address: ${order.deliveryAddress?.trim() ?? order.deliveryLocation?.trim()}',
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
            if ((order.deliveryVerificationCode ?? '').trim().isNotEmpty &&
                order.status != 'delivered') ...[
              const SizedBox(height: 6),
              Text(
                'Delivery Code: ${order.deliveryVerificationCode}',
                style: const TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Track button - only for non-cancelled orders
            if (order.status != 'cancelled')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(order: order)),
                  ),
                  icon: const Icon(Icons.timeline, size: 16),
                  label: const Text('Track Order'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE91E63),
                    side: const BorderSide(color: Color(0xFFE91E63)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutDetails {
  const _CheckoutDetails({
    required this.address,
  });

  final String address;
}

class _CartDeliveryAddressDialog extends StatefulWidget {
  final String savedAddress;

  const _CartDeliveryAddressDialog({required this.savedAddress});

  @override
  State<_CartDeliveryAddressDialog> createState() =>
      _CartDeliveryAddressDialogState();
}

class _CartDeliveryAddressDialogState
    extends State<_CartDeliveryAddressDialog> {
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
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Confirm Delivery Address',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter or edit your delivery address for this order.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF64748B), height: 1.4),
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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
