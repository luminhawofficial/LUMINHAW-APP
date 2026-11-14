import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:luminhaw/core/services/supabase_backend.dart';

class ProfilePhotoService {
  ProfilePhotoService._();

  static const _bucket = 'avatars';
  static const maximumPhotoBytes = 1000000;

  static Future<String?> avatarUrl() async {
    final user = _requireVerifiedUser();
    final row = await SupabaseBackend.client
        .from('profiles')
        .select('avatar_url, avatar_path, avatar_hidden')
        .eq('id', user.id)
        .maybeSingle();
    if (row?['avatar_hidden'] == true) return null;

    final avatarUrl = row?['avatar_url'];
    if (avatarUrl is String && avatarUrl.isNotEmpty) return avatarUrl;
    final path = row?['avatar_path'];
    if (path is String && path.startsWith('${user.id}/profile/')) {
      return SupabaseBackend.client.storage
          .from('plant-photos')
          .createSignedUrl(path, 60 * 60);
    }

    final providerAvatar =
        user.userMetadata?['avatar_url'] ?? user.userMetadata?['picture'];
    if (providerAvatar is String &&
        providerAvatar.startsWith('https://') &&
        Uri.tryParse(providerAvatar)?.hasAuthority == true) {
      return providerAvatar;
    }
    return null;
  }

  static Future<void> upload(XFile photo) async {
    final fileLength = await photo.length();
    if (fileLength == 0 || fileLength >= maximumPhotoBytes) {
      throw const FormatException('Choose a photo smaller than 1 MB.');
    }
    final bytes = await photo.readAsBytes();
    if (bytes.length != fileLength || bytes.length >= maximumPhotoBytes) {
      throw const FormatException('Choose a photo smaller than 1 MB.');
    }
    await uploadBytes(bytes);
  }

  static Future<void> uploadBytes(Uint8List bytes) async {
    final user = _requireVerifiedUser();
    if (bytes.isEmpty || bytes.length >= maximumPhotoBytes) {
      throw const FormatException('Choose a photo smaller than 1 MB.');
    }

    final contentType = _contentType(bytes);
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const FormatException(
        'Choose a JPEG, PNG, or WebP profile photo.',
      ),
    };

    final client = SupabaseBackend.client;
    final newPath =
        '${user.id}/avatar_${DateTime.now().toUtc().microsecondsSinceEpoch}.$extension';
    final previousRow = await client
        .from('profiles')
        .select('avatar_path')
        .eq('id', user.id)
        .maybeSingle();

    await client.storage
        .from(_bucket)
        .uploadBinary(
          newPath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    try {
      final publicUrl = client.storage.from(_bucket).getPublicUrl(newPath);
      await client.from('profiles').upsert({
        'id': user.id,
        'avatar_url': publicUrl,
        'avatar_path': newPath,
        'avatar_hidden': false,
      });
    } catch (error) {
      try {
        await client.storage.from(_bucket).remove([newPath]);
      } catch (cleanupError) {
        throw StateError(
          'Could not save your profile photo ($error), and its uploaded copy '
          'could not be removed ($cleanupError).',
        );
      }
      rethrow;
    }

    final previousPath = previousRow?['avatar_path'];
    if (previousPath is String &&
        previousPath.startsWith('${user.id}/avatar_') &&
        previousPath != newPath) {
      await client.storage.from(_bucket).remove([previousPath]);
    }
  }

  static Future<void> remove() async {
    final user = _requireVerifiedUser();
    final client = SupabaseBackend.client;
    final oldRow = await client
        .from('profiles')
        .select('avatar_path')
        .eq('id', user.id)
        .maybeSingle();

    await client.from('profiles').upsert({
      'id': user.id,
      'avatar_url': null,
      'avatar_path': null,
      'avatar_hidden': true,
    });

    final oldPath = oldRow?['avatar_path'];
    if (oldPath is String && oldPath.startsWith('${user.id}/profile/')) {
      await client.storage.from('plant-photos').remove([oldPath]);
    }

    final files = await client.storage.from(_bucket).list(path: user.id);
    final ownedAvatarPaths = files
        .where(
          (file) =>
              RegExp(r'^avatar_[0-9]+\.(jpg|png|webp)$').hasMatch(file.name),
        )
        .map((file) => '${user.id}/${file.name}')
        .toList(growable: false);
    if (ownedAvatarPaths.isNotEmpty) {
      await client.storage.from(_bucket).remove(ownedAvatarPaths);
    }
  }

  static User _requireVerifiedUser() {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }

    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      throw StateError('Sign in with a verified email to manage your photo.');
    }

    return user;
  }

  static String? _contentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }
}
