import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse;

class AssistantRequestException implements Exception {
  const AssistantRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiAssistantService {
  GeminiAssistantService._();

  static const int _maxMessageLength = 4000;
  static const int _maxHistoryMessages = 10;
  static const int _maxHistoryItemLength = 2000;

  static Future<String> sendMessage({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final trimmedMessage = message.trim();

    if (trimmedMessage.isEmpty || trimmedMessage.length > _maxMessageLength) {
      throw const AssistantRequestException(
        'Enter a message between 1 and 4000 characters.',
      );
    }

    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }

    final user = SupabaseAuthService.currentUser;

    if (user == null || user.emailConfirmedAt == null) {
      throw StateError('Sign in with a verified email to use LUMIN AI.');
    }

    // Obtain the current session without exposing its access token.
    final session = SupabaseBackend.client.auth.currentSession;

    if (session == null || session.accessToken.isEmpty) {
      throw StateError(
        'Your session has expired. Sign in again to use LUMIN AI.',
      );
    }

    late final FunctionResponse response;

    try {
      response = await SupabaseBackend.client.functions.invoke(
        'assistant-chat',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {'message': trimmedMessage, 'history': boundedHistory(history)},
      );
    } on FunctionException catch (error) {
      throw AssistantRequestException(
        messageForErrorCode(
          _errorCode(error.details) ?? _codeForStatus(error.status),
        ),
      );
    }

    if (response.status < 200 || response.status >= 300) {
      throw AssistantRequestException(
        messageForErrorCode(
          _errorCode(response.data) ?? _codeForStatus(response.status),
        ),
      );
    }

    final payload = response.data;

    if (payload is! Map ||
        payload['reply'] is! String ||
        (payload['reply'] as String).trim().isEmpty) {
      throw const FormatException('LUMIN AI returned an invalid response.');
    }

    // Preserve the entire response. Do not slice or shorten it.
    final reply = (payload['reply'] as String).trim();

    // Read completion metadata returned by Supabase.
    final finishReason = payload['finishReason'];
    final truncated = payload['truncated'] == true;

    // Do not silently present a MAX_TOKENS response as complete.
    if (truncated || finishReason == 'MAX_TOKENS') {
      return '$reply\n\n'
          '_Note: This response may be incomplete because the AI '
          'reached its response limit. Please ask me to continue._';
    }

    return reply;
  }

  @visibleForTesting
  static List<Map<String, String>> boundedHistory(
    List<Map<String, String>> history,
  ) {
    final messages = <Map<String, String>>[];

    for (final item in history.reversed) {
      final role = item['role'];
      final content = item['content'];

      if ((role != 'user' && role != 'assistant') ||
          content == null ||
          content.isEmpty) {
        continue;
      }

      final runes = content.runes.toList(growable: false);

      final boundedContent = runes.length > _maxHistoryItemLength
          ? String.fromCharCodes(
              runes.skip(runes.length - _maxHistoryItemLength),
            )
          : content;

      messages.add({'role': role!, 'content': boundedContent});

      if (messages.length == _maxHistoryMessages) {
        break;
      }
    }

    return List.unmodifiable(messages.reversed);
  }

  @visibleForTesting
  static String messageForErrorCode(String code) {
    if (code == 'assistant_network_error') {
      return 'Could not reach the LUMIN AI server. Check your connection and Supabase function URL.';
    }

    if (code.startsWith('assistant_http_')) {
      return 'Assistant request failed with '
          '${code.substring('assistant_http_'.length)}. '
          'Check the deployed Supabase function and LUMIN AI provider configuration.';
    }

    return switch (code) {
      'assistant_free_daily_limit' =>
        'You have used your 10 free LUMIN AI messages for today. '
            'Your allowance resets at UTC midnight. '
            'Upgrade to Premium for unlimited AI chat.',

      'premium_entitlement_required' =>
        'Could not verify your AI chat access. Please try again later.',

      'assistant_not_configured' =>
        'LUMIN AI is not configured on the server. '
            'Add GEMINI_API_KEY to Supabase Edge Function secrets.',

      'rate_limit_exceeded' || 'assistant_rate_limited' =>
        'You have reached the assistant request limit. Try again later.',

      'email_verification_required' =>
        'Verify your email before using LUMIN AI.',

      'message_must_be_between_1_and_4000_characters' =>
        'Enter a message between 1 and 4000 characters.',

      'function_not_configured' ||
      'rate_limit_unavailable' ||
      'entitlement_check_unavailable' =>
        'LUMIN AI is temporarily unavailable. Please try again later.',

      'authentication_required' || 'invalid_session' =>
        'Your session has expired. Sign in again to use LUMIN AI.',

      'assistant_access_denied' =>
        'LUMIN AI access was denied. Verify your email and account status.',

      'assistant_provider_error' || 'gemini_provider_error' =>
        'LUMIN AI could not process the request. Check the server function logs.',

      'assistant_unavailable' => 'LUMIN AI could not be reached. Check the server function logs and try again.',

      'assistant_invalid_provider_response' =>
        'LUMIN AI returned an unreadable response. Try again later.',

      'assistant_request_failed' =>
        'The assistant function returned an unrecognized error. '
            'Check Supabase function logs and deployment.',

      _ => 'LUMIN AI could not reply ($code). Please try again later.',
    };
  }

  static String? _errorCode(Object? details) {
    Object? payload = details;

    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        return null;
      }
    }

    if (payload is Map) {
      final error = payload['error'];

      if (error is Map && error['code'] is String) {
        return error['code'] as String;
      }
    }

    return null;
  }

  static String _codeForStatus(int status) {
    if (status == 0) return 'assistant_network_error';
    if (status == 401) return 'authentication_required';
    if (status == 403) return 'assistant_access_denied';
    if (status == 429) return 'rate_limit_exceeded';
    if (status == 502) return 'assistant_provider_error';
    if (status == 503) return 'assistant_not_configured';

    return 'assistant_http_$status';
  }
}
