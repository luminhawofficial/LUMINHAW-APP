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
