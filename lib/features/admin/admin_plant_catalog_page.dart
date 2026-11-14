import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

class AdminPlantCatalogPage extends StatefulWidget {
  const AdminPlantCatalogPage({super.key});

  @override
  State<AdminPlantCatalogPage> createState() => _AdminPlantCatalogPageState();
}

class _AdminPlantCatalogPageState extends State<AdminPlantCatalogPage> {
  static const _fields = <_CatalogField>[
    _CatalogField('common_name', 'Common name', maxLength: 160, required: true),
    _CatalogField(
      'scientific_name',
      'Scientific name',
      maxLength: 200,
      required: true,
    ),
    _CatalogField('tagalog_name', 'Tagalog name', maxLength: 160),
    _CatalogField('bisaya_name', 'Cebuano/Bisaya name', maxLength: 160),
    _CatalogField(
      'description',
      'Description',
      maxLength: 12000,
      multiline: true,
    ),
    _CatalogField('image_url', 'Image URL (HTTPS)', maxLength: 2048),
    _CatalogField(
      'water_requirement',
      'Water requirements',
      maxLength: 4000,
      multiline: true,
    ),
    _CatalogField(
      'sunlight_requirement',
      'Sunlight requirements',
      maxLength: 4000,
      multiline: true,
    ),
    _CatalogField(
      'soil_requirement',
      'Soil requirements',
      maxLength: 4000,
      multiline: true,
    ),
    _CatalogField('fertilizer', 'Fertilizer', maxLength: 4000, multiline: true),
    _CatalogField(
      'growth_tips',
      'Growth tips',
      maxLength: 4000,
      multiline: true,
    ),
    _CatalogField(
      'common_diseases',
      'Common diseases',
      maxLength: 4000,
      multiline: true,
    ),
    _CatalogField('treatment', 'Treatment', maxLength: 4000, multiline: true),
  ];

  static const _toxicityOptions = <String, String>{
    'unknown': 'Not specified',
    'safe': 'Not known to be toxic',
    'toxic_pets': 'Toxic to pets',
    'toxic_humans': 'Toxic to humans',
    'toxic_pets_humans': 'Toxic to pets and humans',
  };

  final _formKey = GlobalKey<FormState>();
  final _values = {
    for (final field in _fields) field.key: TextEditingController(),
  };
  final _references = {
    for (final field in _fields) field.key: TextEditingController(),
  };
  final _toxicityReference = TextEditingController();
  String _toxicity = 'unknown';
  bool _isSaving = false;

  @override
  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
    for (final controller in _references.values) {
      controller.dispose();
    }
    _toxicityReference.dispose();
    super.dispose();
  }

  List<String> _referenceUrls(String value) => value
      .split('\n')
      .map((source) => source.trim())
      .where((source) => source.isNotEmpty)
      .toList(growable: false);

  String? _validateReferences(String value, {required bool hasValue}) {
    if (!hasValue) return null;
    final sources = _referenceUrls(value);
    if (sources.isEmpty) return 'Add at least one source URL.';
    if (sources.fold<int>(0, (total, source) => total + source.length + 1) >
        4000) {
      return 'Keep source URLs under 4000 characters total.';
    }
    for (final source in sources) {
      final uri = Uri.tryParse(source);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return 'Use valid HTTPS source URL(s).';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fieldReferences = <String, List<String>>{};
    final body = <String, Object?>{
      'action': 'plant_catalog.create',
      'date_updated': _currentDate(),
      'toxicity': _toxicity,
    };
    for (final field in _fields) {
      final value = _values[field.key]!.text.trim();
      body[field.key] = value;
      if (value.isNotEmpty) {
        fieldReferences[field.key] = _referenceUrls(
          _references[field.key]!.text,
        );
      }
    }
    if (_toxicity != 'unknown') {
      fieldReferences['toxicity'] = _referenceUrls(_toxicityReference.text);
    }
    body['field_references'] = fieldReferences;

    setState(() => _isSaving = true);
    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'admin-api',
        body: body,
      );
      final data = response.data;
      if (response.status < 200 ||
          response.status >= 300 ||
          data is! Map ||
          data['plant_id'] is! String) {
        throw StateError(_responseError(data, response.status));
      }
      if (!mounted) return;
      for (final controller in _values.values) {
        controller.clear();
      }
      for (final controller in _references.values) {
        controller.clear();
      }
      _toxicityReference.clear();
      setState(() {
        _toxicity = 'unknown';
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plant added to the library and is ready to search.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not add plant: $error')));
    }
  }

  String _responseError(Object? data, int status) {
    final error = data is Map ? data['error'] : null;
    final code = error is Map ? error['code'] : null;
    return switch (code) {
      'administrator_access_required' || 'insufficient_role' =>
        'Only an active administrator can add library plants.',
      'plant_reference_required' =>
        'Add a valid source URL for every plant detail you entered.',
      'invalid_plant_catalog_record' =>
        'Check the plant details, date, and HTTPS image URL.',
      'plant_catalog_save_failed' => 'The plant could not be saved.',
      'plant_catalog_audit_unavailable' => 'The plant may have been saved, but its audit record could not be written. Refresh the library before retrying.',
      'plant_catalog_record_not_found' => 'The plant record was not found.',
      _ =>
        code is String
            ? 'The server rejected the plant details ($code, HTTP $status).'
            : 'The server rejected the plant details (HTTP $status).',
    };
  }

  String _currentDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Widget _fieldEditor(_CatalogField field) {
    final controller = _values[field.key]!;
    final referenceController = _references[field.key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey('admin-plant-${field.key}'),
            controller: controller,
            maxLength: field.maxLength,
            minLines: field.multiline ? 2 : 1,
            maxLines: field.multiline ? 5 : 1,
            enabled: !_isSaving,
            decoration: InputDecoration(
              labelText: field.required ? '${field.label} *' : field.label,
              alignLabelWithHint: field.multiline,
              border: const OutlineInputBorder(),
            ),
            validator: field.required
                ? (value) => value == null || value.trim().isEmpty
                      ? '${field.label} is required.'
                      : null
                : null,
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('admin-plant-source-${field.key}'),
            controller: referenceController,
            maxLength: 4000,
            minLines: 1,
            maxLines: 3,
            enabled: !_isSaving,
            decoration: InputDecoration(
              labelText: '${field.label} source URL(s)',
              hintText:
                  'One HTTPS URL per line; required when this value is set',
              border: const OutlineInputBorder(),
            ),
            validator: (value) => _validateReferences(
              value ?? '',
              hasValue: controller.text.trim().isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Manage plant library')),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add a verified plant',
              style: TextStyle(
                color: AppColors.green,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Provide a source URL for each detail. Saved plants become searchable in the user library.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            for (final field in _fields) _fieldEditor(field),
            DropdownButtonFormField<String>(
              key: const ValueKey('admin-plant-toxicity'),
              initialValue: _toxicity,
              decoration: const InputDecoration(
                labelText: 'Toxicity',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in _toxicityOptions.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _isSaving
                  ? null
                  : (value) => setState(() => _toxicity = value ?? 'unknown'),
            ),
            if (_toxicity != 'unknown') ...[
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('admin-plant-source-toxicity'),
                controller: _toxicityReference,
                maxLength: 4000,
                minLines: 1,
                maxLines: 3,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Toxicity source URL(s)',
                  hintText: 'One HTTPS URL per line',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validateReferences(
                  value ?? '',
                  hasValue: _toxicity != 'unknown',
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('admin-plant-catalog-save'),
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_isSaving ? 'Saving plant…' : 'Add plant to library'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CatalogField {
  const _CatalogField(
    this.key,
    this.label, {
    required this.maxLength,
    this.required = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final int maxLength;
  final bool required;
  final bool multiline;
}
