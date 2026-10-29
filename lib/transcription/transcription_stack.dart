/// Chooses the speech backend for the platform.
///
/// The *only* place in TeenBrain that names a concrete recogniser — the same
/// rule `ai_stack.dart` and `vision_stack.dart` follow. A cloud recogniser, or
/// Windows speech, is a branch here plus one class.
library;

import 'dart:io';

import '../domain/services/transcriber.dart';
import 'apple/apple_transcriber.dart';
import 'fallback/unavailable_transcriber.dart';

class TranscriptionStack {
  const TranscriptionStack._();

  static Transcriber forCurrentPlatform() {
    if (Platform.isMacOS) return AppleTranscriber();
    return UnavailableTranscriber(platformTranscriptionExplanation());
  }
}
