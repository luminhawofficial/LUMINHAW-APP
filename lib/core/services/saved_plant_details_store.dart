import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPlantDetailsStore {
  SavedPlantDetailsStore({String? Function()? ownerIdProvider})
    : _ownerIdProvider =
          ownerIdProvider ?? (() => SupabaseAuthService.currentUser?.id);

  static final instance = SavedPlantDetailsStore();
  static const _storageKey = 'saved_library_plant_details';

  final String? Function() _ownerIdProvider;
  final ValueNotifier<Map<String, Map<String, Object?>>> savedPlants =
      ValueNotifier(const {});

  Future<void>? _loadFuture;
  String? _activeScope;

  String get _currentScope {
    final ownerId = _ownerIdProvider();
    return ownerId == null ? 'device' : 'account:$ownerId';
  }

  String _storageKeyForScope(String scope) => scope == 'device'
      ? _storageKey
      : '${_storageKey}_account_${scope.substring('account:'.length)}';

  Future<void> load() {
    final scope = _currentScope;
    if (_activeScope != scope) {
      _activeScope = scope;
      _loadFuture = null;
      savedPlants.value = const {};
    }

    final existing = _loadFuture;
    if (existing != null) return existing;
    final future = _loadFromPreferences(scope);
    _loadFuture = future;
    return future.catchError((Object error) {
      _loadFuture = null;
      throw error;
    });
  }

  Future<void> reload() {
    _loadFuture = null;
    return load();
  }

  Future<void> _loadFromPreferences(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKeyForScope(scope));
    final plants = <String, Map<String, Object?>>{};
    if (encoded != null) {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key is String && entry.value is Map) {
            plants[entry.key as String] = Map<String, Object?>.from(
              entry.value as Map,
            );
          }
        }
      }
    }
    if (_activeScope == scope && _currentScope == scope) {
      savedPlants.value = Map.unmodifiable(plants);
    }
  }

  Future<void> save(
    PlantRecord plant, {
    Map<String, String> enrichedFields = const {},
    Map<String, String> enrichmentSources = const {},
    Set<String> aiGeneratedFields = const {},
  }) async {
    await load();
    final scope = _activeScope!;
    if (_currentScope != scope) {
      throw StateError('The account changed before the plant could be saved.');
    }
    final name = plant.commonName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(plant.commonName, 'commonName');
    }
    final details = <String, Object?>{
      ...plant.toStoredDetails(),
      'enrichedFields': {...plant.enrichedFields, ...enrichedFields},
      'enrichmentSources': {...plant.enrichmentSources, ...enrichmentSources},
      'aiGeneratedFields': {
        ...plant.aiGeneratedFields,
        ...aiGeneratedFields,
      }.toList(),
    };
    final updated = {...savedPlants.value, name: details};
    final preferences = await SharedPreferences.getInstance();
    final persisted = await preferences.setString(
      _storageKeyForScope(scope),
      jsonEncode(updated),
    );
    if (!persisted) {
      throw StateError('Plant details could not be saved on this device.');
    }
    if (_currentScope == scope) {
      savedPlants.value = Map.unmodifiable(updated);
    }
  }

  Future<bool> remove(String commonName) async {
    await load();
    final scope = _activeScope!;
    if (_currentScope != scope) {
      throw StateError(
        'The account changed before the saved plant could be removed.',
      );
    }
    final name = commonName.trim();
    if (name.isEmpty || !savedPlants.value.containsKey(name)) return false;
    final updated = {...savedPlants.value}..remove(name);
    final preferences = await SharedPreferences.getInstance();
    final persisted = await preferences.setString(
      _storageKeyForScope(scope),
      jsonEncode(updated),
    );
    if (!persisted) {
      throw StateError('Saved plant details could not be removed.');
    }
    if (_currentScope == scope) {
      savedPlants.value = Map.unmodifiable(updated);
    }
    return true;
  }

  Future<void> clearPersonalData({required String ownerId}) async {
    final preferences = await SharedPreferences.getInstance();
    final scope = 'account:$ownerId';
    final storageKey = _storageKeyForScope(scope);
    if (!preferences.containsKey(storageKey)) {
      if (_activeScope == scope) {
        savedPlants.value = const {};
        _loadFuture = Future<void>.value();
      }
      return;
    }
    final removed = await preferences.remove(storageKey);
    if (!removed) {
      throw StateError('Saved plant details could not be cleared.');
    }
    if (_activeScope == scope) {
      savedPlants.value = const {};
      _loadFuture = Future<void>.value();
    }
  }

  List<PlantRecord> get plants => [
    for (final entry in savedPlants.value.entries)
      PlantRecord.fromStoredDetails(entry.key, entry.value),
  ];
}
