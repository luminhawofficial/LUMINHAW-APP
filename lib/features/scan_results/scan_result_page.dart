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
          else if (_section == 'Biology')
            PremiumFeatureGate(
              feature: 'Advanced plant biology',
              child: _biologyContent(plant, widget.scanResult),
            )
          else
            PremiumFeatureGate(
              feature: 'Detailed nutrient information',
              child: _nutrientContent(plant, widget.scanResult),
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
              if (scanResult?.hasLowConfidence == true) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFF8A5A00),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Low provider match score. This identification may be '
                          'inaccurate. Try a clearer photo showing the leaves, '
                          'flowers, or fruit, or verify the result with another '
                          'reliable source.',
                          style: TextStyle(
                            color: Color(0xFF704800),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                  label: 'Provider match score',
                  value: '${(probability * 100).toStringAsFixed(1)}%',
                ),
              if (scanResult?.probability != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Provider-reported score; not a measured accuracy rate.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                scanResult == null
                    ? 'Identification results are estimates. Check important plant decisions with a reliable botanical source.'
                    : 'Automated plant identification is an estimate. Confirm important plant decisions with a reliable botanical source.',
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
                const SizedBox(height: 6),
                const Text(
                  'Provider-sourced information is not necessarily expert-reviewed. '
                  'Use trusted botanical references for school work.',
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

  Widget _biologyContent(
    PlantRecord? plant,
    PlantIdentificationResult? scanResult,
  ) {
    if (plant == null) return _noPlantContext();
    final fields = _profileFields(plant, scanResult);
    const biologyGroups = <String, List<String>>{
      'Classification': [
        'kingdom',
        'phylum',
        'taxonomicClass',
        'order',
        'family',
        'genus',
        'species',
      ],
      'Description and characteristics': [
        'description',
        'characteristics',
        'classification',
        'usesBenefits',
      ],
      'Origin and habitat': [
        'originHabitat',
        'weatherClimate',
        'climateTypes',
        'suitability',
      ],
      'Life cycle and growth': [
        'lifespan',
        'growthCharacteristics',
        'growthStages',
        'propagation',
      ],
    };
    final hasBiologyDetails = biologyGroups.values
        .expand((groupFields) => groupFields)
        .any(fields.containsKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plant biology: ${plant.commonName}',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (plant.scientificName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  plant.scientificName,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Explore how plants function, then review the species-specific '
                'facts available for this identification. Identification and '
                'generated details can be wrong, so verify them with your '
                'course materials or a trusted botanical reference.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How plants function',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const _BiologyLesson(
                title: 'Photosynthesis',
                body:
                    'In photosynthetic plants, chloroplasts capture light energy '
                    'to make sugars from water and carbon dioxide. Oxygen is '
                    'released as part of this process.',
              ),
              const _BiologyLesson(
                title: 'Plant structures',
                body:
                    'Roots commonly anchor a plant and absorb water and minerals. '
                    'Stems support the plant and move materials. Leaves are '
                    'important sites of photosynthesis and gas exchange.',
              ),
              const _BiologyLesson(
                title: 'Growth and reproduction',
                body:
                    'Plants grow through cell division and expansion. Their '
                    'reproductive structures differ: flowering plants form '
                    'flowers and seeds, while other plant groups may reproduce '
                    'using cones or spores.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final group in biologyGroups.entries)
          if (group.value.any(fields.containsKey)) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.key,
                    style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final field in group.value)
                    if (fields[field] case final value?)
                      _profileFact(field, value, plant, scanResult),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        if (!hasBiologyDetails)
          AppCard(
            child: Text(
              scanResult?.enrichmentError == null
                  ? 'Species-specific biology details are not available for this result yet. '
                        'The general lessons above are not specific to this plant.'
                  : 'Species-specific biology details could not be loaded. '
                        'The general lessons above are not specific to this plant.',
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ),
      ],
    );
  }

  Widget _nutrientContent(
    PlantRecord? plant,
    PlantIdentificationResult? scanResult,
  ) {
    if (plant == null) return _noPlantContext();
    final fields = _profileFields(plant, scanResult);
    const nutrientFields = [
      'compost',
      'fertilizer',
      'fertilizingFrequency',
      'nutrientDeficiencies',
      'fertilizerApplication',
    ];
    final hasNutrientDetails = nutrientFields.any(fields.containsKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plant nutrients: ${plant.commonName}',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Plants need mineral nutrients to grow. Nitrogen supports '
                'proteins and chlorophyll; phosphorus is part of energy transfer '
                'and genetic material; potassium supports many cell processes. '
                'Plants also need smaller amounts of other essential elements.',
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
              const SizedBox(height: 10),
              const Text(
                'Yellowing, spots, or slow growth do not prove a nutrient '
                'deficiency. Similar symptoms can come from watering, light, '
                'pests, disease, or soil conditions. Do not add fertilizer '
                'based on symptoms alone; check the plant and soil, and follow '
                'a reliable species-specific reference or soil test.',
                style: TextStyle(
                  color: AppColors.dark,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasNutrientDetails)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available information for this plant',
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (final field in nutrientFields)
                  if (fields[field] case final value?)
                    _profileFact(field, value, plant, scanResult),
              ],
            ),
          )
        else
          AppCard(
            child: Text(
              scanResult?.enrichmentError == null
                  ? 'No species-specific nutrient or fertilizer information is available for this result.'
                  : 'Species-specific nutrient information could not be loaded.',
              style: const TextStyle(color: AppColors.muted, height: 1.45),
            ),
          ),
      ],
    );
  }

  Widget _profileFact(
    String field,
    String value,
    PlantRecord plant,
    PlantIdentificationResult? scanResult,
  ) {
    final source =
        scanResult?.informationSources[field] ??
        plant.enrichmentSources[field] ??
        plant.source;
    final status =
        scanResult?.informationStatuses[field] ??
        (plant.aiGeneratedFields.contains(field)
            ? 'AI-Generated'
            : _fieldStatusForSource(source));
    return _ProfileFact(
      label: _informationLabel(field),
      value: value,
      status: status,
      source: source,
      generatedAt: scanResult?.fieldGeneratedAt[field],
    );
  }

  Map<String, String> _profileFields(
    PlantRecord plant,
    PlantIdentificationResult? scanResult,
  ) {
    final fields = <String, String>{
      ...plant.enrichedFields,
      ...?scanResult?.botanicalInformation,
    };

    void add(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        fields.putIfAbsent(key, () => value.trim());
      }
    }

    add('commonName', plant.commonName);
    add('scientificName', plant.scientificName);
    add('family', plant.family == 'Not listed' ? null : plant.family);
    add('kingdom', plant.kingdom);
    add('phylum', plant.phylum);
    add('taxonomicClass', plant.taxonomicClass);
    add('order', plant.order);
    add('genus', plant.genus);
    add('species', plant.species);
    add('description', plant.description);
    return fields;
  }

  Widget _noPlantContext() => const AppCard(
    child: Text(
      'Identify or select a plant first to view its biology and nutrient information.',
      style: TextStyle(color: AppColors.muted, height: 1.45),
    ),
  );

  String _fieldStatusForSource(String? source) {
    if (source == null || source.isEmpty) return 'Needs Verification';
    if (RegExp(
      r'\b(gbif|perenual|trefle|kew|plants of the world online)\b',
      caseSensitive: false,
    ).hasMatch(source)) {
      return 'API Verified';
    }
    return 'Needs Verification';
  }

  Widget _plantDetails(PlantIdentificationResult result) {
    const groups = ['Plant Information', 'Basic plant care'];
    const freeFields = {
      'genus',
      'species',
      'dailyCare',
      'careInstructions',
      'wateringFrequency',
      'wateringAmount',
      'sunlightRequirements',
    };
    final visibleFields = result.botanicalInformation.entries.where((entry) {
      return freeFields.contains(entry.key);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups)
          _informationGroup(
            group,
            visibleFields,
            result.unavailableFields.intersection(freeFields),
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
    return section;
  }

  String _informationGroupFor(String field) {
    if (const {'genus', 'species'}.contains(field)) {
      return 'Plant Information';
    }
    return 'Basic plant care';
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
    r'\b(gbif|perenual|trefle|kew|plants of the world online)\b',
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

class _BiologyLesson extends StatelessWidget {
  const _BiologyLesson({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(color: AppColors.muted, height: 1.4)),
      ],
    ),
  );
}

class _ProfileFact extends StatelessWidget {
  const _ProfileFact({
    required this.label,
    required this.value,
    required this.status,
    this.source,
    this.generatedAt,
  });

  final String label;
  final String value;
  final String status;
  final String? source;
  final String? generatedAt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
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
          value,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 2),
        Text(
          _statusLabel(status, source, generatedAt),
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
        if (entry.key == 'nutrientDeficiencies')
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Leaf symptoms can have several causes. Do not diagnose a deficiency '
              'or apply fertilizer from symptoms alone; check growing conditions '
              'and consult a reliable source or soil test.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
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
  final displayedStatus = status == 'API Verified'
      ? 'Provider-sourced'
      : status;
  final parts = <String>[displayedStatus];
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
