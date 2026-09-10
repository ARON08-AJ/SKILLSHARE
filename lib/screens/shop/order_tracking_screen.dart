import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_helpers.dart';
import '../chat/chat_detail_screen.dart';

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.order});

  final OrderModel order;

  // Ordered list of all possible delivery steps
  static const _steps = [
    _TrackStep(
      key: 'pending',
      label: 'Order Placed',
      icon: Icons.receipt_long,
      description: 'Your order has been placed successfully.',
    ),
    _TrackStep(
      key: 'confirmed',
      label: 'Confirmed',
      icon: Icons.check_circle_outline,
      description: 'Seller has confirmed your order.',
    ),
    _TrackStep(
      key: 'shipped',
      label: 'Shipped',
      icon: Icons.inventory_2_outlined,
      description: 'Your order has been shipped.',
    ),
    _TrackStep(
      key: 'out_for_delivery',
      label: 'Out for Delivery',
      icon: Icons.local_shipping_outlined,
      description: 'Your order is out for delivery.',
    ),
    _TrackStep(
      key: 'delivered',
      label: 'Delivered',
      icon: Icons.home_outlined,
      description: 'Your order has been delivered.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderModel?>(
      stream: FirestoreService().streamOrder(order.id),
      initialData: order,
      builder: (context, snapshot) {
        final currentOrder = snapshot.data ?? order;
        final timeline = currentOrder.statusTimeline;
        final isCancelled = currentOrder.status == 'cancelled';
        final isFailedDelivery = currentOrder.status == 'failed_delivery';

        // Find current step index based on status or latest recorded timeline entry
        int currentStep = -1;
        for (int i = _steps.length - 1; i >= 0; i--) {
          if (timeline.containsKey(_steps[i].key) ||
              currentOrder.status == _steps[i].key) {
            currentStep = i;
            break;
          }
        }
        if (currentStep == -1 && !isCancelled) currentStep = 0;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: AppBar(
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            title: const Text(
              'Track Order',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Summary card
                _OrderSummaryCard(order: currentOrder),
                const SizedBox(height: 24),

                // Cancelled / failed banner
                if (isCancelled || isFailedDelivery) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_outlined, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isCancelled
                                ? 'This order has been cancelled.'
                                : 'Delivery attempt failed. Contact support.',
                            style: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Timeline title
                const Text(
                  'Delivery Timeline',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Timeline steps
                ...List.generate(_steps.length, (i) {
                  final step = _steps[i];
                  // A step is done if present in timeline OR if a later milestone was reached (unless cancelled/failed)
                  final isDone = timeline.containsKey(step.key) ||
                      (!isCancelled && !isFailedDelivery && i <= currentStep);
                  final isCurrent = i == currentStep &&
                      !isCancelled &&
                      !isFailedDelivery &&
                      currentOrder.status != 'delivered';
                  final isLast = i == _steps.length - 1;

                  // Estimated or actual time for this milestone
                  DateTime? stepTime = timeline[step.key];
                  if (stepTime == null && isDone) {
                    for (int j = i + 1; j < _steps.length; j++) {
                      if (timeline.containsKey(_steps[j].key)) {
                        stepTime = timeline[_steps[j].key];
                        break;
                      }
                    }
                    stepTime ??= currentOrder.createdAt;
                  }

                  return _TimelineRow(
                    step: step,
                    isDone: isDone,
                    isCurrent: isCurrent,
                    isLast: isLast,
                    time: stepTime,
                  );
                }),

                // Delivery partner section
                if (currentOrder.deliveryPartnerId != null &&
                    currentOrder.deliveryPartnerId!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _DeliveryPartnerCard(
                    order: currentOrder,
                    partnerId: currentOrder.deliveryPartnerId!,
                    partnerName:
                        currentOrder.deliveryPartnerName ?? 'Delivery Partner',
                    estimatedDelivery: currentOrder.estimatedDelivery,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Order Summary Card ────────────────────────────────────────────────────────

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_bag,
                    color: Color(0xFF6A11CB), size: 28),
              ),
              const SizedBox(width: 14),
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
                    Text(
                      'Order #${order.id.substring(0, 8).toUpperCase()}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SummaryDetail(label: 'Qty', value: '${order.quantity}'),
              _SummaryDetail(
                  label: 'Total',
                  value: '₹${order.totalPrice.toStringAsFixed(2)}'),
              _SummaryDetail(
                  label: 'Placed',
                  value: AppHelpers.formatDate(order.createdAt)),
              _SummaryDetail(
                  label: 'Payment', value: order.paymentStatus.toUpperCase()),
            ],
          ),
          if ((order.deliveryAddress ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _SummaryInfo(
              icon: Icons.home_outlined,
              label: 'Address',
              value: order.deliveryAddress!,
            ),
          ],
          if ((order.deliveryLocation ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _SummaryInfo(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: order.deliveryLocation!,
            ),
          ],
          if (FirebaseAuth.instance.currentUser?.uid == order.buyerId &&
              (order.deliveryVerificationCode ?? '').trim().isNotEmpty &&
              order.status != 'delivered') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivery Verification Code',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.deliveryVerificationCode!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share this only with the delivery person when they ask.',
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryDetail extends StatelessWidget {
  const _SummaryDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

class _SummaryInfo extends StatelessWidget {
  const _SummaryInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Timeline Row ──────────────────────────────────────────────────────────────

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
    this.time,
  });

  final _TrackStep step;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;
  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? const Color(0xFF4CAF50)
        : isCurrent
            ? const Color(0xFFFF9800)
            : Colors.grey[300]!;

    final iconColor = isDone
        ? Colors.white
        : isCurrent
            ? Colors.white
            : Colors.grey[400]!;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: icon + line
          SizedBox(
            width: 40,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: isDone || isCurrent
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    isDone ? Icons.check_rounded : step.icon,
                    color: iconColor,
                    size: isDone ? 20 : 18,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color:
                          isDone ? const Color(0xFF4CAF50) : Colors.grey[200],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Right side: content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDone || isCurrent
                              ? Colors.black87
                              : Colors.grey,
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF9800).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'IN PROGRESS',
                            style: TextStyle(
                              color: Color(0xFFFF9800),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isDone && time != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      AppHelpers.formatDateTime(time!),
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Delivery Partner Card ─────────────────────────────────────────────────────

class _DeliveryPartnerCard extends StatefulWidget {
  const _DeliveryPartnerCard({
    required this.order,
    required this.partnerId,
    required this.partnerName,
    this.estimatedDelivery,
  });

  final OrderModel order;
  final String partnerId;
  final String partnerName;
  final DateTime? estimatedDelivery;

  @override
  State<_DeliveryPartnerCard> createState() => _DeliveryPartnerCardState();
}

class _DeliveryPartnerCardState extends State<_DeliveryPartnerCard> {
  bool _isChatLoading = false;



  Future<void> _openChat() async {
    if (_isChatLoading) return;
    setState(() => _isChatLoading = true);
    try {
      final chatId = await FirestoreService().ensureDeliveryBuyerChat(
        orderId: widget.order.id,
        deliveryPartnerId: widget.partnerId,
        deliveryPartnerName: widget.partnerName,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chatId,
            otherUserId: widget.partnerId,
            otherUserName: widget.partnerName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _isChatLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserModel?>(
      stream: FirestoreService().streamUserModel(widget.partnerId),
      builder: (context, snapshot) {
        final partnerUser = snapshot.data;
        final rawPhone = partnerUser?.phone?.trim() ?? '';
        final hasPhone = rawPhone.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white30,
                    child: Icon(Icons.person, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Partner',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          widget.partnerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (widget.estimatedDelivery != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Est. Delivery: ${AppHelpers.formatDateTime(widget.estimatedDelivery!)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                hasPhone ? rawPhone : 'Contact via chat',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isChatLoading ? null : _openChat,
                  icon: _isChatLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.white),
                  label: const Text(
                    'Chat with Delivery Partner',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Data class ────────────────────────────────────────────────────────────────

class _TrackStep {
  const _TrackStep({
    required this.key,
    required this.label,
    required this.icon,
    required this.description,
  });

  final String key;
  final String label;
  final IconData icon;
  final String description;
}
