import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

class PlantEnrichment {
  const PlantEnrichment({
    required this.fields,
    required this.sources,
    required this.aiGeneratedFields,
    required this.unavailableFields,
    this.fieldStatuses = const {},
    this.fieldGeneratedAt = const {},
    this.generatedAt,
    this.error,
  });

  final Map<String, String> fields;
  final Map<String, String> sources;
  final Map<String, String> fieldStatuses;
  final Map<String, String> fieldGeneratedAt;
  final String? generatedAt;
  final Set<String> aiGeneratedFields;
  final Set<String> unavailableFields;
  final String? error;

  @visibleForTesting
  static PlantEnrichment parseResponse(Object? response) {
    final payload = _asMap(response);
    final profile = _asMap(payload?['profile']);
    if (profile == null) {
      throw const FormatException(
        'The plant information service returned an invalid response.',
      );
    }

    final fields = <String, String>{};
    for (final entry in profile.entries) {
      final value = _string(entry.value);
      if (value != null) fields[entry.key] = value;
    }
    final sources = <String, String>{};
    final sourceMap = _asMap(payload?['fieldSources']);
    for (final entry
        in sourceMap?.entries ?? const <MapEntry<String, dynamic>>[]) {
      final value = _string(entry.value);
      if (value != null) sources[entry.key] = value;
    }
    final generated = payload?['aiGeneratedFields'];
    return PlantEnrichment(
      fields: Map.unmodifiable(fields),
      sources: Map.unmodifiable(sources),
      fieldStatuses: Map.unmodifiable(_stringMap(payload?['fieldStatuses'])),
      fieldGeneratedAt: Map.unmodifiable(
        _stringMap(payload?['fieldGeneratedAt']),
      ),
      generatedAt: _string(payload?['generatedAt']),
      aiGeneratedFields: Set.unmodifiable(
        generated is List ? generated.whereType<String>().toSet() : <String>{},
      ),
      unavailableFields: Set.unmodifiable(
        payload?['unavailableFields'] is List
            ? (payload!['unavailableFields'] as List)
                  .whereType<String>()
                  .toSet()
            : <String>{},
      ),
      error: _string(payload?['enrichmentError']),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static Map<String, String> _stringMap(Object? value) {
    final map = _asMap(value);
    if (map == null) return const {};
    return {
      for (final entry in map.entries)
        if (entry.value is String && (entry.value as String).trim().isNotEmpty)
          entry.key: (entry.value as String).trim(),
    };
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

class PlantEnrichmentService {
  PlantEnrichmentService._();

  static Future<PlantEnrichment> load({
    required PlantRecord plant,
    Map<String, String> sourceOverrides = const {},
  }) async {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError(
        'Sign in with a verified email to view plant information.',
      );
    }
    final scientificName = plant.scientificName.trim();
    if (scientificName.length < 2 || scientificName.length > 120) {
      throw ArgumentError.value(plant.scientificName, 'scientificName');
    }

    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'plant-enrich',
        body: {
          'scientificName': scientificName,
          'commonName': plant.commonName,
          'family': plant.family,
          'kingdom': plant.kingdom,
          'phylum': plant.phylum,
          'taxonomicClass': plant.taxonomicClass,
          'order': plant.order,
          'genus': plant.genus,
          'species': plant.species,
          'description': plant.description,
          'tagalogName': plant.tagalogName,
          'bisayaName': plant.bisayaName,
          'source': plant.source,
          'fieldSources': sourceOverrides,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw StateError(_messageFor(_errorCode(response.data)));
      }
      return PlantEnrichment.parseResponse(response.data);
    } on FunctionException catch (error) {
      throw StateError(
        _messageFor(_errorCode(error.details) ?? _codeForStatus(error.status)),
      );
    }
  }

  static String? _codeForStatus(int? statusCode) {
    if (statusCode == null) return null;
    return switch (statusCode) {
      401 => 'invalid_session',
      403 => 'email_verification_required',
      404 => 'plant_enrichment_not_deployed',
      429 => 'rate_limit_exceeded',
      >= 500 => 'plant_enrichment_unavailable',
      _ => null,
    };
  }

  static String _messageFor(String? code) => switch (code) {
    'authentication_required' ||
    'invalid_session' => 'Sign in again to view plant information.',
    'email_verification_required' =>
      'Verify your email to view plant information.',
    'rate_limit_exceeded' =>
      'Too many plant information requests. Please try again later.',
    'valid_scientific_name_required' =>
      'The plant information needs a valid scientific name.',
    'plant_enrichment_unavailable' =>
      'Plant information is temporarily unavailable.',
    'plant_enrichment_not_deployed' => 'Detailed plant information is not available yet. Please try again later.',
    _ => 'Could not load additional plant information. Please try again later.',
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
    final map = PlantEnrichment._asMap(payload);
    final error = PlantEnrichment._asMap(map?['error']);
    final code = error?['code'];
    return code is String && code.trim().isNotEmpty ? code.trim() : null;
  }
}
