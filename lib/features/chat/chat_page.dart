/// The assistant.
///
/// Streams the reply as it arrives, and says which of the user's own data it
/// looked at — "kiggede i dine noter" is the difference between a chat window
/// and a second brain.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models/chat.dart';
import '../../domain/services/ai_client.dart';
import '../../shared/widgets/markdown_text.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, this.conversationId, this.initialMessage});

  final int? conversationId;
  final String? initialMessage;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  int? _conversationId;
  bool _sending = false;

  /// The reply as it streams in, before it is persisted.
  final StringBuffer _streaming = StringBuffer();
  final Set<String> _toolsUsed = {};
  AiFailure? _failure;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_conversationId == null) {
      final conversation = await ref.read(chatRepositoryProvider).createConversation();
      if (!mounted) return;
      setState(() => _conversationId = conversation.id);
      ref.read(dataRevisionProvider.notifier).bump();
    }
    final initial = widget.initialMessage;
    if (initial != null && initial.trim().isNotEmpty) {
      await _send(initial);
    }
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    final conversationId = _conversationId;
    if (message.isEmpty || conversationId == null || _sending) return;

    setState(() {
      _sending = true;
      _failure = null;
      _streaming.clear();
      _toolsUsed.clear();
    });
    _input.clear();

    final stream = ref.read(brainProvider).chat(
          conversationId: conversationId,
          message: message,
        );

    // The user's turn is already persisted by the service, so show it now.
    ref.read(dataRevisionProvider.notifier).bump();
    _scrollToEnd();

    try {
      await for (final delta in stream) {
        if (!mounted) return;
        switch (delta) {
          case AiTextDelta(:final text):
            setState(() => _streaming.write(text));
            _scrollToEnd();
          case AiToolDelta(:final toolName):
            setState(() => _toolsUsed.add(toolName));
          case AiFailure():
            setState(() => _failure = delta);
          case AiDone():
            break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _streaming.clear();
          _toolsUsed.clear();
        });
        ref.read(dataRevisionProvider.notifier).bump();
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ai = ref.watch(aiStackProvider);
    final conversationId = _conversationId;

    final messages = conversationId == null
        ? const <ChatMessage>[]
        : ref.watch(messagesProvider(conversationId)).value ?? const <ChatMessage>[];

    final inset = context.pageInset;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty && _streaming.isEmpty && !_sending
              ? _EmptyChat(configured: ai.isConfigured, reason: ai.unconfiguredReason)
              : ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(inset, 20, inset, 20),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: Insets.maxContent),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final message in messages)
                              _Bubble(message: message),
                            if (_sending) _StreamingBubble(
                              text: _streaming.toString(),
                              tools: _toolsUsed,
                            ),
                            if (_failure != null) ...[
                              const SizedBox(height: 8),
                              InlineError(
                                message: _failure!.message,
                                actionLabel: _failure!.kind == AiFailureKind.notConfigured
                                    ? 'Åbn indstillinger'
                                    : null,
                                onRetry: _failure!.kind == AiFailureKind.notConfigured
                                    ? () => ref
                                        .read(navigationProvider.notifier)
                                        .go(const SettingsRoute())
                                    : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Container(height: 1, color: colors.border),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, context.isCompact ? 12 : 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Insets.maxContent),
              child: _Composer(
                controller: _input,
                focusNode: _inputFocus,
                enabled: !_sending,
                onSend: () => _send(_input.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  const _EmptyChat({required this.configured, required this.reason});

  final bool configured;
  final String reason;

  static const _examples = [
    'Forklar fotosyntese',
    'Hvad skal jeg lave i dag?',
    'Lav en quiz ud fra mine noter',
    'Hvad har jeg svært ved?',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!configured) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EmptyState(
            icon: AppIcons.myAi,
            title: 'Jeg mangler en nøgle',
            message: reason,
            action: AppButton(
              label: 'Åbn indstillinger',
              tone: ButtonTone.primary,
              onPressed: () =>
                  ref.read(navigationProvider.notifier).go(const SettingsRoute()),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.pageInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Spørg mig om noget',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              for (final example in _examples)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () {
                      final state =
                          context.findAncestorStateOfType<_ChatPageState>();
                      state?._send(example);
                    },
                    child: Text(
                      example,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final colors = context.colors;

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(Insets.radius),
                border: Border.all(color: colors.accent.withValues(alpha: 0.18)),
              ),
              child: SelectableText(
                message.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.toolCalls.isNotEmpty) ...[
            _ToolNote(tools: message.toolCalls.toSet()),
            const SizedBox(height: 8),
          ],
          MarkdownText(message.content),
        ],
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text, required this.tools});

  final String text;
  final Set<String> tools;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tools.isNotEmpty) ...[
            _ToolNote(tools: tools),
            const SizedBox(height: 8),
          ],
          if (text.isEmpty) const ThinkingDots() else MarkdownText(text),
        ],
      ),
    );
  }
}

/// "Kiggede i dine noter" — what the assistant actually did to answer.
class _ToolNote extends StatelessWidget {
  const _ToolNote({required this.tools});
  final Set<String> tools;

  static const _labels = {
    'search_notes': 'kiggede i dine noter',
    'get_subject_status': 'slog dine fag op',
    'get_schedule': 'tjekkede dine deadlines',
    'create_note': 'gemte en note',
    'remember': 'huskede noget om dig',
  };

  @override
  Widget build(BuildContext context) {
    final described = tools.map((t) => _labels[t] ?? t).toList();
    if (described.isEmpty) return const SizedBox.shrink();

    final sentence = described.length == 1
        ? described.single
        : '${described.take(described.length - 1).join(', ')} og ${described.last}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.myAi, size: 12, color: context.colors.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${sentence[0].toUpperCase()}${sentence.substring(1)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              // Enter sends; Shift-Enter makes a new line, the way every chat
              // app the user already knows behaves.
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (enabled) onSend();
              },
            },
            child: AppTextField(
              controller: controller,
              focusNode: focusNode,
              hint: enabled ? 'Skriv en besked' : 'Vent lige …',
              minLines: 1,
              maxLines: 6,
              enabled: enabled,
              autofocus: true,
            ),
          ),
        ),
        const SizedBox(width: 10),
        AppButton(
          label: 'Send',
          tone: ButtonTone.primary,
          onPressed: enabled ? onSend : null,
        ),
      ],
    );
  }
}
