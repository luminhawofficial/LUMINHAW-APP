import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/plant_enrichment_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

class PlantIdentificationResult {
  const PlantIdentificationResult({
    required this.scanId,
    required this.name,
    required this.scientificName,
    required this.family,
    required this.probability,
    required this.imageBytes,
    this.commonName,
    this.tagalogName,
    this.bisayaName,
    this.kingdom,
    this.phylum,
    this.taxonomicClass,
    this.order,
    this.genus,
    this.species,
    this.description,
    this.botanicalInformation = const {},
    this.informationSources = const {},
    this.informationStatuses = const {},
    this.aiGeneratedFields = const {},
    this.fieldGeneratedAt = const {},
    this.unavailableFields = const {},
    this.enrichmentGeneratedAt,
    this.enrichmentError,
  });

  final String scanId;
  final String name;
  final String? commonName;
  final String scientificName;
  final String family;
  final double? probability;
  final Uint8List imageBytes;
  final String? tagalogName;
  final String? bisayaName;
  final String? kingdom;
  final String? phylum;
  final String? taxonomicClass;
  final String? order;
  final String? genus;
  final String? species;
  final String? description;
  final Map<String, String> botanicalInformation;
  final Map<String, String> informationSources;
  final Map<String, String> informationStatuses;
  final Set<String> aiGeneratedFields;
  final Map<String, String> fieldGeneratedAt;
  final Set<String> unavailableFields;
  final String? enrichmentGeneratedAt;
  final String? enrichmentError;

  PlantRecord toPlantRecord() => PlantRecord(
    commonName: commonName ?? scientificName,
    scientificName: scientificName,
    category: 'Plants',
    water: 'Not provided by the identification result',
    image: 'assets/images/plants/plant_1.png',
    family: family,
    description: description,
    tagalogName: tagalogName ?? botanicalInformation['tagalogName'],
    bisayaName: bisayaName ?? botanicalInformation['bisayaName'],
    kingdom: kingdom,
    phylum: phylum,
    taxonomicClass: taxonomicClass,
    order: order,
    genus: genus,
    species: species,
    enrichedFields: botanicalInformation,
    enrichmentSources: informationSources,
    aiGeneratedFields: aiGeneratedFields,
    source: 'Plant.ID',
  );

  PlantIdentificationResult copyWithEnrichment({
    Map<String, String>? fields,
    Map<String, String>? sources,
    Map<String, String>? statuses,
    Set<String>? generatedFields,
    Map<String, String>? generatedAtByField,
    Set<String>? missingFields,
    String? generatedAt,
    String? error,
  }) => PlantIdentificationResult(
    scanId: scanId,
    name: name,
    scientificName: scientificName,
    family: family,
    probability: probability,
    imageBytes: imageBytes,
    commonName: commonName,
    tagalogName: fields?['tagalogName'] ?? tagalogName,
    bisayaName: fields?['bisayaName'] ?? bisayaName,
    kingdom: kingdom,
    phylum: phylum,
    taxonomicClass: taxonomicClass,
    order: order,
    genus: genus,
    species: species,
    description: fields?['description'] ?? description,
    botanicalInformation: fields ?? botanicalInformation,
    informationSources: sources ?? informationSources,
    informationStatuses: statuses ?? informationStatuses,
    aiGeneratedFields: generatedFields ?? aiGeneratedFields,
    fieldGeneratedAt: generatedAtByField ?? fieldGeneratedAt,
    unavailableFields: missingFields ?? unavailableFields,
    enrichmentGeneratedAt: generatedAt ?? enrichmentGeneratedAt,
    enrichmentError: error,
  );
}

class PlantIdentificationService {
  PlantIdentificationService._();

  static Future<PlantIdentificationResult> identify({
    required Uint8List imageBytes,
  }) async {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }

    final user = SupabaseAuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in before identifying a plant.');
    }
    if (user.emailConfirmedAt == null) {
      throw StateError('Verify your email before identifying a plant.');
    }
    if (imageBytes.isEmpty || imageBytes.length > 10 * 1024 * 1024) {
      throw ArgumentError.value(imageBytes.length, 'imageBytes');
    }

    final client = SupabaseBackend.client;
    final scanRow = await client
        .from('plant_identifications')
        .insert({'owner_id': user.id, 'status': 'pending'})
        .select('id')
        .single();
    final scanId = scanRow['id'] as String;

    try {
      final response = await client.functions.invoke(
        'plant-identification',
        body: {'imageBase64': base64Encode(imageBytes)},
      );
      final identifiedResult = parseResponse(
        response.data,
        scanId: scanId,
        imageBytes: imageBytes,
      );
      var result = identifiedResult;
      try {
        final enrichment = await PlantEnrichmentService.load(
          plant: identifiedResult.toPlantRecord(),
          sourceOverrides: {
            if (identifiedResult.tagalogName != null) 'tagalogName': 'GBIF',
            if (identifiedResult.bisayaName != null) 'bisayaName': 'GBIF',
          },
        );
        result = identifiedResult.copyWithEnrichment(
          fields: enrichment.fields,
          sources: enrichment.sources,
          statuses: enrichment.fieldStatuses,
          generatedFields: enrichment.aiGeneratedFields,
          generatedAtByField: enrichment.fieldGeneratedAt,
          missingFields: enrichment.unavailableFields,
          generatedAt: enrichment.generatedAt,
          error: enrichment.error,
        );
      } catch (error) {
        result = identifiedResult.copyWithEnrichment(
          error:
              'Additional plant details could not be loaded: ${error.toString().replaceFirst('Bad state: ', '')}',
          missingFields:
              {
                'tagalogName',
                'bisayaName',
                'weatherClimate',
                'soilCompatibility',
                'originHabitat',
                'growthCharacteristics',
                'careInstructions',
              }.where((field) {
                if (field == 'tagalogName') {
                  return identifiedResult.tagalogName == null;
                }
                if (field == 'bisayaName') {
                  return identifiedResult.bisayaName == null;
                }
                return true;
              }).toSet(),
        );
      }
      final responsePayload = _asMap(response.data);
      await client
          .from('plant_identifications')
          .update({
            'status': 'completed',
            'provider':
                _nonEmptyString(responsePayload?['provider']) ?? 'plant.id',
            'result': {
              ...?responsePayload,
              'plantEnrichment': {
                'profile': result.botanicalInformation,
                'fieldSources': result.informationSources,
                'fieldStatuses': result.informationStatuses,
                'aiGeneratedFields': result.aiGeneratedFields.toList(),
                'fieldGeneratedAt': result.fieldGeneratedAt,
                'generatedAt': result.enrichmentGeneratedAt,
                'unavailableFields': result.unavailableFields.toList(),
                'enrichmentError': result.enrichmentError,
              },
            },
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', scanId)
          .eq('owner_id', user.id);

      return result;
    } catch (error) {
      try {
        await client
            .from('plant_identifications')
            .update({
              'status': 'failed',
              'provider': 'plant.id',
              'completed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', scanId)
            .eq('owner_id', user.id);
      } catch (updateError) {
        throw StateError(
          'Plant identification failed ($error), and its scan status could '
          'not be saved ($updateError).',
        );
      }
      if (error is FunctionException) {
        throw StateError(
          _messageFor(
            _errorCode(error.details) ?? _codeForStatus(error.status),
          ),
        );
      }
      if (error is FormatException) {
        throw StateError(error.message);
      }
      rethrow;
    }
  }

  @visibleForTesting
  static PlantIdentificationResult parseResponse(
    Object? response, {
    required String scanId,
    required Uint8List imageBytes,
  }) {
    if (response is! Map) {
      throw const FormatException(
        'The plant identification service returned an invalid response.',
      );
    }
    final payload = Map<String, dynamic>.from(response);
    final errorCode = _errorCode(payload);
    if (errorCode != null) throw StateError(_messageFor(errorCode));
    final result = _asMap(payload['result']);
    final classification = _asMap(result?['classification']);
    final suggestions = classification?['suggestions'];
    if (suggestions is! List || suggestions.isEmpty) {
      throw const FormatException(
        'The service did not return a plant identification.',
      );
    }

    final suggestion = _asMap(suggestions.first);
    final name = _nonEmptyString(suggestion?['name']);
    if (name == null) {
      throw const FormatException(
        'The service returned a suggestion without a plant name.',
      );
    }

    final details = _asMap(suggestion?['details']);
    final taxonomy = _asMap(details?['taxonomy']);
    final localizedNames = _asMap(payload['localizedNames']);
    final enrichment = _asMap(payload['plantEnrichment']);
    final enrichedProfile = _asMap(enrichment?['profile']);
    final sources = _asMap(enrichment?['fieldSources']);
    final statuses = _asMap(enrichment?['fieldStatuses']);
    final generatedAt = _asMap(enrichment?['fieldGeneratedAt']);
    final tagalogName =
        _nonEmptyString(localizedNames?['tagalog']) ??
        _nonEmptyString(enrichedProfile?['tagalogName']);
    final bisayaName =
        _nonEmptyString(localizedNames?['bisaya']) ??
        _nonEmptyString(enrichedProfile?['bisayaName']);
    final botanicalInformation = _stringMap(enrichedProfile);
    final informationSources = <String, String>{..._stringMap(sources)};
    final informationStatuses = <String, String>{..._stringMap(statuses)};
    final aiGeneratedFields = _stringSet(enrichment?['aiGeneratedFields']);
    final commonName = _firstString(details?['common_names']);
    final provider = _nonEmptyString(payload['provider']) ?? 'Plant.ID';
    informationSources.putIfAbsent('commonName', () => provider);
    informationSources.putIfAbsent('scientificName', () => provider);
    if (tagalogName != null) {
      informationSources.putIfAbsent(
        'tagalogName',
        () => localizedNames?['tagalog'] == null ? provider : 'GBIF',
      );
    }
    if (bisayaName != null) {
      informationSources.putIfAbsent(
        'bisayaName',
        () => localizedNames?['bisaya'] == null ? provider : 'GBIF',
      );
    }
    for (final entry in {
      'commonName': commonName,
      'scientificName': _nonEmptyString(details?['scientific_name']) ?? name,
      'tagalogName': tagalogName,
      'bisayaName': bisayaName,
      ...botanicalInformation,
    }.entries) {
      if (informationStatuses.containsKey(entry.key)) continue;
      if (entry.value == null) {
        informationStatuses[entry.key] = 'Unavailable';
      } else if (aiGeneratedFields.contains(entry.key)) {
        informationStatuses[entry.key] = 'AI-Generated';
      } else if (_isVerifiedSource(informationSources[entry.key])) {
        informationStatuses[entry.key] = 'API Verified';
      } else {
        informationStatuses[entry.key] = 'Needs Verification';
      }
    }
    final unavailableFields = _stringSet(enrichment?['unavailableFields']);
    for (final field in unavailableFields) {
      informationStatuses.putIfAbsent(field, () => 'Unavailable');
    }
    final probability = suggestion?['probability'];
    return PlantIdentificationResult(
      scanId: scanId,
      name: name,
      commonName: commonName,
      scientificName: _nonEmptyString(details?['scientific_name']) ?? name,
      family: _nonEmptyString(taxonomy?['family']) ?? 'Not listed',
      probability: probability is num && probability.isFinite
          ? probability.toDouble()
          : null,
      imageBytes: imageBytes,
      tagalogName: tagalogName,
      bisayaName: bisayaName,
      kingdom: _nonEmptyString(taxonomy?['kingdom']),
      phylum: _nonEmptyString(taxonomy?['phylum']),
      taxonomicClass: _nonEmptyString(taxonomy?['class']),
      order: _nonEmptyString(taxonomy?['order']),
      genus: _nonEmptyString(taxonomy?['genus']),
      species: _nonEmptyString(taxonomy?['species']),
      description: _nonEmptyString(details?['description']),
      botanicalInformation: botanicalInformation,
      informationSources: Map.unmodifiable(informationSources),
      informationStatuses: Map.unmodifiable(informationStatuses),
      aiGeneratedFields: aiGeneratedFields,
      fieldGeneratedAt: _stringMap(generatedAt),
      unavailableFields: unavailableFields,
      enrichmentGeneratedAt: _nonEmptyString(enrichment?['generatedAt']),
      enrichmentError: _nonEmptyString(enrichment?['enrichmentError']),
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _firstString(Object? value) {
    if (value is! List) return null;
    for (final item in value) {
      final string = _nonEmptyString(item);
      if (string != null) return string;
    }
    return null;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Map<String, String> _stringMap(Map<String, dynamic>? value) {
    final result = <String, String>{};
    for (final entry in value?.entries ?? const <MapEntry<String, dynamic>>[]) {
      final text = _nonEmptyString(entry.value);
      if (text == null) continue;
      result[entry.key] = text;
    }
    return Map.unmodifiable(result);
  }

  static Set<String> _stringSet(Object? value) =>
      value is List ? Set.unmodifiable(value.whereType<String>()) : const {};

  static bool _isVerifiedSource(String? source) =>
      source != null &&
      RegExp(
        r'\b(gbif|perenual|kew|plants of the world online)\b',
        caseSensitive: false,
      ).hasMatch(source);

  static String _messageFor(String code) => switch (code) {
    'authentication_required' ||
    'invalid_session' => 'Sign in again before identifying a plant.',
    'email_verification_required' =>
      'Verify your email before identifying a plant.',
    'rate_limit_exceeded' || 'plant_identification_rate_limited' =>
      'Too many plant scans. Please try again later.',
    'valid_image_required' =>
      'Choose a readable JPEG, PNG, or WebP photo and try again.',
    'plant_identification_not_configured' =>
      'Plant identification is not configured on the server.',
    'plant_identification_no_match' =>
      'No plant match was found. Try a clearer photo of the leaves.',
    'plant_identification_provider_error' ||
    'plant_identification_unavailable' => 'Plant identification is temporarily unavailable. Please try again later.',
    _ => 'Plant identification failed. Please try again later.',
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
    final map = _asMap(payload);
    final error = _asMap(map?['error']);
    return _nonEmptyString(error?['code']);
  }

  static String _codeForStatus(int status) => switch (status) {
    401 => 'authentication_required',
    403 => 'email_verification_required',
    429 => 'rate_limit_exceeded',
    422 => 'plant_identification_no_match',
    500 || 502 || 503 => 'plant_identification_provider_error',
    _ => 'plant_identification_unavailable',
  };
}
