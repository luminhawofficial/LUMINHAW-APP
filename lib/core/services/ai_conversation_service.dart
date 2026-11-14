import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_backend.dart';

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String userId;
  final String role;
  final String message;
  final DateTime createdAt;

  bool get fromAssistant => role == 'assistant';

  Map<String, Object?> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'user_id': userId,
    'role': role,
    'message': message,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory AiChatMessage.fromRow(Map<String, dynamic> row) =>
      AiChatMessage.fromJson(row);

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    final role = _requiredString(json, 'role');
    if (role != 'user' && role != 'assistant') {
      throw const FormatException(
        'Saved LUMIN AI message has an invalid role.',
      );
    }
    return AiChatMessage(
      id: _requiredString(json, 'id'),
      conversationId: _requiredString(json, 'conversation_id'),
      userId: _requiredString(json, 'user_id'),
      role: role,
      message: _requiredString(json, 'message'),
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
    );
  }
}

class AiPendingMessage {
  const AiPendingMessage({
    required this.userId,
    required this.conversationId,
    required this.conversationTitle,
    required this.userMessageId,
    required this.message,
    required this.createdAt,
    this.assistantMessageId,
    this.assistantReply,
    this.assistantCreatedAt,
  });

  final String userId;
  final String conversationId;
  final String conversationTitle;
  final String userMessageId;
  final String message;
  final DateTime createdAt;
  final String? assistantMessageId;
  final String? assistantReply;
  final DateTime? assistantCreatedAt;

  AiPendingMessage withAssistantReply(String reply) => AiPendingMessage(
    userId: userId,
    conversationId: conversationId,
    conversationTitle: conversationTitle,
    userMessageId: userMessageId,
    message: message,
    createdAt: createdAt,
    assistantMessageId: AiConversationService.newId(),
    assistantReply: reply,
    assistantCreatedAt: DateTime.now().toUtc(),
  );

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'conversation_id': conversationId,
    'conversation_title': conversationTitle,
    'user_message_id': userMessageId,
    'message': message,
    'created_at': createdAt.toUtc().toIso8601String(),
    'assistant_message_id': assistantMessageId,
    'assistant_reply': assistantReply,
    'assistant_created_at': assistantCreatedAt?.toUtc().toIso8601String(),
  };

  factory AiPendingMessage.fromJson(Map<String, dynamic> json) {
    final assistantMessageId = json['assistant_message_id'];
    final assistantReply = json['assistant_reply'];
    final assistantCreatedAt = json['assistant_created_at'];
    if (assistantMessageId != null && assistantMessageId is! String ||
        assistantReply != null && assistantReply is! String ||
        assistantCreatedAt != null && assistantCreatedAt is! String) {
      throw const FormatException('Invalid saved AI message state.');
    }

    return AiPendingMessage(
      userId: _requiredString(json, 'user_id'),
      conversationId: _requiredString(json, 'conversation_id'),
      conversationTitle: _requiredString(json, 'conversation_title'),
      userMessageId: _requiredString(json, 'user_message_id'),
      message: _requiredString(json, 'message'),
      createdAt: DateTime.parse(_requiredString(json, 'created_at')).toUtc(),
      assistantMessageId: assistantMessageId as String?,
      assistantReply: assistantReply as String?,
      assistantCreatedAt: assistantCreatedAt == null
          ? null
          : DateTime.parse(assistantCreatedAt as String).toUtc(),
    );
  }
}

class AiConversationSnapshot {
  const AiConversationSnapshot({
    required this.conversationId,
    required this.title,
    required this.messages,
    required this.pendingMessages,
    this.syncError,
  });

  final String? conversationId;
  final String? title;
  final List<AiChatMessage> messages;
  final List<AiPendingMessage> pendingMessages;
  final Object? syncError;
}

class AiConversationCache {
  const AiConversationCache({
    required this.conversationId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String conversationId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiChatMessage> messages;

  Map<String, Object?> toJson() => {
    'conversation_id': conversationId,
    'title': title,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  factory AiConversationCache.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    if (rawMessages is! List) {
      throw const FormatException('Saved LUMIN AI conversation is invalid.');
    }
    final conversationId = _requiredString(json, 'conversation_id');
    final messages = rawMessages
        .map((item) {
          if (item is! Map) {
            throw const FormatException(
              'Saved LUMIN AI conversation message is invalid.',
            );
          }
          return AiChatMessage.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
    if (messages.any((message) => message.conversationId != conversationId)) {
      throw const FormatException(
        'Saved LUMIN AI conversation contains unrelated messages.',
      );
    }
    return AiConversationCache(
      conversationId: conversationId,
      title: _requiredString(json, 'title'),
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ?? _requiredString(json, 'updated_at'),
      ).toUtc(),
      updatedAt: DateTime.parse(_requiredString(json, 'updated_at')).toUtc(),
      messages: messages,
    );
  }
}

class AiConversationHistoryItem {
  const AiConversationHistoryItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.preview,
    required this.searchText,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String preview;
  final String searchText;
}

class AiConversationHistorySnapshot {
  const AiConversationHistorySnapshot({
    required this.conversations,
    this.syncError,
  });

  final List<AiConversationHistoryItem> conversations;
  final Object? syncError;
}

class AiConversationService {
  AiConversationService._();

  static const _outboxPrefix = 'ai_chat_outbox_';
  static const _cachePrefix = 'ai_chat_cache_';
  static final _random = Random.secure();
  static final Map<String, String> _activeConversationIds = {};

  static String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static String currentSessionConversationId() {
    final userId = _currentUserId();
    return _activeConversationIds.putIfAbsent(userId, newId);
  }

  static String startNewConversation() {
    final userId = _currentUserId();
    final id = newId();
    _activeConversationIds[userId] = id;
    return id;
  }

  static String activateConversation(String conversationId) {
    final userId = _currentUserId();
    _activeConversationIds[userId] = conversationId;
    return conversationId;
  }

  static List<AiConversationHistoryItem> filterConversationHistory(
    List<AiConversationHistoryItem> conversations,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return List.unmodifiable(conversations);
    return List.unmodifiable(
      conversations.where(
        (conversation) =>
            conversation.title.toLowerCase().contains(normalizedQuery) ||
            conversation.preview.toLowerCase().contains(normalizedQuery) ||
            conversation.searchText.toLowerCase().contains(normalizedQuery),
      ),
    );
  }

  static Future<AiConversationHistorySnapshot> loadConversationHistory({
    int limit = 250,
  }) async {
    if (limit < 1 || limit > 250) {
      throw RangeError.range(limit, 1, 250, 'limit');
    }

    final userId = _currentUserId();
    final pendingMessages = await _readPendingMessages(userId);
    var cachedConversation = await _readCachedConversation(userId);
    final remoteConversations = <AiConversationHistoryItem>[];
    Object? syncError;
    var remoteLoaded = false;

    try {
      final rows = await SupabaseBackend.client
          .from('ai_conversations')
          .select('id,title,created_at,updated_at')
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false)
          .limit(limit);
      final conversations = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      if (conversations.isNotEmpty) {
        final conversationIds = conversations
            .map((row) => row['id'] as String)
            .toList(growable: false);
        final messages = <AiChatMessage>[];
        var offset = 0;
        const pageSize = 1000;
        while (true) {
          final messageRows = await SupabaseBackend.client
              .from('ai_messages')
              .select('id,conversation_id,user_id,role,message,created_at')
              .eq('user_id', userId)
              .inFilter('conversation_id', conversationIds)
              .order('created_at')
              .order('id')
              .range(offset, offset + pageSize - 1);
          final batch = (messageRows as List)
              .map(
                (row) => AiChatMessage.fromRow(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .toList(growable: false);
          messages.addAll(batch);
          if (batch.length < pageSize) break;
          offset += pageSize;
        }

        for (final row in conversations) {
          final id = row['id'] as String;
          final conversationMessages = messages
              .where((message) => message.conversationId == id)
              .toList(growable: false);
          remoteConversations.add(
            AiConversationHistoryItem(
              id: id,
              title: row['title'] as String,
              createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
              updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
              preview: conversationMessages.isEmpty
                  ? ''
                  : conversationMessages.last.message,
              searchText: conversationMessages
                  .map((message) => message.message)
                  .join('\n'),
            ),
          );
        }
      }

      final localConversationIds = <String>{
        if (cachedConversation != null) cachedConversation.conversationId,
        for (final pending in pendingMessages) pending.conversationId,
      };
      if (localConversationIds.isNotEmpty) {
        final deletedRows = await SupabaseBackend.client
            .from('ai_conversations')
            .select('id')
            .eq('user_id', userId)
            .inFilter('id', localConversationIds.toList(growable: false))
            .not('deleted_at', 'is', null);
        final deletedIds = (deletedRows as List)
            .map((row) => (row as Map)['id'] as String)
            .toSet();
        pendingMessages.removeWhere(
          (pending) => deletedIds.contains(pending.conversationId),
        );
        if (cachedConversation != null &&
            deletedIds.contains(cachedConversation.conversationId)) {
          cachedConversation = null;
        }
        for (final deletedId in deletedIds) {
          await _discardDeletedConversationLocally(userId, deletedId);
        }
      }
      remoteLoaded = true;
    } catch (error) {
      if (pendingMessages.isEmpty && cachedConversation == null) rethrow;
      syncError = error;
    }

    final byId = {
      for (final conversation in remoteConversations)
        conversation.id: conversation,
    };
    final currentCachedConversation = cachedConversation;
    if (currentCachedConversation != null &&
        (!remoteLoaded ||
            remoteConversations.any(
              (item) => item.id == currentCachedConversation.conversationId,
            ) ||
            pendingMessages.any(
              (item) =>
                  item.conversationId ==
                  currentCachedConversation.conversationId,
            ))) {
      final cachedMessages = currentCachedConversation.messages;
      final latestCachedMessage = cachedMessages.isEmpty
          ? null
          : mergeMessages(cachedMessages).last;
      final existing = byId[currentCachedConversation.conversationId];
      byId[currentCachedConversation.conversationId] =
          AiConversationHistoryItem(
        id: currentCachedConversation.conversationId,
        title: existing?.title ?? currentCachedConversation.title,
        createdAt: existing?.createdAt ?? currentCachedConversation.createdAt,
        updatedAt:
            existing != null &&
                existing.updatedAt.isAfter(currentCachedConversation.updatedAt)
            ? existing.updatedAt
            : currentCachedConversation.updatedAt,
        preview: latestCachedMessage?.message ?? existing?.preview ?? '',
        searchText: [
          existing?.searchText ?? '',
          for (final message in cachedMessages) message.message,
        ].where((text) => text.isNotEmpty).join('\n'),
      );
    }
    for (final pending in pendingMessages) {
      final existing = byId[pending.conversationId];
      final pendingUpdatedAt = pending.assistantCreatedAt ?? pending.createdAt;
      if (existing?.updatedAt.isAfter(pendingUpdatedAt) != true) {
        byId[pending.conversationId] = AiConversationHistoryItem(
          id: pending.conversationId,
          title: existing?.title ?? pending.conversationTitle,
          createdAt: existing?.createdAt ?? pending.createdAt,
          updatedAt: pendingUpdatedAt,
          preview: pending.assistantReply ?? pending.message,
          searchText: [
            existing?.searchText ?? '',
            pending.message,
            ?pending.assistantReply,
          ].where((text) => text.isNotEmpty).join('\n'),
        );
      }
    }
    final results = byId.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return AiConversationHistorySnapshot(
      conversations: List.unmodifiable(results.take(limit)),
      syncError: syncError,
    );
  }

  static Future<AiConversationSnapshot> loadConversation(
    String conversationId,
  ) async {
    final userId = _currentUserId();
    final pendingMessages = await _readPendingMessages(userId);
    final cachedConversation = await _readCachedConversation(userId);
    Map<String, dynamic>? conversationRow;
    var remoteMessages = <AiChatMessage>[];
    Object? syncError;
    var remoteLoaded = false;
    var conversationWasDeleted = false;

    try {
      conversationRow = await SupabaseBackend.client
          .from('ai_conversations')
          .select('id,title,updated_at,deleted_at')
          .eq('id', conversationId)
          .eq('user_id', userId)
          .maybeSingle();

      conversationWasDeleted = conversationRow?['deleted_at'] != null;
      if (conversationRow != null && !conversationWasDeleted) {
        var offset = 0;
        const pageSize = 1000;
        while (true) {
          final rows = await SupabaseBackend.client
              .from('ai_messages')
              .select('id,conversation_id,user_id,role,message,created_at')
              .eq('conversation_id', conversationRow['id'] as String)
              .eq('user_id', userId)
              .order('created_at')
              .order('id')
              .range(offset, offset + pageSize - 1);
          final batch = (rows as List)
              .map(
                (row) => AiChatMessage.fromRow(
                  Map<String, dynamic>.from(row as Map),
                ),
              )
              .toList(growable: false);
          remoteMessages.addAll(batch);
          if (batch.length < pageSize) break;
          offset += pageSize;
        }
      }
      remoteLoaded = true;
    } catch (error) {
      final hasLocalConversation =
          cachedConversation?.conversationId == conversationId ||
          pendingMessages.any(
            (pending) => pending.conversationId == conversationId,
          );
      if (!hasLocalConversation) rethrow;
      syncError = error;
    }

    if (conversationWasDeleted) {
      await _discardDeletedConversationLocally(userId, conversationId);
      return AiConversationSnapshot(
        conversationId: null,
        title: null,
        messages: const [],
        pendingMessages: const [],
        syncError: StateError(
          'This conversation was deleted. Start a new chat to continue.',
        ),
      );
    }

    final remoteUpdatedAt = conversationRow == null
        ? null
        : DateTime.parse(conversationRow['updated_at'] as String).toUtc();
    final useCachedConversation =
        cachedConversation?.conversationId == conversationId &&
        (!remoteLoaded ||
            conversationRow != null &&
                cachedConversation!.updatedAt.isAfter(remoteUpdatedAt!));
    final conversationTitle = useCachedConversation
        ? cachedConversation!.title
        : conversationRow?['title'] as String? ??
              pendingMessages
                  .where((pending) => pending.conversationId == conversationId)
                  .firstOrNull
                  ?.conversationTitle;

    final localMessages = <AiChatMessage>[];
    for (final pending in pendingMessages.where(
      (item) => item.conversationId == conversationId,
    )) {
      localMessages.add(
        AiChatMessage(
          id: pending.userMessageId,
          conversationId: conversationId,
          userId: userId,
          role: 'user',
          message: pending.message,
          createdAt: pending.createdAt,
        ),
      );
      if (pending.assistantReply case final reply?) {
        localMessages.add(
          AiChatMessage(
            id: pending.assistantMessageId!,
            conversationId: conversationId,
            userId: userId,
            role: 'assistant',
            message: reply,
            createdAt: pending.assistantCreatedAt!,
          ),
        );
      }
    }

    final messages = mergeMessages([
      ...remoteMessages.where((item) => item.conversationId == conversationId),
      if (useCachedConversation) ...cachedConversation!.messages,
      ...localMessages,
    ]);

    if (remoteLoaded &&
        conversationTitle != null &&
        messages.isNotEmpty &&
        conversationRow != null) {
      try {
        final lastMessageAt = messages.last.createdAt;
        final updatedAt = lastMessageAt.isAfter(remoteUpdatedAt!)
            ? lastMessageAt
            : remoteUpdatedAt;
        await _writeCachedConversation(
          userId,
          AiConversationCache(
            conversationId: conversationId,
            title: conversationTitle,
            createdAt: cachedConversation?.conversationId == conversationId
                ? cachedConversation!.createdAt
                : messages.first.createdAt,
            updatedAt: updatedAt,
            messages: messages,
          ),
        );
      } catch (error) {
        syncError ??= error;
      }
    }

    return AiConversationSnapshot(
      conversationId: conversationId,
      title: conversationTitle,
      messages: messages,
      pendingMessages: pendingMessages
          .where((item) => item.conversationId == conversationId)
          .toList(growable: false),
      syncError: syncError,
    );
  }

  static Future<AiPendingMessage> queueUserMessage({
    required String message,
    required String? conversationId,
    required String? conversationTitle,
  }) async {
    final userId = _currentUserId();
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError.value(message, 'message', 'Must not be empty.');
    }

    final existing = await _readPendingMessages(userId);
    final createdAt = DateTime.now().toUtc();
    final title = conversationTitle ?? _conversationTitle(trimmedMessage);
    final pending = AiPendingMessage(
      userId: userId,
      conversationId: conversationId ?? newId(),
      conversationTitle: title,
      userMessageId: newId(),
      message: trimmedMessage,
      createdAt: createdAt,
    );
    await _writePendingMessages(userId, [...existing, pending]);
    return pending;
  }

  static Future<void> syncUserMessage(AiPendingMessage pending) async {
    _requireSameUser(pending.userId);
    final client = SupabaseBackend.client;
    final now = DateTime.now().toUtc().toIso8601String();

    await client.from('ai_conversations').upsert({
      'id': pending.conversationId,
      'user_id': pending.userId,
      'title': pending.conversationTitle,
      'updated_at': now,
    }, onConflict: 'id');

    await client
        .from('ai_messages')
        .upsert(
          {
            'id': pending.userMessageId,
            'conversation_id': pending.conversationId,
            'user_id': pending.userId,
            'role': 'user',
            'message': pending.message,
            'created_at': pending.createdAt.toIso8601String(),
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }

  static Future<AiPendingMessage> saveAssistantReply(
    AiPendingMessage pending,
    String reply,
  ) async {
    _requireSameUser(pending.userId);
    final updated = pending.withAssistantReply(reply);
    final queue = await _readPendingMessages(pending.userId);
    final index = queue.indexWhere(
      (item) => item.userMessageId == pending.userMessageId,
    );
    if (index < 0) {
      throw StateError('The pending LUMIN AI message could not be found.');
    }
    queue[index] = updated;
    await _writePendingMessages(pending.userId, queue);
    return updated;
  }

  static Future<void> syncAssistantReply(AiPendingMessage pending) async {
    _requireSameUser(pending.userId);
    final messageId = pending.assistantMessageId;
    final reply = pending.assistantReply;
    final createdAt = pending.assistantCreatedAt;
    if (messageId == null || reply == null || createdAt == null) {
      throw StateError('The pending LUMIN AI response is incomplete.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await SupabaseBackend.client.from('ai_conversations').upsert({
      'id': pending.conversationId,
      'user_id': pending.userId,
      'title': pending.conversationTitle,
      'updated_at': now,
    }, onConflict: 'id');

    await SupabaseBackend.client
        .from('ai_messages')
        .upsert(
          {
            'id': messageId,
            'conversation_id': pending.conversationId,
            'user_id': pending.userId,
            'role': 'assistant',
            'message': reply,
            'created_at': createdAt.toIso8601String(),
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    await _cacheSyncedReply(pending);
  }

  static Future<void> deleteConversation(String conversationId) async {
    final userId = _currentUserId();
    await SupabaseBackend.client.rpc(
      'delete_ai_conversation',
      params: {'p_conversation_id': conversationId},
    );
    await _discardDeletedConversationLocally(userId, conversationId);
  }

  static Future<void> clearPersonalData({required String ownerId}) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in ['$_outboxPrefix$ownerId', '$_cachePrefix$ownerId']) {
      if (preferences.containsKey(key) && !await preferences.remove(key)) {
        throw StateError('Local LUMIN AI history could not be cleared.');
      }
    }
    _activeConversationIds.remove(ownerId);
  }

  static Future<void> _discardDeletedConversationLocally(
    String userId,
    String conversationId,
  ) async {
    final pendingMessages = await _readPendingMessages(userId);
    pendingMessages.removeWhere(
      (pending) => pending.conversationId == conversationId,
    );
    await _writePendingMessages(userId, pendingMessages);

    final preferences = await SharedPreferences.getInstance();
    final cachedConversation = await _readCachedConversation(userId);
    if (cachedConversation?.conversationId == conversationId) {
      final removed = await preferences.remove('$_cachePrefix$userId');
      if (!removed) {
        throw StateError('The deleted LUMIN AI conversation cache remains.');
      }
    }
    if (_activeConversationIds[userId] == conversationId) {
      _activeConversationIds.remove(userId);
    }
  }

  static Future<void> removePendingMessage(AiPendingMessage pending) async {
    _requireSameUser(pending.userId);
    final queue = await _readPendingMessages(pending.userId);
    queue.removeWhere((item) => item.userMessageId == pending.userMessageId);
    await _writePendingMessages(pending.userId, queue);
  }

  static String _currentUserId() {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null) throw StateError('Sign in to use LUMIN AI.');
    return user.id;
  }

  static void _requireSameUser(String userId) {
    if (_currentUserId() != userId) {
      throw StateError('Your account changed before the message was saved.');
    }
  }

  static String _conversationTitle(String message) {
    final runes = message.runes.toList(growable: false);
    return String.fromCharCodes(runes.take(80));
  }

  static Future<List<AiPendingMessage>> _readPendingMessages(
    String userId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('$_outboxPrefix$userId');
    if (saved == null) return [];

    final decoded = jsonDecode(saved);
    if (decoded is! List) {
      throw const FormatException('Saved LUMIN AI messages are invalid.');
    }
    final messages = decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Saved LUMIN AI message is invalid.');
          }
          return AiPendingMessage.fromJson(Map<String, dynamic>.from(item));
        })
        .where((item) => item.userId == userId)
        .toList(growable: true);
    messages.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return messages;
  }

  static Future<void> _writePendingMessages(
    String userId,
    List<AiPendingMessage> messages,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      '$_outboxPrefix$userId',
      jsonEncode(messages.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw StateError(
        'The unsynchronized LUMIN AI message could not be saved.',
      );
    }
  }

  static Future<AiConversationCache?> _readCachedConversation(
    String userId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString('$_cachePrefix$userId');
    if (saved == null) return null;

    final decoded = jsonDecode(saved);
    if (decoded is! Map) {
      throw const FormatException('Saved LUMIN AI conversation is invalid.');
    }
    final cache = AiConversationCache.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    if (cache.messages.any((message) => message.userId != userId)) {
      throw const FormatException(
        'Saved LUMIN AI conversation belongs to another account.',
      );
    }
    return cache;
  }

  static Future<void> _writeCachedConversation(
    String userId,
    AiConversationCache cache,
  ) async {
    if (cache.messages.any((message) => message.userId != userId)) {
      throw StateError('The LUMIN AI conversation belongs to another account.');
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      '$_cachePrefix$userId',
      jsonEncode(cache.toJson()),
    );
    if (!saved) {
      throw StateError('The LUMIN AI conversation could not be cached.');
    }
  }

  static Future<void> _cacheSyncedReply(AiPendingMessage pending) async {
    final reply = pending.assistantReply;
    final assistantMessageId = pending.assistantMessageId;
    final assistantCreatedAt = pending.assistantCreatedAt;
    if (reply == null ||
        assistantMessageId == null ||
        assistantCreatedAt == null) {
      throw StateError('The pending LUMIN AI response is incomplete.');
    }

    final existing = await _readCachedConversation(pending.userId);
    final existingMessages = existing?.conversationId == pending.conversationId
        ? existing!.messages
        : const <AiChatMessage>[];
    final userMessage = AiChatMessage(
      id: pending.userMessageId,
      conversationId: pending.conversationId,
      userId: pending.userId,
      role: 'user',
      message: pending.message,
      createdAt: pending.createdAt,
    );
    final assistantMessage = AiChatMessage(
      id: assistantMessageId,
      conversationId: pending.conversationId,
      userId: pending.userId,
      role: 'assistant',
      message: reply,
      createdAt: assistantCreatedAt,
    );
    final messages = mergeMessages([
      ...existingMessages,
      userMessage,
      assistantMessage,
    ]);
    final now = DateTime.now().toUtc();
    final updatedAt = now.isAfter(assistantCreatedAt)
        ? now
        : assistantCreatedAt;

    await _writeCachedConversation(
      pending.userId,
      AiConversationCache(
        conversationId: pending.conversationId,
        title: pending.conversationTitle,
        createdAt: existing?.conversationId == pending.conversationId
            ? existing!.createdAt
            : pending.createdAt,
        updatedAt: updatedAt,
        messages: messages,
      ),
    );
  }

  @visibleForTesting
  static List<AiChatMessage> mergeMessages(List<AiChatMessage> messages) {
    final byId = <String, AiChatMessage>{};
    for (final message in messages) {
      byId.putIfAbsent(message.id, () => message);
    }
    final merged = byId.values.toList()
      ..sort((left, right) {
        final timeOrder = left.createdAt.compareTo(right.createdAt);
        return timeOrder != 0 ? timeOrder : left.id.compareTo(right.id);
      });
    return List.unmodifiable(merged);
  }

  @visibleForTesting
  static List<AiPendingMessage> decodePendingMessages(String saved) {
    final decoded = jsonDecode(saved);
    if (decoded is! List) {
      throw const FormatException('Saved LUMIN AI messages are invalid.');
    }
    return List.unmodifiable(
      decoded.map((item) {
        if (item is! Map) {
          throw const FormatException('Saved LUMIN AI message is invalid.');
        }
        return AiPendingMessage.fromJson(Map<String, dynamic>.from(item));
      }),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Saved LUMIN AI message has an invalid $key.');
  }
  return value;
}
