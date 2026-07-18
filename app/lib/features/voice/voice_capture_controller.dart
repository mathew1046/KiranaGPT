import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';

enum VoiceCaptureStatus {
  ready,
  capturing,
  processing,
  manualEntry,
  transcriptReady,
  cancelled,
  failed,
}

/// Holds a reviewable transcript in memory until the queue feature approves it.
///
/// This controller has no persistence dependency, so raw audio cannot be saved
/// accidentally through the capture flow.
class VoiceCaptureController extends ChangeNotifier {
  VoiceCaptureController({VoiceCapturePort? capturePort})
    : _capturePort = capturePort ?? UnavailableVoiceCapture();

  final VoiceCapturePort _capturePort;

  VoiceCaptureStatus _status = VoiceCaptureStatus.ready;
  String? _draftTranscript;
  String? _message;

  VoiceCaptureAvailability get availability => _capturePort.availability;
  VoiceCaptureStatus get status => _status;
  String? get draftTranscript => _draftTranscript;
  String? get message => _message;
  bool get isCapturing => _capturePort.isListening;
  bool get isProcessing => _capturePort.isProcessing;

  /// Starts one recording. The user explicitly stops it before processing.
  Future<VoiceCaptureResult> startListening() async {
    _status = VoiceCaptureStatus.capturing;
    _message = null;
    notifyListeners();

    VoiceCaptureResult result;
    try {
      result = await _capturePort.startListening(_handleResult);
    } catch (_) {
      result = const VoiceCaptureResult.failed(
        message:
            'Voice capture could not start. Type the approved transcript instead.',
      );
    }
    _applyResult(result);
    return result;
  }

  Future<VoiceCaptureResult> stopListening() async {
    if (_capturePort.isProcessing) {
      return const VoiceCaptureResult.cancelled();
    }
    _status = VoiceCaptureStatus.processing;
    _message = 'Processing audio…';
    notifyListeners();
    final result = await _capturePort.stopListening();
    _applyResult(result);
    return result;
  }

  Future<VoiceCaptureResult> toggleListening() {
    if (isProcessing) return Future.value(const VoiceCaptureResult.cancelled());
    return isCapturing ? stopListening() : startListening();
  }

  void _handleResult(VoiceCaptureResult result) {
    _applyResult(result);
  }

  void _applyResult(VoiceCaptureResult result) {
    _message = result.message;
    switch (result.outcome) {
      case VoiceCaptureOutcome.listening:
        _status = VoiceCaptureStatus.capturing;
        break;
      case VoiceCaptureOutcome.transcriptReady:
        _draftTranscript = result.transcript;
        _status = VoiceCaptureStatus.transcriptReady;
        break;
      case VoiceCaptureOutcome.manualEntryRequired:
        _status = VoiceCaptureStatus.manualEntry;
        break;
      case VoiceCaptureOutcome.cancelled:
        _status = VoiceCaptureStatus.cancelled;
        break;
      case VoiceCaptureOutcome.failed:
        _status = VoiceCaptureStatus.failed;
        break;
    }
    notifyListeners();
  }

  /// Accepts a typed fallback transcript; it is not persisted by this class.
  void setManualTranscript(String transcript) {
    final cleanTranscript = transcript.trim();
    _draftTranscript = cleanTranscript.isEmpty ? null : cleanTranscript;
    _status = cleanTranscript.isEmpty
        ? VoiceCaptureStatus.manualEntry
        : VoiceCaptureStatus.transcriptReady;
    _message = null;
    notifyListeners();
  }

  void clearDraft() {
    _draftTranscript = null;
    _message = null;
    _status = VoiceCaptureStatus.ready;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_capturePort.dispose());
    super.dispose();
  }
}
