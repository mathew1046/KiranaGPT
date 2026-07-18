import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/core/api/voice_transcription_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';

enum VoiceCaptureAvailability { continuousVad, manualOnly }

enum VoiceCaptureOutcome {
  listening,
  transcriptReady,
  manualEntryRequired,
  cancelled,
  failed,
}

class VoiceCaptureResult {
  const VoiceCaptureResult._({
    required this.outcome,
    this.transcript,
    this.message,
  });

  const VoiceCaptureResult.listening()
    : this._(outcome: VoiceCaptureOutcome.listening);

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
    : this._(outcome: VoiceCaptureOutcome.manualEntryRequired, message: message);

  const VoiceCaptureResult.cancelled({String? message})
    : this._(outcome: VoiceCaptureOutcome.cancelled, message: message);

  const VoiceCaptureResult.failed({String? message})
    : this._(outcome: VoiceCaptureOutcome.failed, message: message);

  final VoiceCaptureOutcome outcome;
  final String? transcript;
  final String? message;
}

typedef VoiceCaptureListener = void Function(VoiceCaptureResult result);

/// A continuous listener: VAD stays active between speech turns until stopped.
abstract interface class VoiceCapturePort {
  VoiceCaptureAvailability get availability;
  bool get isListening;

  Future<VoiceCaptureResult> startListening(VoiceCaptureListener onResult);
  Future<VoiceCaptureResult> stopListening();
  Future<void> dispose();
}

/// Browser and unsupported-device fallback; manual entry remains available.
class UnavailableVoiceCapture implements VoiceCapturePort {
  @override
  VoiceCaptureAvailability get availability => VoiceCaptureAvailability.manualOnly;

  @override
  bool get isListening => false;

  @override
  Future<VoiceCaptureResult> startListening(VoiceCaptureListener onResult) async =>
      const VoiceCaptureResult.manualEntryRequired(
        message: 'Voice capture is not available on this device. Type the transcript instead.',
      );

  @override
  Future<VoiceCaptureResult> stopListening() async => const VoiceCaptureResult.cancelled();

  @override
  Future<void> dispose() async {}
}

/// On-device Silero VAD followed by server-side Whisper transcription.
///
/// Audio segments exist only in memory. They are converted to a short WAV,
/// posted to the protected backend, then released; they are never stored by
/// the app or backend.
class ContinuousVadVoiceCapture implements VoiceCapturePort {
  ContinuousVadVoiceCapture({required VoiceTranscriptionGateway transcriber})
    : _transcriber = transcriber;

  final VoiceTranscriptionGateway _transcriber;
  VadHandler? _vad;
  StreamSubscription<List<double>>? _speechEndSubscription;
  StreamSubscription<String>? _errorSubscription;
  Future<void> _transcriptionTail = Future<void>.value();
  VoiceCaptureListener? _onResult;
  bool _isListening = false;
  bool _isDisposed = false;

  @override
  VoiceCaptureAvailability get availability => kIsWeb
      ? VoiceCaptureAvailability.manualOnly
      : VoiceCaptureAvailability.continuousVad;

  @override
  bool get isListening => _isListening;

  @override
  Future<VoiceCaptureResult> startListening(VoiceCaptureListener onResult) async {
    if (kIsWeb) {
      return const VoiceCaptureResult.manualEntryRequired(
        message: 'Continuous voice capture is available in the Android app only.',
      );
    }
    if (_isDisposed) {
      return const VoiceCaptureResult.failed(message: 'Voice capture is no longer available.');
    }
    if (_isListening) {
      return const VoiceCaptureResult.listening();
    }

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      return const VoiceCaptureResult.manualEntryRequired(
        message: 'Allow microphone access to use continuous voice capture.',
      );
    }

    try {
      _onResult = onResult;
      final vad = _vad ??= VadHandler.create();
      _speechEndSubscription ??= vad.onSpeechEnd.listen(_queueTranscription);
      _errorSubscription ??= vad.onError.listen((_) {
        _onResult?.call(const VoiceCaptureResult.failed(
          message: 'Voice detection stopped. Start listening again or type the transcript.',
        ));
      });
      await vad.startListening(model: 'v5');
      _isListening = true;
      return const VoiceCaptureResult.listening();
    } catch (_) {
      return const VoiceCaptureResult.failed(
        message: 'Voice capture could not start. Type the transcript instead.',
      );
    }
  }

  @override
  Future<VoiceCaptureResult> stopListening() async {
    if (!_isListening) {
      return const VoiceCaptureResult.cancelled();
    }
    try {
      await _vad?.stopListening();
      _isListening = false;
      return const VoiceCaptureResult.cancelled(message: 'Voice capture stopped.');
    } catch (_) {
      _isListening = false;
      return const VoiceCaptureResult.failed(message: 'Voice capture could not stop cleanly.');
    }
  }

  void _queueTranscription(List<double> samples) {
    if (samples.isEmpty || !_isListening) {
      return;
    }
    // Keep each utterance short even if a user speaks continuously. The VAD
    // stays live afterwards and will capture the next turn independently.
    const maxSamples = 16000 * 8;
    final boundedSamples = samples.length > maxSamples
        ? samples.sublist(0, maxSamples)
        : samples;
    _transcriptionTail = _transcriptionTail.then((_) => _transcribe(boundedSamples));
  }

  Future<void> _transcribe(List<double> samples) async {
    try {
      final transcript = await _transcriber.transcribeWav(_pcm16Wav(samples));
      _onResult?.call(VoiceCaptureResult.transcript(transcript));
    } on VoiceTranscriptionException catch (error) {
      _onResult?.call(VoiceCaptureResult.failed(message: error.message));
    } catch (_) {
      _onResult?.call(const VoiceCaptureResult.failed(
        message: 'Speech transcription could not finish. Try again or type the transcript.',
      ));
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await stopListening();
    await _speechEndSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _vad?.dispose();
  }
}

Uint8List _pcm16Wav(List<double> samples, {int sampleRate = 16000}) {
  final bytes = ByteData(44 + (samples.length * 2));
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  final dataLength = samples.length * 2;
  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index].clamp(-1.0, 1.0);
    bytes.setInt16(44 + (index * 2), (sample * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
