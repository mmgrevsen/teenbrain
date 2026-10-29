/// The seam between TeenBrain and whatever language model is behind it.
///
/// Nothing in this file names Anthropic, and nothing outside `lib/ai/` may.
/// Swapping in a local model, or a proxy that holds a shared key, means writing
/// one class and adding a branch to `ai_stack.dart` — the rest of the app does
/// not notice.
library;

import 'package:meta/meta.dart';

/// A turn in the conversation as the provider sees it.
@immutable
class AiMessage {
  const AiMessage.user(this.text) : isUser = true;
  const AiMessage.assistant(this.text) : isUser = false;

  final String text;
  final bool isUser;
}

/// A capability the model may invoke to reach the user's own data.
///
/// This is what separates TeenBrain from a chat window: the model can look
/// things up and write things down instead of guessing.
@immutable
class AiTool {
  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.run,
  });

  final String name;
  final String description;

  /// JSON Schema for the arguments, as a plain map.
  final Map<String, dynamic> parameters;

  /// Executes the call and returns what the model should see. Errors are
  /// returned as text, not thrown: a failed lookup is information the model can
  /// work with, not a reason to lose the whole turn.
  final Future<String> Function(Map<String, dynamic> args) run;
}

@immutable
class AiRequest {
  const AiRequest({
    required this.system,
    required this.messages,
    this.tools = const [],
    this.maxTokens = 2048,
    this.effort = AiEffort.low,
    this.model,
  });

  /// The system prompt, memory context already spliced in.
  final String system;

  final List<AiMessage> messages;
  final List<AiTool> tools;
  final int maxTokens;

  /// How hard the model should think. Sampling knobs (temperature, top_p) are
  /// deliberately absent: the current Claude models reject them outright, and
  /// effort is the parameter that actually trades quality against latency.
  /// A teenager waiting for an explanation notices latency, so chat runs low.
  final AiEffort effort;

  /// Overrides the client's default model. Used to send cheap background work
  /// (memory extraction, titles) to a smaller model.
  final String? model;
}

enum AiEffort { low, medium, high }

extension AiEffortCode on AiEffort {
  String get code => name;
}

/// One piece of a streaming reply.
sealed class AiDelta {
  const AiDelta();
}

/// Text arriving token by token.
class AiTextDelta extends AiDelta {
  const AiTextDelta(this.text);
  final String text;
}

/// The model decided to use a tool. Emitted so the UI can say what it is doing
/// while it happens.
class AiToolDelta extends AiDelta {
  const AiToolDelta(this.toolName);
  final String toolName;
}

/// The turn finished cleanly.
class AiDone extends AiDelta {
  const AiDone({this.inputTokens = 0, this.outputTokens = 0, this.toolsUsed = const []});
  final int inputTokens;
  final int outputTokens;
  final List<String> toolsUsed;
}

/// Something went wrong, in language a teenager can act on.
class AiFailure extends AiDelta implements Exception {
  const AiFailure(this.message, {this.kind = AiFailureKind.unknown});

  final String message;
  final AiFailureKind kind;

  @override
  String toString() => message;
}

enum AiFailureKind { notConfigured, auth, rateLimit, network, overloaded, badRequest, unknown }

/// Describes a structured output the model must produce.
///
/// Implemented on top of tool use rather than "please reply with JSON", because
/// the former is enforced by the API and the latter is a wish.
@immutable
class AiSchema<T> {
  const AiSchema({
    required this.name,
    required this.description,
    required this.schema,
    required this.parse,
  });

  final String name;
  final String description;
  final Map<String, dynamic> schema;

  /// Turns the model's arguments into a typed value. Throws on malformed input
  /// so the caller can retry rather than store nonsense.
  final T Function(Map<String, dynamic> json) parse;
}

/// Whether the client can actually reach a model right now.
@immutable
class AiHealth {
  const AiHealth({required this.ok, required this.message, this.model});

  const AiHealth.ok(this.model) : ok = true, message = 'Forbundet';
  const AiHealth.down(this.message) : ok = false, model = null;

  final bool ok;
  final String message;
  final String? model;
}

abstract class AiClient {
  /// Stable identifier, e.g. `anthropic`.
  String get id;

  /// What to show the user: "Claude Opus 5".
  String get modelLabel;

  /// False when there is no key, or no model. The UI uses this to offer setup
  /// instead of failing on send.
  bool get isConfigured;

  /// Why it is not configured, in Danish, for the empty state.
  String get unconfiguredReason;

  /// Streams a reply, running any tool calls the model makes along the way.
  Stream<AiDelta> complete(AiRequest request);

  /// Forces a typed result out of the model.
  Future<T> structured<T>(AiRequest request, AiSchema<T> schema);

  /// A cheap round trip to prove the key works. Used by Settings.
  Future<AiHealth> check();

  void dispose();
}
