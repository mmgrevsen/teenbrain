/// What the app uses before an API key exists.
///
/// It fails, but it fails in one predictable way with one sentence the UI can
/// show — which is what lets every screen call the AI without first checking
/// whether there is one.
library;

import '../domain/services/ai_client.dart';

class UnconfiguredAiClient implements AiClient {
  const UnconfiguredAiClient([this.reason = _default]);

  static const _default =
      'Tilføj din egen API-nøgle under Indstillinger, så kan jeg hjælpe dig.';

  final String reason;

  @override
  String get id => 'unconfigured';

  @override
  String get modelLabel => 'Ingen model';

  @override
  bool get isConfigured => false;

  @override
  String get unconfiguredReason => reason;

  @override
  Stream<AiDelta> complete(AiRequest request) =>
      Stream.value(AiFailure(reason, kind: AiFailureKind.notConfigured));

  @override
  Future<T> structured<T>(AiRequest request, AiSchema<T> schema) =>
      Future.error(AiFailure(reason, kind: AiFailureKind.notConfigured));

  @override
  Future<AiHealth> check() async => AiHealth.down(reason);

  @override
  void dispose() {}
}
