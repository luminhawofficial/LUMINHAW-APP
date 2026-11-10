import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_notification_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class AddGardenPlantPage extends StatefulWidget {
  const AddGardenPlantPage({super.key});

  @override
  State<AddGardenPlantPage> createState() => _AddGardenPlantPageState();
}

class _AddGardenPlantPageState extends State<AddGardenPlantPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _heightController = TextEditingController();
  final _notesController = TextEditingController();
  final _store = LocalPlantDataStore.instance;
  final _picker = ImagePicker();
  DateTime _plantingDate = DateTime.now();
  String _growthStage = 'Seedling';
  Uint8List? _photoBytes;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _choosePlantingDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _plantingDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) setState(() => _plantingDate = date);
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length > LocalPlantDataStore.maximumObservationPhotoBytes) {
        _showMessage('Choose a photo no larger than 2 MB.');
        return;
      }
      if (mounted) setState(() => _photoBytes = bytes);
    } on PlatformException {
      _showMessage('Could not access the selected photo.');
    } catch (error) {
      _showMessage('Could not read the selected photo: $error');
    }
  }

  Future<void> _savePlant() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final name = _nameController.text.trim();
    try {
      await _store.load();
      if (_store.gardenPlantNames.value.contains(name)) {
        _showMessage('$name is already in My Garden.');
        return;
      }
      final added = await _store.addPlant(
        name,
        details: {
          'plantingDate': _plantingDate.toIso8601String().split('T').first,
          'growthStage': _growthStage,
        },
      );
      if (!added) {
        _showMessage('$name is already in My Garden.');
        return;
      }

      final heightText = _heightController.text.trim();
      if (_photoBytes != null ||
          heightText.isNotEmpty ||
          _notesController.text.trim().isNotEmpty) {
        try {
          await _store.saveGrowthEntry(
            GrowthEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              plantName: name,
              activity: 'Observation',
              date: _plantingDate,
              heightCm: heightText.isEmpty ? null : double.parse(heightText),
              notes: _notesController.text.trim(),
            ),
            photoBytes: _photoBytes,
          );
        } catch (error) {
          _showMessage(
            '$name was added, but its first growth record could not be saved: $error',
          );
          return;
        }
      }
      String? reminderError;
      try {
        await refreshEnabledCareReminders();
      } catch (error, stackTrace) {
        reminderError = error.toString();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'care reminder scheduling',
          ),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reminderError == null
                ? '$name was added to My Garden.'
                : '$name was added, but reminders could not be updated: $reminderError',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      _showMessage('Could not add this plant: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateHeight(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final height = double.tryParse(trimmed);
    if (height == null || !height.isFinite || height < 0) {
      return 'Enter a valid non-negative height.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ScreenBody(
    title: 'Add a plant to track',
    subtitle: 'Only plants you add here are saved to My Garden.',
    back: true,
    child: Form(
      key: _formKey,
      child: AppCard(
        child: Column(
          children: [
            TextFormField(
              key: const ValueKey('garden-plant-name'),
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Plant name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a plant name.'
                  : null,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Planting date'),
              child: InkWell(
                onTap: _isSaving ? null : _choosePlantingDate,
                child: Row(
                  children: [
                    Expanded(child: Text(_formatDate(_plantingDate))),
                    const Icon(Icons.calendar_today_outlined),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const ValueKey('garden-growth-stage'),
              initialValue: _growthStage,
              decoration: const InputDecoration(labelText: 'Growth stage'),
              items:
                  const [
                    'Seedling',
                    'Vegetative',
                    'Budding',
                    'Flowering',
                    'Fruiting',
                    'Mature',
                    'Other',
                  ].map((stage) {
                    return DropdownMenuItem(value: stage, child: Text(stage));
                  }).toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _growthStage = value);
                    },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('garden-initial-height'),
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Current height (cm)',
                hintText: 'Optional',
              ),
              validator: _validateHeight,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('garden-initial-observation'),
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Initial observation',
                hintText: 'Optional notes about this plant',
              ),
            ),
            const SizedBox(height: 12),
            if (_photoBytes case final bytes?) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  height: 160,
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
                key: const ValueKey('garden-plant-photo'),
                onPressed: _isSaving ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload plant photo (optional)'),
              ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: _isSaving ? 'Adding plant…' : 'Add to My Garden',
              icon: Icons.yard_outlined,
              onPressed: _isSaving ? null : _savePlant,
            ),
          ],
        ),
      ),
    ),
  );

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
