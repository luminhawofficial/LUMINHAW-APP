import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/ai_conversation_service.dart';
import 'package:luminhaw/core/services/gemini_assistant_service.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage>
    with WidgetsBindingObserver {
  final _message = TextEditingController();
  final _chatScroll = ScrollController();
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;

  final List<AiChatMessage> _messages = [];
  final List<AiPendingMessage> _pendingMessages = [];
  final Set<String> _pendingMessageIds = {};

  bool _isSending = false;
  bool _isLoadingHistory = true;
  bool _isHistoryLoadError = false;
  String? _conversationId;
  String? _conversationTitle;
  Object? _historyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'chat connectivity monitoring',
          ),
        );
        if (mounted) setState(() => _historyError = error);
      },
    );
    unawaited(_restoreConversation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_connectivitySubscription.cancel());
    _message.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isHistoryLoadError) {
        unawaited(_restoreConversation());
      } else if (_pendingMessages.isNotEmpty) {
        unawaited(_retryPendingMessages());
      }
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (_isLoadingHistory || _isSending) return;
    if (!results.any((result) => result != ConnectivityResult.none)) return;
    if (_isHistoryLoadError) {
      unawaited(_restoreConversation());
    } else if (_pendingMessages.isNotEmpty) {
      unawaited(_retryPendingMessages());
    }
  }

  Future<void> _restoreConversation() async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
      _isHistoryLoadError = false;
    });

    try {
      final snapshot = await AiConversationService.loadLatestConversation();
      if (!mounted) return;

      setState(() {
        _conversationId = snapshot.conversationId;
        _conversationTitle = snapshot.title;
        _messages
          ..clear()
          ..addAll(snapshot.messages);
        _pendingMessages
          ..clear()
          ..addAll(snapshot.pendingMessages);
        _pendingMessageIds
          ..clear()
          ..addAll(
            snapshot.pendingMessages.expand(
              (pending) => [
                pending.userMessageId,
                if (pending.assistantMessageId != null)
                  pending.assistantMessageId!,
              ],
            ),
          );
        _historyError = snapshot.syncError;
        _isHistoryLoadError = snapshot.syncError != null;
        _isLoadingHistory = false;
      });
      _scrollToBottom();

      if (_pendingMessages.isNotEmpty) {
        await _retryPendingMessages();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error;
        _isHistoryLoadError = true;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _message.text.trim();

    if (text.isEmpty || _isSending || _isLoadingHistory) return;

    late final AiPendingMessage pending;
    try {
      pending = await AiConversationService.queueUserMessage(
        message: text,
        conversationId: _conversationId,
        conversationTitle: _conversationTitle,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save your message locally: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _conversationId = pending.conversationId;
      _conversationTitle = pending.conversationTitle;
      _pendingMessages.add(pending);
      _pendingMessageIds.add(pending.userMessageId);
      _messages.add(
        AiChatMessage(
          id: pending.userMessageId,
          conversationId: pending.conversationId,
          userId: pending.userId,
          role: 'user',
          message: pending.message,
          createdAt: pending.createdAt,
        ),
      );
      _message.clear();
    });
    _scrollToBottom();
    await _retryPendingMessages();
  }

  Future<void> _retryPendingMessages() async {
    if (_isSending || _pendingMessages.isEmpty) return;
    for (final pending in List<AiPendingMessage>.of(_pendingMessages)) {
      if (!await _processPendingMessage(pending)) break;
    }
  }

  Future<bool> _processPendingMessage(AiPendingMessage initial) async {
    if (_isSending) return false;
    setState(() => _isSending = true);

    try {
      await AiConversationService.syncUserMessage(initial);
      var pending = initial;
      var reply = pending.assistantReply;

      if (reply == null) {
        final pendingIndex = _pendingMessages.indexWhere(
          (item) => item.userMessageId == pending.userMessageId,
        );
        final laterPendingIds = <String>{
          for (final item in _pendingMessages.skip(pendingIndex + 1)) ...[
            item.userMessageId,
            if (item.assistantMessageId != null) item.assistantMessageId!,
          ],
        };
        final history = _messages
            .where(
              (item) =>
                  item.id != pending.userMessageId &&
                  !laterPendingIds.contains(item.id),
            )
            .map((item) => {'role': item.role, 'content': item.message})
            .toList(growable: false);
        reply = await GeminiAssistantService.sendMessage(
          message: pending.message,
          history: history,
        );
        pending = await AiConversationService.saveAssistantReply(
          pending,
          reply,
        );
        if (!mounted) return false;
        setState(() {
          final index = _pendingMessages.indexWhere(
            (item) => item.userMessageId == pending.userMessageId,
          );
          if (index >= 0) _pendingMessages[index] = pending;
          _pendingMessageIds.add(pending.assistantMessageId!);
          _messages.add(
            AiChatMessage(
              id: pending.assistantMessageId!,
              conversationId: pending.conversationId,
              userId: pending.userId,
              role: 'assistant',
              message: reply!,
              createdAt: pending.assistantCreatedAt!,
            ),
          );
        });
      }

      await AiConversationService.syncAssistantReply(pending);
      await AiConversationService.removePendingMessage(pending);
      if (!mounted) return false;
      setState(() {
        _pendingMessages.removeWhere(
          (item) => item.userMessageId == pending.userMessageId,
        );
        _pendingMessageIds
          ..remove(pending.userMessageId)
          ..remove(pending.assistantMessageId);
        _historyError = null;
        _isSending = false;
      });
      _scrollToBottom();
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _historyError = error;
        _isSending = false;
      });
      _showMessageError(error);
      return false;
    }
  }

  void _showMessageError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message saved locally but could not sync: $error'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.green,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(back: true, dark: true),

            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/images/ai_lumin_logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'LUMIN',
                      style: TextStyle(
                        color: AppColors.dark,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),

                    const Text(
                      'Your AI Assistant',
                      style: TextStyle(color: AppColors.green),
                    ),

                    ValueListenableBuilder<PlanTier>(
                      valueListenable: PlanEntitlementStore.instance.tier,
                      builder: (context, tier, _) => Text(
                        tier == PlanTier.premium
                            ? 'Premium plan · No daily prompt limit'
                            : 'Basic plan · 10 prompts per day',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_isLoadingHistory)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Restoring your latest conversation…',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),

                    if (_historyError != null || _pendingMessages.isNotEmpty)
                      TextButton.icon(
                        onPressed: _isSending || _isLoadingHistory
                            ? null
                            : _pendingMessages.isEmpty || _isHistoryLoadError
                            ? _restoreConversation
                            : _retryPendingMessages,
                        icon: const Icon(Icons.sync, size: 16),
                        label: Text(
                          _pendingMessages.isEmpty
                              ? 'Retry loading conversation'
                              : 'Retry syncing ${_pendingMessages.length} message(s)',
                        ),
                      ),

                    // CHAT MESSAGES
                    Expanded(
                      child: ListView.builder(
                        controller: _chatScroll,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _messages.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const _ChatBubble(
                              text: 'Hi, grower! Ask me about plant care, light, or watering.',
                              fromAssistant: true,
                            );
                          }

                          final entry = _messages[index - 1];

                          return _ChatBubble(
                            text: entry.message,
                            fromAssistant: entry.fromAssistant,
                            pending: _pendingMessageIds.contains(entry.id),
                          );
                        },
                      ),
                    ),

                    // LOADING INDICATOR
                    if (_isSending)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: LinearProgressIndicator(
                          color: AppColors.green,
                          minHeight: 2,
                        ),
                      ),

                    const SizedBox(height: 12),

                    // MESSAGE INPUT
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _message,
                            onSubmitted: (_) => _sendMessage(),
                            textInputAction: TextInputAction.send,
                            enabled: !_isSending && !_isLoadingHistory,
                            maxLines: 4,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: 'Ask a plant question...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        IconButton.filled(
                          tooltip: 'Send message',
                          onPressed: _isSending || _isLoadingHistory
                              ? null
                              : _sendMessage,
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// CHAT BUBBLE WITH MARKDOWN SUPPORT
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.fromAssistant,
    this.pending = false,
  });

  final String text;
  final bool fromAssistant;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fromAssistant ? AppColors.background : AppColors.green,
          borderRadius: BorderRadius.circular(16),
        ),

        // RENDER MARKDOWN FOR AI RESPONSES
        child: Column(
          crossAxisAlignment: fromAssistant
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            if (fromAssistant)
              MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    color: AppColors.dark,
                    fontSize: 14,
                    height: 1.6,
                  ),

                  h1: const TextStyle(
                    color: AppColors.green,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),

                  h2: const TextStyle(
                    color: AppColors.green,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),

                  h3: const TextStyle(
                    color: AppColors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),

                  strong: const TextStyle(
                    color: AppColors.dark,
                    fontWeight: FontWeight.bold,
                  ),

                  em: const TextStyle(
                    color: AppColors.dark,
                    fontStyle: FontStyle.italic,
                  ),

                  listBullet: const TextStyle(
                    color: AppColors.green,
                    fontSize: 14,
                  ),

                  blockquote: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),

                  code: const TextStyle(
                    color: AppColors.green,
                    fontSize: 13,
                    backgroundColor: Color(0xFFE8F0E8),
                  ),
                ),
              )
            else
              SelectableText(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            if (pending) ...[
              const SizedBox(height: 4),
              Text(
                'Pending sync',
                style: TextStyle(
                  color: fromAssistant ? AppColors.muted : Colors.white70,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
