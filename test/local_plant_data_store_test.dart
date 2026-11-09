import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('garden plants persist and duplicate additions are rejected', () async {
    final store = LocalPlantDataStore();

    expect(await store.addPlant('Monstera'), isTrue);
    expect(await store.addPlant('Monstera'), isFalse);

    final reloadedStore = LocalPlantDataStore();
    await reloadedStore.load();
    expect(reloadedStore.gardenPlantNames.value, ['Monstera']);
  });

  test('saved plant details persist with the garden plant', () async {
    final details = <String, Object?>{
      'scientificName': 'Monstera deliciosa',
      'family': 'Araceae',
      'description': 'A climbing tropical plant.',
    };
    final store = LocalPlantDataStore();

    expect(await store.addPlant('Monstera', details: details), isTrue);

    final reloadedStore = LocalPlantDataStore();
    await reloadedStore.load();
    expect(reloadedStore.gardenPlantNames.value, ['Monstera']);
    expect(reloadedStore.gardenPlantDetails.value['Monstera'], details);
  });

  test('catalog details can enrich a previously saved plant', () async {
    final store = LocalPlantDataStore();
    await store.addPlant('Monstera');

    expect(
      await store.addPlant(
        'Monstera',
        details: {'scientificName': 'Monstera deliciosa'},
      ),
      isFalse,
    );

    expect(store.gardenPlantDetails.value['Monstera'], {
      'scientificName': 'Monstera deliciosa',
    });
  });

  test('saved plant details restore a garden-ready plant record', () {
    final plant = PlantRecord.fromStoredDetails('Monstera', {
      'scientificName': 'Monstera deliciosa',
      'family': 'Araceae',
      'description': 'A climbing tropical plant.',
      'water': 'Water when the top soil dries.',
    });

    expect(plant.commonName, 'Monstera');
    expect(plant.scientificName, 'Monstera deliciosa');
    expect(plant.family, 'Araceae');
    expect(plant.description, 'A climbing tropical plant.');
    expect(plant.water, 'Water when the top soil dries.');
    expect(plant.isSaved, isTrue);
  });

  test('growth entries persist with measurements and notes', () async {
    final entry = GrowthEntry(
      id: 'entry-1',
      plantName: 'Snake Plant',
      activity: 'Observation',
      date: DateTime(2026, 10, 27),
      notes: 'A new leaf appeared.',
      heightCm: 24.5,
      leafCount: 8,
    );
    final store = LocalPlantDataStore();
    await store.addPlant('Snake Plant');

    await store.saveGrowthEntry(entry);

    final reloadedStore = LocalPlantDataStore();
    await reloadedStore.load();
    expect(reloadedStore.growthEntries.value, hasLength(1));
    final savedEntry = reloadedStore.growthEntries.value.single;
    expect(savedEntry.id, entry.id);
    expect(savedEntry.plantName, entry.plantName);
    expect(savedEntry.activity, entry.activity);
    expect(savedEntry.date, entry.date);
    expect(savedEntry.notes, entry.notes);
    expect(savedEntry.heightCm, entry.heightCm);
    expect(savedEntry.leafCount, entry.leafCount);
  });

  test('growth observation photos persist on device', () async {
    final pngBytes = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    final store = LocalPlantDataStore();
    await store.addPlant('Monstera');

    await store.saveGrowthEntry(
      GrowthEntry(
        id: 'photo-entry',
        plantName: 'Monstera',
        activity: 'Observation',
        date: DateTime(2026, 11, 6),
        notes: 'New leaf.',
      ),
      photoBytes: Uint8List.fromList(pngBytes),
    );

    final reloadedStore = LocalPlantDataStore();
    await reloadedStore.load();
    expect(
      reloadedStore.growthEntries.value.single.photoDataBase64,
      base64Encode(pngBytes),
    );
  });

  test('empty plant names are rejected', () async {
    final store = LocalPlantDataStore();

    await expectLater(store.addPlant('  '), throwsArgumentError);
  });

  test('growth records cannot implicitly create garden plants', () async {
    final store = LocalPlantDataStore();

    await expectLater(
      store.saveGrowthEntry(
        GrowthEntry(
          id: 'untracked-entry',
          plantName: 'Scanned plant',
          activity: 'Observation',
          date: DateTime(2026, 11, 7),
          notes: '',
        ),
      ),
      throwsStateError,
    );
    expect(store.gardenPlantNames.value, isEmpty);
  });
}
