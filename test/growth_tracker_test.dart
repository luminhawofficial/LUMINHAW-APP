import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_care_recommendations.dart';
import 'package:luminhaw/features/growth_tracker/growth_tracker_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('growth journal displays the photo saved with an observation', (
    tester,
  ) async {
    final store = LocalPlantDataStore();
    await store.addPlant(
      'Tomato',
      details: {'plantingDate': '2026-10-01', 'growthStage': 'Seedling'},
    );
    final photoBytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL+nwAAAABJRU5ErkJggg==',
      ),
    );
    await store.saveGrowthEntry(
      GrowthEntry(
        id: 'photo-observation',
        plantName: 'Tomato',
        activity: 'Observation',
        date: DateTime(2026, 11, 12),
        notes: 'First flowers appeared.',
      ),
      photoBytes: photoBytes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GrowthTrackerPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    final photo = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect(photo.height, 180);
    expect(find.text('First flowers appeared.'), findsOneWidget);
  });

  test(
    'care task completion persists its recommendation, time, and notes',
    () async {
      final store = LocalPlantDataStore();
      await store.addPlant(
        'Tomato',
        details: {'plantingDate': '2026-10-01', 'growthStage': 'Vegetative'},
      );
      final completedAt = DateTime(2026, 11, 9, 9, 15);
      final task = CompletedCareTask(
        id: 'tomato|Check soil moisture|2026-11-09',
        plantName: 'Tomato',
        title: 'Check soil moisture',
        recommendation: 'Water only when the plant needs it.',
        dueAt: DateTime(2026, 11, 9),
        completedAt: completedAt,
        notes: 'Top layer was dry.',
      );

      await store.saveCompletedCareTask(task);

      final reloadedStore = LocalPlantDataStore();
      await reloadedStore.load();
      final restored = reloadedStore.completedCareTasks.value.single;
      expect(restored.title, task.title);
      expect(restored.recommendation, task.recommendation);
      expect(restored.dueAt, task.dueAt);
      expect(restored.completedAt, completedAt);
      expect(restored.notes, task.notes);
    },
  );

  test('recommendations use the growth stage and completed care history', () {
    final now = DateTime(2026, 11, 9, 12);
    final details = {'plantingDate': '2026-10-01', 'growthStage': 'Vegetative'};
    final completed = CompletedCareTask(
      id: 'soil-check-1',
      plantName: 'Tomato',
      title: 'Check soil moisture',
      recommendation: 'Check the soil.',
      dueAt: DateTime(2026, 11, 9),
      completedAt: DateTime(2026, 11, 9, 9),
      notes: '',
    );

    final recommendations = PlantCareRecommendations.dueForPlant(
      plantName: 'Tomato',
      plantDetails: details,
      growthEntries: const [],
      completedTasks: [completed],
      now: now,
    );

    expect(
      recommendations.any((task) => task.title == 'Check soil moisture'),
      isFalse,
    );
    expect(
      recommendations.any((task) => task.title == 'Review fertilizer needs'),
      isTrue,
    );
    expect(
      recommendations
          .firstWhere((task) => task.title == 'Review fertilizer needs')
          .guidance,
      contains('Vegetative'),
    );
  });

  testWidgets('Growth Tracker lets users complete and annotate a task', (
    tester,
  ) async {
    final store = LocalPlantDataStore();
    await store.addPlant(
      'Tomato',
      details: {
        'plantingDate': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String()
            .split('T')
            .first,
        'growthStage': 'Seedling',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GrowthTrackerPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Growth journal'), findsOneWidget);
    expect(find.text('Care activities'), findsOneWidget);
    expect(find.text('Smart suggestion plan'), findsOneWidget);
    expect(find.text('General reminders and cautions'), findsOneWidget);
    expect(find.text('Smart care plan'), findsNothing);
    expect(find.text('Premium feature'), findsNothing);

    final moistureTask = find.byType(Checkbox).first;
    await tester.ensureVisible(moistureTask);
    await tester.tap(moistureTask);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('care-task-completion-notes')),
      'Soil felt dry.',
    );
    await tester.tap(find.text('Save completion'));
    await tester.pumpAndSettle();

    expect(find.text('Completed care'), findsOneWidget);
    expect(find.text('Check soil moisture'), findsWidgets);
    expect(find.textContaining('Soil felt dry.'), findsOneWidget);
    expect(store.completedCareTasks.value.single.notes, 'Soil felt dry.');
    expect(tester.takeException(), isNull);
  });
}
