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

  factory AiChatMessage.fromRow(Map<String, dynamic> row) => AiChatMessage(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    userId: row['user_id'] as String,
    role: row['role'] as String,
    message: row['message'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
  );
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

class AiConversationService {
  AiConversationService._();

  static const _outboxPrefix = 'ai_chat_outbox_';
  static final _random = Random.secure();

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

  static Future<AiConversationSnapshot> loadLatestConversation() async {
    final userId = _currentUserId();
    final pendingMessages = await _readPendingMessages(userId);
    Map<String, dynamic>? conversationRow;
    var remoteMessages = <AiChatMessage>[];
    Object? syncError;

    try {
      conversationRow = await SupabaseBackend.client
          .from('ai_conversations')
          .select('id,title,updated_at')
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (conversationRow != null) {
        final rows = await SupabaseBackend.client
            .from('ai_messages')
            .select('id,conversation_id,user_id,role,message,created_at')
            .eq('conversation_id', conversationRow['id'] as String)
            .eq('user_id', userId)
            .order('created_at')
            .order('id');
        remoteMessages = (rows as List)
            .map(
              (row) =>
                  AiChatMessage.fromRow(Map<String, dynamic>.from(row as Map)),
            )
            .toList(growable: false);
      }
    } catch (error) {
      if (pendingMessages.isEmpty) rethrow;
      syncError = error;
    }

    final latestPending = pendingMessages.isEmpty ? null : pendingMessages.last;
    final usePendingConversation =
        latestPending != null &&
        (conversationRow == null ||
            latestPending.createdAt.isAfter(
              DateTime.parse(conversationRow['updated_at'] as String).toUtc(),
            ));
    final conversationId = usePendingConversation
        ? latestPending.conversationId
        : conversationRow?['id'] as String?;
    final conversationTitle = usePendingConversation
        ? latestPending.conversationTitle
        : conversationRow?['title'] as String?;

    if (conversationId == null) {
      return AiConversationSnapshot(
        conversationId: null,
        title: null,
        messages: const [],
        pendingMessages: pendingMessages,
        syncError: syncError,
      );
    }

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
      ...localMessages,
    ]);

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
