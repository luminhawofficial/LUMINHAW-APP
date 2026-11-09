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
        'weatherClimate': 'Warm tropical climate with full sunlight.',
        'soilCompatibility': 'Well-drained loamy soil.',
        'originHabitat': 'Native to tropical America.',
        'growthCharacteristics': 'Fast-growing; size varies by cultivar.',
        'wateringFrequency': 'Water when the topsoil begins to dry.',
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
    expect(find.text('Papaya'), findsWidgets);
    expect(find.text('Tagalog name'), findsOneWidget);
    expect(find.text('API Verified · GBIF'), findsOneWidget);
    expect(find.text('Cebuano/Bisaya name'), findsOneWidget);
    expect(
      find.textContaining('AI-Generated · LUMIN AI (Gemini)'),
      findsWidgets,
    );
    expect(find.text('Plant Information'), findsOneWidget);
    expect(find.text('Compatible Weather'), findsOneWidget);
    expect(find.text('Suitable Soil'), findsOneWidget);
    expect(find.text('Plant Origin'), findsOneWidget);
    expect(find.text('Growth Information'), findsOneWidget);
    expect(find.text('Unlock detailed plant care.'), findsOneWidget);
    expect(find.text('Watering frequency'), findsNothing);
    expect(find.text('Water when the topsoil begins to dry.'), findsNothing);
    expect(find.text('Explore Subscription'), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
    expect(find.text('Library'), findsNothing);
  });
}
