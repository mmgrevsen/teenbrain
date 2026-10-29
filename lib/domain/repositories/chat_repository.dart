import '../models/chat.dart';

abstract class ChatRepository {
  Future<List<Conversation>> conversations({int limit = 50});
  Future<Conversation?> conversation(int id);
  Future<Conversation> createConversation({String? title});
  Future<void> renameConversation(int id, String title);
  Future<void> deleteConversation(int id);

  Future<List<ChatMessage>> messages(int conversationId);

  Future<ChatMessage> addMessage({
    required int conversationId,
    required ChatRole role,
    required String content,
    List<String> toolCalls = const [],
  });

  /// Replaces the text of a message already on screen — used to commit a
  /// streamed assistant reply once it has finished arriving.
  Future<void> updateMessage(int id, String content, {List<String>? toolCalls});

  Future<void> deleteMessage(int id);
}
