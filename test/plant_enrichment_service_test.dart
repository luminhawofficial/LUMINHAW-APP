import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_enrichment_service.dart';

void main() {
  test('parses care fields and marks AI estimates with provenance', () {
    final enrichment = PlantEnrichment.parseResponse({
      'success': true,
      'profile': {
        'tagalogName': 'Papaya',
        'bisayaName': 'Kapayas',
        'soilCompatibility': 'Well-drained loam',
        'wateringFrequency': 'Check soil moisture; interval varies.',
        'temperatureRange': 'Warm tropical conditions',
      },
      'fieldSources': {
        'tagalogName': 'GBIF',
        'soilCompatibility': 'Gemini AI',
        'wateringFrequency': 'Gemini AI',
        'temperatureRange': 'Perenual',
      },
      'fieldStatuses': {
        'tagalogName': 'API Verified',
        'soilCompatibility': 'AI-Generated',
        'wateringFrequency': 'AI-Generated',
        'temperatureRange': 'API Verified',
      },
      'aiGeneratedFields': ['soilCompatibility', 'wateringFrequency'],
      'fieldGeneratedAt': {
        'soilCompatibility': '2026-11-08T12:00:00Z',
        'wateringFrequency': '2026-11-08T12:00:00Z',
      },
      'generatedAt': '2026-11-08T12:00:00Z',
      'unavailableFields': ['humidity'],
    });

    expect(enrichment.fields['tagalogName'], 'Papaya');
    expect(enrichment.fields['bisayaName'], 'Kapayas');
    expect(enrichment.fields['soilCompatibility'], 'Well-drained loam');
    expect(enrichment.sources['temperatureRange'], 'Perenual');
    expect(enrichment.fieldStatuses['tagalogName'], 'API Verified');
    expect(enrichment.fieldStatuses['soilCompatibility'], 'AI-Generated');
    expect(
      enrichment.fieldGeneratedAt['soilCompatibility'],
      '2026-11-08T12:00:00Z',
    );
    expect(enrichment.generatedAt, '2026-11-08T12:00:00Z');
    expect(enrichment.aiGeneratedFields, {
      'soilCompatibility',
      'wateringFrequency',
    });
    expect(enrichment.unavailableFields, {'humidity'});
  });

  test('rejects invalid responses instead of fabricating data', () {
    expect(
      () => PlantEnrichment.parseResponse({'success': true}),
      throwsFormatException,
    );
    final enrichment = PlantEnrichment.parseResponse({
      'profile': {'soilCompatibility': null, 'tagalogName': ''},
      'fieldStatuses': {'tagalogName': 'Unavailable'},
      'unavailableFields': ['tagalogName'],
    });
    expect(enrichment.fields, isEmpty);
    expect(enrichment.fieldStatuses['tagalogName'], 'Unavailable');
    expect(enrichment.unavailableFields, {'tagalogName'});
  });
}
