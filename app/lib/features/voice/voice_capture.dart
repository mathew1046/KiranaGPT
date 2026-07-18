import 'package:flutter/foundation.dart';

/// The only information that crosses the voice-capture boundary is text.
///
/// Platform recognizers may use a short-lived audio buffer internally, but they
/// must discard it before completing [TransientTranscriptRecognizer]. This
/// package neither receives, stores, uploads, nor serializes raw audio.
typedef TransientTranscriptRecognizer = Future<String?> Function();

enum VoiceCaptureAvailability { transientRecognizer, manualOnly }

enum VoiceCaptureOutcome {
  transcriptReady,
  manualEntryRequired,
  cancelled,
  failed,
}

/// A capture result intentionally has no audio, path, byte, or recording field.
class VoiceCaptureResult {
  const VoiceCaptureResult._({
    required this.outcome,
    this.transcript,
    this.message,
  });

  factory VoiceCaptureResult.transcript(String transcript) {
    final cleanTranscript = transcript.trim();
    if (cleanTranscript.isEmpty) {
      return const VoiceCaptureResult.cancelled();
    }
    return VoiceCaptureResult._(
      outcome: VoiceCaptureOutcome.transcriptReady,
      transcript: cleanTranscript,
    );
  }

  const VoiceCaptureResult.manualEntryRequired({String? message})
    : this._(
        outcome: VoiceCaptureOutcome.manualEntryRequired,
        message: message,
      );

  const VoiceCaptureResult.cancelled({String? message})
    : this._(outcome: VoiceCaptureOutcome.cancelled, message: message);

  const VoiceCaptureResult.failed({String? message})
    : this._(outcome: VoiceCaptureOutcome.failed, message: message);

  final VoiceCaptureOutcome outcome;
  final String? transcript;
  final String? message;

  bool get hasTranscript =>
      outcome == VoiceCaptureOutcome.transcriptReady &&
      transcript != null &&
      transcript!.isNotEmpty;
}

/// Adapter boundary for an on-device speech recognizer.
///
/// The default implementation is deliberately safe on every platform: browser
/// builds and builds without an injected recognizer request manual text entry.
abstract interface class VoiceCapturePort {
  VoiceCaptureAvailability get availability;

  Future<VoiceCaptureResult> captureTranscript();
}

/// Privacy-preserving adapter for a native recognizer supplied by the host app.
///
/// There is no microphone package in this feature. A future Android integration
/// can inject a recognizer that returns a final transcript after discarding its
/// transient audio buffer. Web always uses the manual-entry fallback.
class PrivacySafeVoiceCapture implements VoiceCapturePort {
  PrivacySafeVoiceCapture({
    TransientTranscriptRecognizer? recognizer,
    bool? isWeb,
  }) : _recognizer = recognizer,
       _isWeb = isWeb ?? kIsWeb;

  final TransientTranscriptRecognizer? _recognizer;
  final bool _isWeb;

  @override
  VoiceCaptureAvailability get availability {
    if (_isWeb || _recognizer == null) {
      return VoiceCaptureAvailability.manualOnly;
    }
    return VoiceCaptureAvailability.transientRecognizer;
  }

  @override
  Future<VoiceCaptureResult> captureTranscript() async {
    final recognizer = _recognizer;
    if (_isWeb || recognizer == null) {
      return VoiceCaptureResult.manualEntryRequired(
        message: _isWeb
            ? 'Voice capture is not available in the browser. Type the approved transcript instead.'
            : 'Voice capture is not configured on this device. Type the approved transcript instead.',
      );
    }

    try {
      final transcript = await recognizer();
      if (transcript == null || transcript.trim().isEmpty) {
        return const VoiceCaptureResult.cancelled(
          message: 'No transcript was captured.',
        );
      }
      return VoiceCaptureResult.transcript(transcript);
    } catch (_) {
      // Do not expose platform exception details, which can include device data.
      return const VoiceCaptureResult.failed(
        message:
            'Voice capture could not finish. Type the approved transcript instead.',
      );
    }
  }
}
