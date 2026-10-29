import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/chat.dart';
import '../../domain/models/search.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/search_index.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteChatRepository implements ChatRepository {
  SqliteChatRepository(this._local, {SearchIndex? searchIndex}) : _search = searchIndex;

  final LocalDatabase _local;
  final SearchIndex? _search;
  Database get _db => _local.db;

  @override
  Future<List<Conversation>> conversations({int limit = 50}) async {
    return _db
        .select('SELECT * FROM conversations ORDER BY updated_at DESC LIMIT ?', [limit])
        .map(_conversation)
        .toList();
  }

  @override
  Future<Conversation?> conversation(int id) async {
    final rows = _db.select('SELECT * FROM conversations WHERE id = ?', [id]);
    return rows.isEmpty ? null : _conversation(rows.first);
  }

  @override
  Future<Conversation> createConversation({String? title}) async {
    final now = ms(DateTime.now());
    _db.execute(
      'INSERT INTO conversations (title, created_at, updated_at) VALUES (?, ?, ?)',
      [title?.trim().isNotEmpty == true ? title!.trim() : 'Ny samtale', now, now],
    );
    return (await conversation(_db.lastInsertRowId))!;
  }

  @override
  Future<void> renameConversation(int id, String title) async {
    _db.execute('UPDATE conversations SET title = ? WHERE id = ?', [title.trim(), id]);
    final c = await conversation(id);
    if (c != null) await _index(c);
  }

  @override
  Future<void> deleteConversation(int id) async {
    _db.execute('DELETE FROM conversations WHERE id = ?', [id]);
    await _search?.remove(SearchScope.conversation, id);
  }

  @override
  Future<List<ChatMessage>> messages(int conversationId) async {
    return _db
        .select('SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at, id',
            [conversationId])
        .map(_message)
        .toList();
  }

  @override
  Future<ChatMessage> addMessage({
    required int conversationId,
    required ChatRole role,
    required String content,
    List<String> toolCalls = const [],
  }) async {
    final now = ms(DateTime.now());
    _db.execute(
      'INSERT INTO messages (conversation_id, role, content, created_at, tool_calls_json) '
      'VALUES (?, ?, ?, ?, ?)',
      [conversationId, role.code, content, now, toolCalls.isEmpty ? null : jsonEncode(toolCalls)],
    );
    final id = _db.lastInsertRowId;
    _db.execute('UPDATE conversations SET updated_at = ? WHERE id = ?', [now, conversationId]);

    final conversation = await this.conversation(conversationId);
    if (conversation != null) await _index(conversation);

    final rows = _db.select('SELECT * FROM messages WHERE id = ?', [id]);
    return _message(rows.first);
  }

  @override
  Future<void> updateMessage(int id, String content, {List<String>? toolCalls}) async {
    _db.execute(
      'UPDATE messages SET content = ?, tool_calls_json = COALESCE(?, tool_calls_json) WHERE id = ?',
      [content, toolCalls == null || toolCalls.isEmpty ? null : jsonEncode(toolCalls), id],
    );
  }

  @override
  Future<void> deleteMessage(int id) async {
    _db.execute('DELETE FROM messages WHERE id = ?', [id]);
  }

  /// A conversation is searchable by its title and the text of its turns, so
  /// "hvad lavede jeg med matematik i sidste uge" can land on the actual talk.
  Future<void> _index(Conversation c) async {
    final body = _db
        .select('SELECT content FROM messages WHERE conversation_id = ? ORDER BY id LIMIT 40',
            [c.id])
        .map((r) => r['content'] as String)
        .join('\n');
    await _search?.index(
      scope: SearchScope.conversation,
      refId: c.id,
      title: c.title,
      body: body,
      occurredAt: c.updatedAt,
    );
  }

  Conversation _conversation(Row row) => Conversation(
        id: intOf(row['id']),
        title: row['title'] as String,
        createdAt: timeOf(row['created_at']),
        updatedAt: timeOf(row['updated_at']),
      );

  ChatMessage _message(Row row) {
    final raw = row['tool_calls_json'] as String?;
    return ChatMessage(
      id: intOf(row['id']),
      conversationId: intOf(row['conversation_id']),
      role: ChatRoleCodec.parse(row['role'] as String?),
      content: row['content'] as String,
      createdAt: timeOf(row['created_at']),
      toolCalls: raw == null
          ? const []
          : (jsonDecode(raw) as List).map((e) => e as String).toList(),
    );
  }
}
