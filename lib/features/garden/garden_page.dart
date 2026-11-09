import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class GardenPage extends StatefulWidget {
  const GardenPage({super.key});

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage> {
  final _store = LocalPlantDataStore.instance;
  late Future<void> _loading = _store.load();

  void _retryLoad() {
    setState(() {
      _store.retryLoad();
      _loading = _store.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(),
        Expanded(
          child: FutureBuilder<void>(
            future: _loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _GardenLoadError(
                  error: snapshot.error!,
                  onRetry: _retryLoad,
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Text(
                    'Loading your garden…',
                    style: TextStyle(color: AppColors.muted),
                  ),
                );
              }
              return ValueListenableBuilder<Object?>(
                valueListenable: _store.loadError,
                builder: (context, error, _) {
                  if (error != null) {
                    return _GardenLoadError(error: error, onRetry: _retryLoad);
                  }
                  return ValueListenableBuilder<List<String>>(
                    valueListenable: _store.gardenPlantNames,
                    builder: (context, plantNames, _) =>
                        ValueListenableBuilder<
                          Map<String, Map<String, Object?>>
                        >(
                          valueListenable: _store.gardenPlantDetails,
                          builder: (context, plantDetails, _) =>
                              _GardenContents(
                                plantNames: plantNames,
                                plantDetails: plantDetails,
                                isCloudSynced: _store.isCloudSynced,
                              ),
                        ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GardenContents extends StatelessWidget {
  const _GardenContents({
    required this.plantNames,
    required this.plantDetails,
    required this.isCloudSynced,
  });

  final List<String> plantNames;
  final Map<String, Map<String, Object?>> plantDetails;
  final bool isCloudSynced;

  @override
  Widget build(BuildContext context) {
    final plants = plantNames
        .map((name) => PlantRecord.fromStoredDetails(name, plantDetails[name]))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'My Garden',
          style: TextStyle(
            color: AppColors.green,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.w700,
            fontSize: 26,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Keep your plants happy, one small habit at a time.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Track plant growth',
          icon: Icons.show_chart,
          onPressed: () => Navigator.pushNamed(context, '/growth'),
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Add a plant',
          icon: Icons.add,
          onPressed: () => Navigator.pushNamed(context, '/add-plant'),
        ),
        const SizedBox(height: 14),
        if (plants.isEmpty)
          const AppCard(
            child: Column(
              children: [
                Icon(Icons.yard_outlined, color: AppColors.green, size: 36),
                SizedBox(height: 8),
                Text(
                  'Your garden is ready to grow.',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Add a plant you want to monitor to see it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          )
        else
          for (final plant in plants)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () =>
                    Navigator.pushNamed(context, '/growth', arguments: plant),
                child: AppCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: PlantPhoto(
                          asset: plant.image,
                          imageUrl: plant.imageUrl,
                          height: 88,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plant.commonName,
                              style: const TextStyle(
                                color: AppColors.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            if (plant.growthStage != null)
                              Text(
                                plant.growthStage!,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                            if (plant.plantingDate != null)
                              Text(
                                'Planted ${plant.plantingDate}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            Text(
                              isCloudSynced
                                  ? 'Synced to your account'
                                  : 'Saved on this device',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Growth tracker',
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/growth',
                          arguments: plant,
                        ),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: AppColors.green,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove from garden',
                        onPressed: () =>
                            _confirmRemove(context, plant.commonName),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: 8),
        const Text(
          'Checklist',
          style: TextStyle(
            color: AppColors.green,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const AppCard(
          child: Column(
            children: [
              _ChecklistRow(label: 'Check soil moisture'),
              Divider(height: 18),
              _ChecklistRow(label: 'Rotate plants toward the light'),
              Divider(height: 18),
              _ChecklistRow(label: 'Review your watering schedule'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SetupNotice(
          message: isCloudSynced
              ? 'Your garden is synced to your verified account.'
              : 'Your garden is saved on this device while signed out. Sign in with a verified email to sync garden records.',
        ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, String plantName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this plant?'),
        content: Text('$plantName will be removed from your garden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await LocalPlantDataStore.instance.removePlant(plantName);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove plant: $error')),
        );
      }
    }
  }
}

class _GardenLoadError extends StatelessWidget {
  const _GardenLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load your garden: $error'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          color: AppColors.green,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
