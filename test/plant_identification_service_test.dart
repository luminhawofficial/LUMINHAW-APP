import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_identification_service.dart';

void main() {
  test('reads Tagalog and Bisaya names from localized identification data', () {
    final imageBytes = Uint8List.fromList([1, 2, 3]);
    final result = PlantIdentificationService.parseResponse(
      {
        'localizedNames': {'tagalog': 'Mangga', 'bisaya': 'Mangga'},
        'result': {
          'classification': {
            'suggestions': [
              {
                'name': 'Mangifera indica',
                'probability': 0.98,
                'details': {
                  'scientific_name': 'Mangifera indica',
                  'common_names': ['Mango'],
                  'taxonomy': {
                    'kingdom': 'Plantae',
                    'phylum': 'Tracheophyta',
                    'class': 'Magnoliopsida',
                    'order': 'Sapindales',
                    'family': 'Anacardiaceae',
                    'genus': 'Mangifera',
                    'species': 'indica',
                  },
                },
              },
            ],
          },
        },
      },
      scanId: 'scan-id',
      imageBytes: imageBytes,
    );

    expect(result.scanId, 'scan-id');
    expect(result.commonName, 'Mango');
    expect(result.tagalogName, 'Mangga');
    expect(result.bisayaName, 'Mangga');
    expect(result.informationSources['tagalogName'], 'GBIF');
    expect(result.informationStatuses['tagalogName'], 'API Verified');
    expect(result.informationStatuses['commonName'], 'Needs Verification');
    final plant = result.toPlantRecord();
    expect(plant.kingdom, 'Plantae');
    expect(plant.genus, 'Mangifera');
    expect(plant.species, 'indica');
    expect(result.imageBytes, same(imageBytes));
  });

  test(
    'allows localized names to be absent without inventing translations',
    () {
      final result = PlantIdentificationService.parseResponse(
        {
          'result': {
            'classification': {
              'suggestions': [
                {
                  'name': 'Unknown plant',
                  'details': {'scientific_name': 'Unknown plant'},
                },
              ],
            },
          },
        },
        scanId: 'scan-id',
        imageBytes: Uint8List(0),
      );

      expect(result.tagalogName, isNull);
      expect(result.bisayaName, isNull);
    },
  );

  test('reads enriched care fields and provenance from saved scan results', () {
    final result = PlantIdentificationService.parseResponse(
      {
        'plantEnrichment': {
          'profile': {
            'soilCompatibility': 'Well-drained loam',
            'wateringFrequency': 'Check soil before watering',
          },
          'fieldSources': {
            'soilCompatibility': 'Gemini AI',
            'wateringFrequency': 'Perenual',
          },
          'fieldStatuses': {
            'soilCompatibility': 'AI-Generated',
            'wateringFrequency': 'API Verified',
          },
          'aiGeneratedFields': ['soilCompatibility'],
          'fieldGeneratedAt': {'soilCompatibility': '2026-11-08T12:00:00Z'},
          'generatedAt': '2026-11-08T12:00:00Z',
          'unavailableFields': ['originHabitat'],
          'enrichmentError': null,
        },
        'result': {
          'classification': {
            'suggestions': [
              {
                'name': 'Carica papaya',
                'details': {
                  'scientific_name': 'Carica papaya',
                  'taxonomy': {'family': 'Caricaceae'},
                },
              },
            ],
          },
        },
      },
      scanId: 'scan-id',
      imageBytes: Uint8List.fromList([1]),
    );

    expect(
      result.botanicalInformation['soilCompatibility'],
      'Well-drained loam',
    );
    expect(result.informationSources['wateringFrequency'], 'Perenual');
    expect(result.informationStatuses['soilCompatibility'], 'AI-Generated');
    expect(result.informationStatuses['originHabitat'], 'Unavailable');
    expect(
      result.fieldGeneratedAt['soilCompatibility'],
      '2026-11-08T12:00:00Z',
    );
    expect(result.enrichmentGeneratedAt, '2026-11-08T12:00:00Z');
    expect(result.aiGeneratedFields, {'soilCompatibility'});
    expect(
      result.toPlantRecord().enrichedFields['soilCompatibility'],
      'Well-drained loam',
    );
  });
}
