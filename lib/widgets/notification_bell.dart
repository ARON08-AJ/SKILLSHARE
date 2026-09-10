import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_constants.dart';
import '../utils/app_helpers.dart';
import '../utils/notification_helpers.dart';
import '../services/firestore_service.dart';
import '../screens/notifications/notifications_screen.dart';

/// Bell icon that shows an unread-count badge and, on tap, a compact dropdown
/// panel with recent notifications positioned directly below it.
///
/// When the panel opens, all current notifications are stamped "seen" so the
/// badge count resets to 0 immediately. Tapping "View all notifications"
/// navigates to the full [NotificationsScreen].
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.userId,
    this.color = Colors.white,
    this.size = 24.0,
    // Legacy onTap kept for API compatibility but now unused internally
    this.onTap,
  });

  final String userId;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _firestore = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();
  final _layerLink = LayerLink();

  final _countCtrl = StreamController<int>.broadcast();
  StreamSubscription? _userSub;
  StreamSubscription? _requestSub;
  StreamSubscription? _buyerOrderSub;
  StreamSubscription? _sellerOrderSub;
  StreamSubscription? _deliveryOrderSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _jobNotifSub;

  QuerySnapshot? _lastJobNotifSnap;

  DateTime? _lastSeen; // lastNotificationSeenAt for requests/orders
  DateTime? _chatSeenAt; // time user last opened the bell (clears chat badge)
  QuerySnapshot? _lastRequestSnap;
  QuerySnapshot? _lastBuyerOrderSnap;
  QuerySnapshot? _lastSellerOrderSnap;
  QuerySnapshot? _lastDeliveryOrderSnap;
  int _chatUnread = 0;

  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    // Re-compute badge whenever the user's lastNotificationSeenAt changes
    _userSub = _firestore
        .collection(AppConstants.usersCollection)
        .doc(widget.userId)
        .snapshots()
        .listen(
      (doc) {
        if (!doc.exists) return;
        final ts = doc.data()?['lastNotificationSeenAt'];
        _lastSeen = ts != null ? (ts as Timestamp).toDate() : null;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell userSub error: $e'),
    );

    // Re-compute badge whenever the requests collection changes
    _requestSub = _firestore
        .collection(AppConstants.requestsCollection)
        .where('participants', arrayContains: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        _lastRequestSnap = snap;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell requestSub error: $e'),
    );

    _buyerOrderSub = _firestore
        .collection(AppConstants.ordersCollection)
        .where('buyerId', isEqualTo: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        _lastBuyerOrderSnap = snap;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell buyerOrderSub error: $e'),
    );

    _sellerOrderSub = _firestore
        .collection(AppConstants.ordersCollection)
        .where('sellerId', isEqualTo: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        _lastSellerOrderSnap = snap;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell sellerOrderSub error: $e'),
    );

    _deliveryOrderSub = _firestore
        .collection(AppConstants.ordersCollection)
        .where('deliveryPartnerId', isEqualTo: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        _lastDeliveryOrderSnap = snap;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell deliveryOrderSub error: $e'),
    );

    // Re-compute badge whenever unread chat count changes for this user
    _chatSub = _firestore
        .collection(AppConstants.chatsCollection)
        .where('participants', arrayContains: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        int total = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          final unread = (data['unreadCount'] as Map?)?[widget.userId];
          if (unread is int && unread > 0) {
            // Only count chats where the last message arrived after we last viewed
            if (_chatSeenAt == null) {
              total += unread;
            } else {
              final lastMsgTime = data['lastMessageTime'];
              if (lastMsgTime is Timestamp &&
                  lastMsgTime.toDate().isAfter(_chatSeenAt!)) {
                total += unread;
              }
            }
          }
        }
        _chatUnread = total;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell chatSub error: $e'),
    );

    _jobNotifSub = _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen(
      (snap) {
        _lastJobNotifSnap = snap;
        _recount();
      },
      onError: (e) => debugPrint('NotificationBell jobNotifSub error: $e'),
    );
  }

  void _recount() {
    final snap = _lastRequestSnap;
    int count = _chatUnread; // always include unread chats
    if (snap != null) {
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final Timestamp? ts = data['updatedAt'] as Timestamp?;
        if (ts == null) continue;
        if (_lastSeen == null || ts.toDate().isAfter(_lastSeen!)) count++;
      }
    }

    final latestOrderUpdateById = <String, DateTime>{};
    final orderSnapshots = [
      _lastBuyerOrderSnap,
      _lastSellerOrderSnap,
      _lastDeliveryOrderSnap,
    ];
    for (final snap in orderSnapshots) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data is! Map<String, dynamic>) continue;
        final ts = data['updatedAt'];
        if (ts is! Timestamp) continue;
        final updatedAt = ts.toDate();
        final existing = latestOrderUpdateById[doc.id];
        if (existing == null || updatedAt.isAfter(existing)) {
          latestOrderUpdateById[doc.id] = updatedAt;
        }
      }
    }
    for (final updatedAt in latestOrderUpdateById.values) {
      if (_lastSeen == null || updatedAt.isAfter(_lastSeen!)) {
        count++;
      }
    }

    // Count unseen job application notifications
    final jobNotifSnap = _lastJobNotifSnap;
    if (jobNotifSnap != null) {
      const jobTypes = <String>{
        'jobApplication',
        'jobReApplication',
        'jobAccepted',
        'jobRejected',
        'jobRevoked',
      };
      for (final doc in jobNotifSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final type = (data['type'] as String?)?.trim();
        if (type == null || !jobTypes.contains(type)) continue;
        final ts = data['createdAt'];
        if (ts is! Timestamp) continue;
        if (_lastSeen == null || ts.toDate().isAfter(_lastSeen!)) count++;
      }
    }

    if (!_countCtrl.isClosed) _countCtrl.add(count);
  }

  @override
  void dispose() {
    // Clean up overlay directly — do NOT call _closeDropdown() which
    // invokes setState and triggers a lifecycle assertion crash.
    _overlayEntry?.remove();
    _overlayEntry = null;
    _userSub?.cancel();
    _requestSub?.cancel();
    _buyerOrderSub?.cancel();
    _sellerOrderSub?.cancel();
    _deliveryOrderSub?.cancel();
    _chatSub?.cancel();
    _jobNotifSub?.cancel();
    _countCtrl.close();
    super.dispose();
  }

  // ─── Dropdown ─────────────────────────────────────────────────────────────

  void _toggle(BuildContext context) =>
      _isOpen ? _closeDropdown() : _openDropdown(context);

  void _openDropdown(BuildContext context) {
    // Optimistically stamp _lastSeen NOW so _recount() emits 0 immediately
    // (instead of waiting for the Firestore round-trip via _userSub).
    final seenAt = DateTime.now();
    _lastSeen = seenAt;
    _chatSeenAt = seenAt;
    _chatUnread = 0;
    _recount(); // emits 0 right away — no flicker

    // Persist to Firestore in the background; when _userSub fires it will
    // re-set _lastSeen to roughly the same value, causing a harmless recount.
    _firestoreService.markNotificationsSeen(widget.userId);

    _overlayEntry = OverlayEntry(
      builder: (_) => _NotificationDropdown(
        layerLink: _layerLink,
        userId: widget.userId,
        hostContext: context,
        onClose: _closeDropdown,
        onViewAll: () {
          _closeDropdown();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(userId: widget.userId),
            ),
          );
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: StreamBuilder<int>(
        stream: _countCtrl.stream,
        initialData: 0,
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return GestureDetector(
            onTap: () => _toggle(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    count > 0
                        ? Icons.notifications
                        : Icons.notifications_outlined,
                    color: widget.color,
                    size: widget.size,
                  ),
                  if (count > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          constraints:
                              const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFFF3D3D)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B6B)
                                    .withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Dropdown panel widget ────────────────────────────────────────────────────

class _NotificationDropdown extends StatefulWidget {
  const _NotificationDropdown({
    required this.layerLink,
    required this.userId,
    required this.hostContext,
    required this.onClose,
    required this.onViewAll,
  });

  final LayerLink layerLink;
  final String userId;
  final BuildContext hostContext;
  final VoidCallback onClose;
  final VoidCallback onViewAll;

  @override
  State<_NotificationDropdown> createState() => _NotificationDropdownState();
}

class _NotificationDropdownState extends State<_NotificationDropdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Future<List<NotificationItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = loadNotificationsForUser(widget.userId, limit: 6);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // Tap-outside barrier
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
          ),
        ),

        // Dropdown card — positioned safely within screen bounds
        Positioned(
          top: topPadding + kToolbarHeight + 4,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  alignment: Alignment.topRight,
                  child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.13),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                          child: Row(
                            children: [
                              const Text(
                                'Notifications',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: widget.onClose,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.close,
                                      size: 18, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // ── Notification list (scrollable, max ~5 items)
                        _buildList(),

                        const Divider(height: 1),

                        // ── View all button
                        InkWell(
                          onTap: widget.onViewAll,
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(16)),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 13),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'View all notifications',
                                  style: TextStyle(
                                    color: Color(0xFF6A11CB),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_ios,
                                    size: 12, color: Color(0xFF6A11CB)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
    );
  }

  Widget _buildList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 310),
      child: FutureBuilder<List<NotificationItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Text(
                  'No notifications yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 14, endIndent: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              final isTappable = item.type == NotificationType.order
                  ? item.orderData != null
                  : item.type == NotificationType.jobApplication
                      ? (item.jobId != null ||
                          item.chatId != null ||
                          item.otherUserId != null)
                      : (item.chatId != null || item.otherUserId != null);
              return InkWell(
                onTap: !isTappable
                    ? null
                    : () async {
                        final navContext = widget.hostContext;
                        widget.onClose();
                        await openNotificationItem(
                          navContext,
                          item: item,
                          currentUserId: widget.userId,
                        );
                      },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: item.color.withValues(alpha: 0.15),
                        child: Icon(item.icon, color: item.color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              AppHelpers.getRelativeTime(item.createdAt),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isTappable)
                        Icon(Icons.chevron_right,
                            size: 16, color: Colors.grey[500]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
