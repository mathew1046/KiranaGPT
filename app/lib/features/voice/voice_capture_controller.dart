import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';

enum VoiceCaptureStatus {
  ready,
  capturing,
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
    : _capturePort = capturePort ?? PrivacySafeVoiceCapture();

  final VoiceCapturePort _capturePort;

  VoiceCaptureStatus _status = VoiceCaptureStatus.ready;
  String? _draftTranscript;
  String? _message;
  bool _isCapturing = false;

  VoiceCaptureAvailability get availability => _capturePort.availability;
  VoiceCaptureStatus get status => _status;
  String? get draftTranscript => _draftTranscript;
  String? get message => _message;
  bool get isCapturing => _isCapturing;

  Future<VoiceCaptureResult> capture() async {
    if (_isCapturing) {
      return const VoiceCaptureResult.cancelled(
        message: 'Voice capture is already in progress.',
      );
    }

    _isCapturing = true;
    _status = VoiceCaptureStatus.capturing;
    _message = null;
    notifyListeners();

    VoiceCaptureResult result;
    try {
      result = await _capturePort.captureTranscript();
    } catch (_) {
      result = const VoiceCaptureResult.failed(
        message:
            'Voice capture could not finish. Type the approved transcript instead.',
      );
    }

    _isCapturing = false;
    _message = result.message;
    switch (result.outcome) {
      case VoiceCaptureOutcome.transcriptReady:
        _draftTranscript = result.transcript;
        _status = VoiceCaptureStatus.transcriptReady;
      case VoiceCaptureOutcome.manualEntryRequired:
        _status = VoiceCaptureStatus.manualEntry;
      case VoiceCaptureOutcome.cancelled:
        _status = VoiceCaptureStatus.cancelled;
      case VoiceCaptureOutcome.failed:
        _status = VoiceCaptureStatus.failed;
    }
    notifyListeners();
    return result;
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
}
