import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_enrichment_service.dart';
import 'package:luminhaw/features/garden/add_garden_plant_page.dart';
import 'package:luminhaw/features/library/library_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mango = PlantRecord(
  commonName: 'Papaya',
  scientificName: 'Carica papaya',
  category: 'Plants',
  water: '',
  image: '',
  family: 'Caricaceae',
  tagalogName: 'Papaya',
  bisayaName: 'Kapayas',
  source: 'GBIF',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalPlantDataStore.instance.retryLoad();
  });

  testWidgets(
    'Library searches local names without adding garden records',
    (tester) async {
      final store = LocalPlantDataStore.instance;
      await store.load();
      String? searched;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryPage(
              searchCatalog: (query) async {
                searched = query;
                return [_mango];
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('plant-catalog-search')),
        'Kapayas',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(searched, 'Kapayas');
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Papaya'), findsOneWidget);
      expect(find.text('Tagalog: Papaya'), findsOneWidget);
      expect(find.text('Cebuano/Bisaya: Kapayas'), findsOneWidget);
      expect(store.gardenPlantNames.value, isEmpty);
    },
  );

  testWidgets('plant profiles show enrichment without a Garden action', (
    tester,
  ) async {
    final store = LocalPlantDataStore.instance;
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlantDetailPage(
            plant: _mango,
            enrichmentLoader: (_) async => const PlantEnrichment(
              fields: {
                'dailyCare': 'Let the top layer of soil dry before watering.',
                'originHabitat': 'Native to Central America.',
                'soilCompatibility': 'Well-drained soil',
                'wateringFrequency': 'Check soil before watering',
              },
              sources: {
                'dailyCare': 'Gemini AI',
                'originHabitat': 'Gemini AI',
                'soilCompatibility': 'Gemini AI',
                'wateringFrequency': 'Perenual',
              },
              aiGeneratedFields: {
                'dailyCare',
                'originHabitat',
                'soilCompatibility',
              },
              unavailableFields: {'humidity'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Growing and care information'), findsOneWidget);
    expect(find.text('Origin and natural habitat'), findsOneWidget);
    expect(find.text('Native to Central America.'), findsOneWidget);
    expect(find.text('Daily care'), findsOneWidget);
    expect(
      find.text('Let the top layer of soil dry before watering.'),
      findsOneWidget,
    );
    expect(find.text('Well-drained soil'), findsOneWidget);
    expect(find.textContaining('AI-generated estimate'), findsWidgets);
    expect(
      find.textContaining(
        'No reliable details available for: Preferred humidity',
      ),
      findsWidgets,
    );
    expect(find.text('Track This Plant'), findsNothing);
    expect(store.gardenPlantNames.value, isEmpty);
  });

  testWidgets('manual Garden registration saves initial growth tracking data', (
    tester,
  ) async {
    final store = LocalPlantDataStore.instance;
    await store.load();
    await tester.pumpWidget(const MaterialApp(home: AddGardenPlantPage()));

    await tester.enterText(
      find.byKey(const ValueKey('garden-plant-name')),
      'Papaya',
    );
    await tester.enterText(
      find.byKey(const ValueKey('garden-initial-height')),
      '24',
    );
    await tester.enterText(
      find.byKey(const ValueKey('garden-initial-observation')),
      'First observation',
    );
    await tester.ensureVisible(find.text('Add to My Garden'));
    await tester.tap(find.text('Add to My Garden'));
    await tester.pumpAndSettle();

    expect(store.gardenPlantNames.value, ['Papaya']);
    expect(
      store.gardenPlantDetails.value['Papaya']?['growthStage'],
      'Seedling',
    );
    expect(store.growthEntries.value.single.heightCm, 24);
    expect(store.growthEntries.value.single.notes, 'First observation');
  });
}
