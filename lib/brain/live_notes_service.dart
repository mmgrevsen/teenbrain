/// One Live Notes session.
///
/// Owns the awkward parts so the page does not have to: the two OS grants, the
/// difference between a revision and a finished sentence, a recogniser that can
/// stop on its own, and the rule that nothing records unless the user switched
/// the microphone on in Privacy.
///
/// It accumulates text and nothing else. Audio is never written to disk, and
/// there is no buffer to delete afterwards, because there is no buffer.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/services/transcriber.dart';

enum LiveNotesStatus { idle, starting, listening, stopping, error }

@immutable
class LiveNotesState {
  const LiveNotesState({
    this.status = LiveNotesStatus.idle,
    this.committed = '',
    this.pending = '',
    this.error,
    this.startedAt,
  });

  final LiveNotesStatus status;

  /// Sentences the recogniser has finished revising.
  final String committed;

  /// The sentence it is still working on. Shown live, greyed out, and folded
  /// into [committed] when it settles.
  final String pending;

  final String? error;
  final DateTime? startedAt;

  bool get isListening => status == LiveNotesStatus.listening;
  bool get isBusy =>
      status == LiveNotesStatus.starting || status == LiveNotesStatus.stopping;

  /// Everything heard so far, live sentence included.
  String get transcript {
    if (pending.trim().isEmpty) return committed;
    return committed.isEmpty ? pending : '$committed $pending';
  }

  bool get hasText => transcript.trim().isNotEmpty;

  int get wordCount {
    final text = transcript.trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  Duration? elapsed(DateTime now) =>
      startedAt == null ? null : now.difference(startedAt!);

  LiveNotesState copyWith({
    LiveNotesStatus? status,
    String? committed,
    String? pending,
    String? error,
    bool clearError = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
  }) =>
      LiveNotesState(
        status: status ?? this.status,
        committed: committed ?? this.committed,
        pending: pending ?? this.pending,
        error: clearError ? null : (error ?? this.error),
        startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      );
}

class LiveNotesService {
  LiveNotesService({
    required this.transcriber,
    required this.microphoneEnabled,
  });

  final Transcriber transcriber;

  /// The Privacy page's microphone switch. Read per call, so turning it off
  /// takes effect without rebuilding the service.
  final bool Function() microphoneEnabled;

  final StreamController<LiveNotesState> _states =
      StreamController<LiveNotesState>.broadcast();

  StreamSubscription<TranscriptSegment>? _segments;
  LiveNotesState _state = const LiveNotesState();

  LiveNotesState get state => _state;
  Stream<LiveNotesState> get states => _states.stream;

  bool get isSupported => transcriber.isSupported;
  String get unsupportedExplanation => transcriber.unsupportedExplanation;
  String get backendLabel => transcriber.backendLabel;
  bool get isOnDevice => transcriber.isOnDevice;

  void _emit(LiveNotesState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<TranscriberAccess> checkPermission() => transcriber.checkPermission();

  /// Starts listening.
  ///
  /// Returns false when it could not start; [state] then carries the reason in
  /// language the page can show directly.
  Future<bool> start({String localeId = 'da-DK'}) async {
    if (_state.isListening || _state.isBusy) return false;

    if (!transcriber.isSupported) {
      _emit(_state.copyWith(
        status: LiveNotesStatus.error,
        error: transcriber.unsupportedExplanation,
      ));
      return false;
    }

    if (!microphoneEnabled()) {
      _emit(_state.copyWith(
        status: LiveNotesStatus.error,
        error: 'Mikrofonen er slået fra. Slå den til under Privatliv, '
            'hvis du vil bruge Live Notes.',
      ));
      return false;
    }

    _emit(_state.copyWith(status: LiveNotesStatus.starting, clearError: true));

    var access = await transcriber.checkPermission();
    if (access.canAsk) access = await transcriber.requestPermission();

    if (!access.isGranted) {
      _emit(_state.copyWith(
        status: LiveNotesStatus.error,
        error: access.blockedReason ?? 'Der mangler adgang til mikrofonen.',
      ));
      return false;
    }

    _segments ??= transcriber.segments.listen(
      _onSegment,
      onError: (Object error) {
        final message = error is TranscriberException
            ? error.message
            : 'Optagelsen stoppede: $error';
        _emit(_state.copyWith(status: LiveNotesStatus.error, error: message));
      },
    );

    try {
      await transcriber.start(localeId: localeId);
    } on TranscriberException catch (e) {
      _emit(_state.copyWith(status: LiveNotesStatus.error, error: e.message));
      return false;
    } catch (e) {
      _emit(_state.copyWith(
        status: LiveNotesStatus.error,
        error: 'Kunne ikke starte optagelsen: $e',
      ));
      return false;
    }

    _emit(_state.copyWith(
      status: LiveNotesStatus.listening,
      startedAt: _state.startedAt ?? DateTime.now(),
      clearError: true,
    ));
    return true;
  }

  void _onSegment(TranscriptSegment segment) {
    if (segment.isEmpty) return;

    // The recogniser revises one utterance repeatedly and then marks it final.
    // Until then it is pending; after, it joins the committed text and the
    // next utterance starts from nothing.
    if (segment.isFinal) {
      final joined = _state.committed.isEmpty
          ? segment.text.trim()
          : '${_state.committed} ${segment.text.trim()}';
      _emit(_state.copyWith(committed: joined, pending: ''));
    } else {
      _emit(_state.copyWith(pending: segment.text.trim()));
    }
  }

  /// Stops listening and returns everything that was heard.
  Future<String> stop() async {
    if (!_state.isListening && _state.status != LiveNotesStatus.starting) {
      return _state.transcript;
    }

    _emit(_state.copyWith(status: LiveNotesStatus.stopping));
    await transcriber.stop();

    // The last utterance may still be pending when the engine stops; keeping
    // it is better than dropping the final sentence of a lesson.
    final transcript = _state.transcript.trim();
    _emit(_state.copyWith(
      status: LiveNotesStatus.idle,
      committed: transcript,
      pending: '',
    ));
    return transcript;
  }

  /// Throws the transcript away. Called after it has become a note, and by the
  /// page's own clear button.
  void reset() {
    _emit(const LiveNotesState());
  }

  Future<void> dispose() async {
    await _segments?.cancel();
    _segments = null;
    try {
      await transcriber.dispose();
    } catch (e) {
      debugPrint('Kunne ikke lukke talegenkendelsen rent: $e');
    }
    await _states.close();
  }
}
