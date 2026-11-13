import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_identification_service.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/features/scan_results/scan_result_page.dart';

void main() {
  setUp(() {
    PlanEntitlementStore.instance.tier.value = PlanTier.free;
    PlanEntitlementStore.instance.expiresAt.value = null;
  });

  testWidgets('warns when the identification match has low confidence', (
    tester,
  ) async {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL+nwAAAABJRU5ErkJggg==',
      ),
    );
    final result = PlantIdentificationResult(
      scanId: 'scan-id',
      name: 'Carica papaya',
      commonName: 'Papaya',
      scientificName: 'Carica papaya',
      family: 'Caricaceae',
      probability: 0.42,
      imageBytes: png,
    );

    await tester.pumpWidget(
      MaterialApp(home: ScanResultPage(scanResult: result)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Low provider match score'), findsOneWidget);
    expect(find.textContaining('Try a clearer photo'), findsOneWidget);
    expect(find.text('Provider match score'), findsOneWidget);
    expect(
      find.text('Provider-reported score; not a measured accuracy rate.'),
      findsOneWidget,
    );
  });

  testWidgets('scan result displays field sources and verification statuses', (
    tester,
  ) async {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL+nwAAAABJRU5ErkJggg==',
      ),
    );
    final result = PlantIdentificationResult(
      scanId: 'scan-id',
      name: 'Carica papaya',
      commonName: 'Papaya',
      scientificName: 'Carica papaya',
      family: 'Caricaceae',
      probability: 0.98,
      imageBytes: png,
      tagalogName: 'Papaya',
      bisayaName: 'Kapayas',
      botanicalInformation: const {
        'description': 'A tropical fruiting plant in the family Caricaceae.',
        'characteristics': 'Large leaves grow near the top of the trunk.',
        'weatherClimate': 'Warm tropical climate with full sunlight.',
        'soilCompatibility': 'Well-drained loamy soil.',
        'originHabitat': 'Native to tropical America.',
        'growthCharacteristics': 'Fast-growing; size varies by cultivar.',
        'wateringFrequency': 'Water when the topsoil begins to dry.',
        'nutrientDeficiencies': 'Older leaves may yellow when nitrogen is low.',
        'genus': 'Carica',
        'species': 'papaya',
      },
      informationSources: const {
        'commonName': 'Plant.ID',
        'scientificName': 'Plant.ID',
        'tagalogName': 'GBIF',
        'bisayaName': 'Gemini AI',
        'weatherClimate': 'LUMIN AI (Gemini)',
        'soilCompatibility': 'LUMIN AI (Gemini)',
        'originHabitat': 'LUMIN AI (Gemini)',
        'growthCharacteristics': 'Perenual',
        'wateringFrequency': 'LUMIN AI (Gemini)',
        'nutrientDeficiencies': 'LUMIN AI (Gemini)',
        'genus': 'Plant.ID',
        'species': 'Plant.ID',
      },
      informationStatuses: const {
        'commonName': 'Needs Verification',
        'scientificName': 'Needs Verification',
        'tagalogName': 'API Verified',
        'bisayaName': 'AI-Generated',
        'weatherClimate': 'AI-Generated',
        'soilCompatibility': 'AI-Generated',
        'originHabitat': 'AI-Generated',
        'growthCharacteristics': 'API Verified',
        'wateringFrequency': 'AI-Generated',
        'nutrientDeficiencies': 'AI-Generated',
        'genus': 'Needs Verification',
        'species': 'Needs Verification',
        'humidity': 'Unavailable',
      },
      aiGeneratedFields: const {
        'bisayaName',
        'weatherClimate',
        'soilCompatibility',
        'originHabitat',
        'wateringFrequency',
        'nutrientDeficiencies',
      },
      fieldGeneratedAt: const {
        'bisayaName': '2026-11-08T12:00:00Z',
        'weatherClimate': '2026-11-08T12:00:00Z',
        'soilCompatibility': '2026-11-08T12:00:00Z',
        'originHabitat': '2026-11-08T12:00:00Z',
        'wateringFrequency': '2026-11-08T12:00:00Z',
      },
      unavailableFields: const {'humidity'},
      enrichmentGeneratedAt: '2026-11-08T12:00:00Z',
    );

    await tester.pumpWidget(
      MaterialApp(home: ScanResultPage(scanResult: result)),
    );
    await tester.pumpAndSettle();

    expect(find.text('English name'), findsOneWidget);
    expect(find.textContaining('Low-confidence match'), findsNothing);
    expect(find.text('Papaya'), findsWidgets);
    expect(find.text('Tagalog name'), findsOneWidget);
    expect(find.text('Provider-sourced · GBIF'), findsOneWidget);
    expect(find.text('Cebuano/Bisaya name'), findsOneWidget);
    expect(
      find.textContaining('AI-Generated · LUMIN AI (Gemini)'),
      findsWidgets,
    );
    expect(find.text('Plant Information'), findsOneWidget);
    expect(find.text('Basic plant care'), findsOneWidget);
    expect(find.text('Compatible Weather'), findsNothing);
    expect(find.text('Suitable Soil'), findsNothing);
    expect(find.text('Plant Origin'), findsNothing);
    expect(find.text('Growth Information'), findsNothing);
    expect(find.text('Unlock detailed plant care.'), findsNothing);
    expect(find.text('Watering frequency'), findsOneWidget);
    expect(find.text('Water when the topsoil begins to dry.'), findsOneWidget);
    expect(
      find.textContaining(
        'Provider-sourced information is not necessarily expert-reviewed.',
      ),
      findsOneWidget,
    );
    expect(find.text('Explore Subscription'), findsNothing);
    expect(find.text('Unavailable'), findsNothing);
    expect(find.text('Library'), findsNothing);

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    expect(find.text('Premium feature'), findsOneWidget);
    expect(find.text('Plant biology: Papaya'), findsNothing);

    PlanEntitlementStore.instance.tier.value = PlanTier.premium;
    PlanEntitlementStore.instance.expiresAt.value = DateTime.now().toUtc().add(
      const Duration(days: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Plant biology: Papaya'), findsOneWidget);
    expect(find.text('How plants function'), findsOneWidget);
    expect(find.text('Photosynthesis'), findsOneWidget);
    expect(find.text('Classification'), findsOneWidget);
    expect(find.text('Description and characteristics'), findsOneWidget);
    expect(find.text('Origin and habitat'), findsOneWidget);
    expect(find.text('Life cycle and growth'), findsOneWidget);
    expect(find.text('Growth characteristics'), findsOneWidget);
    expect(find.text('Premium feature'), findsNothing);

    await tester.tap(find.text('Nutrients'));
    await tester.pumpAndSettle();
    expect(find.text('Plant nutrients: Papaya'), findsOneWidget);
    expect(
      find.textContaining('Nitrogen supports proteins and chlorophyll;'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Do not add fertilizer based on symptoms alone'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Yellowing, spots, or slow growth do not prove a nutrient deficiency.',
      ),
      findsOneWidget,
    );
    expect(find.text('Available information for this plant'), findsOneWidget);
    expect(find.text('Premium feature'), findsNothing);
  });
}
