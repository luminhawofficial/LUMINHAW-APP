import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/scan_history_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class ScanHistoryPage extends StatefulWidget {
  const ScanHistoryPage({super.key});

  @override
  State<ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  Future<List<ScanHistoryRecord>>? _history;

  Future<List<ScanHistoryRecord>> _loadHistory() =>
      ScanHistoryService.fetchRecent();

  void _refresh() {
    setState(() => _history = _loadHistory());
  }

  Future<void> _signIn() async {
    await Navigator.pushNamed(context, '/login');
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!SupabaseBackend.isInitialized) {
      return ScreenBody(
        title: 'Your green discoveries.',
        subtitle: 'Revisit the plants you have scanned.',
        back: true,
        child: SetupNotice(message: SupabaseBackend.configurationMessage),
      );
    }

    if (SupabaseAuthService.currentUser == null) {
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

          final records = snapshot.data!;
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
                    child: Row(
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
                                record.plantName ?? _statusLabel(record.status),
                                style: const TextStyle(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formattedDate(context, record.createdAt),
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                              if (record.provider != null)
                                Text(
                                  'Provider: ${record.provider}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _StatusBadge(status: record.status),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'Identification pending',
    'failed' => 'Identification failed',
    _ => 'Plant identification',
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
