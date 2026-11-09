import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, FunctionException, SupabaseClient;

class PlantHealthPrediction {
  const PlantHealthPrediction({
    required this.name,
    required this.probability,
    this.localName,
    this.description,
    this.cause,
    this.treatment,
  });

  final String name;
  final double? probability;
  final String? localName;
  final String? description;
  final String? cause;
  final String? treatment;
}

class PlantHealthAssessment {
  const PlantHealthAssessment({
    required this.id,
    required this.isHealthy,
    required this.healthProbability,
    required this.predictions,
  });

  final String id;
  final bool? isHealthy;
  final double? healthProbability;
  final List<PlantHealthPrediction> predictions;

  @visibleForTesting
  static PlantHealthAssessment parseResponse(
    Object? response, {
    String id = 'test-assessment',
  }) {
    final payload = _asMap(response);
    final result = _asMap(payload?['result']);
    if (result == null) {
      throw const FormatException(
        'The plant health service returned an invalid response.',
      );
    }

    final health = _asMap(result['is_healthy']);
    final healthBinary = health?['binary'];
    final healthProbability = _number(health?['probability']);
    final disease = _asMap(result['disease']);
    final suggestions = disease?['suggestions'];
    final predictions = <PlantHealthPrediction>[];

    if (suggestions is List) {
      for (final item in suggestions) {
        final suggestion = _asMap(item);
        final name = _string(suggestion?['name']);
        if (suggestion == null || name == null) continue;

        final details = _asMap(suggestion['details']);
        predictions.add(
          PlantHealthPrediction(
            name: name,
            probability: _number(suggestion['probability']),
            localName: _string(details?['local_name']),
            description: _detailText(details?['description']),
            cause: _detailText(details?['cause']),
            treatment: _detailText(details?['treatment']),
          ),
        );
      }
    }

    if (healthBinary is! bool && predictions.isEmpty) {
      throw const FormatException(
        'The plant health service returned no usable assessment.',
      );
    }

    return PlantHealthAssessment(
      id: id,
      isHealthy: healthBinary is bool ? healthBinary : null,
      healthProbability: healthProbability,
      predictions: List.unmodifiable(predictions),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _string(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static double? _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static String? _detailText(Object? value) {
    if (value is String) return _string(value);
    final map = _asMap(value);
    final direct = _string(map?['value']) ?? _string(map?['text']);
    if (direct != null) return direct;
    if (value is List) {
      for (final item in value) {
        final text = _detailText(item);
        if (text != null) return text;
      }
    }
    return null;
  }
}

class PlantHealthService {
  PlantHealthService._();

  static Future<PlantHealthAssessment> assess({
    required Uint8List imageBytes,
  }) async {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError('Sign in with a verified email to assess plant health.');
    }
    if (imageBytes.isEmpty || imageBytes.length > 10 * 1024 * 1024) {
      throw ArgumentError.value(imageBytes.length, 'imageBytes');
    }

    final contentType = _contentType(imageBytes);
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const FormatException(
        'Choose a readable JPEG, PNG, or WebP photo.',
      ),
    };

    final client = SupabaseBackend.client;
    final imagePath =
        '${user.id}/health/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage
        .from('plant-photos')
        .uploadBinary(
          imagePath,
          imageBytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    late final String assessmentId;
    try {
      final row = await client
          .from('plant_health_assessments')
          .insert({
            'owner_id': user.id,
            'image_path': imagePath,
            'status': 'pending',
          })
          .select('id')
          .single();
      assessmentId = row['id'] as String;
    } catch (error) {
      try {
        await client.storage.from('plant-photos').remove([imagePath]);
      } catch (cleanupError) {
        throw StateError(
          'Could not create the health assessment ($error), and its uploaded '
          'photo could not be removed ($cleanupError).',
        );
      }
      rethrow;
    }

    try {
      final response = await client.functions.invoke(
        'plant-health',
        body: {'imageBase64': base64Encode(imageBytes)},
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError(_messageFor(_errorCode(response.data)));
      }

      final assessment = PlantHealthAssessment.parseResponse(
        response.data,
        id: assessmentId,
      );
      await client
          .from('plant_health_assessments')
          .update({
            'status': 'completed',
            'provider': 'plant.id',
            'result': response.data,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', assessmentId)
          .eq('owner_id', user.id);
      return assessment;
    } on FunctionException catch (error) {
      await _markFailed(client, user.id, assessmentId, error);
      throw StateError(_messageFor(_errorCode(error.details)));
    } catch (error) {
      await _markFailed(client, user.id, assessmentId, error);
      rethrow;
    }
  }

  static Future<void> _markFailed(
    SupabaseClient client,
    String userId,
    String assessmentId,
    Object cause,
  ) async {
    try {
      await client
          .from('plant_health_assessments')
          .update({
            'status': 'failed',
            'provider': 'plant.id',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', assessmentId)
          .eq('owner_id', userId);
    } catch (error) {
      throw StateError(
        'Health assessment failed ($cause), and its status could not be '
        'saved ($error).',
      );
    }
  }

  static String _messageFor(String? code) => switch (code) {
    'premium_entitlement_required' =>
      'Plant health analysis requires an active verified Premium subscription.',
    'authentication_required' ||
    'invalid_session' => 'Sign in again before assessing plant health.',
    'email_verification_required' =>
      'Verify your email before assessing plant health.',
    'rate_limit_exceeded' || 'plant_health_rate_limited' =>
      'Too many health checks. Please try again later.',
    'valid_image_required' => 'Choose a valid plant photo and try again.',
    'plant_health_not_configured' =>
      'Plant health analysis is not configured on the server.',
    'plant_health_provider_error' || 'plant_health_unavailable' =>
      'The plant health provider is temporarily unavailable.',
    _ => 'Plant health analysis failed. Please try again later.',
  };

  static String? _errorCode(Object? details) {
    Object? payload = details;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        return null;
      }
    }
    final map = PlantHealthAssessment._asMap(payload);
    final error = PlantHealthAssessment._asMap(map?['error']);
    return _nonEmptyString(error?['code']);
  }

  static String? _nonEmptyString(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _contentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}
