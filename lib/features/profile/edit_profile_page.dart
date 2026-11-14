import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/profile_details.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/services/profile_photo_service.dart';
import 'package:luminhaw/core/services/profile_settings_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/profile/profile_account_actions.dart';
import 'package:luminhaw/features/profile/profile_avatar.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _dateOfBirthKey = GlobalKey<FormFieldState<DateTime>>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _bio = TextEditingController();
  final _picker = ImagePicker();
  final _cropper = ImageCropper();

  ProfileDetails _originalProfile = const ProfileDetails();
  DateTime? _dateOfBirth;
  String? _gender;
  String? _gardeningExperience;
  String? _favoritePlantCategory;
  String? _growingEnvironment;
  Uint8List? _pendingPhotoBytes;
  String? _usernameConflict;
  Object? _loadError;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPickingPhoto = false;
  bool _removePhoto = false;
  bool _allowPop = false;
  bool _discardDialogOpen = false;

  bool get _hasUnsavedChanges {
    final current = _currentProfile();
    return !mapEquals(current.formValues(), _originalProfile.formValues()) ||
        _pendingPhotoBytes != null ||
        _removePhoto;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _username, _phone, _location, _bio]) {
      controller.addListener(_onFormChanged);
    }
    _loadProfile();
  }

  @override
  void dispose() {
    for (final controller in [_name, _username, _phone, _location, _bio]) {
      controller
        ..removeListener(_onFormChanged)
        ..dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final profile = await ProfileSettingsService.load();
      if (!mounted) return;
      setState(() {
        _originalProfile = profile;
        _name.text = profile.fullName;
        _username.text = profile.username;
        _gender = profile.gender;
        _dateOfBirth = profile.dateOfBirth;
        _phone.text = profile.phoneNumber;
        _location.text = profile.location;
        _bio.text = profile.bio;
        _gardeningExperience = profile.gardeningExperience;
        _favoritePlantCategory = profile.favoritePlantCategory;
        _growingEnvironment = profile.growingEnvironment;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() => _usernameConflict = null);
  }

  ProfileDetails _currentProfile() => ProfileDetails(
    fullName: _name.text,
    username: _username.text,
    gender: _gender,
    dateOfBirth: _dateOfBirth,
    phoneNumber: _phone.text,
    location: _location.text,
    bio: _bio.text,
    gardeningExperience: _gardeningExperience,
    favoritePlantCategory: _favoritePlantCategory,
    growingEnvironment: _growingEnvironment,
    avatarUrl: _originalProfile.avatarUrl,
    avatarPath: _originalProfile.avatarPath,
    avatarHidden: _originalProfile.avatarHidden,
  );

  int get _completedDetails {
    final profile = _currentProfile();
    return [
      profile.fullName.trim().isNotEmpty,
      profile.username.trim().isNotEmpty,
      profile.gender != null,
      profile.dateOfBirth != null,
      profile.phoneNumber.trim().isNotEmpty,
      profile.location.trim().isNotEmpty,
      profile.bio.trim().isNotEmpty,
      profile.gardeningExperience != null,
      profile.favoritePlantCategory != null,
      profile.growingEnvironment != null,
    ].where((complete) => complete).length;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Select your date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme
              .copyWith(primary: AppColors.green, secondary: AppColors.green),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dateOfBirth = DateTime(selected.year, selected.month, selected.day);
      _dateOfBirthKey.currentState?.didChange(_dateOfBirth);
    });
  }

  Future<void> _changePhoto() async {
    if (_isPickingPhoto || _isSaving) return;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, _PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            if (_hasCurrentPhoto)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFF9D3A36),
                ),
                title: const Text(
                  'Remove profile photo',
                  style: TextStyle(color: Color(0xFF9D3A36)),
                ),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == _PhotoAction.remove) {
      setState(() {
        _pendingPhotoBytes = null;
        _removePhoto = true;
      });
      return;
    }
    await _pickAndCropPhoto(
      action == _PhotoAction.camera ? ImageSource.camera : ImageSource.gallery,
    );
  }

  bool get _hasCurrentPhoto {
    if (_originalProfile.avatarHidden) return false;
    final user = SupabaseAuthService.currentUser;
    final metadata = user?.userMetadata;
    final providerPhoto = metadata?['avatar_url'] ?? metadata?['picture'];
    return _originalProfile.avatarUrl != null ||
        _originalProfile.avatarPath != null ||
        (providerPhoto is String && providerPhoto.isNotEmpty);
  }

  Future<void> _pickAndCropPhoto(ImageSource source) async {
    setState(() => _isPickingPhoto = true);
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (photo == null || !mounted) return;

      final cropped = await _cropper.cropImage(
        sourcePath: photo.path,
        aspectRatio: kIsWeb
            ? null
            : const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 600,
        maxHeight: 600,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          if (kIsWeb)
            WebUiSettings(
              context: context,
              viewMode: WebViewMode.mode_1,
              initialAspectRatio: 1,
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            AndroidUiSettings(
              toolbarTitle: 'Crop profile photo',
              toolbarColor: AppColors.green,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: AppColors.green,
              lockAspectRatio: true,
              cropStyle: CropStyle.circle,
              initAspectRatio: CropAspectRatioPreset.square,
              aspectRatioPresets: [CropAspectRatioPreset.square],
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            IOSUiSettings(
              title: 'Crop profile photo',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
              cropStyle: CropStyle.circle,
              aspectRatioPresets: [CropAspectRatioPreset.square],
            ),
        ],
      );
      if (cropped == null || !mounted) return;

      final bytes = await cropped.readAsBytes();
      if (bytes.isEmpty ||
          bytes.length >= ProfilePhotoService.maximumPhotoBytes) {
        _showMessage('Choose a cropped photo smaller than 1 MB.');
        return;
      }
      setState(() {
        _pendingPhotoBytes = bytes;
        _removePhoto = false;
      });
    } catch (error) {
      if (mounted) _showMessage('Could not select or crop the photo: $error');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    if (!SupabaseBackend.isInitialized) {
      _showMessage(SupabaseBackend.configurationMessage);
      return;
    }

    final profile = _currentProfile();
    setState(() => _isSaving = true);
    try {
      await ProfileSettingsService.save(profile);
      try {
        if (_pendingPhotoBytes != null) {
          await ProfilePhotoService.uploadBytes(_pendingPhotoBytes!);
        } else if (_removePhoto) {
          await ProfilePhotoService.remove();
        }
      } catch (error) {
        if (!mounted) return;
        setState(() => _originalProfile = profile);
        _showMessage(
          'Profile details saved, but the photo could not be updated: $error',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _originalProfile = profile;
        _pendingPhotoBytes = null;
        _removePhoto = false;
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } on UsernameUnavailableException catch (error) {
      if (mounted) {
        setState(() => _usernameConflict = error.toString());
        _formKey.currentState?.validate();
      }
    } catch (error) {
      _showMessage('Could not save your profile: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDiscardChanges() async {
    if (_discardDialogOpen || !_hasUnsavedChanges) return;
    _discardDialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard profile changes?'),
        content: const Text(
          'You have changes that have not been saved. Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.green),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _discardDialogOpen = false;
    if (discard != true || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateName(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter your full name.' : null;

  String? _validateUsername(String? value) =>
      ProfileDetails.usernameError(value ?? '') ?? _usernameConflict;

  String? _validateDateOfBirth(DateTime? value) {
    if (value == null) return 'Date of birth is required.';
    final today = DateTime.now();
    if (value.isAfter(DateTime(today.year, today.month, today.day))) {
      return 'Date of birth cannot be in the future.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_hasUnsavedChanges || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_allowPop) unawaited(_confirmDiscardChanges());
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(back: true),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.green,
                            ),
                          )
                        : _loadError != null
                        ? _loadErrorView()
                        : _buildProfileForm(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadErrorView() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.green, size: 44),
        const SizedBox(height: 12),
        Text(
          'Your profile could not be loaded: $_loadError',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: _loadProfile,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
        if (!SupabaseBackend.isInitialized) ...[
          const SizedBox(height: 12),
          SetupNotice(message: SupabaseBackend.configurationMessage),
        ],
      ],
    ),
  );

  Widget _buildProfileForm() {
    final user = SupabaseAuthService.currentUser;
    final email = user?.email ?? '';
    final googleConnected = SupabaseAuthService.hasGoogleProvider;
    final current = _currentProfile();
    final progress = _completedDetails / 10;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Text(
            'Complete Your Profile',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.green,
              fontFamily: 'PlayfairDisplay',
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Make your LUMINHAW space feel like yours.',
            style: TextStyle(color: AppColors.muted, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 18),
          _photoCard(),
          const SizedBox(height: 14),
          _progressCard(progress),
          const SizedBox(height: 14),
          _sectionCard(
            icon: Icons.person_outline,
            title: 'Personal Information',
            child: Column(
              children: [
                _textField(
                  controller: _name,
                  label: 'Full Name',
                  required: true,
                  validator: _validateName,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 13),
                _textField(
                  controller: _username,
                  label: 'Username',
                  required: true,
                  validator: _validateUsername,
                  prefixText: '@',
                  helperText:
                      '3–30 lowercase letters, numbers, dots, or underscores.',
                  onChanged: (_) {
                    if (_usernameConflict != null) {
                      setState(() => _usernameConflict = null);
                    }
                  },
                ),
                const SizedBox(height: 13),
                _dropdownField(
                  label: 'Gender',
                  value: _gender,
                  options: ProfileDetails.genders,
                  onChanged: (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: 13),
                FormField<DateTime>(
                  key: _dateOfBirthKey,
                  initialValue: _dateOfBirth,
                  validator: _validateDateOfBirth,
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: _isSaving ? null : _pickDateOfBirth,
                        borderRadius: BorderRadius.circular(14),
                        child: InputDecorator(
                          decoration:
                              _inputDecoration(
                                'Date of Birth',
                                required: true,
                              ).copyWith(
                                errorText: field.errorText,
                                suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                  color: AppColors.green,
                                ),
                              ),
                          child: Text(
                            _dateOfBirth == null
                                ? 'Select your date of birth'
                                : _formatDate(_dateOfBirth!),
                            style: TextStyle(
                              color: _dateOfBirth == null
                                  ? AppColors.muted
                                  : AppColors.dark,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      if (current.age != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Age: ${current.age} years',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 13),
                TextFormField(
                  key: const ValueKey('profile-email'),
                  initialValue: email,
                  readOnly: true,
                  decoration: _inputDecoration('Email Address').copyWith(
                    prefixIcon: const Icon(Icons.mail_outline),
                    suffixIcon: googleConnected
                        ? const Tooltip(
                            message: 'Connected with Google',
                            child: Icon(Icons.verified_outlined),
                          )
                        : null,
                    helperText: googleConnected
                        ? 'Connected with Google'
                        : 'Your registered email cannot be changed here.',
                  ),
                ),
                const SizedBox(height: 13),
                _textField(
                  controller: _phone,
                  label: 'Phone Number',
                  optional: true,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 13),
                _textField(
                  controller: _location,
                  label: 'Location',
                  optional: true,
                  hintText: 'City or region',
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 13),
                _textField(
                  controller: _bio,
                  label: 'Bio',
                  optional: true,
                  hintText: 'Tell us a little about your plant journey',
                  maxLength: 150,
                  maxLines: 3,
                  validator: (value) => (value?.length ?? 0) > 150
                      ? 'Bio must be 150 characters or fewer.'
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            icon: Icons.eco_outlined,
            title: 'Gardening Profile',
            child: Column(
              children: [
                _dropdownField(
                  label: 'Gardening Experience',
                  value: _gardeningExperience,
                  options: ProfileDetails.gardeningExperiences,
                  onChanged: (value) =>
                      setState(() => _gardeningExperience = value),
                ),
                const SizedBox(height: 13),
                _dropdownField(
                  label: 'Favorite Plant Category',
                  value: _favoritePlantCategory,
                  options: ProfileDetails.plantCategories,
                  onChanged: (value) =>
                      setState(() => _favoritePlantCategory = value),
                ),
                const SizedBox(height: 13),
                _dropdownField(
                  label: 'Growing Environment',
                  value: _growingEnvironment,
                  options: ProfileDetails.growingEnvironments,
                  onChanged: (value) =>
                      setState(() => _growingEnvironment = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _accountCard(
            DateTime.tryParse(user?.createdAt ?? ''),
            googleConnected,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.maybePop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.green,
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: _isSaving || _isPickingPhoto ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ];
              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buttons[0],
                    const SizedBox(height: 10),
                    buttons[1],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: buttons[0]),
                  const SizedBox(width: 12),
                  Expanded(child: buttons[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _photoCard() => _sectionCard(
    icon: Icons.account_circle_outlined,
    title: 'Profile Photo',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB8D7C2), width: 2),
          ),
          child: _pendingPhotoBytes != null
              ? CircleAvatar(
                  radius: 48,
                  backgroundImage: MemoryImage(_pendingPhotoBytes!),
                )
              : _removePhoto
              ? const CircleAvatar(
                  radius: 48,
                  backgroundColor: Color(0xFFD9EADB),
                  child: Icon(Icons.person, color: AppColors.green, size: 48),
                )
              : const ProfileAvatar(radius: 48),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isPickingPhoto || _isSaving ? null : _changePhoto,
          icon: _isPickingPhoto
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(_isPickingPhoto ? 'Opening photo…' : 'Change Photo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.green,
            side: const BorderSide(color: Color(0xFFB8D7C2)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Choose a photo, then crop it to fit your profile.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _progressCard(double progress) => _sectionCard(
    icon: Icons.check_circle_outline,
    title: 'Profile Completion',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your profile details',
                style: TextStyle(color: AppColors.dark, fontSize: 13),
              ),
            ),
            Text(
              '$_completedDetails / 10',
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE7EFE8),
            color: AppColors.green,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Full name, username, and date of birth are required.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _accountCard(
    DateTime? memberSince,
    bool googleConnected,
  ) => _sectionCard(
    icon: Icons.verified_user_outlined,
    title: 'Account',
    child: Column(
      children: [
        _accountRow(
          icon: Icons.g_mobiledata,
          title: 'Google Account',
          value: googleConnected ? 'Connected' : 'Not connected',
          status: googleConnected,
        ),
        const Divider(height: 20),
        ValueListenableBuilder<PlanTier>(
          valueListenable: PlanEntitlementStore.instance.tier,
          builder: (context, tier, _) => _accountRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Premium Status',
            value: tier == PlanTier.premium ? 'Premium' : 'Free',
            status: tier == PlanTier.premium,
          ),
        ),
        const Divider(height: 20),
        _accountRow(
          icon: Icons.calendar_month_outlined,
          title: 'Member Since',
          value: memberSince == null ? 'Unavailable' : _formatDate(memberSince),
        ),
        const Divider(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shield_outlined, color: AppColors.green),
          title: const Text(
            'Privacy Settings',
            style: TextStyle(color: AppColors.dark, fontSize: 14),
          ),
          subtitle: const Text('Review your privacy information'),
          trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
          onTap: _isSaving
              ? null
              : () => Navigator.pushNamed(context, '/privacy'),
        ),
        const Divider(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_outline, color: Color(0xFF9D3A36)),
          title: const Text(
            'Delete Account',
            style: TextStyle(
              color: Color(0xFF9D3A36),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text('Permanently remove your account and data'),
          onTap: _isSaving ? null : () => confirmAndDeleteAccount(context),
        ),
      ],
    ),
  );

  Widget _accountRow({
    required IconData icon,
    required String title,
    required String value,
    bool? status,
  }) => Row(
    children: [
      Icon(icon, color: AppColors.green),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(color: AppColors.dark, fontSize: 14),
        ),
      ),
      if (status != null)
        Icon(
          status ? Icons.check_circle : Icons.info_outline,
          color: status ? AppColors.green : AppColors.muted,
          size: 17,
        ),
      const SizedBox(width: 6),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDCE9DE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D173D2E),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF5ED),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.green, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    bool optional = false,
    String? hintText,
    String? helperText,
    String? prefixText,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLength,
    int maxLines = 1,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) => TextFormField(
    controller: controller,
    enabled: !_isSaving,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    maxLength: maxLength,
    maxLines: maxLines,
    validator: validator,
    onChanged: onChanged,
    decoration: _inputDecoration(label, required: required, optional: optional)
        .copyWith(
          hintText: hintText,
          helperText: helperText,
          prefixText: prefixText,
          alignLabelWithHint: maxLines > 1,
        ),
  );

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: _inputDecoration(label, optional: true),
    items: options
        .map((option) => DropdownMenuItem(value: option, child: Text(option)))
        .toList(growable: false),
    onChanged: _isSaving ? null : onChanged,
  );

  InputDecoration _inputDecoration(
    String label, {
    bool required = false,
    bool optional = false,
  }) => InputDecoration(
    labelText: required ? '$label *' : label,
    hintText: optional ? 'Optional' : null,
    labelStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
    filled: true,
    fillColor: const Color(0xFFFBFDFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE9DE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFDCE9DE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.green, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF9D3A36)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF9D3A36), width: 1.5),
    ),
  );

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';
}

enum _PhotoAction { camera, gallery, remove }
