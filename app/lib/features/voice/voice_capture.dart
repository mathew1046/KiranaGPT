import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/core/api/voice_transcription_client.dart';
import 'package:record/record.dart';

enum VoiceCaptureAvailability { tapToRecord, manualOnly }

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
}

typedef VoiceCaptureListener = void Function(VoiceCaptureResult result);

/// A short, user-controlled recording. No background or continuous listening
/// is used: the shop owner starts and stops each utterance explicitly.
abstract interface class VoiceCapturePort {
  VoiceCaptureAvailability get availability;
  bool get isListening;
  bool get isProcessing;

  Future<VoiceCaptureResult> startListening(VoiceCaptureListener onResult);
  Future<VoiceCaptureResult> stopListening();
  Future<void> dispose();
}

/// Browser and unsupported-device fallback; manual entry remains available.
class UnavailableVoiceCapture implements VoiceCapturePort {
  @override
  VoiceCaptureAvailability get availability =>
      VoiceCaptureAvailability.manualOnly;

  @override
  bool get isListening => false;

  @override
  bool get isProcessing => false;

  @override
  Future<VoiceCaptureResult> startListening(
    VoiceCaptureListener onResult,
  ) async => const VoiceCaptureResult.manualEntryRequired(
    message:
        'Voice capture is not available on this device. Type the transcript instead.',
  );

  @override
  Future<VoiceCaptureResult> stopListening() async =>
      const VoiceCaptureResult.cancelled();

  @override
  Future<void> dispose() async {}
}

/// Records PCM audio in memory, converts it to WAV, and sends it only after
/// the owner taps stop. The backend immediately forwards it to the audio model
/// and does not persist the bytes.
class TapToRecordVoiceCapture implements VoiceCapturePort {
  TapToRecordVoiceCapture({required VoiceTranscriptionGateway transcriber})
    : _transcriber = transcriber;

  final VoiceTranscriptionGateway _transcriber;
  final AudioRecorder _recorder = AudioRecorder();
  final BytesBuilder _audioBytes = BytesBuilder();
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _streamFinished;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isDisposed = false;

  @override
  VoiceCaptureAvailability get availability => kIsWeb
      ? VoiceCaptureAvailability.manualOnly
      : VoiceCaptureAvailability.tapToRecord;

  @override
  bool get isListening => _isListening;

  @override
  bool get isProcessing => _isProcessing;

  @override
  Future<VoiceCaptureResult> startListening(
    VoiceCaptureListener onResult,
  ) async {
    if (kIsWeb) {
      return const VoiceCaptureResult.manualEntryRequired(
        message: 'Audio recording is available in the Android app only.',
      );
    }
    if (_isDisposed) {
      return const VoiceCaptureResult.failed(
        message: 'Voice capture is no longer available.',
      );
    }
    if (_isListening || _isProcessing) {
      return const VoiceCaptureResult.listening();
    }

    try {
      if (!await _recorder.hasPermission()) {
        return const VoiceCaptureResult.manualEntryRequired(
          message: 'Allow microphone access to record a shop update.',
        );
      }
      _audioBytes.clear();
      _streamFinished = Completer<void>();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSubscription = stream.listen(
        _audioBytes.add,
        onError: (Object _, StackTrace _) {},
        onDone: () {
          if (!(_streamFinished?.isCompleted ?? true)) {
            _streamFinished!.complete();
          }
        },
      );
      _isListening = true;
      return const VoiceCaptureResult.listening();
    } catch (_) {
      return const VoiceCaptureResult.failed(
        message:
            'Recording could not start. Type the approved transcript instead.',
      );
    }
  }

  @override
  Future<VoiceCaptureResult> stopListening() async {
    if (!_isListening || _isProcessing) {
      return const VoiceCaptureResult.cancelled();
    }
    // Mark the recording as stopped before awaiting platform cleanup. This
    // makes a second tap unable to race a second recorder.stop()/takeBytes().
    _isListening = false;
    _isProcessing = true;
    try {
      await _recorder.stop();
      await _streamFinished?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      final pcmBytes = _audioBytes.takeBytes();
      if (pcmBytes.isEmpty) {
        return const VoiceCaptureResult.cancelled(
          message: 'No audio was recorded.',
        );
      }
      final transcript = await _transcriber.transcribeWav(_pcm16Wav(pcmBytes));
      return VoiceCaptureResult.transcript(transcript);
    } on VoiceTranscriptionException catch (error) {
      return VoiceCaptureResult.failed(message: error.message);
    } catch (_) {
      return const VoiceCaptureResult.failed(
        message:
            'Audio could not be processed. Try recording again or type the transcript.',
      );
    } finally {
      _isListening = false;
      _isProcessing = false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_isListening) {
      await _recorder.cancel();
    }
    _isListening = false;
    _isProcessing = false;
    await _audioSubscription?.cancel();
    await _recorder.dispose();
  }
}

Uint8List _pcm16Wav(Uint8List pcmBytes, {int sampleRate = 16000}) {
  final bytes = ByteData(44 + pcmBytes.length);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  final dataLength = pcmBytes.length;
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
  for (var index = 0; index < pcmBytes.length; index++) {
    bytes.setUint8(44 + index, pcmBytes[index]);
  }
  return bytes.buffer.asUint8List();
}
