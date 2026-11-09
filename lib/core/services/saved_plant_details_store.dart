import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPlantDetailsStore {
  SavedPlantDetailsStore();

  static final instance = SavedPlantDetailsStore();
  static const _storageKey = 'saved_library_plant_details';

  final ValueNotifier<Map<String, Map<String, Object?>>> savedPlants =
      ValueNotifier(const {});

  Future<void>? _loadFuture;

  Future<void> load() async {
    final existing = _loadFuture;
    if (existing != null) return existing;
    final future = _loadFromPreferences();
    _loadFuture = future;
    try {
      await future;
    } catch (_) {
      _loadFuture = null;
      rethrow;
    }
  }

  Future<void> reload() {
    _loadFuture = null;
    return load();
  }

  Future<void> _loadFromPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
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
    savedPlants.value = Map.unmodifiable(plants);
  }

  Future<void> save(
    PlantRecord plant, {
    Map<String, String> enrichedFields = const {},
    Map<String, String> enrichmentSources = const {},
    Set<String> aiGeneratedFields = const {},
  }) async {
    await load();
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
      _storageKey,
      jsonEncode(updated),
    );
    if (!persisted) {
      throw StateError('Plant details could not be saved on this device.');
    }
    savedPlants.value = Map.unmodifiable(updated);
  }

  Future<bool> remove(String commonName) async {
    await load();
    final name = commonName.trim();
    if (name.isEmpty || !savedPlants.value.containsKey(name)) return false;
    final updated = {...savedPlants.value}..remove(name);
    final preferences = await SharedPreferences.getInstance();
    final persisted = await preferences.setString(
      _storageKey,
      jsonEncode(updated),
    );
    if (!persisted) {
      throw StateError('Saved plant details could not be removed.');
    }
    savedPlants.value = Map.unmodifiable(updated);
    return true;
  }

  Future<void> clearPersonalData() async {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey(_storageKey)) {
      savedPlants.value = const {};
      _loadFuture = Future<void>.value();
      return;
    }
    final removed = await preferences.remove(_storageKey);
    if (!removed) {
      throw StateError('Saved plant details could not be cleared.');
    }
    savedPlants.value = const {};
    _loadFuture = Future<void>.value();
  }

  List<PlantRecord> get plants => [
    for (final entry in savedPlants.value.entries)
      PlantRecord.fromStoredDetails(entry.key, entry.value),
  ];
}
