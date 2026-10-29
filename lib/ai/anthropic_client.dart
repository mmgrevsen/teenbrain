/// The Anthropic implementation of [AiClient].
///
/// Written against the raw Messages API over HTTP because Dart has no official
/// Anthropic SDK. This is the only file in TeenBrain that knows the wire
/// format; everything else programs against `AiClient`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/services/ai_client.dart';

/// Model identifiers. Kept together so a model change is one edit.
class AnthropicModels {
  const AnthropicModels._();

  /// The model the user talks to.
  static const chat = 'claude-opus-5';

  /// Background work the user never sees: extracting memories, naming a
  /// conversation. Cheap and fast matters more than depth here.
  static const background = 'claude-haiku-4-5';

  static const label = 'Claude Opus 5';
}

class AnthropicClient implements AiClient {
  AnthropicClient(this._apiKey, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// The API stops a runaway tool loop; this stops a runaway *turn*. Seven is
  /// well past what any of TeenBrain's tools need chained together.
  static const _maxToolRounds = 7;

  final String _apiKey;
  final http.Client _http;

  @override
  String get id => 'anthropic';

  @override
  String get modelLabel => AnthropicModels.label;

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  @override
  String get unconfiguredReason => 'Der er ingen API-nøgle endnu.';

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': _version,
      };

  // ------------------------------------------------------------- streaming

  @override
  Stream<AiDelta> complete(AiRequest request) async* {
    final messages = <Map<String, dynamic>>[
      for (final m in request.messages)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];

    final toolsUsed = <String>[];
    var inputTokens = 0;
    var outputTokens = 0;

    for (var round = 0; round < _maxToolRounds; round++) {
      final turn = _StreamedTurn();

      try {
        await for (final event in _stream(request, messages)) {
          switch (event) {
            case _TextChunk(:final text):
              turn.text.write(text);
              yield AiTextDelta(text);
            case _ToolStart(:final index, :final id, :final name):
              turn.beginTool(index, id, name);
              toolsUsed.add(name);
              yield AiToolDelta(name);
            case _ToolArgs(:final index, :final json):
              turn.appendToolArgs(index, json);
            case _Usage(:final input, :final output):
              inputTokens += input;
              outputTokens += output;
            case _StopReason(:final reason):
              turn.stopReason = reason;
          }
        }
      } on AiFailure catch (failure) {
        yield failure;
        return;
      } catch (e) {
        yield _classify(e);
        return;
      }

      // No tool call means the model is finished talking.
      if (turn.stopReason != 'tool_use' || turn.tools.isEmpty) {
        yield AiDone(
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          toolsUsed: toolsUsed,
        );
        return;
      }

      // Echo the assistant turn back verbatim, then answer every tool call in
      // one user message. Splitting results across messages teaches the model
      // to stop calling tools in parallel.
      messages.add({'role': 'assistant', 'content': turn.assistantContent()});
      messages.add({
        'role': 'user',
        'content': [
          for (final call in turn.tools)
            await _runTool(request.tools, call),
        ],
      });
    }

    yield const AiFailure(
      'Jeg kom til at slå for mange ting op i træk. Prøv at spørge lidt smallere.',
      kind: AiFailureKind.badRequest,
    );
  }

  Future<Map<String, dynamic>> _runTool(List<AiTool> available, _ToolCall call) async {
    final tool = available.where((t) => t.name == call.name).firstOrNull;
    if (tool == null) {
      return {
        'type': 'tool_result',
        'tool_use_id': call.id,
        'content': 'Værktøjet "${call.name}" findes ikke.',
        'is_error': true,
      };
    }

    try {
      final args = call.arguments();
      final result = await tool.run(args);
      return {'type': 'tool_result', 'tool_use_id': call.id, 'content': result};
    } catch (e) {
      // A failed lookup is information the model can work with, not a reason
      // to lose the whole turn.
      debugPrint('Værktøjet ${call.name} fejlede: $e');
      return {
        'type': 'tool_result',
        'tool_use_id': call.id,
        'content': 'Opslaget fejlede: $e',
        'is_error': true,
      };
    }
  }

  /// One streamed request. Emits parsed SSE events, or throws [AiFailure].
  Stream<_Event> _stream(AiRequest request, List<Map<String, dynamic>> messages) async* {
    final body = _body(request, messages, stream: true);

    final httpRequest = http.Request('POST', Uri.parse(_endpoint))
      ..headers.addAll(_headers)
      ..body = jsonEncode(body);

    final response = await _http.send(httpRequest);

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      throw _failureFor(response.statusCode, text);
    }

    // SSE frames are separated by a blank line; a frame's payload is its
    // `data:` line. Decoding line by line keeps memory flat on a long answer.
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(payload) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      switch (event['type']) {
        case 'content_block_start':
          final block = event['content_block'] as Map<String, dynamic>?;
          if (block?['type'] == 'tool_use') {
            yield _ToolStart(
              index: event['index'] as int? ?? 0,
              id: block!['id'] as String,
              name: block['name'] as String,
            );
          }

        case 'content_block_delta':
          final delta = event['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              yield _TextChunk(delta!['text'] as String? ?? '');
            case 'input_json_delta':
              yield _ToolArgs(
                index: event['index'] as int? ?? 0,
                json: delta!['partial_json'] as String? ?? '',
              );
          }

        case 'message_start':
          final usage =
              (event['message'] as Map<String, dynamic>?)?['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            yield _Usage(input: usage['input_tokens'] as int? ?? 0, output: 0);
          }

        case 'message_delta':
          final delta = event['delta'] as Map<String, dynamic>?;
          final reason = delta?['stop_reason'] as String?;
          if (reason != null) yield _StopReason(reason);
          final usage = event['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            yield _Usage(input: 0, output: usage['output_tokens'] as int? ?? 0);
          }

        case 'error':
          final error = event['error'] as Map<String, dynamic>?;
          throw AiFailure(
            _danishFor(error?['type'] as String?, error?['message'] as String?),
            kind: _kindFor(error?['type'] as String?),
          );
      }
    }
  }

  // ---------------------------------------------------------- structured

  @override
  Future<T> structured<T>(AiRequest request, AiSchema<T> schema) async {
    // Forced tool use rather than "please reply with JSON": the API enforces
    // the schema, prose does not. `strict` makes the arguments validate exactly.
    final body = _body(
      request,
      [
        for (final m in request.messages)
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
      ],
      stream: false,
      tools: [
        {
          'name': schema.name,
          'description': schema.description,
          'input_schema': schema.schema,
          'strict': true,
        }
      ],
      toolChoice: {'type': 'tool', 'name': schema.name},
    );

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      throw _classify(e);
    }

    if (response.statusCode != 200) {
      throw _failureFor(response.statusCode, response.body);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (decoded['stop_reason'] == 'refusal') {
      throw const AiFailure(
        'Jeg kunne ikke svare på det her. Prøv at formulere det på en anden måde.',
        kind: AiFailureKind.badRequest,
      );
    }

    for (final block in (decoded['content'] as List? ?? const [])) {
      final map = block as Map<String, dynamic>;
      if (map['type'] == 'tool_use' && map['name'] == schema.name) {
        return schema.parse(map['input'] as Map<String, dynamic>);
      }
    }

    throw const AiFailure(
      'Jeg fik ikke et brugbart svar tilbage. Prøv igen.',
      kind: AiFailureKind.unknown,
    );
  }

  // --------------------------------------------------------------- health

  @override
  Future<AiHealth> check() async {
    if (!isConfigured) return AiHealth.down(unconfiguredReason);
    try {
      final response = await _http.post(
        Uri.parse(_endpoint),
        headers: _headers,
        body: jsonEncode({
          'model': AnthropicModels.background,
          'max_tokens': 4,
          'messages': [
            {'role': 'user', 'content': 'ping'}
          ],
        }),
      );
      if (response.statusCode == 200) return const AiHealth.ok(AnthropicModels.label);
      final failure = _failureFor(response.statusCode, response.body);
      return AiHealth.down(failure.message);
    } catch (e) {
      return AiHealth.down(_classify(e).message);
    }
  }

  @override
  void dispose() => _http.close();

  // ---------------------------------------------------------------- shared

  Map<String, dynamic> _body(
    AiRequest request,
    List<Map<String, dynamic>> messages, {
    required bool stream,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? toolChoice,
  }) {
    final declared = tools ??
        [
          for (final t in request.tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parameters,
            }
        ];

    return {
      'model': request.model ?? AnthropicModels.chat,
      'max_tokens': request.maxTokens,
      if (stream) 'stream': true,
      // The system prompt is the stable prefix and is worth caching: it carries
      // the memory context, which changes far less often than the question does.
      'system': [
        {
          'type': 'text',
          'text': request.system,
          'cache_control': {'type': 'ephemeral'},
        }
      ],
      'messages': messages,
      if (declared.isNotEmpty) 'tools': declared,
      'tool_choice': ?toolChoice,
      'output_config': {'effort': request.effort.code},
    };
  }

  AiFailure _failureFor(int status, String rawBody) {
    String? type;
    String? message;
    try {
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      type = error?['type'] as String?;
      message = error?['message'] as String?;
    } catch (_) {
      // Not JSON; the status code alone has to carry the meaning.
    }

    return AiFailure(
      switch (status) {
        401 || 403 => 'API-nøglen blev afvist. Tjek den under Indstillinger.',
        429 => 'Der er for mange forespørgsler lige nu. Vent et øjeblik.',
        400 => _danishFor(type, message),
        529 => 'Claude er overbelastet lige nu. Prøv igen om lidt.',
        _ when status >= 500 => 'Der er problemer med serveren. Prøv igen om lidt.',
        _ => _danishFor(type, message),
      },
      kind: switch (status) {
        401 || 403 => AiFailureKind.auth,
        429 => AiFailureKind.rateLimit,
        400 => AiFailureKind.badRequest,
        529 => AiFailureKind.overloaded,
        _ when status >= 500 => AiFailureKind.overloaded,
        _ => AiFailureKind.unknown,
      },
    );
  }

  AiFailure _classify(Object error) {
    if (error is AiFailure) return error;
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('connection') ||
        text.contains('network')) {
      return const AiFailure(
        'Der er ingen forbindelse til internettet.',
        kind: AiFailureKind.network,
      );
    }
    return AiFailure('Noget gik galt: $error');
  }

  String _danishFor(String? type, String? message) => switch (type) {
        'authentication_error' => 'API-nøglen blev afvist. Tjek den under Indstillinger.',
        'permission_error' => 'Nøglen har ikke adgang til den model.',
        'rate_limit_error' => 'Der er for mange forespørgsler lige nu. Vent et øjeblik.',
        'overloaded_error' => 'Claude er overbelastet lige nu. Prøv igen om lidt.',
        _ => message == null || message.isEmpty ? 'Noget gik galt undervejs.' : message,
      };

  AiFailureKind _kindFor(String? type) => switch (type) {
        'authentication_error' || 'permission_error' => AiFailureKind.auth,
        'rate_limit_error' => AiFailureKind.rateLimit,
        'overloaded_error' => AiFailureKind.overloaded,
        'invalid_request_error' => AiFailureKind.badRequest,
        _ => AiFailureKind.unknown,
      };
}

// ---------------------------------------------------------------- internals

/// Accumulates one assistant turn as it streams in.
class _StreamedTurn {
  final StringBuffer text = StringBuffer();
  final List<_ToolCall> tools = [];
  String? stopReason;

  /// Blocks are keyed by their stream index, not by arrival order: when the
  /// model calls two tools in one turn, their argument deltas carry different
  /// indices, and appending both to whichever block started last would splice
  /// two JSON documents into one unparseable string.
  final Map<int, _ToolCall> _byIndex = {};

  void beginTool(int index, String id, String name) {
    final call = _ToolCall(id: id, name: name);
    tools.add(call);
    _byIndex[index] = call;
  }

  void appendToolArgs(int index, String json) {
    _byIndex[index]?.raw.write(json);
  }

  /// The assistant turn in the shape the API wants it echoed back.
  List<Map<String, dynamic>> assistantContent() => [
        if (text.isNotEmpty) {'type': 'text', 'text': text.toString()},
        for (final call in tools)
          {
            'type': 'tool_use',
            'id': call.id,
            'name': call.name,
            'input': call.arguments(),
          },
      ];
}

class _ToolCall {
  _ToolCall({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer raw = StringBuffer();

  /// Tool arguments arrive as a stream of JSON fragments. Never string-match
  /// them — decode.
  Map<String, dynamic> arguments() {
    final text = raw.toString();
    if (text.trim().isEmpty) return const {};
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}

sealed class _Event {
  const _Event();
}

class _TextChunk extends _Event {
  const _TextChunk(this.text);
  final String text;
}

class _ToolStart extends _Event {
  const _ToolStart({required this.index, required this.id, required this.name});
  final int index;
  final String id;
  final String name;
}

class _ToolArgs extends _Event {
  const _ToolArgs({required this.index, required this.json});
  final int index;
  final String json;
}

class _Usage extends _Event {
  const _Usage({required this.input, required this.output});
  final int input;
  final int output;
}

class _StopReason extends _Event {
  const _StopReason(this.reason);
  final String reason;
}
