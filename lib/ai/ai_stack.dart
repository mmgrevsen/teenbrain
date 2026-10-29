/// Chooses the AI backend.
///
/// This is the *only* place in TeenBrain that names a concrete provider —
/// the same rule `vision_stack.dart` follows for computer vision. A local
/// model, or a proxy holding a shared key, is a branch here plus one class.
library;

import 'package:http/http.dart' as http;

import '../domain/services/ai_client.dart';
import 'anthropic_client.dart';
import 'unconfigured_client.dart';

class AiStack {
  const AiStack._();

  /// Builds a client for the key the user has stored, or the unconfigured
  /// stand-in when there is none.
  static AiClient forKey(String? apiKey, {http.Client? httpClient}) {
    if (apiKey == null || apiKey.trim().isEmpty) {
      return const UnconfiguredAiClient();
    }
    return AnthropicClient(apiKey.trim(), httpClient: httpClient);
  }
}
