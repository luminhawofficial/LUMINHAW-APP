import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/app/router.dart';
import 'package:luminhaw/core/services/plant_catalog_service.dart';

void main() {
  test('parses catalog JSON and removes duplicate scientific taxa', () {
    final plants = PlantCatalogService.parseResponse({
      'success': true,
      'source': 'GBIF',
      'results': [
        {
          'vernacularName': 'Monstera',
          'scientificName': 'Monstera deliciosa',
          'family': 'Araceae',
        },
        {
          'canonicalName': 'Swiss cheese plant',
          'scientificName': ' monstera   deliciosa ',
          'family': 'Araceae',
        },
        {
          'commonName': 'Monstera adansonii',
          'scientificName': 'Monstera adansonii',
          'family': 'Araceae',
        },
        {'commonName': 'Missing scientific name'},
        null,
      ],
    });

    expect(plants, hasLength(2));
    expect(plants.first.commonName, 'Monstera');
    expect(plants.first.scientificName, 'Monstera deliciosa');
    expect(plants.first.source, 'GBIF');
    expect(plants.last.scientificName, 'Monstera adansonii');
    expect(plants.last.imageUrl, isNull);
  });

  test('filters provider search results unrelated to the query', () {
    final plants = PlantCatalogService.parseResponse({
      'source': 'GBIF',
      'results': [
        {'commonName': 'Mango', 'scientificName': 'Mangifera indica'},
        {'commonName': 'Plantain', 'scientificName': 'Musa paradisiaca'},
      ],
    });

    final filtered = PlantCatalogService.filterRelevantSearchResults(
      'mango indica',
      plants,
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.scientificName, 'Mangifera indica');
  });

  test(
    'matches complete name tokens and ranks exact no-photo matches first',
    () {
      final plants = PlantCatalogService.parseResponse({
        'source': 'GBIF',
        'results': [
          {'commonName': 'Primrose', 'scientificName': 'Primula vulgaris'},
          {'commonName': 'Wild Mango', 'scientificName': 'Mangifera zeylanica'},
          {'commonName': 'Mango', 'scientificName': 'Mangifera indica'},
        ],
      });

      final results = PlantCatalogService.filterRelevantSearchResults(
        'mango',
        plants,
      );

      expect(results, hasLength(2));
      expect(results.first.commonName, 'Mango');
      expect(results.first.imageUrl, isNull);
      expect(results.last.commonName, 'Wild Mango');
    },
  );

  test('rejects malformed catalog JSON', () {
    expect(
      () => PlantCatalogService.parseResponse({'source': 'gbif'}),
      throwsFormatException,
    );
  });

  test('handles the legacy provider failure response', () {
    expect(
      () => PlantCatalogService.parseResponse({
        'success': false,
        'error': 'Unable to retrieve plant information',
      }),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Plant catalog providers are temporarily unavailable.',
        ),
      ),
    );
  });

  test('accepts the existing plants response format', () {
    final plants = PlantCatalogService.parseResponse({
      'source': 'gbif',
      'plants': [
        {'commonName': 'Monstera', 'scientificName': 'Monstera deliciosa'},
      ],
    });

    expect(plants, hasLength(1));
    expect(plants.single.commonName, 'Monstera');
  });

  test('parses current function results for Monstera, Mango and Hibiscus', () {
    final plants = PlantCatalogService.parseResponse({
      'success': true,
      'source': 'GBIF',
      'results': [
        {
          'commonName': 'Monstera',
          'scientificName': 'Monstera deliciosa',
          'rank': 'SPECIES',
          'taxonomicStatus': 'ACCEPTED',
        },
        {
          'commonName': 'Mango',
          'scientificName': 'Mangifera indica',
          'tagalogName': 'Mangga',
          'bisayaName': 'Mangga',
          'rank': 'SPECIES',
          'taxonomicStatus': 'ACCEPTED',
        },
        {
          'commonName': 'Hibiscus',
          'scientificName': 'Hibiscus rosa-sinensis',
          'rank': 'SPECIES',
          'taxonomicStatus': 'ACCEPTED',
        },
      ],
    });

    expect(plants.map((plant) => plant.commonName), [
      'Monstera',
      'Mango',
      'Hibiscus',
    ]);
    expect(plants.map((plant) => plant.scientificName), [
      'Monstera deliciosa',
      'Mangifera indica',
      'Hibiscus rosa-sinensis',
    ]);
  });

  test('keeps Cebuano and Tagalog names in library search results', () {
    final plant = PlantCatalogService.parseResponse({
      'source': 'GBIF',
      'results': [
        {
          'commonName': 'Papaya',
          'scientificName': 'Carica papaya',
          'tagalogName': 'Papaya',
          'bisayaName': 'Kapayas',
        },
      ],
    }).single;

    expect(plant.tagalogName, 'Papaya');
    expect(plant.bisayaName, 'Kapayas');
  });

  test(
    'matches Philippine local, English, scientific, and alternate names',
    () {
      final plants = PlantCatalogService.parseResponse({
        'source': 'LUMINHAW local Philippine catalog',
        'results': [
          {
            'commonName': 'Kangkong',
            'englishName': 'Water spinach',
            'scientificName': 'Ipomoea aquatica',
            'family': 'Convolvulaceae',
            'category': 'Vegetable',
            'alternativeNames': ['Kangkong', 'Kang Kong', 'Water spinach'],
          },
          {
            'commonName': 'Mangga',
            'englishName': 'Mango',
            'scientificName': 'Mangifera indica',
            'family': 'Anacardiaceae',
            'category': 'Fruit',
            'alternativeNames': ['Mangga', 'Mango'],
          },
          {
            'commonName': 'Malunggay',
            'englishName': 'Moringa',
            'scientificName': 'Moringa oleifera',
            'alternativeNames': ['Malunggay', 'Moringa', 'Kamunggay'],
          },
          {
            'commonName': 'Ampalaya',
            'englishName': 'Bitter gourd',
            'scientificName': 'Momordica charantia',
            'alternativeNames': ['Ampalaya', 'Bitter gourd'],
          },
          {
            'commonName': 'Kamote',
            'englishName': 'Sweet potato',
            'scientificName': 'Ipomoea batatas',
            'alternativeNames': ['Kamote', 'Sweet potato'],
          },
          {
            'commonName': 'Saging',
            'englishName': 'Banana',
            'scientificName': 'Musa × paradisiaca',
            'alternativeNames': ['Saging', 'Banana'],
          },
          {
            'commonName': 'Talong',
            'englishName': 'Eggplant',
            'scientificName': 'Solanum melongena',
            'alternativeNames': ['Talong', 'Eggplant'],
          },
          {
            'commonName': 'Kamatis',
            'englishName': 'Tomato',
            'scientificName': 'Solanum lycopersicum',
            'alternativeNames': ['Kamatis', 'Tomato'],
          },
          {
            'commonName': 'Pechay',
            'englishName': 'Bok choy',
            'scientificName': 'Brassica rapa',
            'alternativeNames': ['Pechay', 'Bok choy', 'Pak choi'],
          },
        ],
      });

      final expectedNames = {
        'Kangkong': 'Kangkong',
        'Kang Kong': 'Kangkong',
        'Water Spinach': 'Kangkong',
        'Ipomoea aquatica': 'Kangkong',
        'Mango': 'Mangga',
        'Mangga': 'Mangga',
        'Malunggay': 'Malunggay',
        'Moringa': 'Malunggay',
        'Ampalaya': 'Ampalaya',
        'Kamote': 'Kamote',
        'Saging': 'Saging',
        'Talong': 'Talong',
        'Pechay': 'Pechay',
      };
      for (final entry in expectedNames.entries) {
        final result = PlantCatalogService.filterRelevantSearchResults(
          entry.key,
          plants,
        );
        expect(result.first.commonName, entry.value, reason: entry.key);
      }

      final kangkong = plants.first;
      expect(kangkong.englishName, 'Water spinach');
      expect(kangkong.family, 'Convolvulaceae');
      expect(kangkong.category, 'Vegetable');
    },
  );

  test('accepts a typo-tolerant alias match returned by the local catalog', () {
    final plant = PlantCatalogService.parseResponse({
      'source': 'LUMINHAW local Philippine catalog',
      'results': [
        {
          'commonName': 'Kangkong',
          'scientificName': 'Ipomoea aquatica',
          'alternativeNames': ['Kangkong', 'Water spinach'],
          'matchedName': 'Kangkong',
        },
      ],
    }).single;

    expect(
      PlantCatalogService.filterRelevantSearchResults('Kangkongg', [plant]),
      [plant],
    );
  });

  test('parses records returned by the database catalog API', () {
    final plants = PlantCatalogService.parseResponse({
      'source': 'catalog',
      'plants': [
        {
          'gbif_key': 2877951,
          'common_name': 'Mango',
          'scientific_name': 'Mangifera indica',
          'family': 'Anacardiaceae',
        },
      ],
    });

    expect(plants, hasLength(1));
    expect(plants.single.commonName, 'Mango');
    expect(plants.single.scientificName, 'Mangifera indica');
    expect(plants.single.acceptedTaxonId, '2877951');
  });

  test('preserves verified admin content and reviewed care fields', () {
    final plant = PlantCatalogService.parseResponse({
      'source': 'LUMINHAW verified catalog',
      'results': [
        {
          'scientific_name': 'Mangifera indica',
          'common_name': 'Mango',
          'tagalog_name': 'Mangga',
          'bisaya_name': 'Mangga',
          'family': 'Anacardiaceae',
          'origin': 'South Asia',
          'compatible_weather': 'Tropical',
          'description': 'Verified mango information.',
          'is_verified': true,
          'plant_care': [
            {
              'reviewed': true,
              'water_requirements': 'Water when the topsoil dries.',
              'sunlight_requirements': 'Full sun',
              'soil_requirements': 'Well-draining soil',
            },
          ],
          'plant_images': [
            {
              'is_verified': true,
              'is_primary': true,
              'image_url': 'https://example.com/mango.jpg',
              'creator': 'LUMINHAW',
              'license': 'CC BY 4.0',
              'source_url': 'https://example.com/source',
            },
          ],
        },
      ],
    }).single;

    expect(plant.isVerified, isTrue);
    expect(plant.source, 'LUMINHAW verified catalog');
    expect(plant.tagalogName, 'Mangga');
    expect(plant.bisayaName, 'Mangga');
    expect(plant.enrichedFields['originHabitat'], 'South Asia');
    expect(plant.enrichedFields['weatherClimate'], 'Tropical');
    expect(plant.enrichedFields['soilCompatibility'], 'Well-draining soil');
    expect(plant.enrichedFields['sunlightRequirements'], 'Full sun');
    expect(
      plant.enrichmentSources['soilCompatibility'],
      'LUMINHAW verified catalog',
    );
    expect(plant.water, 'Water when the topsoil dries.');
    expect(plant.imageUrl, 'https://example.com/mango.jpg');
    expect(plant.imageAttribution, 'LUMINHAW');
    expect(plant.imageLicense, 'CC BY 4.0');
  });

  test('verified admin records take precedence over provider duplicates', () {
    final verified = PlantCatalogService.parseResponse({
      'source': 'LUMINHAW verified catalog',
      'results': [
        {
          'scientific_name': 'Mangifera indica',
          'common_name': 'Verified Mango',
          'is_verified': true,
        },
      ],
    });
    final providers = PlantCatalogService.parseResponse({
      'source': 'GBIF',
      'results': [
        {'scientificName': 'Mangifera indica', 'commonName': 'Provider Mango'},
        {'scientificName': 'Carica papaya', 'commonName': 'Papaya'},
      ],
    });

    final merged = PlantCatalogService.preferVerifiedCatalogRecords(
      verified,
      providers,
    );
    expect(merged, hasLength(2));
    expect(merged.first.commonName, 'Verified Mango');
    expect(merged.first.isVerified, isTrue);
    expect(merged.last.commonName, 'Papaya');
  });

  test('accepts nested and JSON-string legacy catalog formats', () {
    final plants = PlantCatalogService.parseResponse(
      '{"success":true,"data":{"source":"legacy","plants":['
      '{"commonName":"Mango","scientificName":"Mangifera indica"}]}}',
    );

    expect(plants, hasLength(1));
    expect(plants.single.commonName, 'Mango');
    expect(plants.single.source, 'legacy');
  });

  testWidgets('a catalog result opens its matching plant details', (
    tester,
  ) async {
    final plant = PlantCatalogService.parseResponse({
      'success': true,
      'source': 'GBIF',
      'results': [
        {'commonName': 'Mango', 'scientificName': 'Mangifera indica'},
      ],
    }).single;

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: LuminhawRouter.onGenerateRoute,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed('/plant', arguments: plant),
              child: const Text('Open catalog plant'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open catalog plant'));
    await tester.pumpAndSettle();

    expect(find.text('Mango'), findsOneWidget);
    expect(find.text('Mangifera indica'), findsWidgets);
  });

  test('groups synonyms by accepted taxon and keeps the accepted name', () {
    final plants = PlantCatalogService.parseResponse({
      'success': true,
      'source': 'GBIF',
      'results': [
        {
          'commonName': 'Snake Plant',
          'scientificName': 'Dracaena trifasciata',
          'acceptedScientificName': 'Dracaena trifasciata',
          'acceptedKey': 1001,
          'kingdom': 'Plantae',
          'phylum': 'Tracheophyta',
          'class': 'Liliopsida',
          'genus': 'Dracaena',
          'species': 'trifasciata',
          'rank': 'SPECIES',
          'taxonomicStatus': 'ACCEPTED',
          'family': 'Asparagaceae',
          'order': 'Asparagales',
          'description': 'A perennial species.',
        },
        {
          'commonName': 'Snake Plant',
          'scientificName': 'Sansevieria trifasciata',
          'acceptedScientificName': 'Dracaena trifasciata',
          'acceptedKey': 1001,
          'rank': 'SPECIES',
          'taxonomicStatus': 'ACCEPTED',
          'family': 'Asparagaceae',
        },
        {
          'commonName': 'Asparagaceae',
          'scientificName': 'Asparagaceae',
          'acceptedKey': 2002,
          'rank': 'FAMILY',
          'taxonomicStatus': 'ACCEPTED',
        },
      ],
    });

    expect(plants, hasLength(1));
    expect(plants.single.scientificName, 'Dracaena trifasciata');
    expect(plants.single.acceptedTaxonId, '1001');
    expect(plants.single.kingdom, 'Plantae');
    expect(plants.single.taxonomicClass, 'Liliopsida');
    expect(plants.single.genus, 'Dracaena');
    expect(plants.single.species, 'trifasciata');
    expect(plants.single.taxonomicRank, 'SPECIES');
    expect(plants.single.order, 'Asparagales');
    expect(plants.single.description, 'A perennial species.');
  });

  test('preserves image license and attribution details', () {
    final plants = PlantCatalogService.parseResponse({
      'success': true,
      'source': 'GBIF',
      'results': [
        {
          'commonName': 'Monstera',
          'scientificName': 'Monstera deliciosa',
          'imageUrl':
              'https://inaturalist-open-data.s3.amazonaws.com/photos/1.jpg',
          'imageAttribution': 'Plant photographer',
          'imageLicense': 'CC BY 4.0',
          'imageLicenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
          'imageReferenceUrl': 'https://www.inaturalist.org/photos/1',
        },
      ],
    });

    expect(plants.single.imageUrl, contains('photos/1.jpg'));
    expect(plants.single.imageAttribution, 'Plant photographer');
    expect(plants.single.imageLicense, 'CC BY 4.0');
    expect(
      plants.single.imageLicenseUrl,
      'https://creativecommons.org/licenses/by/4.0/',
    );
    expect(
      plants.single.imageReferenceUrl,
      'https://www.inaturalist.org/photos/1',
    );
  });

  test('rejects insecure or malformed image URLs', () {
    final plants = PlantCatalogService.parseResponse({
      'success': true,
      'results': [
        {
          'commonName': 'Unsafe image',
          'scientificName': 'Testus plantus',
          'imageUrl': 'http://example.test/plant.jpg',
        },
        {
          'commonName': 'Credential URL',
          'scientificName': 'Otherus plantus',
          'imageUrl': 'https://user:password@example.test/plant.jpg',
        },
      ],
    });

    expect(plants, hasLength(2));
    expect(plants.map((plant) => plant.imageUrl), everyElement(isNull));
  });
}
