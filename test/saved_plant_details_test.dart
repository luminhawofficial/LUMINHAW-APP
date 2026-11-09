import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_enrichment_service.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/features/library/library_page.dart';
import 'package:luminhaw/features/settings/saved_plant_details_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _plant = PlantRecord(
  commonName: 'Monstera',
  scientificName: 'Monstera deliciosa',
  category: 'Plants',
  water: 'Water when the top soil starts to dry.',
  image: '',
  family: 'Araceae',
  genus: 'Monstera',
  species: 'deliciosa',
  description: 'A climbing tropical plant with split leaves.',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalPlantDataStore.instance.retryLoad();
  });

  test('saved plant details persist separately from My Garden', () async {
    final store = SavedPlantDetailsStore();
    await store.save(
      _plant,
      enrichedFields: const {'soilCompatibility': 'Well-drained soil.'},
      enrichmentSources: const {'soilCompatibility': 'LUMIN AI (Gemini)'},
      aiGeneratedFields: const {'soilCompatibility'},
    );

    await LocalPlantDataStore.instance.load();
    expect(store.plants, hasLength(1));
    expect(
      store.plants.single.enrichedFields['soilCompatibility'],
      'Well-drained soil.',
    );
    expect(LocalPlantDataStore.instance.gardenPlantNames.value, isEmpty);

    final reloaded = SavedPlantDetailsStore();
    await reloaded.load();
    expect(reloaded.plants.single.commonName, 'Monstera');
    expect(
      reloaded.plants.single.aiGeneratedFields,
      contains('soilCompatibility'),
    );
  });

  testWidgets(
    'saved detail page shows saved plant and removes only saved data',
    (tester) async {
      final store = SavedPlantDetailsStore();
      await store.save(_plant);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SavedPlantDetailsPage(
                      store: store,
                      plant: store.plants.single,
                    ),
                  ),
                ),
                child: const Text('Open saved details'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open saved details'));
      await tester.pumpAndSettle();

      expect(find.text('Your saved plant'), findsOneWidget);
      expect(find.text('Monstera deliciosa'), findsWidgets);
      expect(find.text('About this plant'), findsOneWidget);
      expect(find.text('Basic care'), findsOneWidget);
      expect(find.text('Remove from saved plant details'), findsOneWidget);

      await tester.ensureVisible(find.text('Remove from saved plant details'));
      await tester.tap(find.text('Remove from saved plant details'));
      await tester.pumpAndSettle();

      expect(store.plants, isEmpty);
      await LocalPlantDataStore.instance.load();
      expect(LocalPlantDataStore.instance.gardenPlantNames.value, isEmpty);
    },
  );

  testWidgets(
    'Library plant can save enriched output without adding to Garden',
    (tester) async {
      final store = SavedPlantDetailsStore.instance;
      await store.reload();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlantDetailPage(
              plant: _plant,
              enrichmentLoader: (_) async => const PlantEnrichment(
                fields: {
                  'dailyCare': 'Bright indirect light.',
                  'originHabitat': 'Native to Central America.',
                },
                sources: {
                  'dailyCare': 'Perenual',
                  'originHabitat': 'LUMIN AI (Gemini)',
                },
                aiGeneratedFields: {'originHabitat'},
                unavailableFields: {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save plant details'), findsOneWidget);

      await tester.tap(find.text('Save plant details'));
      await tester.pumpAndSettle();

      expect(store.plants, hasLength(1));
      expect(
        store.plants.single.enrichedFields['originHabitat'],
        'Native to Central America.',
      );
      await LocalPlantDataStore.instance.load();
      expect(LocalPlantDataStore.instance.gardenPlantNames.value, isEmpty);
    },
  );
}
