import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/plant_identification_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  static const _maxImageBytes = 10 * 1024 * 1024;
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageName;
  bool _isPicking = false;
  bool _isIdentifying = false;
  bool _consentToAnalysis = false;

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Identify a plant',
      subtitle: 'Take a clear photo of the plant you want to identify.',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 270,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.green.withValues(alpha: 0.25),
              ),
            ),
            child: _imageBytes == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.center_focus_weak,
                        color: AppColors.green,
                        size: 68,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Your plant photo will appear here',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.memory(
                      _imageBytes!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'This image could not be previewed.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Open camera',
            icon: Icons.camera_alt,
            onPressed: _isPicking ? null : () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isPicking
                ? null
                : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose from gallery'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: AppColors.green,
            ),
          ),
          const SizedBox(height: 18),
          const SetupNotice(
            message: 'A plant photo is sent to Supabase Edge Functions and Plant.ID only after you confirm below. Provider availability depends on server configuration.',
          ),
          if (_isPicking) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_imageName != null) ...[
            const SizedBox(height: 8),
            Text(
              'Selected: $_imageName',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          if (_imageBytes != null) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _consentToAnalysis,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I agree to send this photo to Plant.ID to identify the plant.',
                style: TextStyle(fontSize: 13, color: AppColors.dark),
              ),
              onChanged: _isIdentifying
                  ? null
                  : (value) =>
                        setState(() => _consentToAnalysis = value ?? false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/privacy'),
                child: const Text('Read Privacy & usage'),
              ),
            ),
            PrimaryButton(
              label: _isIdentifying ? 'Identifying…' : 'Identify plant',
              icon: Icons.search,
              onPressed: _isIdentifying || !_consentToAnalysis
                  ? null
                  : _identifyPlant,
            ),
            TextButton(
              onPressed: () => setState(() {
                _imageBytes = null;
                _imageName = null;
                _consentToAnalysis = false;
              }),
              child: const Text('Remove photo'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/history'),
            icon: const Icon(Icons.history),
            label: const Text('View scan history'),
          ),
        ],
      ),
    );
  }

  Future<void> _identifyPlant() async {
    final imageBytes = _imageBytes;
    if (imageBytes == null || !_consentToAnalysis) return;
    if (!SupabaseBackend.isInitialized) {
      _showMessage(SupabaseBackend.configurationMessage);
      return;
    }
    if (SupabaseAuthService.currentUser == null) {
      _showMessage('Sign in to identify and save a plant scan.');
      await Navigator.pushNamed(context, '/login');
      return;
    }

    setState(() => _isIdentifying = true);
    try {
      final result = await PlantIdentificationService.identify(
        imageBytes: imageBytes,
      );
      if (mounted) {
        await Navigator.pushNamed(context, '/result', arguments: result);
      }
    } catch (error) {
      _showMessage('Could not identify the plant: $error');
    } finally {
      if (mounted) setState(() => _isIdentifying = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isPicking = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 88,
      );
      if (picked == null) return;

      final extension = picked.name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        throw const FormatException('Choose a JPEG, PNG, or WebP image file.');
      }

      final size = await picked.length();
      if (size == 0 || size > _maxImageBytes) {
        throw const FormatException('The image must be smaller than 10 MB.');
      }
      final bytes = await picked.readAsBytes();
      if (!_hasSupportedImageHeader(bytes)) {
        throw const FormatException(
          'The selected file is not a readable image.',
        );
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name;
        _consentToAnalysis = false;
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    } on PlatformException catch (error) {
      _showMessage(
        error.message ?? 'The camera or photo library could not be opened.',
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _hasSupportedImageHeader(List<int> bytes) {
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final isWebp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return isPng || isJpeg || isWebp;
  }
}
