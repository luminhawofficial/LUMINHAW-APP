import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

class PlantCareGuide {
  const PlantCareGuide({
    required this.scientificName,
    required this.source,
    required this.sourceUrl,
    required this.care,
  });

  final String scientificName;
  final String source;
  final String sourceUrl;
  final Map<String, String> care;

  @visibleForTesting
  static PlantCareGuide parseResponse(Object? response) {
    final payload = _asMap(response);
    final care = _asMap(payload?['care']);
    final scientificName = _string(payload?['scientificName']);
    final source = _string(payload?['source']);
    final sourceUrl = _string(payload?['sourceUrl']);
    if (care == null ||
        scientificName == null ||
        source == null ||
        sourceUrl == null) {
      throw const FormatException(
        'The plant care service returned an invalid response.',
      );
    }

    final fields = <String, String>{};
    for (final entry in care.entries) {
      final value = _string(entry.value);
      if (value != null) fields[entry.key] = value;
    }
    if (fields.isEmpty) {
      throw const FormatException(
        'No care information is available for this plant.',
      );
    }
    return PlantCareGuide(
      scientificName: scientificName,
      source: source,
      sourceUrl: sourceUrl,
      care: Map.unmodifiable(fields),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

class PlantCareService {
  PlantCareService._();

  static Future<PlantCareGuide> load({required String scientificName}) async {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError(
        'Sign in with a verified email to view plant care information.',
      );
    }
    final name = scientificName.trim();
    if (name.length < 2 || name.length > 120) {
      throw ArgumentError.value(scientificName, 'scientificName');
    }

    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'plant-care',
        body: {'scientificName': name},
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError(_messageFor(_errorCode(response.data)));
      }
      return PlantCareGuide.parseResponse(response.data);
    } on FunctionException catch (error) {
      throw StateError(_messageFor(_errorCode(error.details)));
    }
  }

  static String _messageFor(String? code) => switch (code) {
    'authentication_required' ||
    'invalid_session' => 'Sign in again to view plant care information.',
    'email_verification_required' =>
      'Verify your email to view plant care information.',
    'rate_limit_exceeded' =>
      'Too many care-guide requests. Please try again later.',
    'premium_entitlement_required' => 'Detailed plant care guides require an active verified Premium subscription.',
    'valid_scientific_name_required' =>
      'The plant name is not specific enough to find a care guide.',
    'care_information_unavailable' =>
      'No species-specific care information was found for this plant.',
    'plant_care_not_configured' =>
      'The plant care provider is not configured on the server.',
    'plant_care_provider_unavailable' =>
      'The plant care provider is temporarily unavailable.',
    _ => 'Could not load plant care information. Please try again later.',
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
    final map = PlantCareGuide._asMap(payload);
    final error = PlantCareGuide._asMap(map?['error']);
    final code = error?['code'];
    return code is String && code.trim().isNotEmpty ? code.trim() : null;
  }
}
