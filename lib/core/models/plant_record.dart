class PlantRecord {
  const PlantRecord({
    required this.commonName,
    required this.scientificName,
    required this.category,
    required this.water,
    required this.image,
    this.family = 'Not listed',
    this.order,
    this.kingdom,
    this.phylum,
    this.taxonomicClass,
    this.genus,
    this.species,
    this.taxonomicRank,
    this.taxonomicStatus,
    this.description,
    this.englishName,
    this.tagalogName,
    this.bisayaName,
    this.alternativeNames = const [],
    this.searchMatchedName,
    this.formerScientificName,
    this.acceptedTaxonId,
    this.imageUrl,
    this.imageAttribution,
    this.imageLicense,
    this.imageLicenseUrl,
    this.imageReferenceUrl,
    this.source,
    this.enrichedFields = const {},
    this.enrichmentSources = const {},
    this.fieldReferences = const {},
    this.aiGeneratedFields = const {},
    this.plantingDate,
    this.growthStage,
    this.initialObservation,
    this.isSaved = false,
    this.isVerified = false,
  });

  factory PlantRecord.fromStoredDetails(
    String commonName,
    Map<String, Object?>? details,
  ) {
    String? optionalString(String key) {
      final value = details?[key];
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return PlantRecord(
      commonName: commonName,
      scientificName: optionalString('scientificName') ?? '',
      category: optionalString('category') ?? 'Plants',
      water: optionalString('water') ?? 'Care guidance is not available yet.',
      image: optionalString('image') ?? '',
      family: optionalString('family') ?? 'Not listed',
      order: optionalString('order'),
      kingdom: optionalString('kingdom'),
      phylum: optionalString('phylum'),
      taxonomicClass: optionalString('taxonomicClass'),
      genus: optionalString('genus'),
      species: optionalString('species'),
      taxonomicRank: optionalString('taxonomicRank'),
      taxonomicStatus: optionalString('taxonomicStatus'),
      description: optionalString('description'),
      englishName: optionalString('englishName'),
      tagalogName: optionalString('tagalogName'),
      bisayaName: optionalString('bisayaName'),
      alternativeNames: _storedStringList(details?['alternativeNames']),
      searchMatchedName: optionalString('searchMatchedName'),
      formerScientificName: optionalString('formerScientificName'),
      acceptedTaxonId: optionalString('acceptedTaxonId'),
      imageUrl: optionalString('imageUrl'),
      imageAttribution: optionalString('imageAttribution'),
      imageLicense: optionalString('imageLicense'),
      imageLicenseUrl: optionalString('imageLicenseUrl'),
      imageReferenceUrl: optionalString('imageReferenceUrl'),
      source: optionalString('source'),
      enrichedFields: _storedStringMap(details?['enrichedFields']),
      enrichmentSources: _storedStringMap(details?['enrichmentSources']),
      fieldReferences: _storedStringListMap(details?['fieldReferences']),
      aiGeneratedFields: _storedStringSet(details?['aiGeneratedFields']),
      plantingDate: optionalString('plantingDate'),
      growthStage: optionalString('growthStage'),
      initialObservation: optionalString('initialObservation'),
      isSaved: true,
      isVerified: details?['isVerified'] == true,
    );
  }

  final String commonName;
  final String scientificName;
  final String category;
  final String water;
  final String image;
  final String family;
  final String? order;
  final String? kingdom;
  final String? phylum;
  final String? taxonomicClass;
  final String? genus;
  final String? species;
  final String? taxonomicRank;
  final String? taxonomicStatus;
  final String? description;
  final String? englishName;
  final String? tagalogName;
  final String? bisayaName;
  final List<String> alternativeNames;
  final String? searchMatchedName;
  final String? formerScientificName;
  final String? acceptedTaxonId;
  final String? imageUrl;
  final String? imageAttribution;
  final String? imageLicense;
  final String? imageLicenseUrl;
  final String? imageReferenceUrl;
  final String? source;
  final Map<String, String> enrichedFields;
  final Map<String, String> enrichmentSources;
  final Map<String, List<String>> fieldReferences;
  final Set<String> aiGeneratedFields;
  final String? plantingDate;
  final String? growthStage;
  final String? initialObservation;
  final bool isSaved;
  final bool isVerified;

  Map<String, Object?> toStoredDetails() => {
    'scientificName': scientificName,
    'category': category,
    'water': water,
    'image': image,
    'family': family,
    'order': order,
    'kingdom': kingdom,
    'phylum': phylum,
    'taxonomicClass': taxonomicClass,
    'genus': genus,
    'species': species,
    'taxonomicRank': taxonomicRank,
    'taxonomicStatus': taxonomicStatus,
    'description': description,
    'englishName': englishName,
    'tagalogName': tagalogName,
    'bisayaName': bisayaName,
    'alternativeNames': alternativeNames,
    'searchMatchedName': searchMatchedName,
    'formerScientificName': formerScientificName,
    'acceptedTaxonId': acceptedTaxonId,
    'imageUrl': imageUrl,
    'imageAttribution': imageAttribution,
    'imageLicense': imageLicense,
    'imageLicenseUrl': imageLicenseUrl,
    'imageReferenceUrl': imageReferenceUrl,
    'source': source,
    'enrichedFields': enrichedFields,
    'enrichmentSources': enrichmentSources,
    'fieldReferences': fieldReferences,
    'aiGeneratedFields': aiGeneratedFields.toList(),
    'plantingDate': plantingDate,
    'growthStage': growthStage,
    'initialObservation': initialObservation,
    'isVerified': isVerified,
  };

  static Map<String, String> _storedStringMap(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    });
  }

  static Set<String> _storedStringSet(Object? value) =>
      value is List ? Set.unmodifiable(value.whereType<String>()) : const {};

  static Map<String, List<String>> _storedStringListMap(Object? value) {
    if (value is! Map) return const {};
    return Map.unmodifiable({
      for (final entry in value.entries)
        if (entry.key is String && entry.value is List)
          entry.key as String: List.unmodifiable(
            (entry.value as List)
                .whereType<String>()
                .map((source) => source.trim())
                .where((source) => source.isNotEmpty),
          ),
    });
  }

  static List<String> _storedStringList(Object? value) =>
      value is List ? List.unmodifiable(value.whereType<String>()) : const [];
}
