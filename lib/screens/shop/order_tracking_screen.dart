import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/chat_service.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_dialog.dart';
import '../../utils/app_helpers.dart';
import '../../utils/web_image_loader.dart';
import '../chat/chat_detail_screen.dart';

class OrderTrackingScreen extends StatelessWidget {
  const OrderTrackingScreen({super.key, required this.order});

  final OrderModel order;

  // Ordered list of all possible delivery steps for physical products
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

        // Route to dedicated Service Progress View for services
        if (currentOrder.isService) {
          return _ServiceProgressScreen(order: currentOrder);
        }

        // Physical product delivery tracking
        final timeline = currentOrder.statusTimeline;
        final isCancelled = currentOrder.status == 'cancelled';
        final isFailedDelivery = currentOrder.status == 'failed_delivery';

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

                // Delivery Timeline title
                const Text(
                  'Delivery Timeline',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Timeline steps
                ...List.generate(_steps.length, (i) {
                  final step = _steps[i];
                  final isDone = timeline.containsKey(step.key) ||
                      (!isCancelled && !isFailedDelivery && i <= currentStep);
                  final isCurrent = i == currentStep &&
                      !isCancelled &&
                      !isFailedDelivery &&
                      currentOrder.status != 'delivered';
                  final isLast = i == _steps.length - 1;

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

// ─── Dedicated Service Progress Screen ──────────────────────────────────────────

class _ServiceProgressScreen extends StatefulWidget {
  const _ServiceProgressScreen({required this.order});
  final OrderModel order;

  @override
  State<_ServiceProgressScreen> createState() => _ServiceProgressScreenState();
}

class _ServiceProgressScreenState extends State<_ServiceProgressScreen> {
  bool _isActionLoading = false;
  bool _isChatLoading = false;

  static const List<_ServiceStageInfo> _stages = [
    _ServiceStageInfo(
      key: AppConstants.serviceStatusAccepted,
      label: 'Request Accepted',
      description: 'Skilled person accepted your service request.',
      icon: Icons.check_circle_outline,
    ),
    _ServiceStageInfo(
      key: AppConstants.serviceStatusRequirementGathering,
      label: 'Requirement Gathering',
      description: 'Discuss customer requirements and collect necessary details.',
      icon: Icons.assignment_outlined,
    ),
    _ServiceStageInfo(
      key: AppConstants.serviceStatusProjectWork,
      label: 'Project Work',
      description: 'Skilled person works on the requested service.',
      icon: Icons.engineering_outlined,
    ),
    _ServiceStageInfo(
      key: AppConstants.serviceStatusTesting,
      label: 'Testing',
      description: 'Verify and test the completed work.',
      icon: Icons.biotech_outlined,
    ),
    _ServiceStageInfo(
      key: AppConstants.serviceStatusReview,
      label: 'Review',
      description: 'Customer reviews the completed service.',
      icon: Icons.rate_review_outlined,
    ),
    _ServiceStageInfo(
      key: AppConstants.serviceStatusFinished,
      label: 'Finished',
      description: 'Service is completed successfully.',
      icon: Icons.task_alt_outlined,
    ),
  ];

  String _getReadableStage(String stageKey) {
    switch (stageKey) {
      case AppConstants.serviceStatusRequested:
        return 'Request Pending';
      case AppConstants.serviceStatusAccepted:
        return 'Accepted';
      case AppConstants.serviceStatusRequirementGathering:
        return 'Requirement Gathering';
      case AppConstants.serviceStatusProjectWork:
        return 'Project Work';
      case AppConstants.serviceStatusTesting:
        return 'Testing';
      case AppConstants.serviceStatusReview:
        return 'Review';
      case AppConstants.serviceStatusFinished:
        return 'Finished';
      case AppConstants.serviceStatusRejected:
        return 'Declined';
      case AppConstants.serviceStatusCancelled:
        return 'Cancelled';
      default:
        return stageKey.replaceAll('_', ' ').toUpperCase();
    }
  }

  String? _getNextStageKey(String currentStage) {
    switch (currentStage) {
      case AppConstants.serviceStatusAccepted:
        return AppConstants.serviceStatusRequirementGathering;
      case AppConstants.serviceStatusRequirementGathering:
        return AppConstants.serviceStatusProjectWork;
      case AppConstants.serviceStatusProjectWork:
        return AppConstants.serviceStatusTesting;
      case AppConstants.serviceStatusTesting:
        return AppConstants.serviceStatusReview;
      case AppConstants.serviceStatusReview:
        return AppConstants.serviceStatusFinished;
      default:
        return null;
    }
  }

  String _getNextStageActionLabel(String nextKey) {
    switch (nextKey) {
      case AppConstants.serviceStatusRequirementGathering:
        return 'Start Requirement Gathering';
      case AppConstants.serviceStatusProjectWork:
        return 'Start Project Work';
      case AppConstants.serviceStatusTesting:
        return 'Proceed to Testing';
      case AppConstants.serviceStatusReview:
        return 'Submit for Customer Review';
      case AppConstants.serviceStatusFinished:
        return 'Mark Service as Finished';
      default:
        return 'Advance to ${_getReadableStage(nextKey)}';
    }
  }

  Future<void> _advanceStage(String nextStageKey) async {
    if (_isActionLoading) return;
    final nextLabel = _getReadableStage(nextStageKey);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Advance to $nextLabel?'),
        content: Text(
          'Are you sure you want to advance this service to "$nextLabel"? '
          'Stages must follow strict sequential order and cannot be skipped or undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A11CB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await FirestoreService().updateServiceStage(widget.order.id, nextStageKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Service progressed to $nextLabel!'),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Could not update stage', detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _acceptRequest() async {
    if (_isActionLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Accept Service Request?'),
        content: const Text(
          'By accepting, you commit to providing this service according to the project timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await FirestoreService().acceptServiceRequest(widget.order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service request accepted! Timeline created.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Could not accept request', detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _rejectRequest() async {
    if (_isActionLoading) return;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Service Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide an optional reason for the client:'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Currently unavailable, outside domain...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await FirestoreService().rejectServiceRequest(
        widget.order.id,
        reason: reasonController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service request declined.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Could not decline request', detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _openChat(String currentUserId, String otherUserId, String otherUserName) async {
    if (_isChatLoading) return;
    setState(() => _isChatLoading = true);
    try {
      final chatId = await ChatService().getOrCreateChat(
        currentUserId,
        otherUserId,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chatId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        AppDialog.error(context, 'Could not open chat', detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isChatLoading = false);
    }
  }

  DateTime? _findStageTimestamp(String stageKey) {
    for (final item in widget.order.serviceTimeline) {
      if (item['stage'] == stageKey) {
        final raw = item['updatedAt'];
        if (raw is Timestamp) return raw.toDate();
        if (raw is DateTime) return raw;
        if (raw is String) return DateTime.tryParse(raw);
      }
    }
    return widget.order.statusTimeline[stageKey];
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isSeller = currentUserId == widget.order.sellerId;

    final otherUserId = isSeller ? widget.order.buyerId : widget.order.sellerId;
    final otherUserName = isSeller
        ? (widget.order.buyerName ?? 'Customer')
        : (widget.order.sellerName ?? 'Skilled Person');

    final stage = widget.order.serviceStatus ??
        (widget.order.status == 'delivered'
            ? AppConstants.serviceStatusFinished
            : (widget.order.status == 'pending'
                ? AppConstants.serviceStatusRequested
                : widget.order.status));

    final isRequested = stage == AppConstants.serviceStatusRequested ||
        (widget.order.status == 'pending' && widget.order.serviceStatus == null);
    final isRejected = stage == AppConstants.serviceStatusRejected ||
        widget.order.status == AppConstants.serviceStatusRejected;
    final isCancelled = stage == AppConstants.serviceStatusCancelled ||
        widget.order.status == 'cancelled';
    final isFinished = stage == AppConstants.serviceStatusFinished ||
        widget.order.status == 'delivered';

    // Find current active stage index
    int currentStageIndex = -1;
    if (isFinished) {
      currentStageIndex = _stages.length - 1;
    } else if (!isRequested && !isRejected && !isCancelled) {
      for (int i = 0; i < _stages.length; i++) {
        if (_stages[i].key == stage) {
          currentStageIndex = i;
          break;
        }
      }
      if (currentStageIndex == -1 && stage == AppConstants.serviceStatusAccepted) {
        currentStageIndex = 0;
      }
    }

    final nextStageKey = (!isFinished && !isRequested && !isRejected && !isCancelled)
        ? _getNextStageKey(stage)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A11CB), Color(0xFF8E24AA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'Service Progress',
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
            // Service Summary Card
            _ServiceSummaryCard(order: widget.order),
            const SizedBox(height: 20),

            // Requested State Banner & Actions
            if (isRequested) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFFF57C00)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isSeller
                                ? 'New Service Request Received'
                                : 'Awaiting Skilled Person Acceptance',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isSeller
                          ? 'Review the requirements submitted by the client below. Once you accept, the project timeline begins.'
                          : 'Your service request has been sent to ${widget.order.sellerName ?? "the skilled person"}. They will accept or decline shortly.',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF5D4037)),
                    ),
                    if (isSeller) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isActionLoading ? null : _rejectRequest,
                              child: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _isActionLoading ? null : _acceptRequest,
                              child: _isActionLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Accept Request', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Rejected Banner
            if (isRejected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel_rounded, color: Colors.red, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service Request Declined',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The skilled person was unable to take on this service request.',
                            style: TextStyle(color: Colors.grey[800], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Cancelled Banner
            if (isCancelled) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.block_rounded, color: Colors.grey),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This service request was cancelled.',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Active or Completed Service Timeline Section
            if (!isRequested && !isRejected && !isCancelled) ...[
              // Current Stage Status Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_graph_rounded, color: Color(0xFF6A11CB), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Service Status',
                            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Current Stage: ${_getReadableStage(stage)}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E1E2D)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFinished
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                            : const Color(0xFF6A11CB).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isFinished ? 'COMPLETED' : 'IN PROGRESS',
                        style: TextStyle(
                          color: isFinished ? const Color(0xFF2E7D32) : const Color(0xFF6A11CB),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Timeline Card Title
              const Text(
                'Service Timeline',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),

              // Vertical Progress Timeline
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: List.generate(_stages.length, (i) {
                    final stageInfo = _stages[i];
                    final isDone = isFinished || i < currentStageIndex;
                    final isCurrent = !isFinished && i == currentStageIndex;
                    final isLast = i == _stages.length - 1;
                    final time = _findStageTimestamp(stageInfo.key);

                    return _ServiceTimelineItem(
                      stage: stageInfo,
                      isDone: isDone,
                      isCurrent: isCurrent,
                      isLast: isLast,
                      timestamp: time,
                    );
                  }),
                ),
              ),

              // Advance Stage Action for Skilled Person
              if (isSeller && nextStageKey != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A11CB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: _isActionLoading ? null : () => _advanceStage(nextStageKey),
                    icon: _isActionLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: Text(
                      _getNextStageActionLabel(nextStageKey),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],

              // Completed Banner
              if (isFinished) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF81C784)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Service Finished Successfully!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'All deliverables and milestones have been delivered.',
                              style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 20),

            // Open Chat Button
            if (currentUserId != null && otherUserId.isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF6A11CB), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isChatLoading
                      ? null
                      : () => _openChat(currentUserId, otherUserId, otherUserName),
                  icon: _isChatLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6A11CB)),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF6A11CB)),
                  label: Text(
                    isSeller
                        ? 'Chat with Client ($otherUserName)'
                        : 'Chat with Skilled Person ($otherUserName)',
                    style: const TextStyle(
                      color: Color(0xFF6A11CB),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Service Stage Data Class ──────────────────────────────────────────────────

class _ServiceStageInfo {
  final String key;
  final String label;
  final String description;
  final IconData icon;

  const _ServiceStageInfo({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
  });
}

// ─── Service Timeline Row ──────────────────────────────────────────────────────

class _ServiceTimelineItem extends StatelessWidget {
  const _ServiceTimelineItem({
    required this.stage,
    required this.isDone,
    required this.isCurrent,
    required this.isLast,
    this.timestamp,
  });

  final _ServiceStageInfo stage;
  final bool isDone;
  final bool isCurrent;
  final bool isLast;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final indicatorColor = isDone
        ? const Color(0xFF2E7D32)
        : isCurrent
            ? const Color(0xFF6A11CB)
            : Colors.grey.shade300;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left indicator + vertical connector line
          SizedBox(
            width: 36,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDone || isCurrent ? indicatorColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: indicatorColor,
                      width: isCurrent ? 2 : 1.5,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: indicatorColor.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                        : Icon(
                            stage.icon,
                            color: isCurrent ? Colors.white : Colors.grey.shade400,
                            size: 16,
                          ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isDone ? const Color(0xFF2E7D32) : Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Right content details
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDone || isCurrent
                                ? const Color(0xFF1E1E2D)
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A11CB).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Color(0xFF6A11CB),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      AppHelpers.formatDateTime(timestamp!),
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    stage.description,
                    style: TextStyle(
                      color: isDone || isCurrent ? Colors.grey.shade700 : Colors.grey.shade400,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
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

// ─── Service Summary Card ──────────────────────────────────────────────────────

class _ServiceSummaryCard extends StatelessWidget {
  const _ServiceSummaryCard({required this.order});
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
            color: Colors.black.withValues(alpha: 0.05),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: WebImageLoader.loadImage(
                    imageUrl: order.productImage,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                      child: const Icon(Icons.design_services_outlined,
                          color: Color(0xFF6A11CB), size: 28),
                    ),
                    errorWidget: Container(
                      color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                      child: const Icon(Icons.design_services_outlined,
                          color: Color(0xFF6A11CB), size: 28),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6A11CB).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'SERVICE',
                            style: TextStyle(
                              color: Color(0xFF6A11CB),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '#${order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
              _SummaryDetail(
                label: 'Price',
                value: '₹${order.totalPrice.toStringAsFixed(2)}',
              ),
              _SummaryDetail(
                label: 'Placed',
                value: AppHelpers.formatDate(order.createdAt),
              ),
              _SummaryDetail(
                label: 'Client',
                value: order.buyerName ?? 'Customer',
              ),
              _SummaryDetail(
                label: 'Skilled Person',
                value: order.sellerName ?? 'Skilled Person',
              ),
            ],
          ),
          if ((order.notes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notes_rounded, size: 15, color: Color(0xFF7B1FA2)),
                      SizedBox(width: 6),
                      Text(
                        'Client Requirements',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B1FA2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.notes!.trim(),
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87),
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

// ─── Physical Order Summary Card ───────────────────────────────────────────────

class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final effectiveDeliveryAddress =
        order.deliveryAddressSnapshot?['address']?.toString() ??
        order.deliveryAddress;

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
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: WebImageLoader.loadImage(
                    imageUrl: order.productImage,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                      child: const Icon(Icons.shopping_bag,
                          color: Color(0xFF6A11CB), size: 28),
                    ),
                    errorWidget: Container(
                      color: const Color(0xFF6A11CB).withValues(alpha: 0.1),
                      child: const Icon(Icons.shopping_bag,
                          color: Color(0xFF6A11CB), size: 28),
                    ),
                  ),
                ),
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
                      'Order #${order.id.length > 8 ? order.id.substring(0, 8).toUpperCase() : order.id.toUpperCase()}',
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
          if ((effectiveDeliveryAddress ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _SummaryInfo(
              icon: Icons.home_outlined,
              label: 'Address',
              value: effectiveDeliveryAddress!,
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

// ─── Physical Delivery Timeline Row ───────────────────────────────────────────

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
