/// Conversations with the assistant, as they are stored.
///
/// Distinct from `AiMessage` in `ai_client.dart`: that one is the wire format
/// for a provider. This one is a row in the user's own history.
library;

import 'package:meta/meta.dart';

enum ChatRole { user, assistant, system }

extension ChatRoleCodec on ChatRole {
  String get code => name;

  static ChatRole parse(String? code) => switch (code) {
        'assistant' => ChatRole.assistant,
        'system' => ChatRole.system,
        _ => ChatRole.user,
      };
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.toolCalls = const [],
  });

  final int id;
  final int conversationId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;

  /// Names of tools the assistant used to answer, so the UI can say
  /// "kiggede i dine noter" instead of pretending it knew.
  final List<String> toolCalls;
}
