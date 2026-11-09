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
