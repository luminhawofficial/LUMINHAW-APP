import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/scan_history_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class ScanHistoryPage extends StatefulWidget {
  const ScanHistoryPage({super.key, this.loadHistory, this.deleteScan});

  final Future<List<ScanHistoryRecord>> Function()? loadHistory;
  final Future<void> Function(String scanId)? deleteScan;

  @override
  State<ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  Future<List<ScanHistoryRecord>>? _history;
  List<ScanHistoryRecord>? _recordsOverride;

  Future<List<ScanHistoryRecord>> _loadHistory() =>
      widget.loadHistory?.call() ?? ScanHistoryService.fetchRecent();

  void _refresh() {
    setState(() {
      _recordsOverride = null;
      _history = _loadHistory();
    });
  }

  Future<void> _confirmDelete(ScanHistoryRecord record) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete scan history?'),
        content: Text(
          'Remove ${record.commonName ?? record.plantName ?? 'this scan'} '
          'from your scan history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    try {
      await (widget.deleteScan ?? ScanHistoryService.delete)(record.id);
      if (!mounted) return;
      final remaining = await (_history ?? _loadHistory()).then(
        (records) => records.where((item) => item.id != record.id).toList(),
      );
      if (!mounted) return;
      setState(() => _recordsOverride = remaining);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan removed from history.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete scan: $error')));
    }
  }

  Future<void> _signIn() async {
    await Navigator.pushNamed(context, '/login');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseBackend.isInitialized && widget.loadHistory == null) {
      return ScreenBody(
        title: 'Your green discoveries.',
        subtitle: 'Revisit the plants you have scanned.',
        back: true,
        child: SetupNotice(message: SupabaseBackend.configurationMessage),
      );
    }

    if (SupabaseAuthService.currentUser == null && widget.loadHistory == null) {
      return ScreenBody(
        title: 'Your green discoveries.',
        subtitle: 'Sign in to view scans saved to your account.',
        back: true,
        child: AppCard(
          child: Column(
            children: [
              const Icon(Icons.eco_outlined, size: 48, color: AppColors.green),
              const SizedBox(height: 12),
              const Text(
                'Your scan history is private to your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.dark),
              ),
              const SizedBox(height: 12),
              PrimaryButton(label: 'Log in', onPressed: _signIn),
            ],
          ),
        ),
      );
    }

    _history ??= _loadHistory();
    return ScreenBody(
      title: 'Your green discoveries.',
      subtitle: 'Revisit the plants you have scanned.',
      back: true,
      trailing: IconButton(
        tooltip: 'Refresh scan history',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: FutureBuilder<List<ScanHistoryRecord>>(
        future: _history!,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppCard(
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.green,
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Could not load scan history: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.dark),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.green),
            );
          }

          final records = _recordsOverride ?? snapshot.data!;
          if (records.isEmpty) {
            return const AppCard(
              child: Column(
                children: [
                  Icon(Icons.eco_outlined, size: 48, color: AppColors.green),
                  SizedBox(height: 12),
                  Text(
                    'No scans yet',
                    style: TextStyle(
                      color: AppColors.green,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your completed plant identifications will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _showDetails(record),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.eco_outlined,
                              color: AppColors.green,
                              size: 34,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.commonName ??
                                        record.plantName ??
                                        _statusLabel(record.status),
                                    style: const TextStyle(
                                      color: AppColors.green,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (record.commonName != null &&
                                      record.plantName != null &&
                                      record.commonName !=
                                          record.plantName) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      record.plantName!,
                                      style: const TextStyle(
                                        color: AppColors.dark,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  if (record.family != null ||
                                      record.probability != null)
                                    Text(
                                      [
                                        if (record.family != null)
                                          'Family: ${record.family}',
                                        if (record.probability != null)
                                          'Provider score: ${(record.probability! * 100).toStringAsFixed(0)}%',
                                      ].join(' · '),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formattedDate(context, record.createdAt),
                                    style: const TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'View plant details',
                                    style: TextStyle(
                                      color: AppColors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: record.status),
                            IconButton(
                              tooltip: 'Delete scan',
                              onPressed: () => _confirmDelete(record),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showDetails(ScanHistoryRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                record.commonName ??
                    record.plantName ??
                    _statusLabel(record.status),
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (record.plantName != null &&
                  record.plantName != record.commonName)
                Text(
                  record.plantName!,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 14),
              _detail('Status', _statusLabel(record.status)),
              _detail('Scanned', _formattedDate(context, record.createdAt)),
              if (record.provider != null)
                _detail('Identification provider', record.provider!),
              if (record.probability != null)
                _detail(
                  'Provider match score',
                  '${(record.probability! * 100).toStringAsFixed(1)}%',
                ),
              if (record.family != null) _detail('Family', record.family!),
              if (record.tagalogName != null)
                _detail('Tagalog name', record.tagalogName!),
              if (record.bisayaName != null)
                _detail('Cebuano/Bisaya name', record.bisayaName!),
              for (final key in const [
                'kingdom',
                'phylum',
                'class',
                'order',
                'genus',
                'species',
              ])
                if (record.taxonomy[key] case final value?)
                  _detail(_label(key), value),
              if (record.description != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Description',
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  record.description!,
                  style: const TextStyle(color: AppColors.dark, height: 1.4),
                ),
              ],
              for (final entry in record.plantDetails.entries)
                if (!{
                  'tagalogName',
                  'bisayaName',
                  'description',
                }.contains(entry.key))
                  _detail(_label(entry.key), entry.value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 145,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.dark,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  String _label(String value) => value
      .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match[1]}')
      .replaceFirst(value[0], value[0].toUpperCase());

  String _statusLabel(String status) => switch (status) {
    'pending' => 'Identification pending',
    'failed' => 'Identification failed',
    'completed' => 'Completed',
    _ => 'Unknown status',
  };

  String _formattedDate(BuildContext context, DateTime date) {
    final localDate = date.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(localDate).format(context);
    return '${localizations.formatMediumDate(localDate)} · $time';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isComplete = status == 'completed';
    final color = isComplete ? AppColors.green : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: color, fontSize: 10),
      ),
    );
  }
}
