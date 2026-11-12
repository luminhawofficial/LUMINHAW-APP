import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/ai_conversation_service.dart';

void main() {
  test('generates UUIDs suitable for database message identifiers', () {
    final id = AiConversationService.newId();

    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(AiConversationService.newId(), isNot(id));
  });

  test('restores a pending message and its saved assistant response', () {
    final pending = AiPendingMessage(
      userId: 'user-id',
      conversationId: 'conversation-id',
      conversationTitle: 'Plant question',
      userMessageId: 'user-message-id',
      message: 'How often should I water it?',
      createdAt: DateTime.utc(2026, 11, 11, 5),
    ).withAssistantReply('Check the soil before watering.');

    final restored = AiConversationService.decodePendingMessages(
      jsonEncode([pending.toJson()]),
    ).single;

    expect(restored.userMessageId, pending.userMessageId);
    expect(restored.message, pending.message);
    expect(restored.assistantMessageId, pending.assistantMessageId);
    expect(restored.assistantReply, pending.assistantReply);
    expect(restored.createdAt, pending.createdAt);
  });

  test(
    'restores a cached conversation with both user and assistant messages',
    () {
      final cache = AiConversationCache(
        conversationId: 'conversation-id',
        title: 'What is mango?',
        createdAt: DateTime.utc(2026, 11, 11, 5),
        updatedAt: DateTime.utc(2026, 11, 11, 5, 1),
        messages: [
          AiChatMessage(
            id: 'user-message-id',
            conversationId: 'conversation-id',
            userId: 'user-id',
            role: 'user',
            message: 'What is mango?',
            createdAt: DateTime.utc(2026, 11, 11, 5),
          ),
          AiChatMessage(
            id: 'assistant-message-id',
            conversationId: 'conversation-id',
            userId: 'user-id',
            role: 'assistant',
            message: 'Mango is a tropical fruit.',
            createdAt: DateTime.utc(2026, 11, 11, 5, 1),
          ),
        ],
      );

      final restored = AiConversationCache.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(cache.toJson())) as Map,
        ),
      );

      expect(restored.conversationId, cache.conversationId);
      expect(restored.title, cache.title);
      expect(restored.createdAt, cache.createdAt);
      expect(restored.updatedAt, cache.updatedAt);
      expect(restored.messages.map((message) => message.message), [
        'What is mango?',
        'Mango is a tropical fruit.',
      ]);
    },
  );

  test('rejects cached messages from a different conversation', () {
    final message = AiChatMessage(
      id: 'message-id',
      conversationId: 'other-conversation',
      userId: 'user-id',
      role: 'user',
      message: 'What is mango?',
      createdAt: DateTime.utc(2026, 11, 11, 5),
    );

    expect(
      () => AiConversationCache.fromJson({
        'conversation_id': 'conversation-id',
        'title': 'What is mango?',
        'updated_at': '2026-11-11T05:00:00Z',
        'messages': [message.toJson()],
      }),
      throwsFormatException,
    );
  });

  test('searches conversation titles, previews, and full message text', () {
    final conversations = [
      AiConversationHistoryItem(
        id: 'conversation-1',
        title: 'Watering help',
        createdAt: DateTime.utc(2026, 11, 11),
        updatedAt: DateTime.utc(2026, 11, 11, 1),
        preview: 'Check the top inch of soil.',
        searchText: 'How often should I water my monstera?',
      ),
      AiConversationHistoryItem(
        id: 'conversation-2',
        title: 'Mango leaves',
        createdAt: DateTime.utc(2026, 11, 10),
        updatedAt: DateTime.utc(2026, 11, 10, 1),
        preview: 'Give it bright indirect light.',
        searchText: 'Mango plant care tips',
      ),
    ];

    expect(
      AiConversationService.filterConversationHistory(
        conversations,
        'MONSTERA',
      ).map((conversation) => conversation.id),
      ['conversation-1'],
    );
    expect(
      AiConversationService.filterConversationHistory(
        conversations,
        'mango',
      ).map((conversation) => conversation.id),
      ['conversation-2'],
    );
    expect(
      AiConversationService.filterConversationHistory(
        conversations,
        'soil',
      ).map((conversation) => conversation.id),
      ['conversation-1'],
    );
    expect(
      AiConversationService.filterConversationHistory(conversations, '   '),
      hasLength(2),
    );
  });

  test('merges by message id and preserves timestamp order', () {
    AiChatMessage message(String id, int minute) => AiChatMessage(
      id: id,
      conversationId: 'conversation-id',
      userId: 'user-id',
      role: 'user',
      message: id,
      createdAt: DateTime.utc(2026, 11, 11, 5, minute),
    );

    final merged = AiConversationService.mergeMessages([
      message('second', 2),
      message('first', 1),
      message('first', 1),
    ]);

    expect(merged.map((item) => item.id), ['first', 'second']);
  });

  test('rejects malformed saved outbox data rather than dropping messages', () {
    expect(
      () => AiConversationService.decodePendingMessages('{"message":"lost"}'),
      throwsFormatException,
    );
  });
}
