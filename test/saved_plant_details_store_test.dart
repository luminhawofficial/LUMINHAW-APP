import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved plant details are separated by account', () async {
    var ownerId = 'user-one';
    final store = SavedPlantDetailsStore(ownerIdProvider: () => ownerId);
    const plant = PlantRecord(
      commonName: 'Monstera',
      scientificName: 'Monstera deliciosa',
      category: 'Plants',
      water: 'Water when the soil is dry.',
      image: '',
      fieldReferences: {
        'water_requirement': ['https://example.com/monstera-watering'],
      },
    );

    await store.save(plant);
    expect(store.savedPlants.value['Monstera']?['fieldReferences'], {
      'water_requirement': ['https://example.com/monstera-watering'],
    });
    ownerId = 'user-two';
    await store.load();
    expect(store.savedPlants.value, isEmpty);

    ownerId = 'user-one';
    await store.reload();
    expect(store.savedPlants.value, contains('Monstera'));
  });

  test('account deletion clears only that account saved details', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('saved_library_plant_details', '{"Device":{}}');
    await preferences.setString(
      'saved_library_plant_details_account_user-one',
      '{"Monstera":{}}',
    );
    final store = SavedPlantDetailsStore(ownerIdProvider: () => null);

    await store.clearPersonalData(ownerId: 'user-one');

    expect(
      preferences.getString('saved_library_plant_details'),
      '{"Device":{}}',
    );
    expect(
      preferences.getString('saved_library_plant_details_account_user-one'),
      isNull,
    );
  });
}
