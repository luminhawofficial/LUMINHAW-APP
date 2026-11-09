import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/gemini_assistant_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _message = TextEditingController();
  final _chatScroll = ScrollController();

  final List<_ChatEntry> _messages = [];

  bool _isSending = false;

  @override
  void dispose() {
    _message.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _message.text.trim();

    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      final reply = await GeminiAssistantService.sendMessage(
        message: text,
        history: _messages
            .map(
              (entry) => {
                'role': entry.fromAssistant ? 'assistant' : 'user',
                'content': entry.text,
              },
            )
            .toList(growable: false),
      );

      if (!mounted) return;

      setState(() {
        _messages
          ..add(_ChatEntry(text: text, fromAssistant: false))
          ..add(_ChatEntry(text: reply, fromAssistant: true));

        _message.clear();
        _isSending = false;
      });

      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;

      setState(() => _isSending = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send message: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

                    const Text(
                      'Free: 10 messages daily · Premium: unlimited',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),

                    const SizedBox(height: 24),

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
                            text: entry.text,
                            fromAssistant: entry.fromAssistant,
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
                            enabled: !_isSending,
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
                          onPressed: _isSending ? null : _sendMessage,
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

// CHAT ENTRY MODEL
class _ChatEntry {
  const _ChatEntry({required this.text, required this.fromAssistant});

  final String text;
  final bool fromAssistant;
}

// CHAT BUBBLE WITH MARKDOWN SUPPORT
class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.fromAssistant});

  final String text;
  final bool fromAssistant;

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
        child: fromAssistant
            ? MarkdownBody(
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
            // NORMAL TEXT FOR USER MESSAGES
            : SelectableText(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
      ),
    );
  }
}
