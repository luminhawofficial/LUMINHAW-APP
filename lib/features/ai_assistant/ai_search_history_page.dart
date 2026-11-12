import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/ai_conversation_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class AiSearchHistoryPage extends StatefulWidget {
  const AiSearchHistoryPage({super.key});

  @override
  State<AiSearchHistoryPage> createState() => _AiSearchHistoryPageState();
}

class _AiSearchHistoryPageState extends State<AiSearchHistoryPage> {
  final _search = TextEditingController();
  AiConversationHistorySnapshot? _history;
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final history = await AiConversationService.loadConversationHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
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

  Future<void> _deleteConversation(
    AiConversationHistoryItem conversation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This conversation and its messages will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await AiConversationService.deleteConversation(conversation.id);
      if (!mounted) return;
      setState(() {
        _history = AiConversationHistorySnapshot(
          conversations: _history!.conversations
              .where((item) => item.id != conversation.id)
              .toList(growable: false),
          syncError: _history!.syncError,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete conversation: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final conversations = AiConversationService.filterConversationHistory(
      _history?.conversations ?? const [],
      query,
    );

    return ScreenBody(
      title: 'LUMIN AI history',
      subtitle: 'Search and reopen your previous conversations.',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.green),
              ),
            )
          else if (_loadError case final error?)
            SetupNotice(message: 'AI history could not be loaded: $error')
          else if (conversations.isEmpty)
            AppCard(
              child: Text(
                query.isEmpty
                    ? 'Your previous LUMIN AI conversations will appear here.'
                    : 'No conversations match your search.',
                style: const TextStyle(color: AppColors.muted),
              ),
            )
          else ...[
            if (_history?.syncError case final error?)
              SetupNotice(
                message:
                    'Showing saved AI history. It could not be refreshed: $error',
              ),
            for (final conversation in conversations)
              _ConversationCard(
                conversation: conversation,
                onOpen: () => Navigator.pushNamed(
                  context,
                  '/assistant',
                  arguments: conversation.id,
                ),
                onDelete: () => _deleteConversation(conversation),
              ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            label: _loadError == null
                ? 'Refresh history'
                : 'Retry loading history',
            icon: Icons.refresh,
            onPressed: _isLoading ? null : _loadHistory,
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'New chat',
            icon: Icons.add,
            onPressed: () => Navigator.pushNamed(context, '/assistant/new'),
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.onOpen,
    required this.onDelete,
  });

  final AiConversationHistoryItem conversation;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _historyDate(conversation.createdAt),
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            if (conversation.preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                conversation.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.dark, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: 'Delete conversation',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, color: AppColors.muted),
      ),
    ),
  );
}

String _historyDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
