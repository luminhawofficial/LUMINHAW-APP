class ProfileDetails {
  const ProfileDetails({
    this.fullName = '',
    this.username = '',
    this.gender,
    this.dateOfBirth,
    this.phoneNumber = '',
    this.location = '',
    this.bio = '',
    this.gardeningExperience,
    this.favoritePlantCategory,
    this.growingEnvironment,
    this.avatarUrl,
    this.avatarPath,
    this.avatarHidden = false,
  });

  static const genders = ['Male', 'Female', 'Prefer not to say'];
  static const gardeningExperiences = ['Beginner', 'Intermediate', 'Expert'];
  static const plantCategories = [
    'Flowers',
    'Vegetables',
    'Fruits',
    'Herbs',
    'Indoor Plants',
    'Trees',
    'Succulents',
    'Others',
  ];
  static const growingEnvironments = ['Indoor', 'Outdoor', 'Both'];

  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._]{2,29}$');

  final String fullName;
  final String username;
  final String? gender;
  final DateTime? dateOfBirth;
  final String phoneNumber;
  final String location;
  final String bio;
  final String? gardeningExperience;
  final String? favoritePlantCategory;
  final String? growingEnvironment;
  final String? avatarUrl;
  final String? avatarPath;
  final bool avatarHidden;

  factory ProfileDetails.fromMap(
    Map<String, dynamic> row, {
    String fallbackName = '',
    String fallbackLocation = '',
  }) {
    return ProfileDetails(
      fullName: _string(row['display_name']) ?? fallbackName,
      username: _string(row['username']) ?? '',
      gender: _string(row['gender']),
      dateOfBirth: DateTime.tryParse(_string(row['date_of_birth']) ?? ''),
      phoneNumber: _string(row['phone_number']) ?? '',
      location: _string(row['location']) ?? fallbackLocation,
      bio: _string(row['bio']) ?? '',
      gardeningExperience: _string(row['gardening_experience']),
      favoritePlantCategory: _string(row['favorite_plant_category']),
      growingEnvironment: _string(row['growing_environment']),
      avatarUrl: _string(row['avatar_url']),
      avatarPath: _string(row['avatar_path']),
      avatarHidden: row['avatar_hidden'] == true,
    );
  }

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static String? usernameError(String value) {
    final username = normalizeUsername(value);
    if (username.isEmpty) return 'Enter a username.';
    if (!_usernamePattern.hasMatch(username)) {
      return 'Use 3–30 letters, numbers, dots, or underscores; start with a letter or number.';
    }
    return null;
  }

  int? get age => ageOn(DateTime.now());

  int? ageOn(DateTime asOf) {
    final birthDate = dateOfBirth;
    if (birthDate == null) return null;

    var years = asOf.year - birthDate.year;
    if (asOf.month < birthDate.month ||
        (asOf.month == birthDate.month && asOf.day < birthDate.day)) {
      years--;
    }
    return years;
  }

  Map<String, dynamic> toDatabase(String userId) => {
    'id': userId,
    'display_name': fullName.trim(),
    'username': normalizeUsername(username),
    'gender': _nullable(gender),
    'date_of_birth': dateOfBirth == null
        ? null
        : '${dateOfBirth!.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth!.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth!.day.toString().padLeft(2, '0')}',
    'phone_number': _nullable(phoneNumber),
    'location': _nullable(location),
    'bio': _nullable(bio),
    'gardening_experience': _nullable(gardeningExperience),
    'favorite_plant_category': _nullable(favoritePlantCategory),
    'growing_environment': _nullable(growingEnvironment),
  };

  Map<String, Object?> formValues() => {
    'fullName': fullName.trim(),
    'username': normalizeUsername(username),
    'gender': gender,
    'dateOfBirth': dateOfBirth == null
        ? null
        : '${dateOfBirth!.year}-${dateOfBirth!.month}-${dateOfBirth!.day}',
    'phoneNumber': phoneNumber.trim(),
    'location': location.trim(),
    'bio': bio.trim(),
    'gardeningExperience': gardeningExperience,
    'favoritePlantCategory': favoritePlantCategory,
    'growingEnvironment': growingEnvironment,
  };

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
