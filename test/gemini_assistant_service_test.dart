import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/gemini_assistant_service.dart';

void main() {
  test('bounds history to the latest ten valid messages', () {
    final history = [
      for (var index = 0; index < 12; index++)
        {'role': index.isEven ? 'user' : 'assistant', 'content': '$index'},
    ];

    expect(GeminiAssistantService.boundedHistory(history), [
      {'role': 'user', 'content': '2'},
      {'role': 'assistant', 'content': '3'},
      {'role': 'user', 'content': '4'},
      {'role': 'assistant', 'content': '5'},
      {'role': 'user', 'content': '6'},
      {'role': 'assistant', 'content': '7'},
      {'role': 'user', 'content': '8'},
      {'role': 'assistant', 'content': '9'},
      {'role': 'user', 'content': '10'},
      {'role': 'assistant', 'content': '11'},
    ]);
  });

  test('truncates long history by Unicode code points', () {
    final content = '${'a' * 2000}🌿tail';

    final bounded = GeminiAssistantService.boundedHistory([
      {'role': 'user', 'content': content},
    ]);

    expect(bounded.single['content'], '${'a' * 1995}🌿tail');
    expect(bounded.single['content']!.runes.length, 2000);
  });

  test('drops invalid history roles and empty messages', () {
    final bounded = GeminiAssistantService.boundedHistory([
      {'role': 'system', 'content': 'do not pass through'},
      {'role': 'user', 'content': ''},
      {'role': 'assistant', 'content': 'Useful context'},
    ]);

    expect(bounded, [
      {'role': 'assistant', 'content': 'Useful context'},
    ]);
  });

  test('explains that the AI assistant requires Premium', () {
    expect(
      GeminiAssistantService.messageForErrorCode(
        'premium_entitlement_required',
      ),
      contains('Premium feature'),
    );
  });

  test('explains the Basic plan daily AI message limit', () {
    expect(
      GeminiAssistantService.messageForErrorCode(
        'assistant_daily_limit_reached',
      ),
      contains('10 LUMIN AI messages today'),
    );
  });
}
