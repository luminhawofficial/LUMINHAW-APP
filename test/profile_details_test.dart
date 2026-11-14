import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/models/profile_details.dart';

void main() {
  test('normalizes usernames and validates the supported format', () {
    expect(
      ProfileDetails.normalizeUsername('  Green.Garden_7 '),
      'green.garden_7',
    );
    expect(ProfileDetails.usernameError('green.garden_7'), isNull);
    expect(ProfileDetails.usernameError('ab'), isNotNull);
    expect(ProfileDetails.usernameError('two words'), isNotNull);
    expect(ProfileDetails.usernameError('.garden'), isNotNull);
  });

  test('calculates age based on whether this year’s birthday has passed', () {
    final profile = ProfileDetails(dateOfBirth: DateTime(2000, 6, 12));

    expect(profile.ageOn(DateTime(2026, 6, 11)), 25);
    expect(profile.ageOn(DateTime(2026, 6, 12)), 26);
    expect(profile.ageOn(DateTime(2026, 6, 13)), 26);
  });

  test(
    'serializes the date of birth and leaves empty optional fields null',
    () {
      final row = ProfileDetails(
        fullName: '  A Green Thumb  ',
        username: '  Plant.Grower ',
        dateOfBirth: DateTime(1995, 2, 3),
        phoneNumber: '',
      ).toDatabase('user-id');

      expect(row['display_name'], 'A Green Thumb');
      expect(row['username'], 'plant.grower');
      expect(row['date_of_birth'], '1995-02-03');
      expect(row['phone_number'], isNull);
      expect(row['bio'], isNull);
    },
  );
}
