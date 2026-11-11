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
    this.tagalogName,
    this.bisayaName,
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
    this.aiGeneratedFields = const {},
    this.plantingDate,
    this.growthStage,
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
      tagalogName: optionalString('tagalogName'),
      bisayaName: optionalString('bisayaName'),
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
      aiGeneratedFields: _storedStringSet(details?['aiGeneratedFields']),
      plantingDate: optionalString('plantingDate'),
      growthStage: optionalString('growthStage'),
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
  final String? tagalogName;
  final String? bisayaName;
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
  final Set<String> aiGeneratedFields;
  final String? plantingDate;
  final String? growthStage;
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
    'tagalogName': tagalogName,
    'bisayaName': bisayaName,
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
    'aiGeneratedFields': aiGeneratedFields.toList(),
    'plantingDate': plantingDate,
    'growthStage': growthStage,
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
}
