import 'package:luminhaw/core/services/supabase_backend.dart';

class ScanHistoryRecord {
  const ScanHistoryRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    this.plantName,
    this.provider,
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final String? plantName;
  final String? provider;

  static ScanHistoryRecord fromJson(Map<String, dynamic> json) {
    final result = _asMap(json['result']);
    final classification = _asMap(result?['classification']);
    final suggestions = classification?['suggestions'];
    String? plantName;
    if (suggestions is List && suggestions.isNotEmpty) {
      final firstSuggestion = _asMap(suggestions.first);
      final name = firstSuggestion?['name'];
      if (name is String && name.trim().isNotEmpty) {
        plantName = name.trim();
      }
    }

    final provider = json['provider'];
    return ScanHistoryRecord(
      id: json['id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      plantName: plantName,
      provider: provider is String && provider.trim().isNotEmpty
          ? provider.trim()
          : null,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    return null;
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
}
