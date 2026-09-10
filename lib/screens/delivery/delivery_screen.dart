import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../models/skilled_user_profile.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_helpers.dart';
import '../../utils/app_dialog.dart';
import '../../utils/modern_pickers.dart';
import '../chat/chat_detail_screen.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final partnerId = authProvider.currentUser?.uid;
    final partnerName = authProvider.currentUser?.name ?? 'Delivery Partner';

    if (partnerId == null) {
      return const Scaffold(
        body: Center(child: Text('Not authenticated')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'Deliveries',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'My Deliveries'),
            Tab(text: 'Available'),
          ],
        ),
        elevation: 0,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyDeliveriesTab(partnerId: partnerId, partnerName: partnerName),
          _AvailableDeliveriesTab(
              partnerId: partnerId, partnerName: partnerName),
        ],
      ),
    );
  }
}

// ─── My Deliveries tab ───────────────────────────────────────────────────────

class _MyDeliveriesTab extends StatelessWidget {
  const _MyDeliveriesTab({required this.partnerId, required this.partnerName});

  final String partnerId;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final svc = FirestoreService();
    return StreamBuilder<List<OrderModel>>(
      stream: svc.streamDeliveryPartnerOrders(partnerId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load deliveries: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return const _EmptyState(
            icon: Icons.delivery_dining,
            message: 'No deliveries assigned to you yet.',
            subtitle: 'Check the "Available" tab to pick up a delivery.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (ctx, i) => _DeliveryCard(
            key: ValueKey(orders[i].id),
            order: orders[i],
            partnerId: partnerId,
            partnerName: partnerName,
            isAssigned: true,
          ),
        );
      },
    );
  }
}

// ─── Available Deliveries tab ─────────────────────────────────────────────────

class _AvailableDeliveriesTab extends StatelessWidget {
  const _AvailableDeliveriesTab(
      {required this.partnerId, required this.partnerName});

  final String partnerId;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    final svc = FirestoreService();
    return StreamBuilder<List<OrderModel>>(
      stream: svc.streamAvailableDeliveries(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load available deliveries: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        final orders = snapshot.data ?? [];
        if (orders.isEmpty) {
          return const _EmptyState(
            icon: Icons.check_circle_outline,
            message: 'No deliveries available right now.',
            subtitle: 'Check back soon for new pickups.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (ctx, i) => _DeliveryCard(
            key: ValueKey(orders[i].id),
            order: orders[i],
            partnerId: partnerId,
            partnerName: partnerName,
            isAssigned: false,
          ),
        );
      },
    );
  }
}

// ─── Delivery Card ─────────────────────────────────────────────────────────────

class _DeliveryCard extends StatefulWidget {
  const _DeliveryCard({
    super.key,
    required this.order,
    required this.partnerId,
    required this.partnerName,
    required this.isAssigned,
  });

  final OrderModel order;
  final String partnerId;
  final String partnerName;
  final bool isAssigned;

  @override
  State<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends State<_DeliveryCard> {
  UserModel? _sellerUser;
  SkilledUserProfile? _sellerProfile;
  UserModel? _buyerUser;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void didUpdateWidget(_DeliveryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.sellerId != widget.order.sellerId ||
        oldWidget.order.buyerId != widget.order.buyerId) {
      _loadProfiles();
    }
  }

  Future<void> _loadProfiles() async {
    try {
      final fs = FirestoreService();
      final futures = await Future.wait([
        fs.getUserById(widget.order.sellerId),
        fs.getSkilledUserProfile(widget.order.sellerId),
        fs.getUserById(widget.order.buyerId),
      ]);
      if (mounted) {
        setState(() {
          _sellerUser = futures[0] as UserModel?;
          _sellerProfile = futures[1] as SkilledUserProfile?;
          _buyerUser = futures[2] as UserModel?;
        });
      }
    } catch (_) {}
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF1976D2);
      case 'delivered':
        return Colors.green;
      case 'out_for_delivery':
        return Colors.orange;
      case 'shipped':
        return const Color(0xFF2196F3);
      case 'failed_delivery':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'confirmed':
        return 'Confirmed';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'failed_delivery':
        return 'Failed Delivery';
      case 'shipped':
        return 'Shipped';
      case 'pending':
        return 'Pending';
      case 'cancelled':
        return 'Cancelled';
      default:
        if (status.trim().isEmpty) return 'Pending';
        return status.trim()[0].toUpperCase() + status.trim().substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isAssigned = widget.isAssigned;
    final partnerId = widget.partnerId;

    final sellerName = _sellerUser?.name.trim().isNotEmpty == true
        ? _sellerUser!.name.trim()
        : 'Skilled Seller';
    final sellerPhone = _sellerUser?.phone?.trim() ?? '';
    final sellerAddress = _sellerProfile?.address?.trim().isNotEmpty == true
        ? _sellerProfile!.address!.trim()
        : (_sellerProfile?.city?.trim().isNotEmpty == true
            ? _sellerProfile!.city!.trim()
            : 'Seller Studio / Shop Location');

    final buyerName = order.buyerName?.trim().isNotEmpty == true
        ? order.buyerName!.trim()
        : (_buyerUser?.name.trim().isNotEmpty == true
            ? _buyerUser!.name.trim()
            : 'Customer');
    final buyerPhone = _buyerUser?.phone?.trim() ?? '';
    final buyerAddress = order.deliveryAddress?.trim().isNotEmpty == true
        ? order.deliveryAddress!.trim()
        : (order.deliveryLocation?.trim().isNotEmpty == true
            ? order.deliveryLocation!.trim()
            : 'Delivery address specified in order');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: ID & Status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_shipping_rounded,
                      color: Color(0xFFFF6B35), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppHelpers.formatDateTime(order.createdAt),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
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
            const SizedBox(height: 14),

            // 1. Product Details Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  if (order.productImage != null &&
                      order.productImage!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        order.productImage!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 54,
                          height: 54,
                          color: Colors.grey[200],
                          child: const Icon(Icons.inventory_2_outlined,
                              color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2_rounded,
                          color: Color(0xFFFF6B35)),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.productName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Qty: ${order.quantity}',
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${order.totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF2E7D32),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
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
            const SizedBox(height: 12),

            // 2. Pickup Location (Seller / Skilled Person)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.storefront_rounded,
                          size: 18, color: Color(0xFFE65100)),
                      SizedBox(width: 6),
                      Text(
                        'Pickup Location (Seller)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Seller: $sellerName',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF263238)),
                  ),
                  if (sellerPhone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Phone: $sellerPhone',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Address: $sellerAddress',
                    style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 3. Deliver To (Customer / Buyer)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBDEFB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 18, color: Color(0xFF1565C0)),
                      SizedBox(width: 6),
                      Text(
                        'Deliver To (Customer)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Customer: $buyerName',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF263238)),
                  ),
                  if (buyerPhone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Phone: $buyerPhone',
                      style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Address: $buyerAddress',
                    style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                  ),
                ],
              ),
            ),

            if (order.estimatedDelivery != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                Icons.schedule,
                'Est. Delivery',
                AppHelpers.formatDateTime(order.estimatedDelivery!),
              ),
            ],

            if ((order.deliveryVerificationCode ?? '').trim().isNotEmpty &&
                isAssigned &&
                order.status == 'out_for_delivery')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Ask the customer for their delivery verification code before marking this as delivered.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1565C0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // Action Buttons
            if (!isAssigned && order.status == 'confirmed')
              _AcceptButton(
                order: order,
                partnerId: partnerId,
                partnerName: widget.partnerName,
              ),

            if (isAssigned && order.status == 'out_for_delivery') ...[
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Mark Delivered',
                      icon: Icons.check_circle,
                      color: Colors.green,
                      onTap: () =>
                          _updateStatus(order, partnerId, 'delivered'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: 'Failed',
                      icon: Icons.cancel,
                      color: Colors.red,
                      onTap: () =>
                          _updateStatus(order, partnerId, 'failed_delivery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      _updateEstimatedDelivery(context, order, partnerId),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: const Text('Update Delivery ETA'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1976D2)),
                ),
              ),
            ],

            // Communication Buttons (Chat with Seller & Chat with Customer)
            if (isAssigned) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (order.sellerId.trim().isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openSellerChat(context, order, partnerId),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text(
                           'Chat Seller',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE65100),
                          side: const BorderSide(color: Color(0xFFE65100)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  if (order.sellerId.trim().isNotEmpty &&
                      order.buyerId.trim().isNotEmpty)
                    const SizedBox(width: 10),
                  if (order.buyerId.trim().isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openBuyerChat(context, order, partnerId),
                        icon: const Icon(Icons.chat_outlined, size: 16),
                        label: const Text(
                          'Chat Customer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1565C0),
                          side: const BorderSide(color: Color(0xFF1565C0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openSellerChat(
    BuildContext context,
    OrderModel order,
    String partnerId,
  ) async {
    try {
      final service = FirestoreService();
      final seller = await service.getUserById(order.sellerId);
      final chatId = await service.ensureDeliverySellerChat(
        orderId: order.id,
        deliveryPartnerId: partnerId,
        deliveryPartnerName: widget.partnerName,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chatId,
            otherUserId: order.sellerId,
            otherUserName: seller?.name.trim().isNotEmpty == true
                ? seller!.name
                : 'Skilled Seller',
            otherUserPhoto: seller?.profilePhoto,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppDialog.error(
          context,
          'Unable to open chat with seller',
          detail: e.toString(),
        );
      }
    }
  }

  Future<void> _openBuyerChat(
    BuildContext context,
    OrderModel order,
    String partnerId,
  ) async {
    try {
      final service = FirestoreService();
      final buyer = await service.getUserById(order.buyerId);
      final chatId = await service.ensureDeliveryBuyerChat(
        orderId: order.id,
        deliveryPartnerId: partnerId,
        deliveryPartnerName: widget.partnerName,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chatId,
            otherUserId: order.buyerId,
            otherUserName: order.buyerName?.trim().isNotEmpty == true
                ? order.buyerName!
                : (buyer?.name.trim().isNotEmpty == true
                    ? buyer!.name
                    : 'Customer'),
            otherUserPhoto: buyer?.profilePhoto,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppDialog.error(
          context,
          'Unable to open chat with customer',
          detail: e.toString(),
        );
      }
    }
  }

  Future<void> _updateStatus(
    OrderModel order,
    String partnerId,
    String status,
  ) async {
    try {
      String? verificationCode;
      if (status == 'delivered') {
        verificationCode = await _promptDeliveryCode(context, order);
        if (verificationCode == null || verificationCode.isEmpty) return;
      }
      if (!mounted) return;
      await FirestoreService().updateDeliveryStatus(
        orderId: order.id,
        deliveryPartnerId: partnerId,
        status: status,
        deliveryVerificationCode: verificationCode,
      );
      if (!mounted) return;
      if (status == 'delivered') {
        AppDialog.success(
            context, 'Delivery code verified. Marked as delivered!');
      } else {
        AppDialog.error(context, 'Marked as failed delivery.');
      }
    } catch (e) {
      if (!mounted) return;
      AppDialog.error(context, 'Error updating delivery status',
          detail: e.toString());
    }
  }

  Future<String?> _promptDeliveryCode(
    BuildContext context,
    OrderModel order,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Verify Delivery Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ask ${order.buyerName ?? 'the customer'} for the delivery code before handing over the product.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Customer code',
                hintText: 'Enter 6-digit code',
                prefixIcon: const Icon(Icons.password_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _updateEstimatedDelivery(
    BuildContext context,
    OrderModel order,
    String partnerId,
  ) async {
    final selected = await _pickEstimatedDelivery(context);
    if (selected == null) return;
    try {
      await FirestoreService().updateDeliveryEstimate(
        orderId: order.id,
        deliveryPartnerId: partnerId,
        estimatedDelivery: selected,
      );
      if (context.mounted) {
        AppDialog.success(context, 'Delivery ETA updated.');
      }
    } catch (e) {
      if (context.mounted) {
        AppDialog.error(context, 'Error updating ETA', detail: e.toString());
      }
    }
  }

  Future<DateTime?> _pickEstimatedDelivery(BuildContext context) async {
    final now = DateTime.now();
    final pickedDate = await ModernPickers.showModernDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
      seedColor: const Color(0xFFFF6B35),
      helpText: 'Select Delivery Date',
      confirmText: 'Select',
    );
    if (pickedDate == null || !context.mounted) return null;

    final pickedTime = await ModernPickers.showModernTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 48))),
      seedColor: const Color(0xFFFF6B35),
      helpText: 'Select Delivery Time',
      confirmText: 'Set Time',
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }
}

class _AcceptButton extends StatefulWidget {
  const _AcceptButton({
    required this.order,
    required this.partnerId,
    required this.partnerName,
  });

  final OrderModel order;
  final String partnerId;
  final String partnerName;

  @override
  State<_AcceptButton> createState() => _AcceptButtonState();
}

class _AcceptButtonState extends State<_AcceptButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _accept,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.local_shipping),
        label: Text(_loading ? 'Accepting...' : 'Accept Delivery'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _accept() async {
    final estimatedDelivery = await _pickEstimatedDelivery(context);
    if (estimatedDelivery == null) return;

    setState(() => _loading = true);
    try {
      await FirestoreService().assignDeliveryPartner(
        orderId: widget.order.id,
        deliveryPartnerId: widget.partnerId,
        deliveryPartnerName: widget.partnerName,
        estimatedDelivery: estimatedDelivery,
      );
      if (mounted) {
        AppDialog.success(context, 'Delivery accepted! You are now assigned.');
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Error accepting delivery',
            detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<DateTime?> _pickEstimatedDelivery(BuildContext context) async {
    final now = DateTime.now();
    final pickedDate = await ModernPickers.showModernDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
      seedColor: const Color(0xFFFF6B35),
      helpText: 'Select Delivery Date',
      confirmText: 'Select',
    );
    if (pickedDate == null || !context.mounted) return null;

    final pickedTime = await ModernPickers.showModernTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 48))),
      seedColor: const Color(0xFFFF6B35),
      helpText: 'Select Delivery Time',
      confirmText: 'Set Time',
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.subtitle,
  });
  final IconData icon;
  final String message;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: const Color(0xFFFF6B35)),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
