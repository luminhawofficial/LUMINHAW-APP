import 'package:luminhaw/core/models/profile_details.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSettingsService {
  ProfileSettingsService._();

  static Future<ProfileDetails> load() async {
    final user = _requireUser();
    final row = await SupabaseBackend.client
        .from('profiles')
        .select(
          'display_name,username,gender,date_of_birth,phone_number,location,'
          'bio,gardening_experience,favorite_plant_category,'
          'growing_environment,avatar_url,avatar_path,avatar_hidden',
        )
        .eq('id', user.id)
        .maybeSingle();

    return ProfileDetails.fromMap(
      row ?? const <String, dynamic>{},
      fallbackName: SupabaseAuthService.displayName ?? '',
      fallbackLocation: SupabaseAuthService.location ?? '',
    );
  }

  static Future<bool> isUsernameAvailable(String username) async {
    final normalized = ProfileDetails.normalizeUsername(username);
    final error = ProfileDetails.usernameError(normalized);
    if (error != null) return false;

    final result = await SupabaseBackend.client.rpc(
      'is_profile_username_available',
      params: {'p_username': normalized},
    );
    return result == true;
  }

  static Future<void> save(ProfileDetails profile) async {
    final user = _requireUser();
    if (profile.fullName.trim().isEmpty) {
      throw ArgumentError.value(profile.fullName, 'fullName', 'Required.');
    }
    final usernameError = ProfileDetails.usernameError(profile.username);
    if (usernameError != null) {
      throw ArgumentError.value(profile.username, 'username', usernameError);
    }
    if (profile.dateOfBirth == null ||
        profile.dateOfBirth!.isAfter(DateTime.now())) {
      throw ArgumentError.value(
        profile.dateOfBirth,
        'dateOfBirth',
        'Choose a valid date of birth.',
      );
    }
    if (profile.bio.length > 150) {
      throw ArgumentError.value(profile.bio, 'bio', 'Maximum 150 characters.');
    }
    if (!await isUsernameAvailable(profile.username)) {
      throw const UsernameUnavailableException();
    }

    final client = SupabaseBackend.client;
    final normalizedName = profile.fullName.trim();
    final normalizedLocation = profile.location.trim();
    await client.auth.updateUser(
      UserAttributes(
        data: {'full_name': normalizedName, 'location': normalizedLocation},
      ),
    );

    try {
      await client
          .from('profiles')
          .upsert(profile.toDatabase(user.id), onConflict: 'id');
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const UsernameUnavailableException();
      }
      rethrow;
    }
  }

  static User _requireUser() {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || SupabaseBackend.client.auth.currentSession == null) {
      throw StateError('Sign in before editing your profile.');
    }
    return user;
  }
}

class UsernameUnavailableException implements Exception {
  const UsernameUnavailableException();

  @override
  String toString() => 'That username is already taken. Choose another.';
}
