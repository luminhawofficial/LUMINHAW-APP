import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart' show safePlantImageUrl;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

class PlantCatalogService {
  PlantCatalogService._();

  static Future<List<PlantRecord>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2 || trimmedQuery.length > 80) {
      throw ArgumentError.value(
        query,
        'query',
        'Plant name must be between 2 and 80 characters.',
      );
    }
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    if (SupabaseAuthService.currentUser?.emailConfirmedAt == null) {
      throw StateError('Sign in with a verified email to search the catalog.');
    }

    List<PlantRecord> verifiedPlants = const [];
    try {
      verifiedPlants = await _searchVerifiedCatalog(trimmedQuery);
    } catch (error) {
      debugPrint('Verified plant catalog lookup failed: $error');
    }

    late final dynamic response;
    try {
      response = await SupabaseBackend.client.functions.invoke(
        'plant-catalog',
        body: {'q': trimmedQuery},
      );
    } on FunctionException catch (error) {
      if (verifiedPlants.isNotEmpty) return verifiedPlants;
      throw StateError(
        _messageFor(_errorCode(error.details) ?? _codeForStatus(error.status)),
      );
    }
    if (response.status < 200 || response.status >= 300) {
      if (verifiedPlants.isNotEmpty) return verifiedPlants;
      throw StateError(
        _messageFor(
          _errorCode(response.data) ?? _codeForStatus(response.status),
        ),
      );
    }

    final providerPlants = parseResponse(response.data);
    return preferVerifiedCatalogRecords(verifiedPlants, providerPlants);
  }

  static Future<List<PlantRecord>> _searchVerifiedCatalog(String query) async {
    final fields = [
      'scientific_name',
      'common_name',
      'tagalog_name',
      'bisaya_name',
    ];
    final rowsById = <String, Map<String, dynamic>>{};
    await Future.wait(
      fields.map((field) async {
        final rows = await SupabaseBackend.client
            .from('plant_catalog')
            .select('*, plant_care(*), plant_images(*)')
            .eq('is_verified', true)
            .eq('is_active', true)
            .ilike(field, '%$query%')
            .limit(20);
        for (final row in rows) {
          final record = Map<String, dynamic>.from(row);
          final id = record['id'];
          if (id is String) rowsById[id] = record;
        }
      }),
    );
    if (rowsById.isEmpty) return const [];
    return parseResponse({
      'success': true,
      'source': 'LUMINHAW verified catalog',
      'results': rowsById.values.toList(growable: false),
    });
  }

  @visibleForTesting
  static List<PlantRecord> preferVerifiedCatalogRecords(
    List<PlantRecord> verified,
    List<PlantRecord> providers,
  ) {
    final names = <String>{
      for (final plant in verified) _normalizedName(plant.scientificName),
    };
    return List.unmodifiable([
      ...verified,
      ...providers.where(
        (plant) => names.add(_normalizedName(plant.scientificName)),
      ),
    ]);
  }

  static String _normalizedName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  @visibleForTesting
  static List<PlantRecord> parseResponse(Object? response) {
    Object? payload = response;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        throw const FormatException(
          'Plant catalog returned an invalid response.',
        );
      }
    }
    if (payload is List) {
      // legacy top-level array format
    } else if (payload is! Map) {
      throw const FormatException(
        'Plant catalog returned an invalid response.',
      );
    }

    final map = payload is Map ? Map<String, dynamic>.from(payload) : null;
    final nestedMap = _asMap(map?['data']) ?? _asMap(map?['result']);
    if (_isErrorResponse(map) || _isErrorResponse(nestedMap)) {
      final code =
          _errorCode(map) ??
          _errorCode(nestedMap) ??
          'plant_catalog_provider_error';
      throw StateError(_messageFor(code));
    }
    final responseMap = nestedMap ?? map;
    final records = payload is List
        ? payload
        : (responseMap?['results'] ??
              responseMap?['plants'] ??
              responseMap?['data'] ??
              responseMap?['items'] ??
              responseMap?['catalog'] ??
              map?['results'] ??
              map?['plants'] ??
              map?['items'] ??
              map?['catalog']);
    if (records is! List) {
      throw const FormatException(
        'Plant catalog returned an invalid response.',
      );
    }

    final defaultSource =
        _string(responseMap?['source']) ?? _string(map?['source']) ?? 'catalog';
    final seenScientificNames = <String>{};
    final plants = <PlantRecord>[];
    for (final item in records) {
      if (item is! Map) continue;
      final rank = _string(item['rank']) ?? _string(item['taxonomic_rank']);
      if (rank != null && rank.toLowerCase() != 'species') continue;
      final taxonomicStatus =
          _string(item['taxonomicStatus']) ??
          _string(item['taxonomic_status']) ??
          _string(item['status']);
      if (taxonomicStatus != null &&
          taxonomicStatus.toLowerCase() != 'accepted') {
        continue;
      }
      final scientificName =
          _string(item['acceptedScientificName']) ??
          _string(item['acceptedName']) ??
          _string(item['scientificName']) ??
          _string(item['scientific_name']);
      if (scientificName == null) continue;
      final commonName =
          _string(item['commonName']) ??
          _string(item['common_name']) ??
          _string(item['vernacularName']) ??
          _string(item['canonicalName']) ??
          scientificName;

      final acceptedTaxonId =
          _identifier(item['acceptedTaxonId']) ??
          _identifier(item['acceptedKey']) ??
          _identifier(item['speciesKey']) ??
          _identifier(item['gbif_key']) ??
          _identifier(item['key']);
      final care = _asMap(_first(item['plant_care']));
      final image = _primaryImage(item['plant_images']);
      final isVerified =
          item['isVerified'] == true || item['is_verified'] == true;
      final soil =
          _string(item['soil_requirements']) ??
          _string(care?['soil_requirements']) ??
          _string(care?['soil']);
      final sunlight =
          _string(item['sunlight_requirements']) ??
          _string(care?['sunlight_requirements']) ??
          _string(care?['sunlight']);
      final careInstructions =
          _string(care?['watering']) ??
          _string(care?['water_requirements']) ??
          _string(care?['instructions']);
      final compatibleWeather =
          _string(item['compatible_weather']) ??
          _string(care?['compatible_weather']);
      final origin = _string(item['origin']);
      final temperature = _string(care?['temperature']);
      final taxonKey =
          acceptedTaxonId ??
          scientificName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!seenScientificNames.add(taxonKey)) continue;

      final enrichedFields = <String, String>{
        ..._stringMap(item['enrichedFields']),
        'originHabitat': origin?,
        'weatherClimate': compatibleWeather?,
        'soilCompatibility': soil?,
        'sunlightRequirements': sunlight?,
        'careInstructions': careInstructions?,
        'temperatureRange': temperature?,
      };
      final plantSource = isVerified
          ? 'LUMINHAW verified catalog'
          : _string(item['source']) ??
                _string(item['description_source']) ??
                defaultSource;
      final enrichmentSources = <String, String>{
        ..._stringMap(item['enrichmentSources']),
        if (isVerified) ...{
          for (final key in [
            'scientificName',
            'family',
            'tagalogName',
            'bisayaName',
            ...enrichedFields.keys,
          ])
            key: plantSource,
        },
      };
      plants.add(
        PlantRecord(
          commonName: commonName,
          scientificName: scientificName,
          category: 'Plants',
          water:
              _string(care?['water_requirements']) ??
              _string(care?['watering']) ??
              _string(care?['instructions']) ??
              'Care guidance is not provided by the catalog.',
          image: '',
          family: _string(item['family']) ?? 'Not listed',
          order: _string(item['order']),
          kingdom: _string(item['kingdom']),
          phylum: _string(item['phylum']),
          taxonomicClass:
              _string(item['class']) ?? _string(item['taxonomicClass']),
          genus: _string(item['genus']),
          species: _string(item['species']),
          taxonomicRank: rank,
          taxonomicStatus: taxonomicStatus,
          description:
              _string(item['description']) ??
              _descriptionFrom(item['descriptions']),
          tagalogName:
              _string(item['tagalogName']) ?? _string(item['tagalog_name']),
          bisayaName:
              _string(item['bisayaName']) ?? _string(item['bisaya_name']),
          formerScientificName:
              _string(item['formerScientificName']) ?? _string(item['synonym']),
          acceptedTaxonId: acceptedTaxonId,
          imageUrl: safePlantImageUrl(
            item['imageUrl'] ??
                item['image_url'] ??
                item['defaultImageUrl'] ??
                image?['image_url'],
          ),
          imageAttribution:
              _string(item['imageAttribution']) ?? _string(image?['creator']),
          imageLicense:
              _string(item['imageLicense']) ?? _string(image?['license']),
          imageLicenseUrl:
              _string(item['imageLicenseUrl']) ??
              _string(image?['license_url']),
          imageReferenceUrl:
              _string(item['imageReferenceUrl']) ??
              _string(image?['source_url']),
          source: plantSource,
          enrichedFields: Map.unmodifiable(enrichedFields),
          enrichmentSources: Map.unmodifiable(enrichmentSources),
          isVerified: isVerified,
        ),
      );
    }
    return List.unmodifiable(plants);
  }

  static String? _string(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static Object? _first(Object? value) =>
      value is List && value.isNotEmpty ? value.first : value;

  static Map<String, dynamic>? _primaryImage(Object? value) {
    if (value is! List) return null;
    final images = value.whereType<Map>().map(
      (image) => Map<String, dynamic>.from(image),
    );
    for (final image in images) {
      if (image['is_verified'] == true && image['is_primary'] == true) {
        return image;
      }
    }
    for (final image in images) {
      if (image['is_verified'] == true) return image;
    }
    return null;
  }

  static Map<String, String> _stringMap(Object? value) {
    final map = _asMap(value);
    if (map == null) return const {};
    return {
      for (final entry in map.entries)
        if (_string(entry.value) != null) entry.key: _string(entry.value)!,
    };
  }

  static bool _isErrorResponse(Map<String, dynamic>? payload) =>
      payload != null &&
      (payload['success'] == false || payload.containsKey('error'));

  static String? _identifier(Object? value) {
    if (value is int && value > 0) return value.toString();
    return _string(value);
  }

  static String? _descriptionFrom(Object? value) {
    if (value is String) return _string(value);
    if (value is! List) return null;
    for (final item in value) {
      if (item is Map) {
        final description =
            _string(item['description']) ?? _string(item['text']);
        if (description != null) return description;
      }
    }
    return null;
  }

  static String _messageFor(String code) => switch (code) {
    'authentication_required' ||
    'invalid_session' => 'Sign in to search the online plant catalog.',
    'email_verification_required' =>
      'Verify your email to search the online plant catalog.',
    'rate_limit_exceeded' =>
      'Too many catalog searches. Please try again later.',
    'query_must_be_between_2_and_80_characters' =>
      'Enter a plant name between 2 and 80 characters.',
    'plant_catalog_unavailable' || 'plant_catalog_provider_error' =>
      'Plant catalog providers are temporarily unavailable.',
    _ => 'Plant catalog search failed. Please try again later.',
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
    if (payload is Map) {
      final error = payload['error'];
      if (error is Map && error['code'] is String) {
        return error['code'] as String;
      }
      if (error is String && error.trim().isNotEmpty) {
        return switch (error.trim().toLowerCase()) {
          'plant_catalog_unavailable' ||
          'plant_catalog_provider_error' => error.trim().toLowerCase(),
          _ => 'plant_catalog_provider_error',
        };
      }
    }
    return null;
  }

  static String _codeForStatus(int status) => switch (status) {
    401 => 'authentication_required',
    403 => 'email_verification_required',
    429 => 'rate_limit_exceeded',
    500 || 502 || 503 => 'plant_catalog_provider_error',
    _ => 'plant_catalog_request_failed',
  };
}
