import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/gemini_assistant_service.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_care_recommendations.dart';
import 'package:luminhaw/core/services/plant_notification_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/core/widgets/growth_entry_photo.dart';

class GrowthTrackerPage extends StatefulWidget {
  const GrowthTrackerPage({super.key, this.plant, this.store});

  final PlantRecord? plant;
  final LocalPlantDataStore? store;

  @override
  State<GrowthTrackerPage> createState() => _GrowthTrackerPageState();
}

class _GrowthTrackerPageState extends State<GrowthTrackerPage> {
  late final LocalPlantDataStore _store;
  final _notesController = TextEditingController();
  final _taskNotesController = TextEditingController();
  late final _plantController = TextEditingController(
    text: widget.plant?.commonName ?? '',
  );
  late Future<void> _loading;
  String _selectedActivity = 'Watered';
  bool _isSaving = false;
  bool _isGeneratingSuggestion = false;
  String? _suggestionPlantName;
  String? _careSuggestion;
  String? _suggestionError;
  final Set<String> _completingTaskIds = {};

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalPlantDataStore.instance;
    _loading = _store.load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _taskNotesController.dispose();
    _plantController.dispose();
    super.dispose();
  }

  Future<void> _saveCareActivity() async {
    final plantName = _plantController.text.trim();
    if (plantName.isEmpty ||
        !_store.gardenPlantNames.value.contains(plantName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a plant to My Garden before tracking its care.'),
        ),
      );
      return;
    }
    final entry = GrowthEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      plantName: plantName,
      activity: _selectedActivity,
      date: DateTime.now(),
      notes: _notesController.text.trim(),
    );
    setState(() => _isSaving = true);
    try {
      await _store.saveGrowthEntry(entry);
      unawaited(_refreshReminderSchedule());
      _notesController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _store.isCloudSynced
                  ? 'Care activity synced to your account.'
                  : 'Care activity saved on this device.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this activity: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (!mounted) return;
    setState(() {
      _suggestionPlantName = plantName;
      _careSuggestion = null;
      _suggestionError = null;
      _isGeneratingSuggestion = true;
    });
    try {
      final suggestion = await GeminiAssistantService.generateCareSuggestion(
        plantName: plantName,
        activity: entry.activity,
        notes: entry.notes,
      );
      if (mounted) setState(() => _careSuggestion = suggestion);
    } catch (error) {
      if (mounted) setState(() => _suggestionError = '$error');
    } finally {
      if (mounted) setState(() => _isGeneratingSuggestion = false);
    }
  }

  Future<void> _completeRecommendation(
    CareRecommendation recommendation,
  ) async {
    _taskNotesController.clear();
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Complete ${recommendation.title.toLowerCase()}?'),
        content: TextField(
          key: const ValueKey('care-task-completion-notes'),
          controller: _taskNotesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'What did you do or notice?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _taskNotesController.text),
            child: const Text('Save completion'),
          ),
        ],
      ),
    );
    if (notes == null || !mounted) return;

    setState(() => _completingTaskIds.add(recommendation.id));
    try {
      await _store.saveCompletedCareTask(
        CompletedCareTask(
          id: recommendation.id,
          plantName: recommendation.plantName,
          title: recommendation.title,
          recommendation: recommendation.guidance,
          dueAt: recommendation.dueAt,
          completedAt: DateTime.now(),
          notes: notes.trim(),
        ),
      );
      await _refreshReminderSchedule();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Care task saved on this device.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this task: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _completingTaskIds.remove(recommendation.id));
      }
    }
  }

  Future<void> _refreshReminderSchedule() async {
    try {
      await refreshEnabledCareReminders();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'care reminder scheduling',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Care was saved, but its reminder schedule could not be updated: $error',
            ),
          ),
        );
      }
    }
  }

  Widget _buildSuggestionPlan() {
    final selectedPlantName =
        _store.gardenPlantNames.value.contains(_plantController.text)
        ? _plantController.text
        : _store.gardenPlantNames.value.firstOrNull;
    final suggestionMatchesPlant =
        selectedPlantName != null && selectedPlantName == _suggestionPlantName;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Smart suggestion plan',
            style: TextStyle(
              color: AppColors.green,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'After you save a care activity, LUMIN AI uses your note to suggest a next step. Basic: 1 suggestion per plant each day; Premium: up to 4. Basic suggestions count toward the 10 daily AI requests. AI suggestions require a verified account.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (selectedPlantName == null)
            const Text(
              'Add a plant to My Garden and save a care activity to get a suggestion.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else if (!suggestionMatchesPlant)
            Text(
              'Save a care activity for $selectedPlantName to get a suggestion.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else if (_isGeneratingSuggestion)
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LUMIN AI is reviewing your saved activity and note…',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
              ],
            )
          else if (_suggestionError != null)
            Text(
              'Could not create a suggestion: $_suggestionError',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else if (_careSuggestion != null)
            Text(
              _careSuggestion!,
              style: const TextStyle(
                color: AppColors.dark,
                fontSize: 14,
                height: 1.5,
              ),
            )
          else
            const Text(
              'Your suggestion will appear here after you save a care activity.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneralReminders() {
    return ValueListenableBuilder<List<String>>(
      valueListenable: _store.gardenPlantNames,
      builder: (context, plants, _) {
        final plantName = plants.contains(_plantController.text)
            ? _plantController.text
            : plants.firstOrNull;
        if (plantName == null) return const SizedBox.shrink();
        return ValueListenableBuilder<Map<String, Map<String, Object?>>>(
          valueListenable: _store.gardenPlantDetails,
          builder: (context, details, _) => ValueListenableBuilder<List<GrowthEntry>>(
            valueListenable: _store.growthEntries,
            builder: (context, entries, _) =>
                ValueListenableBuilder<List<CompletedCareTask>>(
                  valueListenable: _store.completedCareTasks,
                  builder: (context, completedTasks, _) {
                    final recommendations =
                        PlantCareRecommendations.dueForPlant(
                          plantName: plantName,
                          plantDetails: details[plantName] ?? const {},
                          growthEntries: entries,
                          completedTasks: completedTasks,
                        );
                    final history = completedTasks
                        .where((task) => task.plantName == plantName)
                        .take(5)
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'General reminders and cautions',
                                style: TextStyle(
                                  color: AppColors.green,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'These reminders use the growth stage and care history. Check your plant’s needs before watering or fertilizing; these are not a diagnosis.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "Today's tasks",
                                style: TextStyle(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (recommendations.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'You are up to date. Your next general check is due tomorrow.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              else
                                for (final recommendation in recommendations)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Checkbox(
                                          key: ValueKey(
                                            'care-task-${recommendation.id}',
                                          ),
                                          value: false,
                                          onChanged:
                                              _completingTaskIds.contains(
                                                recommendation.id,
                                              )
                                              ? null
                                              : (_) => _completeRecommendation(
                                                  recommendation,
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  recommendation.title,
                                                  style: const TextStyle(
                                                    color: AppColors.green,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  recommendation.guidance,
                                                  style: const TextStyle(
                                                    color: AppColors.muted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              if (history.isNotEmpty) ...[
                                const Divider(height: 24),
                                const Text(
                                  'Completed care',
                                  style: TextStyle(
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                for (final task in history)
                                  Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      leading: const Icon(
                                        Icons.check_circle,
                                        color: AppColors.green,
                                      ),
                                      title: Text(task.title),
                                      subtitle: Text(
                                        '${_formatDate(task.completedAt)} · '
                                        '${TimeOfDay.fromDateTime(task.completedAt).format(context)}'
                                        '${task.notes.isEmpty ? '' : '\n${task.notes}'}',
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Track plant growth',
      subtitle: 'Keep growth observations, photos, and care activities.',
      back: true,
      child: FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppCard(
              child: Column(
                children: [
                  Text('Could not load your journal: ${snapshot.error}'),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _store.retryLoad();
                        _loading = _store.load();
                      });
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Text(
                'Loading your journal…',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.plant == null
                                ? 'Growth journal'
                                : '${widget.plant!.commonName} journal',
                            style: const TextStyle(
                              color: AppColors.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/add-entry',
                            arguments: widget.plant,
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Add entry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Care activities',
                      style: TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<List<String>>(
                      valueListenable: _store.gardenPlantNames,
                      builder: (context, plants, _) {
                        if (plants.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Add a plant to My Garden before recording care activities.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/add-plant'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add a plant'),
                              ),
                            ],
                          );
                        }
                        if (!plants.contains(_plantController.text)) {
                          _plantController.text = plants.first;
                        }
                        return DropdownButtonFormField<String>(
                          initialValue: _plantController.text,
                          items: [
                            for (final name in plants)
                              DropdownMenuItem(value: name, child: Text(name)),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _plantController.text = value);
                            }
                          },
                          decoration: const InputDecoration(labelText: 'Plant'),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedActivity,
                      items: const [
                        DropdownMenuItem(
                          value: 'Watered',
                          child: Text('Watered'),
                        ),
                        DropdownMenuItem(
                          value: 'Fertilized',
                          child: Text('Fertilized'),
                        ),
                        DropdownMenuItem(
                          value: 'Pruned',
                          child: Text('Pruned'),
                        ),
                        DropdownMenuItem(
                          value: 'Repotted',
                          child: Text('Repotted'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedActivity = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Activity'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      maxLength: 2500,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      label: _isSaving ? 'Saving…' : 'Save care activity',
                      onPressed: _isSaving ? null : _saveCareActivity,
                    ),
                  ],
                ),
              ),
              _buildSuggestionPlan(),
              const SizedBox(height: 16),
              const Text(
                'Recent activity',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<List<GrowthEntry>>(
                valueListenable: _store.growthEntries,
                builder: (context, entries, _) {
                  final visibleEntries = entries
                      .where(
                        (entry) =>
                            widget.plant == null ||
                            entry.plantName == widget.plant!.commonName,
                      )
                      .take(10)
                      .toList();
                  if (visibleEntries.isEmpty) {
                    return const AppCard(
                      child: Text(
                        'No growth or care entries yet.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final entry in visibleEntries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.plantName} · ${entry.activity}',
                                        style: const TextStyle(
                                          color: AppColors.green,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDate(entry.date),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                if (entry.heightCm != null ||
                                    entry.leafCount != null) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    [
                                      if (entry.heightCm != null)
                                        '${entry.heightCm} cm',
                                      if (entry.leafCount != null)
                                        '${entry.leafCount} leaves',
                                    ].join(' · '),
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (entry.notes.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    entry.notes,
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                if (entry.photoPath != null ||
                                    entry.photoDataBase64 != null) ...[
                                  const SizedBox(height: 8),
                                  _GrowthEntryPhoto(entry: entry),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildGeneralReminders(),
              const SizedBox(height: 12),
              ValueListenableBuilder<Object?>(
                valueListenable: _store.loadError,
                builder: (context, error, _) => error == null
                    ? SetupNotice(
                        message: _store.isCloudSynced
                            ? 'Your journal is synced to your verified account.'
                            : 'Journal entries are saved on this device. Sign in with a verified account to sync them.',
                      )
                    : AppCard(
                        child: Column(
                          children: [
                            Text('Could not sync your journal: $error'),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _store.retryLoad();
                                  _loading = _store.load();
                                });
                              },
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GrowthEntryPhoto extends StatelessWidget {
  const _GrowthEntryPhoto({required this.entry});

  final GrowthEntry entry;

  @override
  Widget build(BuildContext context) => GrowthEntryPhoto(
    entry: entry,
    width: double.infinity,
    height: 180,
    borderRadius: 12,
  );
}

class AddGrowthEntryPage extends StatefulWidget {
  const AddGrowthEntryPage({super.key, this.plant});

  final PlantRecord? plant;

  @override
  State<AddGrowthEntryPage> createState() => _AddGrowthEntryPageState();
}

class _AddGrowthEntryPageState extends State<AddGrowthEntryPage> {
  final _formKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _leafCountController = TextEditingController();
  final _notesController = TextEditingController();
  final _store = LocalPlantDataStore.instance;
  final _picker = ImagePicker();
  late String _selectedPlant = widget.plant?.commonName ?? '';
  DateTime _date = DateTime.now();
  Uint8List? _photoBytes;
  bool _isSaving = false;

  @override
  void dispose() {
    _heightController.dispose();
    _leafCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selectedDate != null && mounted) setState(() => _date = selectedDate);
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > LocalPlantDataStore.maximumObservationPhotoBytes) {
        _showMessage('Choose a photo no larger than 2 MB.');
        return;
      }
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    } on PlatformException {
      _showMessage('Could not access the selected photo.');
    } catch (error) {
      _showMessage('Could not read the selected photo: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveObservation() async {
    if (!_store.gardenPlantNames.value.contains(_selectedPlant)) {
      _showMessage('Add a plant to My Garden before recording growth.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _store.saveGrowthEntry(
        GrowthEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          plantName: _selectedPlant,
          activity: 'Observation',
          date: _date,
          heightCm: _heightController.text.trim().isEmpty
              ? null
              : double.parse(_heightController.text.trim()),
          leafCount: _leafCountController.text.trim().isEmpty
              ? null
              : int.parse(_leafCountController.text.trim()),
          notes: _notesController.text.trim(),
        ),
        photoBytes: _photoBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _store.isCloudSynced
                  ? 'Observation synced to your account.'
                  : 'Observation saved on this device.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this observation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Add entry',
      subtitle: 'Record a growth observation for your plant.',
      back: true,
      child: Form(
        key: _formKey,
        child: AppCard(
          child: Column(
            children: [
              ValueListenableBuilder<List<String>>(
                valueListenable: _store.gardenPlantNames,
                builder: (context, plants, _) {
                  if (plants.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Add a plant to My Garden before recording growth.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/add-plant'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add a plant'),
                        ),
                      ],
                    );
                  }
                  if (!plants.contains(_selectedPlant)) {
                    _selectedPlant = plants.first;
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedPlant,
                    decoration: const InputDecoration(labelText: 'Plant'),
                    items: [
                      for (final name in plants)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedPlant = value);
                      }
                    },
                    validator: (value) => value == null
                        ? 'Choose a plant from your garden'
                        : null,
                  );
                },
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Observation date',
                ),
                child: InkWell(
                  onTap: _chooseDate,
                  child: Row(
                    children: [
                      Expanded(child: Text(_formatDate(_date))),
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.green,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _heightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Height (cm)',
                  hintText: 'Optional',
                ),
                validator: _validateNumber,
              ),
              TextFormField(
                controller: _leafCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of leaves',
                  hintText: 'Optional',
                ),
                validator: _validateLeafCount,
              ),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observation notes',
                  hintText: 'A new leaf appeared today...',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Growth photo (optional, up to 2 MB)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 6),
              if (_photoBytes case final bytes?) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _photoBytes = null),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove photo'),
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Upload Photo'),
                ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: _isSaving ? 'Saving…' : 'Save observation',
                onPressed: _isSaving ? null : _saveObservation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _validateNumber(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final number = double.tryParse(value);
  if (number == null || !number.isFinite || number < 0) {
    return 'Enter a valid non-negative number';
  }
  return null;
}

String? _validateLeafCount(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final count = int.tryParse(value);
  if (count == null || count < 0) {
    return 'Enter a valid non-negative whole number';
  }
  return null;
}

String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
