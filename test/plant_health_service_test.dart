import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_health_service.dart';

void main() {
  test('parses health status and possible disease details', () {
    final assessment = PlantHealthAssessment.parseResponse({
      'result': {
        'is_healthy': {'binary': false, 'probability': 0.91},
        'disease': {
          'suggestions': [
            {
              'name': 'Leaf spot',
              'probability': 0.78,
              'details': {
                'local_name': 'Leaf spot disease',
                'description': {'value': 'Dark lesions may appear on leaves.'},
                'cause': [
                  {'value': 'Can be associated with prolonged leaf wetness.'},
                ],
                'treatment': {'value': 'Remove affected foliage.'},
              },
            },
          ],
        },
      },
    }, id: 'assessment-1');

    expect(assessment.id, 'assessment-1');
    expect(assessment.isHealthy, isFalse);
    expect(assessment.healthProbability, 0.91);
    expect(assessment.predictions, hasLength(1));
    expect(assessment.predictions.single.name, 'Leaf spot');
    expect(assessment.predictions.single.localName, 'Leaf spot disease');
    expect(
      assessment.predictions.single.description,
      'Dark lesions may appear on leaves.',
    );
    expect(
      assessment.predictions.single.cause,
      'Can be associated with prolonged leaf wetness.',
    );
    expect(assessment.predictions.single.treatment, 'Remove affected foliage.');
  });

  test('parses healthy results without disease suggestions', () {
    final assessment = PlantHealthAssessment.parseResponse({
      'result': {
        'is_healthy': {'binary': true, 'probability': 0.98},
        'disease': {'suggestions': []},
      },
    });

    expect(assessment.isHealthy, isTrue);
    expect(assessment.predictions, isEmpty);
  });

  test('rejects a response without usable health data', () {
    expect(
      () => PlantHealthAssessment.parseResponse({
        'result': {
          'disease': {'suggestions': []},
        },
      }),
      throwsFormatException,
    );
  });
}
