import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_care_service.dart';

void main() {
  test('parses only care fields returned by the provider', () {
    final guide = PlantCareGuide.parseResponse({
      'scientificName': 'Abies alba',
      'source': 'Perenual',
      'sourceUrl': 'https://perenual.com/',
      'care': {
        'watering': 'Frequent',
        'sunlight': 'Part shade',
        'soil': 'Rocky, Dry, Well-drained',
        'hardinessZone': '7–7',
        'temperature': null,
        'humidity': '',
      },
    });

    expect(guide.scientificName, 'Abies alba');
    expect(guide.source, 'Perenual');
    expect(guide.care, {
      'watering': 'Frequent',
      'sunlight': 'Part shade',
      'soil': 'Rocky, Dry, Well-drained',
      'hardinessZone': '7–7',
    });
    expect(guide.care.containsKey('temperature'), isFalse);
    expect(guide.care.containsKey('humidity'), isFalse);
  });

  test('rejects a response without supported care information', () {
    expect(
      () => PlantCareGuide.parseResponse({
        'scientificName': 'Abies alba',
        'source': 'Perenual',
        'sourceUrl': 'https://perenual.com/',
        'care': {'watering': null},
      }),
      throwsFormatException,
    );
  });

  test('preserves available plant knowledge fields without filling gaps', () {
    final guide = PlantCareGuide.parseResponse({
      'scientificName': 'Monstera deliciosa',
      'source': 'Perenual',
      'sourceUrl': 'https://perenual.com/',
      'care': {
        'wateringBenchmark': '3–5 days',
        'hardinessZone': '10–12',
        'soil': 'Well-draining soil',
        'soilPh': '5.5–7.0',
        'origin': 'Central America',
        'growthRate': 'Moderate',
        'nitrogen': null,
        'humidity': '',
      },
    });

    expect(guide.care, {
      'wateringBenchmark': '3–5 days',
      'hardinessZone': '10–12',
      'soil': 'Well-draining soil',
      'soilPh': '5.5–7.0',
      'origin': 'Central America',
      'growthRate': 'Moderate',
    });
  });
}
