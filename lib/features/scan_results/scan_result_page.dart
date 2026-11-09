import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/plant_identification_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key, this.plant, this.scanResult});

  final PlantRecord? plant;
  final PlantIdentificationResult? scanResult;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  String _section = 'Identification';

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant ?? widget.scanResult?.toPlantRecord();
    return ScreenBody(
      title: 'Scanned result',
      subtitle: 'Plant identification',
      back: true,
      child: Column(
        children: [
          _SectionSelector(
            selected: _section,
            onChanged: (value) => setState(() => _section = value),
          ),
          const SizedBox(height: 18),
          if (_section == 'Identification')
            _identificationContent(plant, widget.scanResult)
          else
            PremiumFeatureGate(
              feature: _section,
              child: _premiumContent(plant),
            ),
        ],
      ),
    );
  }

  Widget _identificationContent(
    PlantRecord? plant,
    PlantIdentificationResult? scanResult,
  ) {
    if (plant == null) {
      return AppCard(
        child: Column(
          children: [
            const Icon(
              Icons.center_focus_weak,
              color: AppColors.green,
              size: 44,
            ),
            const SizedBox(height: 10),
            const Text(
              'No scan result yet',
              style: TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Identify a plant to see the service results here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/scan'),
              child: const Text('Open plant scanner'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              if (scanResult == null)
                PlantPhoto(asset: plant.image, height: 220)
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    scanResult.imageBytes,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 14),
              Text(
                plant.commonName,
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _ResultField(
                label: 'English name',
                value: plant.commonName,
                status: _fieldStatus(scanResult, 'commonName', hasValue: true),
                source: scanResult?.informationSources['commonName'],
              ),
              if (scanResult != null) ...[
                _ResultField(
                  label: 'Tagalog name',
                  value: scanResult.tagalogName ?? 'Unavailable',
                  status: _fieldStatus(
                    scanResult,
                    'tagalogName',
                    hasValue: scanResult.tagalogName != null,
                  ),
                  source: scanResult.informationSources['tagalogName'],
                  generatedAt: scanResult.fieldGeneratedAt['tagalogName'],
                ),
                _ResultField(
                  label: 'Cebuano/Bisaya name',
                  value: scanResult.bisayaName ?? 'Unavailable',
                  status: _fieldStatus(
                    scanResult,
                    'bisayaName',
                    hasValue: scanResult.bisayaName != null,
                  ),
                  source: scanResult.informationSources['bisayaName'],
                  generatedAt: scanResult.fieldGeneratedAt['bisayaName'],
                ),
              ],
              _ResultField(
                label: 'Scientific name',
                value: plant.scientificName,
                status: _fieldStatus(
                  scanResult,
                  'scientificName',
                  hasValue: plant.scientificName.isNotEmpty,
                ),
                source: scanResult?.informationSources['scientificName'],
              ),
              _ResultField(
                label: 'Family',
                value: plant.family,
                status: _fieldStatus(
                  scanResult,
                  'family',
                  hasValue: plant.family != 'Not listed',
                ),
                source: scanResult?.informationSources['family'],
              ),
              if (scanResult?.probability case final probability?)
                _ResultField(
                  label: 'Match confidence',
                  value: '${(probability * 100).toStringAsFixed(1)}%',
                ),
              const SizedBox(height: 8),
              Text(
                scanResult == null
                    ? 'Identification results are estimates. Check important plant decisions with a reliable botanical source.'
                    : 'Plant.ID identification estimate. Confirm important plant decisions with a reliable botanical source.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (scanResult?.description case final description?) ...[
                const SizedBox(height: 12),
                const Text(
                  'Description',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
              ],
              if (scanResult != null) ...[
                const SizedBox(height: 14),
                _plantDetails(scanResult),
                if (scanResult.enrichmentError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Some details could not be loaded: ${scanResult.enrichmentError}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'AI-generated recommendations are estimates. Check plant conditions before applying care advice.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _plantDetails(PlantIdentificationResult result) {
    const groups = [
      'Plant Information',
      'Compatible Weather',
      'Suitable Soil',
      'Plant Origin',
      'Growth Information',
      'Plant Care',
    ];
    final visibleFields = result.botanicalInformation.entries.where((entry) {
      return !const {
        'commonName',
        'scientificName',
        'tagalogName',
        'bisayaName',
        'family',
        'description',
      }.contains(entry.key);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups)
          _informationGroup(
            group,
            visibleFields,
            result.unavailableFields,
            result,
          ),
        if (result.botanicalInformation.isEmpty &&
            result.unavailableFields.isEmpty &&
            result.enrichmentError == null)
          const Text(
            'Plant growing information is not available yet.',
            style: TextStyle(color: AppColors.muted),
          ),
      ],
    );
  }

  Widget _informationGroup(
    String group,
    List<MapEntry<String, String>> entries,
    Set<String> unavailableFields,
    PlantIdentificationResult result,
  ) {
    final groupEntries = entries
        .where((entry) => _informationGroupFor(entry.key) == group)
        .toList();
    final missingFields = unavailableFields
        .where((field) => _informationGroupFor(field) == group)
        .where((field) => !result.botanicalInformation.containsKey(field))
        .toList();
    if (groupEntries.isEmpty && missingFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final section = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group,
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in groupEntries)
            _DetailEntry(
              entry: entry,
              label: _informationLabel(entry.key),
              result: result,
            ),
          for (final field in missingFields)
            _DetailEntry(
              entry: MapEntry(field, 'Unavailable'),
              label: _informationLabel(field),
              result: result,
              statusOverride: 'Unavailable',
            ),
        ],
      ),
    );
    if (group == 'Plant Care') {
      return PremiumFeatureGate(feature: group, child: section);
    }
    return section;
  }

  String _informationGroupFor(String field) {
    if (const {
      'genus',
      'species',
      'kingdom',
      'phylum',
      'taxonomicClass',
      'order',
    }.contains(field)) {
      return 'Plant Information';
    }
    if (const {
      'weatherClimate',
      'temperatureRange',
      'humidity',
      'climateTypes',
      'rainfallTolerance',
      'heatTolerance',
      'coldSensitivity',
      'seasonalCare',
    }.contains(field)) {
      return 'Compatible Weather';
    }
    if (const {
      'soilCompatibility',
      'soilPH',
      'soilDrainage',
      'soilMoisture',
      'soilMix',
      'compost',
    }.contains(field)) {
      return 'Suitable Soil';
    }
    if (field == 'originHabitat') return 'Plant Origin';
    if (const {
      'growthCharacteristics',
      'growthStages',
      'lifespan',
      'repotting',
      'growingConditions',
      'classification',
      'suitability',
    }.contains(field)) {
      return 'Growth Information';
    }
    return 'Plant Care';
  }

  Widget _premiumContent(PlantRecord? plant) {
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plant == null
                    ? 'Plant context unavailable'
                    : '$_section for ${plant.commonName}',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Plant-specific premium information is not available until a verified botanical data source is connected.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
        if (_section == 'Biology') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _section = 'Nutrients'),
            icon: const Icon(Icons.grass_outlined),
            label: const Text('Explore nutrients'),
          ),
          OutlinedButton.icon(
            onPressed: plant == null
                ? null
                : () => Navigator.pushNamed(context, '/care', arguments: plant),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Open care guide'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, '/health', arguments: plant),
            icon: const Icon(Icons.health_and_safety_outlined),
            label: const Text('Plant health checker'),
          ),
        ],
      ],
    );
  }

  String _informationLabel(String field) => switch (field) {
    'commonName' => 'English name',
    'scientificName' => 'Scientific name',
    'family' => 'Family',
    'genus' => 'Genus',
    'species' => 'Species',
    'kingdom' => 'Kingdom',
    'phylum' => 'Phylum',
    'taxonomicClass' => 'Class',
    'order' => 'Order',
    'tagalogName' => 'Tagalog name',
    'bisayaName' => 'Cebuano/Bisaya name',
    'description' => 'Description',
    'characteristics' => 'Characteristics',
    'usesBenefits' => 'Uses and benefits',
    'originHabitat' => 'Native origin and habitat',
    'classification' => 'Plant classification',
    'suitability' => 'Indoor/outdoor suitability',
    'lifespan' => 'Expected lifespan',
    'dailyCare' => 'Daily care',
    'weatherClimate' => 'Weather and climate',
    'climateTypes' => 'Suitable climate',
    'rainfallTolerance' => 'Rainfall tolerance',
    'heatTolerance' => 'Heat tolerance',
    'coldSensitivity' => 'Cold sensitivity',
    'seasonalCare' => 'Seasonal care',
    'soilCompatibility' => 'Soil requirements',
    'soilPH' => 'Soil pH',
    'soilDrainage' => 'Soil drainage',
    'soilMoisture' => 'Soil moisture',
    'soilMix' => 'Soil mix',
    'compost' => 'Compost',
    'wateringFrequency' => 'Watering frequency',
    'wateringAmount' => 'Watering amount',
    'wateringDrySeason' => 'Dry-season watering',
    'wateringRainySeason' => 'Rainy-season watering',
    'soilMoistureCheck' => 'Checking soil moisture',
    'overwateringSigns' => 'Overwatering signs',
    'underwateringSigns' => 'Underwatering signs',
    'growthStageWatering' => 'Watering by growth stage',
    'sunlightRequirements' => 'Sunlight',
    'sunlightHours' => 'Daily sunlight',
    'lowLightSigns' => 'Insufficient-light signs',
    'excessiveLightSigns' => 'Excessive-light signs',
    'temperatureRange' => 'Temperature',
    'humidity' => 'Humidity',
    'fertilizer' => 'Fertilizer and nutrients',
    'fertilizingFrequency' => 'Fertilizing frequency',
    'nutrientDeficiencies' => 'Nutrient deficiency signs',
    'fertilizerApplication' => 'Fertilizer application',
    'growthCharacteristics' => 'Growth characteristics',
    'growthStages' => 'Growth stages',
    'propagation' => 'Propagation',
    'repotting' => 'Repotting',
    'growingConditions' => 'Growing conditions',
    'careInstructions' => 'Care instructions',
    _ => field,
  };
}

String _fieldStatus(
  PlantIdentificationResult? result,
  String field, {
  required bool hasValue,
}) {
  if (!hasValue) return 'Unavailable';
  final status = result?.informationStatuses[field];
  if (status != null) return status;
  if (result?.aiGeneratedFields.contains(field) ?? false) {
    return 'AI-Generated';
  }
  final source = result?.informationSources[field] ?? '';
  if (RegExp(
    r'\b(gbif|perenual|kew|plants of the world online)\b',
    caseSensitive: false,
  ).hasMatch(source)) {
    return 'API Verified';
  }
  return 'Needs Verification';
}

class _SectionSelector extends StatelessWidget {
  const _SectionSelector({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  static const _sections = ['Identification', 'Biology', 'Nutrients'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.green.withAlpha(77), width: 1.5),
      ),
      child: Row(
        children: [
          for (final section in _sections)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(section),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: section == selected ? AppColors.green : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    section == 'Identification' ? 'Identify' : section,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: section == selected
                          ? Colors.white
                          : AppColors.dark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultField extends StatelessWidget {
  const _ResultField({
    required this.label,
    required this.value,
    this.status,
    this.source,
    this.generatedAt,
  });

  final String label;
  final String value;
  final String? status;
  final String? source;
  final String? generatedAt;

  @override
  Widget build(BuildContext context) {
    final valueRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    if (status == null) return valueRow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          valueRow,
          const SizedBox(height: 2),
          Text(
            _statusLabel(status!, source, generatedAt),
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailEntry extends StatelessWidget {
  const _DetailEntry({
    required this.entry,
    required this.label,
    required this.result,
    this.statusOverride,
  });

  final MapEntry<String, String> entry;
  final String label;
  final PlantIdentificationResult result;
  final String? statusOverride;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          entry.value,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        Text(
          _statusLabel(
            statusOverride ??
                _fieldStatus(
                  result,
                  entry.key,
                  hasValue: entry.value != 'Unavailable',
                ),
            result.informationSources[entry.key],
            result.fieldGeneratedAt[entry.key],
          ),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            height: 1.3,
          ),
        ),
      ],
    ),
  );
}

String _statusLabel(String status, String? source, String? generatedAt) {
  final parts = <String>[status];
  if (source != null && source.isNotEmpty) {
    parts.add(
      source.toLowerCase() == 'gemini ai' || source.toLowerCase() == 'gemini'
          ? 'LUMIN AI (Gemini)'
          : source,
    );
  }
  if (status == 'AI-Generated' && generatedAt != null) {
    final timestamp = DateTime.tryParse(generatedAt)?.toLocal();
    if (timestamp != null) {
      parts.add(
        'Generated ${timestamp.year.toString().padLeft(4, '0')}-'
        '${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')}',
      );
    }
  }
  return parts.join(' · ');
}
