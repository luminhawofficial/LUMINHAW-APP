import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/scan_history_service.dart';

void main() {
  test('reads the top plant suggestion from an identification result', () {
    final record = ScanHistoryRecord.fromJson({
      'id': 'scan-1',
      'status': 'completed',
      'provider': 'plant.id',
      'created_at': '2026-10-27T02:00:00.000Z',
      'result': {
        'classification': {
          'suggestions': [
            {'name': 'Monstera deliciosa'},
          ],
        },
      },
    });

    expect(record.id, 'scan-1');
    expect(record.status, 'completed');
    expect(record.plantName, 'Monstera deliciosa');
    expect(record.provider, 'plant.id');
    expect(record.createdAt, DateTime.utc(2026, 10, 27, 2));
  });

  test('reads nested provider results stored by Supabase', () {
    final record = ScanHistoryRecord.fromJson({
      'id': 'scan-nested',
      'status': 'completed',
      'created_at': '2026-10-27T02:00:00.000Z',
      'result': {
        'provider': 'plant.id',
        'localizedNames': {'tagalog': 'Mangga'},
        'result': {
          'classification': {
            'suggestions': [
              {
                'name': 'Mangifera indica',
                'probability': 0.96,
                'details': {
                  'common_names': ['Mango'],
                  'taxonomy': {'family': 'Anacardiaceae'},
                },
              },
            ],
          },
        },
      },
    });

    expect(record.plantName, 'Mangifera indica');
    expect(record.commonName, 'Mango');
    expect(record.family, 'Anacardiaceae');
    expect(record.probability, 0.96);
    expect(record.tagalogName, 'Mangga');
  });

  test('reads scan names, taxonomy, confidence, and enriched details', () {
    final record = ScanHistoryRecord.fromJson({
      'id': 'scan-3',
      'status': 'completed',
      'provider': 'plant.id',
      'created_at': '2026-10-27T02:00:00.000Z',
      'result': {
        'localizedNames': {'tagalog': 'Mangga', 'bisaya': 'Mangga'},
        'plantEnrichment': {
          'profile': {'soilCompatibility': 'Well-drained soil'},
        },
        'classification': {
          'suggestions': [
            {
              'name': 'Mangifera indica',
              'probability': 0.94,
              'details': {
                'scientific_name': 'Mangifera indica',
                'common_names': ['Mango'],
                'description': 'A tropical fruit tree.',
                'taxonomy': {'family': 'Anacardiaceae', 'genus': 'Mangifera'},
              },
            },
          ],
        },
      },
    });

    expect(record.commonName, 'Mango');
    expect(record.plantName, 'Mangifera indica');
    expect(record.family, 'Anacardiaceae');
    expect(record.probability, 0.94);
    expect(record.tagalogName, 'Mangga');
    expect(record.bisayaName, 'Mangga');
    expect(record.description, 'A tropical fruit tree.');
    expect(record.taxonomy['genus'], 'Mangifera');
    expect(record.plantDetails['soilCompatibility'], 'Well-drained soil');
  });

  test('allows pending rows without an identification result', () {
    final record = ScanHistoryRecord.fromJson({
      'id': 'scan-2',
      'status': 'pending',
      'provider': null,
      'created_at': '2026-10-27T02:00:00.000Z',
      'result': null,
    });

    expect(record.status, 'pending');
    expect(record.plantName, isNull);
    expect(record.provider, isNull);
  });
}
