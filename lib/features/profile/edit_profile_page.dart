import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/services/profile_photo_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/profile/profile_avatar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _name = TextEditingController();
  final _picker = ImagePicker();
  int _avatarRefreshToken = 0;
  Uint8List? _previewBytes;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _name.text = SupabaseAuthService.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!SupabaseBackend.isInitialized) {
      _showMessage(SupabaseBackend.configurationMessage);
      return;
    }
    if (_name.text.trim().isEmpty) {
      _showMessage('Enter your name before saving.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await SupabaseAuthService.updateProfileName(_name.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile name updated.')));
        Navigator.pop(context);
      }
    } catch (error) {
      _showMessage('Could not update your profile: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 600,
        maxHeight: 600,
      );
      if (photo == null || !mounted) return;

      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _isUploadingPhoto = true;
      });
      await ProfilePhotoService.upload(photo);
      if (!mounted) return;
      setState(() {
        _avatarRefreshToken++;
        _previewBytes = null;
        _isUploadingPhoto = false;
      });
      _showMessage('Profile photo updated.');
    } on PlatformException {
      if (mounted) {
        setState(() {
          _previewBytes = null;
          _avatarRefreshToken++;
          _isUploadingPhoto = false;
        });
        _showMessage('Could not access the selected photo.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewBytes = null;
        _avatarRefreshToken++;
        _isUploadingPhoto = false;
      });
      _showMessage('Could not update your profile photo: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'A little more you.',
      subtitle: 'Update your name and profile picture.',
      back: true,
      child: AppCard(
        child: Column(
          children: [
            _previewBytes == null
                ? ProfileAvatar(radius: 36, refreshToken: _avatarRefreshToken)
                : CircleAvatar(
                    radius: 36,
                    backgroundImage: MemoryImage(_previewBytes!),
                  ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isUploadingPhoto || _isSaving
                      ? null
                      : () => _pickProfilePhoto(ImageSource.camera),
                  icon: _isUploadingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                  label: Text(_isUploadingPhoto ? 'Uploading…' : 'Take photo'),
                ),
                OutlinedButton.icon(
                  onPressed: _isUploadingPhoto || _isSaving
                      ? null
                      : () => _pickProfilePhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from gallery'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: _isSaving ? 'Saving…' : 'Save profile',
              onPressed: _isSaving || _isUploadingPhoto ? null : _saveProfile,
            ),
            const SizedBox(height: 12),
            if (!SupabaseBackend.isInitialized)
              SetupNotice(message: SupabaseBackend.configurationMessage),
          ],
        ),
      ),
    );
  }
}
