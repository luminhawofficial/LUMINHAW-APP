import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/plant_catalog_service.dart';
import 'package:luminhaw/core/services/plant_enrichment_service.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.searchCatalog});

  final Future<List<PlantRecord>> Function(String query)? searchCatalog;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  Timer? _searchDebounce;
  List<PlantRecord>? _catalogResults;
  String? _catalogError;
  bool _isSearchingCatalog = false;
  bool _isLoadingMore = false;
  bool _hasMoreResults = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _catalogResults = null;
        _catalogError = null;
        _isSearchingCatalog = false;
        _isLoadingMore = false;
        _hasMoreResults = false;
      });
      return;
    }

    setState(() {
      _catalogResults = null;
      _isSearchingCatalog = true;
      _catalogError = null;
      _isLoadingMore = false;
      _hasMoreResults = false;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final submittedQuery = query.trim();
      try {
        final page = widget.searchCatalog == null
            ? await PlantCatalogService.searchPage(submittedQuery)
            : null;
        final results =
            page?.results ?? await widget.searchCatalog!(submittedQuery);
        if (!mounted || _search.text.trim() != submittedQuery) return;
        setState(() {
          _catalogResults = results;
          _hasMoreResults = page?.hasMore ?? false;
          _isSearchingCatalog = false;
        });
      } catch (error) {
        if (!mounted || _search.text.trim() != submittedQuery) return;
        setState(() {
          _catalogResults = const [];
          _catalogError = error.toString();
          _isSearchingCatalog = false;
        });
      }
    });
  }

  Future<void> _loadMoreResults() async {
    final query = _search.text.trim();
    final current = _catalogResults;
    if (current == null ||
        !_hasMoreResults ||
        _isLoadingMore ||
        widget.searchCatalog != null) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final page = await PlantCatalogService.searchPage(
        query,
        offset: current.length,
      );
      if (!mounted || _search.text.trim() != query) return;
      final seen = current
          .map((plant) => plant.scientificName.toLowerCase().trim())
          .toSet();
      final nextResults = [
        ...current,
        ...page.results.where(
          (plant) => seen.add(plant.scientificName.toLowerCase().trim()),
        ),
      ];
      setState(() {
        _catalogResults = List.unmodifiable(nextResults);
        _hasMoreResults = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || _search.text.trim() != query) return;
      setState(() {
        _catalogError = error.toString();
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogPlants = _catalogResults;
    final filtered = catalogPlants ?? const <PlantRecord>[];

    return Column(
      children: [
        const AppHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Library',
                style: TextStyle(
                  color: AppColors.green,
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('plant-catalog-search'),
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search English, scientific, Tagalog, or Cebuano',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_catalogError != null)
                SetupNotice(
                  message:
                      'Plant catalog search failed: ${_displayCatalogError(_catalogError!)}',
                )
              else if (catalogPlants == null)
                const SetupNotice(
                  message:
                      'Search by English/common, scientific, Tagalog, or Cebuano name.',
                )
              else
                SetupNotice(
                  message: _isSearchingCatalog
                      ? 'Searching plant databases…'
                      : filtered.isEmpty
                      ? 'No online plant records matched this search.'
                      : 'Catalog source: ${filtered.first.source ?? 'provider'}.',
                ),
              const SizedBox(height: 12),
              if (_isSearchingCatalog)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_catalogError == null &&
                  filtered.isEmpty &&
                  catalogPlants != null)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No plants match your search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              else if (filtered.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.68,
                  ),
                  itemBuilder: (context, index) =>
                      _PlantGridCard(plant: filtered[index]),
                ),
              if (_hasMoreResults && widget.searchCatalog == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton(
                    onPressed: _isLoadingMore ? null : _loadMoreResults,
                    child: _isLoadingMore
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load more plants'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _displayCatalogError(String error) {
  if (error.startsWith('Bad state: ')) return error.substring(11);
  if (error.startsWith('FormatException: ')) return error.substring(17);
  return error;
}

class _PlantGridCard extends StatelessWidget {
  const _PlantGridCard({required this.plant});

  final PlantRecord plant;

  @override
  Widget build(BuildContext context) {
    final imageUrl = safePlantImageUrl(plant.imageUrl);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pushNamed(context, '/plant', arguments: plant),
      child: AppCard(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl == null
                    ? _plantImagePlaceholder()
                    : Image.network(
                        imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return _plantImagePlaceholder(isLoading: true);
                        },
                        errorBuilder: (_, _, _) => _plantImagePlaceholder(),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              plant.commonName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (plant.englishName != null)
              Text(
                'English: ${plant.englishName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            Text(
              'Category: ${plant.category}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
            if (plant.isVerified)
              const Text(
                'Verified by LUMINHAW',
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (plant.tagalogName != null)
              Text(
                'Tagalog: ${plant.tagalogName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            if (plant.bisayaName != null)
              Text(
                'Cebuano/Bisaya: ${plant.bisayaName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
            Text(
              plant.scientificName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (plant.description != null)
              Text(
                plant.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 9),
              ),
          ],
        ),
      ),
    );
  }

  Widget _plantImagePlaceholder({bool isLoading = false}) => Container(
    width: double.infinity,
    color: AppColors.background,
    alignment: Alignment.center,
    child: isLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: AppColors.green,
              strokeWidth: 2,
            ),
          )
        : const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.eco_outlined, color: AppColors.green, size: 40),
              SizedBox(height: 4),
              Text(
                'No photo available',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
  );
}

class PlantDetailPage extends StatefulWidget {
  const PlantDetailPage({
    super.key,
    required this.plant,
    this.enrichmentLoader,
  });

  final PlantRecord plant;
  final Future<PlantEnrichment> Function(PlantRecord plant)? enrichmentLoader;

  @override
  State<PlantDetailPage> createState() => _PlantDetailPageState();
}

class _PlantDetailPageState extends State<PlantDetailPage> {
  PlantEnrichment? _enrichment;
  Object? _enrichmentError;
  bool _isLoadingEnrichment = false;
  bool _isSavingDetails = false;
  Object? _savedDetailsError;

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
    if (widget.plant.enrichedFields.isNotEmpty) {
      _enrichment = PlantEnrichment(
        fields: widget.plant.enrichedFields,
        sources: widget.plant.enrichmentSources,
        aiGeneratedFields: widget.plant.aiGeneratedFields,
        unavailableFields: const {},
      );
    }
    if (widget.plant.scientificName.isNotEmpty &&
        (widget.plant.isVerified || widget.plant.enrichedFields.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadEnrichment();
      });
    }
  }

  Future<void> _loadSavedDetails() async {
    try {
      await SavedPlantDetailsStore.instance.load();
    } catch (error) {
      if (mounted) setState(() => _savedDetailsError = error);
    }
  }

  Future<void> _savePlantDetails() async {
    setState(() => _isSavingDetails = true);
    try {
      await SavedPlantDetailsStore.instance.save(
        widget.plant,
        enrichedFields: _enrichment?.fields ?? const {},
        enrichmentSources: _enrichment?.sources ?? const {},
        aiGeneratedFields: _enrichment?.aiGeneratedFields ?? const {},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Settings · Plant details')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save plant details: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDetails = false);
    }
  }

  Future<void> _removeSavedDetails(String commonName) async {
    try {
      await SavedPlantDetailsStore.instance.remove(commonName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove saved details: $error')),
        );
      }
    }
  }

  Future<void> _loadEnrichment() async {
    setState(() {
      _isLoadingEnrichment = true;
      _enrichmentError = null;
    });
    try {
      final result =
          await (widget.enrichmentLoader ??
              (plant) => PlantEnrichmentService.load(
                plant: plant,
                sourceOverrides: plant.enrichmentSources,
              ))(widget.plant);
      if (!mounted) return;
      final verifiedKeys = widget.plant.enrichmentSources.keys.toSet();
      final verifiedFields = widget.plant.enrichedFields;
      final fields = <String, String>{...result.fields, ...verifiedFields};
      final sources = <String, String>{
        ...result.sources,
        ...widget.plant.enrichmentSources,
      };
      setState(() {
        _enrichment = PlantEnrichment(
          fields: Map.unmodifiable(fields),
          sources: Map.unmodifiable(sources),
          fieldStatuses: result.fieldStatuses,
          fieldGeneratedAt: result.fieldGeneratedAt,
          generatedAt: result.generatedAt,
          aiGeneratedFields: Set.unmodifiable(
            result.aiGeneratedFields.difference(verifiedKeys),
          ),
          unavailableFields: Set.unmodifiable(
            result.unavailableFields.difference(verifiedKeys),
          ),
          error: result.error,
        );
        _enrichmentError = result.error;
        _isLoadingEnrichment = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enrichmentError = error;
        _isLoadingEnrichment = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final enrichedFields = _enrichment?.fields ?? const <String, String>{};
    final allInformationFields = _plantInformationFields(plant, enrichedFields);
    final informationFields = Map.fromEntries(
      allInformationFields.entries.where(
        (entry) => _isFreePlantInformationField(entry.key),
      ),
    );
    final advancedInformationFields = Map.fromEntries(
      allInformationFields.entries.where(
        (entry) => !_isFreePlantInformationField(entry.key),
      ),
    );
    final basicCareFields = enrichedFields.entries
        .where((entry) => _isBasicCareField(entry.key))
        .toList();
    final displayedInformationKeys = allInformationFields.keys.toSet();
    final additionalFields = [
      ...advancedInformationFields.entries,
      ...enrichedFields.entries.where(
        (entry) =>
            !_isBasicCareField(entry.key) &&
            !displayedInformationKeys.contains(entry.key) &&
            entry.key != 'description',
      ),
    ];
    final description = plant.description ?? enrichedFields['description'];
    final hasAdditionalBotanicalDetails =
        informationFields.keys.any((key) => key != 'scientificName') ||
        description != null ||
        plant.formerScientificName != null;
    final hasCatalogCare = !_isCatalogCarePlaceholder(plant.water);
    return ScreenBody(
      title: plant.commonName,
      subtitle: plant.scientificName,
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlantPhoto(asset: plant.image, imageUrl: plant.imageUrl, height: 220),
          if (plant.isVerified) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.verified, color: AppColors.green, size: 16),
                SizedBox(width: 5),
                Text(
                  'Verified by LUMINHAW',
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          ValueListenableBuilder<Map<String, Map<String, Object?>>>(
            valueListenable: SavedPlantDetailsStore.instance.savedPlants,
            builder: (context, savedPlants, _) {
              final isSaved = savedPlants.containsKey(plant.commonName);
              return OutlinedButton.icon(
                onPressed: _isSavingDetails
                    ? null
                    : isSaved
                    ? () => _removeSavedDetails(plant.commonName)
                    : _isLoadingEnrichment
                    ? null
                    : _savePlantDetails,
                icon: Icon(
                  isSaved ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  _isSavingDetails
                      ? 'Saving details…'
                      : isSaved
                      ? 'Saved in Settings'
                      : _isLoadingEnrichment
                      ? 'Loading plant details…'
                      : 'Save plant details',
                ),
              );
            },
          ),
          if (_savedDetailsError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SetupNotice(
                message:
                    'Saved plant details could not be loaded: '
                    '$_savedDetailsError',
              ),
            ),
          if (plant.imageUrl != null &&
              (plant.imageAttribution != null ||
                  plant.imageLicense != null ||
                  plant.imageReferenceUrl != null)) ...[
            const SizedBox(height: 8),
            if (plant.imageAttribution != null)
              SelectableText(
                'Photo credit: ${plant.imageAttribution} (cropped to fit)',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            if (plant.imageLicense != null)
              SelectableText(
                'License: ${plant.imageLicense}'
                '${plant.imageLicenseUrl == null ? '' : ' (${plant.imageLicenseUrl})'}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            if (plant.imageReferenceUrl != null)
              SelectableText(
                'Photo source: ${plant.imageReferenceUrl}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
          ],
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plant information',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                for (final entry in informationFields.entries)
                  _EnrichmentField(entry: entry, enrichment: _enrichment),
                if (plant.plantingDate != null) ...[
                  const SizedBox(height: 5),
                  Text('Planting date: ${plant.plantingDate}'),
                ],
                if (plant.growthStage != null) ...[
                  const SizedBox(height: 5),
                  Text('Growth stage: ${plant.growthStage}'),
                ],
                if (plant.formerScientificName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Former name: ${plant.formerScientificName}'),
                  ),
                if (!_isLoadingEnrichment && !hasAdditionalBotanicalDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _enrichmentError == null
                          ? 'No additional botanical details are available for this plant yet.'
                          : 'Some botanical details could not be loaded.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ),
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
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
                if (basicCareFields.isNotEmpty) ...[
                  for (final entry in basicCareFields)
                    _EnrichmentField(entry: entry, enrichment: _enrichment!),
                ] else if (hasCatalogCare)
                  Text(
                    plant.water,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  )
                else if (_isLoadingEnrichment)
                  const Text(
                    'Loading plant-specific care guidance…',
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  )
                else if (_enrichmentError != null)
                  const Text(
                    'Care guidance could not be loaded. See the details below to retry.',
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  )
                else
                  const Text(
                    'No reliable basic-care guidance is available yet.',
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  ),
              ],
            ),
          ),
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
                  const SizedBox(height: 8),
                  if (_isLoadingEnrichment)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_enrichmentError != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _enrichmentErrorMessage(_enrichmentError!),
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.4,
                          ),
                        ),
                        TextButton(
                          onPressed: _loadEnrichment,
                          child: const Text('Try again'),
                        ),
                      ],
                    )
                  else if (additionalFields.isEmpty &&
                      (_enrichment?.unavailableFields.isEmpty ?? true))
                    const Text(
                      'No additional plant information is available from the connected sources.',
                      style: TextStyle(color: AppColors.muted, height: 1.4),
                    )
                  else ...[
                    if (_enrichment!.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Some details could not be enriched: ${_enrichment!.error}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    for (final entry in additionalFields)
                      _EnrichmentField(entry: entry, enrichment: _enrichment!),
                    if (_enrichment!.unavailableFields.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No reliable details available for: '
                          '${_enrichment!.unavailableFields.map(_fieldLabel).join(', ')}.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    const Text(
                      'Care recommendations are general guidance. Adjust watering to soil moisture, pot size, drainage, temperature, humidity, and rainfall.',
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
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

Map<String, String> _plantInformationFields(
  PlantRecord plant,
  Map<String, String> enrichment,
) {
  final fields = <String, String>{
    'category': plant.category,
    if (plant.englishName != null) 'englishName': plant.englishName!,
    if (plant.scientificName.isNotEmpty) 'scientificName': plant.scientificName,
    if (plant.family != 'Not listed') 'family': plant.family,
    if (plant.order != null) 'order': plant.order!,
    if (plant.tagalogName != null) 'tagalogName': plant.tagalogName!,
    if (plant.bisayaName != null) 'bisayaName': plant.bisayaName!,
  };
  for (final key in [
    'genus',
    'species',
    'kingdom',
    'phylum',
    'taxonomicClass',
    'taxonomicRank',
  ]) {
    final value = _taxonomicValue(plant, key);
    if (value != null) fields[key] = value;
  }
  for (final key in [
    'family',
    'genus',
    'species',
    'tagalogName',
    'bisayaName',
    'characteristics',
    'originHabitat',
    'classification',
    'suitability',
    'lifespan',
    'usesBenefits',
  ]) {
    final value = enrichment[key];
    if (value != null && value.isNotEmpty) fields[key] ??= value;
  }
  return fields;
}

bool _isFreePlantInformationField(String key) => const {
  'scientificName',
  'category',
  'englishName',
  'family',
  'genus',
  'species',
  'tagalogName',
  'bisayaName',
}.contains(key);

bool _isBasicCareField(String key) => const {
  'dailyCare',
  'careInstructions',
  'wateringFrequency',
  'wateringAmount',
  'sunlightRequirements',
}.contains(key);

bool _isCatalogCarePlaceholder(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'care guidance is not provided by the catalog.' ||
      normalized == 'care guidance is not available yet.';
}

String _enrichmentErrorMessage(Object error) {
  if (error is StateError) return error.message.toString();
  return 'Plant details could not be loaded. Please try again.';
}

class _EnrichmentField extends StatelessWidget {
  const _EnrichmentField({required this.entry, this.enrichment});

  final MapEntry<String, String> entry;
  final PlantEnrichment? enrichment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _fieldLabel(entry.key),
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
        if (enrichment case final current?)
          if (current.sources[entry.key] case final source?)
            Text(
              current.aiGeneratedFields.contains(entry.key)
                  ? 'AI-generated estimate · $source'
                  : 'Source: $source',
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
      ],
    ),
  );
}

String? _taxonomicValue(PlantRecord plant, String key) => switch (key) {
  'genus' => plant.genus,
  'species' => plant.species,
  'kingdom' => plant.kingdom,
  'phylum' => plant.phylum,
  'taxonomicClass' => plant.taxonomicClass,
  'taxonomicRank' => plant.taxonomicRank,
  _ => null,
};

String _fieldLabel(String key) => switch (key) {
  'category' => 'Category',
  'englishName' => 'English name',
  'scientificName' => 'Scientific name',
  'tagalogName' => 'Tagalog name',
  'bisayaName' => 'Cebuano/Bisaya name',
  'family' => 'Family',
  'order' => 'Order',
  'genus' => 'Genus',
  'species' => 'Species',
  'description' => 'Description',
  'characteristics' => 'Characteristics',
  'originHabitat' => 'Origin and natural habitat',
  'classification' => 'Plant classification',
  'suitability' => 'Indoor/outdoor suitability',
  'lifespan' => 'Expected lifespan',
  'usesBenefits' => 'Uses and benefits',
  'dailyCare' => 'Daily care',
  'careInstructions' => 'Care instructions',
  'weatherClimate' => 'Weather and climate',
  'climateTypes' => 'Suitable climate types',
  'rainfallTolerance' => 'Rainfall tolerance',
  'heatTolerance' => 'Heat tolerance',
  'coldSensitivity' => 'Cold sensitivity',
  'seasonalCare' => 'Seasonal care',
  'soilCompatibility' => 'Soil requirements',
  'soilPH' => 'Ideal soil pH',
  'soilDrainage' => 'Soil drainage',
  'soilMoisture' => 'Soil moisture',
  'soilMix' => 'Recommended soil mix',
  'compost' => 'Suitable compost',
  'wateringFrequency' => 'Watering frequency',
  'wateringAmount' => 'Watering amount',
  'wateringDrySeason' => 'Dry-season watering',
  'wateringRainySeason' => 'Rainy-season watering',
  'soilMoistureCheck' => 'Checking soil moisture',
  'overwateringSigns' => 'Signs of overwatering',
  'underwateringSigns' => 'Signs of underwatering',
  'growthStageWatering' => 'Watering by growth stage',
  'sunlightRequirements' => 'Sunlight',
  'sunlightHours' => 'Daily sunlight',
  'lowLightSigns' => 'Signs of insufficient light',
  'excessiveLightSigns' => 'Signs of excessive light',
  'temperatureRange' => 'Temperature',
  'humidity' => 'Preferred humidity',
  'fertilizer' => 'Fertilizer and N-P-K',
  'fertilizingFrequency' => 'Fertilizing frequency',
  'nutrientDeficiencies' => 'Nutrient deficiency signs',
  'fertilizerApplication' => 'Fertilizer application',
  'growthCharacteristics' => 'Growth characteristics',
  'growthStages' => 'Growth stages',
  'propagation' => 'Propagation',
  'repotting' => 'Repotting',
  'growingConditions' => 'Growing conditions',
  'taxonomicClass' => 'Class',
  'taxonomicRank' => 'Classification',
  _ => key,
};
