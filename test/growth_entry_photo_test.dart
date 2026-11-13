import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/widgets/growth_entry_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalPlantDataStore.instance.growthEntries.value = const [];
  });

  test('selects the earliest photo-bearing entry for a plant', () {
    final entries = [
      GrowthEntry(
        id: 'later',
        plantName: 'Papaya',
        activity: 'Observation',
        date: DateTime(2026, 11, 10),
        notes: '',
        photoDataBase64: 'later-photo',
      ),
      GrowthEntry(
        id: 'other-plant',
        plantName: 'Mango',
        activity: 'Observation',
        date: DateTime(2026, 10, 1),
        notes: '',
        photoDataBase64: 'mango-photo',
      ),
      GrowthEntry(
        id: 'initial',
        plantName: 'Papaya',
        activity: 'Observation',
        date: DateTime(2026, 10, 1),
        notes: '',
        photoDataBase64: 'initial-photo',
      ),
      GrowthEntry(
        id: 'without-photo',
        plantName: 'Papaya',
        activity: 'Observation',
        date: DateTime(2026, 9, 1),
        notes: '',
      ),
    ];

    final initialPhoto = initialGrowthPhotoForPlant(' papaya ', entries);

    expect(initialPhoto?.id, 'initial');
  });

  testWidgets('shows an uploaded initial photo as the plant cover', (
    tester,
  ) async {
    final png = base64Encode(
      Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL+nwAAAABJRU5ErkJggg==',
        ),
      ),
    );
    LocalPlantDataStore.instance.growthEntries.value = [
      GrowthEntry(
        id: 'initial',
        plantName: 'Papaya',
        activity: 'Observation',
        date: DateTime(2026, 10, 1),
        notes: '',
        photoDataBase64: png,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 120,
          height: 96,
          child: PlantCoverPhoto(
            plant: const PlantRecord(
              commonName: 'Papaya',
              scientificName: 'Carica papaya',
              category: 'Plants',
              water: '',
              image: '',
            ),
            width: 120,
            height: 96,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });
}
