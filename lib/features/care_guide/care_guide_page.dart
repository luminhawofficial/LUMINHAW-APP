import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/services/plant_care_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class CareGuidePage extends StatefulWidget {
  const CareGuidePage({super.key, this.plant});

  final PlantRecord? plant;

  @override
  State<CareGuidePage> createState() => _CareGuidePageState();
}

class _CareGuidePageState extends State<CareGuidePage> {
  PlantCareGuide? _guide;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isPremium = false;
  bool _entitlementLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCareGuide();
  }

  @override
  void didUpdateWidget(covariant CareGuidePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plant?.scientificName != widget.plant?.scientificName) {
      _loadCareGuide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    return ScreenBody(
      title: 'Care guide',
      subtitle: 'Available species-specific care information.',
      back: true,
      child: plant == null
          ? AppCard(
              child: Column(
                children: [
                  const Text(
                    'Select a plant to view its care guide.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/library'),
                    child: const Text('Open plant library'),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          plant.commonName,
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          plant.scientificName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: AppColors.green,
                            ),
                          ),
                        )
                      else if (_errorMessage != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SetupNotice(message: _errorMessage!),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _loadCareGuide,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                            ),
                          ],
                        )
                      else if (_entitlementLoaded && !_isPremium)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SetupNotice(
                              message: 'Detailed species-specific care guides are a Premium feature.',
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/premium'),
                              child: const Text('View Premium'),
                            ),
                          ],
                        )
                      else if (_guide != null) ...[
                        for (final entry in _guide!.care.entries)
                          _CareInfo(
                            icon: _iconFor(entry.key),
                            label: _labelFor(entry.key),
                            value: entry.value,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Source: ${_guide!.source} · ${_guide!.sourceUrl}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const SetupNotice(
                  message: 'Provider information is general guidance, not a guarantee. Adjust care for the plant, pot, season, and local conditions.',
                ),
                const SizedBox(height: 14),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Log a care activity',
                        style: TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final activity in [
                            'Watered',
                            'Fertilized',
                            'Pruned',
                            'Repotted',
                          ])
                            OutlinedButton(
                              onPressed: () =>
                                  _logActivity(context, plant, activity),
                              child: Text(activity),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _loadCareGuide() async {
    final plant = widget.plant;
    if (plant == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _guide = null;
    });
    try {
      await PlanEntitlementStore.instance.refreshFromServer();
      if (!mounted || widget.plant?.scientificName != plant.scientificName) {
        return;
      }
      final isPremium =
          PlanEntitlementStore.instance.tier.value == PlanTier.premium;
      setState(() {
        _isPremium = isPremium;
        _entitlementLoaded = true;
      });
      if (!isPremium) return;

      final guide = await PlantCareService.load(
        scientificName: plant.scientificName,
      );
      if (mounted && widget.plant?.scientificName == plant.scientificName) {
        setState(() => _guide = guide);
      }
    } catch (error) {
      if (mounted && widget.plant?.scientificName == plant.scientificName) {
        setState(
          () =>
              _errorMessage = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logActivity(
    BuildContext context,
    PlantRecord plant,
    String activity,
  ) async {
    try {
      await LocalPlantDataStore.instance.recordCareActivity(
        plantName: plant.commonName,
        activity: activity,
      );
      if (context.mounted) {
        final destination = LocalPlantDataStore.instance.isCloudSynced
            ? 'synced to your account'
            : 'saved on this device';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$activity $destination.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save care activity: $error')),
        );
      }
    }
  }

  static String _labelFor(String key) => switch (key) {
    'watering' => 'Watering',
    'wateringBenchmark' => 'Watering interval',
    'sunlight' => 'Sunlight',
    'soil' => 'Soil',
    'hardinessZone' => 'Hardiness zone',
    'maintenance' => 'Maintenance',
    'pestSusceptibility' => 'Pest susceptibility',
    _ => key,
  };

  static IconData _iconFor(String key) => switch (key) {
    'watering' || 'wateringBenchmark' => Icons.water_drop_outlined,
    'sunlight' => Icons.wb_sunny_outlined,
    'soil' => Icons.grass_outlined,
    'hardinessZone' => Icons.thermostat_outlined,
    'maintenance' => Icons.spa_outlined,
    'pestSusceptibility' => Icons.pest_control_outlined,
    _ => Icons.info_outline,
  };
}

class _CareInfo extends StatelessWidget {
  const _CareInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
