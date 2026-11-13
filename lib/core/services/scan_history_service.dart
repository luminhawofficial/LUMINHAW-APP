import 'package:luminhaw/core/services/supabase_backend.dart';

class ScanHistoryRecord {
  const ScanHistoryRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    this.plantName,
    this.provider,
    this.commonName,
    this.family,
    this.probability,
    this.tagalogName,
    this.bisayaName,
    this.description,
    this.taxonomy = const {},
    this.plantDetails = const {},
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? plantName;
  final String? provider;
  final String? commonName;
  final String? family;
  final double? probability;
  final String? tagalogName;
  final String? bisayaName;
  final String? description;
  final Map<String, String> taxonomy;
  final Map<String, String> plantDetails;

  static ScanHistoryRecord fromJson(Map<String, dynamic> json) {
    final result = _asMap(json['result']);
    final providerResult = _asMap(result?['result']);
    final classification =
        _asMap(providerResult?['classification']) ??
        _asMap(result?['classification']);
    final suggestions = classification?['suggestions'];
    String? plantName;
    if (suggestions is List && suggestions.isNotEmpty) {
      final firstSuggestion = _asMap(suggestions.first);
      final name = firstSuggestion?['name'];
      if (name is String && name.trim().isNotEmpty) {
        plantName = name.trim();
      }
    }
    final firstSuggestion = suggestions is List && suggestions.isNotEmpty
        ? _asMap(suggestions.first)
        : null;
    final suggestionDetails = _asMap(firstSuggestion?['details']);
    final rawTaxonomy = _asMap(suggestionDetails?['taxonomy']);
    final localizedNames = _asMap(result?['localizedNames']);
    final enrichment = _asMap(result?['plantEnrichment']);
    final profile = _asMap(enrichment?['profile']);
    final commonNames = suggestionDetails?['common_names'];
    final commonName = commonNames is List
        ? commonNames
              .whereType<String>()
              .map((name) => name.trim())
              .firstWhere((name) => name.isNotEmpty, orElse: () => '')
        : null;
    final rawProbability = firstSuggestion?['probability'];
    final probability =
        rawProbability is num &&
            rawProbability.isFinite &&
            rawProbability >= 0 &&
            rawProbability <= 1
        ? rawProbability.toDouble()
        : null;

    final provider = json['provider'];
    return ScanHistoryRecord(
      id: json['id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      plantName: plantName,
      commonName: commonName == null || commonName.isEmpty ? null : commonName,
      family: _string(rawTaxonomy?['family']),
      probability: probability,
      tagalogName:
          _string(localizedNames?['tagalog']) ??
          _string(profile?['tagalogName']),
      bisayaName:
          _string(localizedNames?['bisaya']) ?? _string(profile?['bisayaName']),
      description:
          _string(suggestionDetails?['description']) ??
          _string(profile?['description']),
      taxonomy: _stringMap(rawTaxonomy),
      plantDetails: _stringMap(profile),
      provider: provider is String && provider.trim().isNotEmpty
          ? provider.trim()
          : null,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static Map<String, String> _stringMap(Map<String, dynamic>? value) {
    if (value == null) return const {};
    final strings = <String, String>{};
    for (final entry in value.entries) {
      final text = _string(entry.value);
      if (text != null) strings[entry.key] = text;
    }
    return Map.unmodifiable(strings);
  }
}

class ScanHistoryService {
  ScanHistoryService._();

  static Future<List<ScanHistoryRecord>> fetchRecent() async {
    final user = SupabaseAuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in to view your scan history.');
    }

    final rows = await SupabaseBackend.client
        .from('plant_identifications')
        .select('id,status,provider,result,created_at')
        .eq('owner_id', user.id)
        .order('created_at', ascending: false)
        .limit(50);

    return rows
        .map(
          (row) => ScanHistoryRecord.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  static Future<void> delete(String scanId) async {
    final user = SupabaseAuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in to delete a scan from your history.');
    }

    final deleted = await SupabaseBackend.client
        .from('plant_identifications')
        .delete()
        .eq('id', scanId)
        .eq('owner_id', user.id)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('This scan was not found in your account.');
    }
  }
}
