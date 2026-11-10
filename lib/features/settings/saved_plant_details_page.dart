import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class SavedPlantDetailsPage extends StatefulWidget {
  const SavedPlantDetailsPage({super.key, this.store, this.plant});

  final SavedPlantDetailsStore? store;
  final PlantRecord? plant;

  @override
  State<SavedPlantDetailsPage> createState() => _SavedPlantDetailsPageState();
}

class _SavedPlantDetailsPageState extends State<SavedPlantDetailsPage> {
  SavedPlantDetailsStore get _store =>
      widget.store ?? SavedPlantDetailsStore.instance;

  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _store.load();
  }

  @override
  Widget build(BuildContext context) => ScreenBody(
    title: widget.plant == null ? 'Saved plant details' : 'Your saved plant',
    subtitle: widget.plant == null
        ? 'Plant information saved from your Library. Not in My Garden.'
        : 'Identification and care details saved from your Library.',
    back: true,
    child: FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppCard(
            child: Text(
              'Saved plant details could not be loaded: ${snapshot.error}',
              style: const TextStyle(color: AppColors.muted),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (widget.plant case final plant?) return _plantDetails(plant);
        return _savedPlantList();
      },
    ),
  );

  Widget _savedPlantList() =>
      ValueListenableBuilder<Map<String, Map<String, Object?>>>(
        valueListenable: _store.savedPlants,
        builder: (context, savedPlants, _) {
          if (savedPlants.isEmpty) {
            return const AppCard(
              child: Column(
                children: [
                  Icon(Icons.bookmark_border, color: AppColors.green, size: 38),
                  SizedBox(height: 10),
                  Text(
                    'No saved plant details yet',
                    style: TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Open a plant in the Library and choose '
                    '“Save plant details”. Saved details stay separate '
                    'from My Garden.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              for (final plant in _store.plants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.background,
                          child: Icon(
                            Icons.local_florist,
                            color: AppColors.green,
                          ),
                        ),
                        title: Text(
                          plant.commonName,
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          plant.scientificName.isEmpty
                              ? 'Plant information'
                              : plant.scientificName,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove saved details',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.muted,
                          ),
                          onPressed: () => _remove(plant.commonName),
                        ),
                        onTap: () => Navigator.pushNamed(
                          context,
                          '/saved-plant-details',
                          arguments: plant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Widget _plantDetails(PlantRecord plant) {
    final description =
        plant.description ?? plant.enrichedFields['description'];
    const freeCareFields = {
      'dailyCare',
      'careInstructions',
      'wateringFrequency',
      'wateringAmount',
      'sunlightRequirements',
    };
    final care = plant.enrichedFields.entries
        .where((entry) => freeCareFields.contains(entry.key))
        .toList();
    final advancedDetails = plant.enrichedFields.entries
        .where(
          (entry) =>
              !freeCareFields.contains(entry.key) &&
              entry.key != 'description' &&
              entry.key != 'family' &&
              entry.key != 'genus' &&
              entry.key != 'species' &&
              entry.key != 'tagalogName' &&
              entry.key != 'bisayaName',
        )
        .toList();
    final information = <MapEntry<String, String>>[
      MapEntry('Common name', plant.commonName),
      if (plant.scientificName.isNotEmpty)
        MapEntry('Scientific name', plant.scientificName),
      if (plant.family != 'Not listed') MapEntry('Family', plant.family),
      if (plant.genus != null) MapEntry('Genus', plant.genus!),
      if (plant.species != null) MapEntry('Species', plant.species!),
      if (plant.tagalogName != null)
        MapEntry('Tagalog name', plant.tagalogName!),
      if (plant.bisayaName != null)
        MapEntry('Cebuano/Bisaya name', plant.bisayaName!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IDENTIFICATION',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              PlantPhoto(
                asset: plant.image,
                imageUrl: plant.imageUrl,
                height: 170,
              ),
              const SizedBox(height: 12),
              Text(
                plant.commonName,
                style: const TextStyle(
                  color: AppColors.dark,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 23,
                ),
              ),
              if (plant.scientificName.isNotEmpty)
                Text(
                  plant.scientificName,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 10),
              for (final entry in information) _SavedDetailRow(entry: entry),
            ],
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About this plant',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Basic care',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (care.isNotEmpty)
                for (final entry in care)
                  _SavedDetailRow(
                    entry: MapEntry(_fieldLabel(entry.key), entry.value),
                  )
              else if (plant.water.isNotEmpty)
                Text(
                  plant.water,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                )
              else
                const Text(
                  'No basic care details were saved for this plant.',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
            ],
          ),
        ),
        if (advancedDetails.isNotEmpty ||
            plant.kingdom != null ||
            plant.phylum != null ||
            plant.taxonomicClass != null ||
            plant.order != null) ...[
          const SizedBox(height: 12),
          PremiumFeatureGate(
            feature: 'Advanced plant information',
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Advanced plant information',
                    style: TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (plant.kingdom case final value?)
                    _SavedDetailRow(entry: MapEntry('Kingdom', value)),
                  if (plant.phylum case final value?)
                    _SavedDetailRow(entry: MapEntry('Phylum', value)),
                  if (plant.taxonomicClass case final value?)
                    _SavedDetailRow(entry: MapEntry('Class', value)),
                  if (plant.order case final value?)
                    _SavedDetailRow(entry: MapEntry('Order', value)),
                  if (plant.formerScientificName case final value?)
                    _SavedDetailRow(entry: MapEntry('Former name', value)),
                  for (final entry in advancedDetails)
                    _SavedDetailRow(
                      entry: MapEntry(_fieldLabel(entry.key), entry.value),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _remove(plant.commonName),
          icon: const Icon(Icons.bookmark_remove_outlined),
          label: const Text('Remove from saved plant details'),
        ),
      ],
    );
  }

  String _fieldLabel(String key) => switch (key) {
    'dailyCare' => 'Daily care',
    'careInstructions' => 'Care instructions',
    'wateringFrequency' => 'Watering frequency',
    'wateringAmount' => 'Watering method',
    'wateringDrySeason' => 'Dry-season watering',
    'wateringRainySeason' => 'Rainy-season watering',
    'sunlightRequirements' => 'Sunlight',
    'fertilizer' => 'Fertilizer',
    'pruning' => 'Pruning',
    _ => key,
  };

  Future<void> _remove(String commonName) async {
    try {
      await _store.remove(commonName);
      if (mounted && widget.plant != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed saved plant details.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove saved details: $error')),
        );
      }
    }
  }
}

class _SavedDetailRow extends StatelessWidget {
  const _SavedDetailRow({required this.entry});

  final MapEntry<String, String> entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            entry.key,
            style: const TextStyle(color: AppColors.dark, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            entry.value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.dark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
