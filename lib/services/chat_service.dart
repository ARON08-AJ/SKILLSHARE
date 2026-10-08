import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_model.dart';
import '../utils/app_constants.dart';
import '../utils/user_roles.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isRecoverableStreamError(FirebaseException e) {
    switch (e.code) {
      case 'unavailable':
      case 'aborted':
      case 'cancelled':
      case 'deadline-exceeded':
      case 'resource-exhausted':
        return true;
      default:
        return false;
    }
  }

  Future<bool> _isConfidentialProjectChat(String chatId) async {
    final chatDoc = await _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .get();
    if (!chatDoc.exists) return false;
    final data = chatDoc.data() ?? const <String, dynamic>{};
    return data['isWorkChat'] == true || data['isJobChat'] == true;
  }

  Map<String, dynamic> _normalizeParticipantDetails(
      Map<String, dynamic> details) {
    final name =
        (details['name'] ?? details['displayName'] ?? '').toString().trim();
    final photo =
        (details['photo'] ?? details['profilePhoto'] ?? details['avatar'] ?? '')
            .toString()
            .trim();
    final role = (details['role'] ?? '').toString().trim();
    final avatarConfig = details['avatarConfig'];

    return {
      'name': name.isEmpty ? 'User' : name,
      'photo': photo,
      if (role.isNotEmpty) 'role': role,
      if (avatarConfig is Map)
        'avatarConfig': Map<String, dynamic>.from(avatarConfig),
    };
  }

  Map<String, dynamic> _mergeParticipantDetails(
    Map<String, dynamic> preferred,
    Map<String, dynamic> fallback,
  ) {
    final preferredName = (preferred['name'] as String?)?.trim() ?? '';
    final preferredPhoto = (preferred['photo'] as String?)?.trim() ?? '';
    final preferredRole = (preferred['role'] as String?)?.trim() ?? '';
    final preferredAvatarConfig = preferred['avatarConfig'];

    final fallbackName = (fallback['name'] as String?)?.trim() ?? '';
    final fallbackPhoto = (fallback['photo'] as String?)?.trim() ?? '';
    final fallbackRole = (fallback['role'] as String?)?.trim() ?? '';
    final fallbackAvatarConfig = fallback['avatarConfig'];

    final mergedRole = preferredRole.isNotEmpty ? preferredRole : fallbackRole;
    final mergedAvatarConfig = preferredAvatarConfig is Map
        ? preferredAvatarConfig
        : fallbackAvatarConfig;

    return {
      'name': preferredName.isNotEmpty
          ? preferredName
          : (fallbackName.isNotEmpty ? fallbackName : 'User'),
      'photo': preferredPhoto.isNotEmpty ? preferredPhoto : fallbackPhoto,
      if (mergedRole.isNotEmpty) 'role': mergedRole,
      if (mergedAvatarConfig is Map)
        'avatarConfig': Map<String, dynamic>.from(mergedAvatarConfig),
    };
  }

  String _chatCategoryForRole(String? role) {
    final normalized = UserRoles.normalizeRole(role);
    if (normalized == UserRoles.company) return 'company';
    if (normalized == UserRoles.customer) return 'customer';
    if (normalized == UserRoles.skilledPerson) return 'skilled';
    if (normalized == UserRoles.deliveryPartner) return 'delivery';
    return 'general';
  }

  String _deriveDirectChatCategory(
    Map<String, dynamic> user1,
    Map<String, dynamic> user2,
  ) {
    final role1 = UserRoles.normalizeRole((user1['role'] as String?)?.trim());
    final role2 = UserRoles.normalizeRole((user2['role'] as String?)?.trim());

    if (role1 == UserRoles.skilledPerson && role2 != null) {
      return _chatCategoryForRole(role2);
    }
    if (role2 == UserRoles.skilledPerson && role1 != null) {
      return _chatCategoryForRole(role1);
    }
    if (role1 == UserRoles.company || role2 == UserRoles.company) {
      return 'company';
    }
    if (role1 == UserRoles.customer || role2 == UserRoles.customer) {
      return 'customer';
    }
    if (role1 == UserRoles.skilledPerson || role2 == UserRoles.skilledPerson) {
      return 'skilled';
    }
    return 'general';
  }

  bool _isTwoUserChat(
      List<String> participants, String user1Id, String user2Id) {
    return participants.length == 2 &&
        participants.contains(user1Id) &&
        participants.contains(user2Id);
  }

  Future<bool> _isUserBlockedEitherWay(
    String user1Id,
    String user2Id,
  ) async {
    try {
      final checks = await Future.wait([
        _firestore
            .collection(AppConstants.blockedUsersCollection)
            .where('blockerId', isEqualTo: user1Id)
            .where('blockedUserId', isEqualTo: user2Id)
            .limit(5)
            .get(),
        _firestore
            .collection(AppConstants.blockedUsersCollection)
            .where('blockerId', isEqualTo: user2Id)
            .where('blockedUserId', isEqualTo: user1Id)
            .limit(5)
            .get(),
      ]);

      return checks.any(
        (snapshot) =>
            snapshot.docs.any((doc) => doc.data()['isActive'] == true),
      );
    } on FirebaseException catch (e) {
      // Compatibility fallback: do not hard-block chat if old rules deny checks.
      if (e.code == 'permission-denied' || e.code == 'failed-precondition') {
        debugPrint('Blocked-user check fallback: ${e.message}');
        return false;
      }
      rethrow;
    }
  }

  Future<String> _createChatWithFallbackId({
    required String preferredChatId,
    required List<String> participants,
    required Map<String, dynamic> participantDetails,
    required String chatCategory,
  }) async {
    final chatData = {
      'participants': participants,
      'participantDetails': participantDetails,
      'isWorkChat': false,
      'isJobChat': false,
      'chatCategory': chatCategory,
      'jobId': null,
      'workRequestId': null,
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': {for (final id in participants) id: 0},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final preferredRef = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(preferredChatId);
    try {
      await preferredRef.set(chatData, SetOptions(merge: true));
      return preferredRef.id;
    } on FirebaseException catch (e) {
      // If preferred deterministic id is not writable, create a fresh chat doc.
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Preferred chat id denied, creating fallback chat doc.');
    }

    try {
      final fallbackRef = await _firestore
          .collection(AppConstants.chatsCollection)
          .add(chatData);
      return fallbackRef.id;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Missing chat permissions in Firestore rules for /chats and /chats/{chatId}/messages.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _loadUserChatDetails(String userId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      return _normalizeParticipantDetails({
        'name': data['name'],
        'profilePhoto': data['profilePhoto'],
        'role': data['role'],
        'avatarConfig': data['avatarConfig'],
      });
    } catch (_) {
      return _normalizeParticipantDetails(const {});
    }
  }

  Future<String> resolveAccessibleDirectChatId({
    required String preferredChatId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (preferredChatId.startsWith('work_') ||
        preferredChatId.startsWith('jobchat_') ||
        currentUserId.trim().isEmpty ||
        otherUserId.trim().isEmpty) {
      return preferredChatId;
    }

    final chatRef = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(preferredChatId);

    try {
      final chatDoc = await chatRef.get();
      if (chatDoc.exists) {
        final participants =
            List<String>.from(chatDoc.data()?['participants'] ?? const []);
        if (_isTwoUserChat(participants, currentUserId, otherUserId)) {
          return preferredChatId;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Preferred chat access denied for $preferredChatId');
    }

    try {
      final existingChat = await _firestore
          .collection(AppConstants.chatsCollection)
          .where('participants', arrayContains: currentUserId)
          .limit(100)
          .get();

      for (final doc in existingChat.docs) {
        final data = doc.data();
        final participants =
            List<String>.from(data['participants'] ?? const []);
        if (_isTwoUserChat(participants, currentUserId, otherUserId) &&
            data['isWorkChat'] != true &&
            data['isJobChat'] != true) {
          return doc.id;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Accessible chat lookup denied: ${e.message}');
    }

    final currentUserDetails = await _loadUserChatDetails(currentUserId);
    final otherUserDetails = await _loadUserChatDetails(otherUserId);
    return getOrCreateChat(
      currentUserId,
      otherUserId,
      currentUserDetails,
      otherUserDetails,
    );
  }

  // Get or create chat between two users
  Future<String> getOrCreateChat(
    String user1Id,
    String user2Id, [
    Map<String, dynamic> user1Details = const {},
    Map<String, dynamic> user2Details = const {},
  ]) async {
    if (user1Id == user2Id) {
      throw Exception('You cannot start a chat with yourself.');
    }

    var normalizedUser1 = _normalizeParticipantDetails(user1Details);
    var normalizedUser2 = _normalizeParticipantDetails(user2Details);

    final loadedUser1 = await _loadUserChatDetails(user1Id);
    normalizedUser1 = _mergeParticipantDetails(normalizedUser1, loadedUser1);
    final loadedUser2 = await _loadUserChatDetails(user2Id);
    normalizedUser2 = _mergeParticipantDetails(normalizedUser2, loadedUser2);

    final directChatCategory =
        _deriveDirectChatCategory(normalizedUser1, normalizedUser2);

    // Respect target profile visibility setting for new/lookup direct chat.
    bool targetProfileVisible = true;
    try {
      final targetUserDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user2Id)
          .get();
      final targetSettings = targetUserDoc.data()?['settings'];
      targetProfileVisible = targetSettings is Map
          ? (targetSettings['profileVisible'] as bool? ?? true)
          : true;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Target profile visibility lookup denied for $user2Id');
    }
    if (!targetProfileVisible) {
      throw Exception('Chat is unavailable due to user privacy settings.');
    }

    final isBlocked = await _isUserBlockedEitherWay(user1Id, user2Id);
    if (isBlocked) {
      throw Exception('Chat is unavailable due to user privacy settings.');
    }

    final sortedParticipants = [user1Id, user2Id]..sort();
    final deterministicChatId =
        '${sortedParticipants[0]}__${sortedParticipants[1]}';
    final deterministicChatRef = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(deterministicChatId);

    try {
      final deterministicChatDoc = await deterministicChatRef.get();
      if (deterministicChatDoc.exists) {
        await deterministicChatRef.set({
          'participantDetails': {
            user1Id: normalizedUser1,
            user2Id: normalizedUser2,
          },
          'chatCategory': directChatCategory,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return deterministicChatId;
      }
    } on FirebaseException catch (e) {
      // Existing inaccessible doc should not block chat creation.
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Deterministic chat read/update denied: ${e.message}');
    }

    // Check if chat already exists
    try {
      final existingChat = await _firestore
          .collection(AppConstants.chatsCollection)
          .where('participants', arrayContains: user1Id)
          .limit(100)
          .get();

      for (var doc in existingChat.docs) {
        final participants =
            List<String>.from(doc.data()['participants'] ?? const []);
        if (_isTwoUserChat(participants, user1Id, user2Id)) {
          try {
            await doc.reference.set({
              'participantDetails': {
                user1Id: normalizedUser1,
                user2Id: normalizedUser2,
              },
              'chatCategory': directChatCategory,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } on FirebaseException catch (e) {
            if (e.code != 'permission-denied') rethrow;
            debugPrint('Existing chat update denied for ${doc.id}');
            continue;
          }
          return doc.id;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('Existing chat lookup denied: ${e.message}');
    }

    return _createChatWithFallbackId(
      preferredChatId: deterministicChatId,
      participants: sortedParticipants,
      participantDetails: {
        user1Id: normalizedUser1,
        user2Id: normalizedUser2,
      },
      chatCategory: directChatCategory,
    );
  }

  // Get user chats
  Stream<List<ChatModel>> getUserChats(String userId) {
    List<ChatModel> lastGoodChats = const <ChatModel>[];

    final query = _firestore
        .collection(AppConstants.chatsCollection)
        .where('participants', arrayContains: userId)
        .snapshots();

    return query.transform(
      StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
          List<ChatModel>>.fromHandlers(
        handleData: (snapshot, sink) {
          final chats = <ChatModel>[];
          for (final doc in snapshot.docs) {
            try {
              chats.add(ChatModel.fromMap(doc.data(), doc.id));
            } catch (e) {
              // Skip malformed chat docs instead of breaking the entire list.
              debugPrint('Skipped malformed chat ${doc.id}: $e');
            }
          }

          // Sort by lastMessageTime in memory to avoid composite index
          chats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
          lastGoodChats = List<ChatModel>.unmodifiable(chats);
          sink.add(chats);
        },
        handleError: (error, stackTrace, sink) {
          if (error is FirebaseException && _isRecoverableStreamError(error)) {
            debugPrint('getUserChats recoverable error: ${error.message}');
            if (lastGoodChats.isNotEmpty) {
              sink.add(lastGoodChats);
              return;
            }
            sink.add(const <ChatModel>[]);
            return;
          }
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  Future<void> pruneEmptyDirectChatsForUser(
    String userId,
    List<ChatModel> chats,
  ) async {
    for (final chat in chats) {
      final isDirectChat = !chat.isWorkChat &&
          !chat.isJobChat &&
          !chat.id.startsWith('work_') &&
          !chat.id.startsWith('jobchat_');
      if (!isDirectChat) continue;
      if (!chat.participants.contains(userId) ||
          chat.participants.length != 2) {
        continue;
      }
      if (chat.lastMessage.trim().isNotEmpty) continue;
      final hasUnread = chat.unreadCount.values.any((value) => value > 0);
      if (hasUnread) continue;

      try {
        final messagesSnap = await _firestore
            .collection(AppConstants.chatsCollection)
            .doc(chat.id)
            .collection(AppConstants.messagesCollection)
            .limit(1)
            .get();
        if (messagesSnap.docs.isNotEmpty) continue;

        await _firestore
            .collection(AppConstants.chatsCollection)
            .doc(chat.id)
            .delete();
      } on FirebaseException catch (e) {
        // Ignore permission/network issues so UI flow is not interrupted.
        debugPrint(
            'pruneEmptyDirectChatsForUser skipped ${chat.id}: ${e.code}');
      } catch (e) {
        debugPrint('pruneEmptyDirectChatsForUser skipped ${chat.id}: $e');
      }
    }
  }

  // Send message
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String text,
    String type = 'text',
    String? mediaUrl,
    String? attachmentName,
  }) async {
    if (senderId == receiverId) {
      throw Exception('Invalid chat users.');
    }

    final trimmedText = text.trim();
    final normalizedMediaUrl = mediaUrl?.trim();
    if (trimmedText.isEmpty &&
        (normalizedMediaUrl == null || normalizedMediaUrl.isEmpty)) {
      return;
    }

    final requestedType = type.trim().isEmpty ? 'text' : type.trim();
    final normalizedType = requestedType == 'text' &&
            normalizedMediaUrl != null &&
            normalizedMediaUrl.isNotEmpty
        ? 'image'
        : requestedType;
    final messageText = normalizedType == 'image'
        ? (trimmedText.isEmpty ? 'Photo' : trimmedText)
        : trimmedText;

    final chatRef =
        _firestore.collection(AppConstants.chatsCollection).doc(chatId);
    final chatDoc = await chatRef.get();
    if (!chatDoc.exists) {
      throw Exception('Chat not found.');
    }

    final participants =
        List<String>.from(chatDoc.data()?['participants'] ?? const []);
    if (!participants.contains(senderId) ||
        !participants.contains(receiverId)) {
      throw Exception('Invalid chat participants.');
    }

    final batch = _firestore.batch();

    // Add message
    final messageRef = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .doc();

    batch.set(messageRef, {
      'chatId': chatId,
      'senderId': senderId,
      'text': messageText,
      'type': normalizedType,
      'mediaUrl': normalizedMediaUrl,
      if (attachmentName != null && attachmentName.trim().isNotEmpty)
        'attachmentName': attachmentName.trim(),
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update chat
    batch.update(chatRef, {
      'lastMessage': normalizedType == 'image' ? 'Photo' : messageText,
      'lastMessageType': normalizedType,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount.$receiverId': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // Get messages stream
  Stream<List<MessageModel>> getMessages(String chatId, {int limit = 200}) {
    List<MessageModel> lastGoodMessages = const <MessageModel>[];

    Query<Map<String, dynamic>> query = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .orderBy('createdAt', descending: true);

    if (limit > 0) {
      query = query.limit(limit);
    }

    return query.snapshots().transform(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              List<MessageModel>>.fromHandlers(
            handleData: (snapshot, sink) {
              final messages = <MessageModel>[];
              for (final doc in snapshot.docs) {
                try {
                  messages.add(MessageModel.fromMap(doc.data(), doc.id));
                } catch (e) {
                  // Skip malformed message docs to keep the thread visible.
                  debugPrint('Skipped malformed message ${doc.id}: $e');
                }
              }
              lastGoodMessages = List<MessageModel>.unmodifiable(messages);
              sink.add(messages);
            },
            handleError: (error, stackTrace, sink) {
              if (error is FirebaseException &&
                  _isRecoverableStreamError(error)) {
                debugPrint(
                    'getMessages recoverable error for $chatId: ${error.message}');
                if (lastGoodMessages.isNotEmpty) {
                  sink.add(lastGoodMessages);
                  return;
                }
                sink.add(const <MessageModel>[]);
                return;
              }
              sink.addError(error, stackTrace);
            },
          ),
        );
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String chatId, String userId) async {
    try {
      final chatRef =
          _firestore.collection(AppConstants.chatsCollection).doc(chatId);

      await chatRef.update({
        'unreadCount.$userId': 0,
      });

      // Mark messages as read - simplified query to avoid index
      final messages = await _firestore
          .collection(AppConstants.chatsCollection)
          .doc(chatId)
          .collection(AppConstants.messagesCollection)
          .where('isRead', isEqualTo: false)
          .get();

      final refsToUpdate = messages.docs
          .where((doc) => doc.data()['senderId'] != userId)
          .map((doc) => doc.reference)
          .toList();
      if (refsToUpdate.isEmpty) return;

      final readTimestamp = FieldValue.serverTimestamp();

      // Update in chunks to stay under Firestore batch limits.
      const chunkSize = 400;
      for (var i = 0; i < refsToUpdate.length; i += chunkSize) {
        final end = (i + chunkSize > refsToUpdate.length)
            ? refsToUpdate.length
            : i + chunkSize;
        final batch = _firestore.batch();
        for (final ref in refsToUpdate.sublist(i, end)) {
          batch.update(ref, {'isRead': true, 'readAt': readTimestamp});
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('markMessagesAsRead error: $e');
    }
  }

  // Report a chat conversation
  Future<void> reportChat({
    required String chatId,
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    await _firestore.collection(AppConstants.reportsCollection).add({
      'type': 'chat',
      'chatId': chatId,
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': reason,
      'details': details ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Block a user from chat
  Future<void> blockUserFromChat({
    required String blockerId,
    required String blockedUserId,
  }) async {
    final docId = '${blockerId}_$blockedUserId';
    await _firestore
        .collection(AppConstants.blockedUsersCollection)
        .doc(docId)
        .set({
      'blockerId': blockerId,
      'blockedUserId': blockedUserId,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Delete chat
  Future<void> deleteChat(String chatId) async {
    // Delete all messages
    final messages = await _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .get();

    final batch = _firestore.batch();
    for (var doc in messages.docs) {
      batch.delete(doc.reference);
    }

    // Delete chat
    batch.delete(
        _firestore.collection(AppConstants.chatsCollection).doc(chatId));

    await batch.commit();
  }

  // Edit a text message (sender only, not deleted messages)
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String newText,
  }) async {
    final isConfidential = await _isConfidentialProjectChat(chatId);
    if (isConfidential) {
      throw Exception(
          'Messages in work/job project chats are confidential and cannot be edited.');
    }

    final trimmed = newText.trim();
    if (trimmed.isEmpty) throw Exception('Message cannot be empty.');

    final ref = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .doc(messageId);

    final snap = await ref.get();
    if (!snap.exists) throw Exception('Message not found.');
    final data = snap.data()!;
    if (data['senderId'] != senderId) throw Exception('Not your message.');
    if (data['isDeleted'] == true) {
      throw Exception('Cannot edit a deleted message.');
    }
    if ((data['type'] ?? 'text') != 'text') {
      throw Exception('Only text messages can be edited.');
    }

    await ref.update({
      'text': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  // Soft-delete a message (sender only)
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required String senderId,
  }) async {
    final isConfidential = await _isConfidentialProjectChat(chatId);
    if (isConfidential) {
      throw Exception(
          'Messages in work/job project chats are confidential and cannot be deleted.');
    }

    final ref = _firestore
        .collection(AppConstants.chatsCollection)
        .doc(chatId)
        .collection(AppConstants.messagesCollection)
        .doc(messageId);

    final snap = await ref.get();
    if (!snap.exists) return;
    if (snap.data()?['senderId'] != senderId) {
      throw Exception('Not your message.');
    }

    await ref.update({
      'text': 'This message was deleted',
      'isDeleted': true,
      'mediaUrl': null,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
