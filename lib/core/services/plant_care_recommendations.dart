import 'package:luminhaw/core/services/local_plant_data_store.dart';

class CareRecommendation {
  const CareRecommendation({
    required this.id,
    required this.plantName,
    required this.title,
    required this.guidance,
    required this.dueAt,
  });

  final String id;
  final String plantName;
  final String title;
  final String guidance;
  final DateTime dueAt;
}

class PlantCareRecommendations {
  const PlantCareRecommendations._();

  static List<CareRecommendation> dueForPlant({
    required String plantName,
    required Map<String, Object?> plantDetails,
    required List<GrowthEntry> growthEntries,
    required List<CompletedCareTask> completedTasks,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final stageValue = plantDetails['growthStage'];
    final stage = stageValue is String && stageValue.isNotEmpty
        ? stageValue
        : 'current';
    final plantingDate = _parseDate(plantDetails['plantingDate']) ?? today;
    final plantEntries = growthEntries
        .where((entry) => entry.plantName == plantName)
        .toList();
    final plantTasks = completedTasks
        .where((task) => task.plantName == plantName)
        .toList();
    final recommendations = <CareRecommendation>[];

    void addIfDue({
      required String title,
      required String guidance,
      required int intervalDays,
      required DateTime lastDone,
    }) {
      final nextDue = _dateOnly(lastDone).add(Duration(days: intervalDays));
      if (nextDue.isAfter(today)) return;
      final due = CareRecommendation(
        id: '$plantName|$title|${_dateKey(nextDue)}',
        plantName: plantName,
        title: title,
        guidance: guidance,
        dueAt: nextDue,
      );
      recommendations.add(due);
    }

    DateTime lastTaskOrEntry({
      required String title,
      required List<String> activities,
    }) {
      final taskDates = plantTasks
          .where((task) => task.title == title)
          .map((task) => task.completedAt);
      final entryDates = plantEntries
          .where((entry) => activities.contains(entry.activity.toLowerCase()))
          .map((entry) => entry.date);
      return [...taskDates, ...entryDates].fold<DateTime>(
        plantingDate,
        (latest, date) => date.isAfter(latest) ? date : latest,
      );
    }

    addIfDue(
      title: 'Check soil moisture',
      guidance:
          '$stage stage: check the soil and follow this plant’s care guide; '
          'water only when it needs it.',
      intervalDays: 1,
      lastDone: lastTaskOrEntry(
        title: 'Check soil moisture',
        activities: ['watered', 'check soil moisture'],
      ),
    );
    addIfDue(
      title: 'Inspect for pests',
      guidance:
          'Look under leaves and along stems for changes. Note anything unusual '
          'before treating the plant.',
      intervalDays: 7,
      lastDone: lastTaskOrEntry(
        title: 'Inspect for pests',
        activities: ['inspect for pests', 'checked for pests'],
      ),
    );
    addIfDue(
      title: 'Review light conditions',
      guidance:
          'Check whether the current light still suits this plant and its '
          '$stage stage before moving it.',
      intervalDays: 7,
      lastDone: lastTaskOrEntry(
        title: 'Review light conditions',
        activities: ['review light conditions'],
      ),
    );
    addIfDue(
      title: 'Record growth progress',
      guidance:
          'Add a dated observation, measurements, or a photo to compare this '
          'plant with earlier entries.',
      intervalDays: 7,
      lastDone: lastTaskOrEntry(
        title: 'Record growth progress',
        activities: ['observation', 'record growth progress'],
      ),
    );

    if (const {
      'vegetative',
      'budding',
      'flowering',
      'fruiting',
    }.contains(stage.toLowerCase())) {
      addIfDue(
        title: 'Review fertilizer needs',
        guidance:
            'At the $stage stage, check this plant’s care instructions and the product label. '
            'Only fertilize if its current stage calls for it.',
        intervalDays: 14,
        lastDone: lastTaskOrEntry(
          title: 'Review fertilizer needs',
          activities: ['fertilized', 'review fertilizer needs'],
        ),
      );
    }

    recommendations.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return List.unmodifiable(recommendations);
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
