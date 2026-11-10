import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/services/plant_health_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class HealthCheckerPage extends StatefulWidget {
  const HealthCheckerPage({super.key, this.plant});

  final PlantRecord? plant;

  @override
  State<HealthCheckerPage> createState() => _HealthCheckerPageState();
}

class _HealthCheckerPageState extends State<HealthCheckerPage> {
  static const _maxImageBytes = 10 * 1024 * 1024;
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageName;
  PlantHealthAssessment? _assessment;
  String? _errorMessage;
  bool _isPicking = false;
  bool _isAssessing = false;
  bool _consentToAnalysis = false;
  bool _entitlementLoaded = false;
  bool _entitlementUnavailable = false;

  @override
  void initState() {
    super.initState();
    _refreshEntitlement();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = PlanEntitlementStore.instance.hasPremiumAccess;
    return ScreenBody(
      title: 'Plant health checker',
      subtitle: 'Check for possible plant health issues using a photo.',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plant',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.plant?.commonName ??
                        'You can still check a plant without selecting it.',
                    style: TextStyle(
                      color: widget.plant == null
                          ? AppColors.muted
                          : AppColors.dark,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Plant photo',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use a clear photo of the leaves or affected area.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 190,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imageBytes == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.eco_outlined,
                              color: AppColors.green,
                              size: 42,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Choose or take a plant photo',
                              style: TextStyle(color: AppColors.green),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'JPEG, PNG, or WebP (up to 10 MB)',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        )
                      : Image.memory(
                          _imageBytes!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Text(
                              'This photo could not be previewed.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPicking || _isAssessing
                            ? null
                            : () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isPicking || _isAssessing
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                if (_imageName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Selected: $_imageName',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const SetupNotice(
                  message: 'With your consent, this photo is uploaded to your private account storage and sent to Plant.ID for analysis. Results are suggestions, not a confirmed diagnosis.',
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _consentToAnalysis,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I agree to send this photo to Plant.ID for analysis.',
                    style: TextStyle(fontSize: 13, color: AppColors.dark),
                  ),
                  onChanged: _isAssessing || _imageBytes == null
                      ? null
                      : (value) =>
                            setState(() => _consentToAnalysis = value ?? false),
                ),
                if (_entitlementUnavailable)
                  const SetupNotice(
                    message: 'Premium status could not be verified. Please check your connection and try again.',
                  ),
                if (!isPremium && _entitlementLoaded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/premium'),
                      child: const Text(
                        'Plant health analysis requires Premium',
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isAssessing ||
                            _isPicking ||
                            !_consentToAnalysis ||
                            !isPremium ||
                            !_entitlementLoaded ||
                            _entitlementUnavailable
                        ? null
                        : _runAssessment,
                    icon: _isAssessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_outlined),
                    label: Text(
                      _isAssessing
                          ? 'Checking plant health...'
                          : 'Check plant health',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            SetupNotice(message: _errorMessage!),
          ],
          if (_assessment != null) ...[
            const SizedBox(height: 14),
            _AssessmentCard(assessment: _assessment!),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshEntitlement() async {
    final entitlements = PlanEntitlementStore.instance;
    try {
      await entitlements.refreshFromServer();
      if (mounted) {
        setState(() {
          _entitlementLoaded = true;
          _entitlementUnavailable = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _entitlementLoaded = true;
          _entitlementUnavailable = true;
          _errorMessage = 'Could not verify Premium status: $error';
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 88,
      );
      if (picked == null) return;

      final size = await picked.length();
      if (size == 0 || size > _maxImageBytes) {
        throw const FormatException('The image must be smaller than 10 MB.');
      }
      final bytes = await picked.readAsBytes();
      if (!_hasSupportedImageHeader(bytes)) {
        throw const FormatException(
          'Choose a readable JPEG, PNG, or WebP photo.',
        );
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name;
        _consentToAnalysis = false;
        _assessment = null;
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

  Future<void> _runAssessment() async {
    final imageBytes = _imageBytes;
    if (imageBytes == null || !_consentToAnalysis) return;

    setState(() {
      _isAssessing = true;
      _errorMessage = null;
      _assessment = null;
    });
    try {
      final assessment = await PlantHealthService.assess(
        imageBytes: imageBytes,
      );
      if (mounted) setState(() => _assessment = assessment);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not assess plant health: $error');
      }
    } finally {
      if (mounted) setState(() => _isAssessing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _hasSupportedImageHeader(List<int> bytes) {
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final isWebp =
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return isJpeg || isPng || isWebp;
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.assessment});

  final PlantHealthAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final isHealthy = assessment.isHealthy;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isHealthy == true
                ? 'No health issue detected'
                : isHealthy == false
                ? 'Possible health issue detected'
                : 'Possible health findings',
            style: const TextStyle(
              color: AppColors.green,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (assessment.healthProbability != null) ...[
            const SizedBox(height: 4),
            Text(
              'Healthy probability: '
              '${(assessment.healthProbability! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (assessment.predictions.isEmpty)
            const Text(
              'No possible disease predictions were returned for this photo.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            )
          else
            ...assessment.predictions.map(
              (prediction) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PredictionDetails(prediction: prediction),
              ),
            ),
          const SetupNotice(
            message: 'Automated image analysis can be wrong and does not replace professional horticultural advice. Confirm symptoms before treating the plant.',
          ),
        ],
      ),
    );
  }
}

class _PredictionDetails extends StatelessWidget {
  const _PredictionDetails({required this.prediction});

  final PlantHealthPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final probability = prediction.probability;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prediction.localName ?? prediction.name,
          style: const TextStyle(
            color: AppColors.dark,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (prediction.localName != null &&
            prediction.localName != prediction.name)
          Text(
            prediction.name,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        if (probability != null)
          Text(
            'Probability: ${(probability * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        if (prediction.description != null)
          _DetailText(label: 'About', text: prediction.description!),
        if (prediction.cause != null)
          _DetailText(label: 'Possible cause', text: prediction.cause!),
        if (prediction.treatment != null)
          _DetailText(label: 'Suggested care', text: prediction.treatment!),
      ],
    );
  }
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      '$label: $text',
      style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
    ),
  );
}
