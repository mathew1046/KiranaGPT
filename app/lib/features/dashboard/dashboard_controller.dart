import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_models.dart';
import 'package:kirana_gpt/features/voice/voice_capture_controller.dart';

/// Coordinates the compact operational dashboard without owning audio data.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required TranscriptRepository repository,
    VoiceCaptureController? voiceCapture,
  }) : _repository = repository,
       _voiceCapture = voiceCapture ?? VoiceCaptureController(),
       _ownsVoiceCapture = voiceCapture == null {
    _voiceCapture.addListener(_handleVoiceChange);
  }

  final TranscriptRepository _repository;
  final VoiceCaptureController _voiceCapture;
  final bool _ownsVoiceCapture;

  DashboardQueueStatus _queueStatus = const DashboardQueueStatus();
  DashboardConfirmation? _confirmation;
  String? _message;
  bool _isLoading = false;
  bool _isQueueing = false;
  bool _isSyncing = false;

  VoiceCaptureController get voiceCapture => _voiceCapture;
  DashboardQueueStatus get queueStatus => _queueStatus;
  DashboardConfirmation? get confirmation => _confirmation;
  String? get message => _message;
  bool get isLoading => _isLoading;
  bool get isQueueing => _isQueueing;
  bool get isSyncing => _isSyncing;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _refreshQueueStatus();
      _message = null;
    } catch (_) {
      _message = 'Could not read the local transcript queue.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> beginCapture() async {
    _message = null;
    notifyListeners();
    await _voiceCapture.capture();
  }

  /// Updates an in-memory draft from the browser/manual entry fallback.
  void updateTranscript(String transcript) {
    _voiceCapture.setManualTranscript(transcript);
  }

  Future<bool> queueApprovedTranscript() async {
    final transcript = _voiceCapture.draftTranscript?.trim();
    if (transcript == null || transcript.isEmpty) {
      _message = 'Enter or capture a transcript before approving it.';
      notifyListeners();
      return false;
    }

    _isQueueing = true;
    _message = null;
    notifyListeners();
    try {
      await _repository.addManualTranscript(transcript);
      _confirmation = DashboardConfirmation(
        transcript: transcript,
        state: DashboardConfirmationState.queued,
        message: 'Approved transcript queued on this device.',
      );
      _voiceCapture.clearDraft();
      await _refreshQueueStatus();
      return true;
    } on ArgumentError {
      _message = 'This transcript cannot be added to the queue.';
      return false;
    } catch (_) {
      _message = 'Could not queue the transcript. It has not been sent.';
      return false;
    } finally {
      _isQueueing = false;
      notifyListeners();
    }
  }

  Future<void> syncQueue() async {
    if (_isSyncing) {
      return;
    }

    _isSyncing = true;
    _message = null;
    notifyListeners();
    try {
      final result = await _repository.syncPending();
      await _refreshQueueStatus();
      _message = result.message ?? _syncMessage(result);
    } catch (_) {
      _message = 'Sync could not finish. Your transcript remains queued.';
      await _refreshQueueStatus();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void dismissConfirmation() {
    _confirmation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _voiceCapture.removeListener(_handleVoiceChange);
    if (_ownsVoiceCapture) {
      _voiceCapture.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshQueueStatus() async {
    final items = await _repository.loadQueue();
    _queueStatus = DashboardQueueStatus.fromItems(items);
  }

  void _handleVoiceChange() {
    final transcript = _voiceCapture.draftTranscript;
    if (transcript != null && transcript.isNotEmpty && !_isQueueing) {
      _confirmation = DashboardConfirmation(
        transcript: transcript,
        state: DashboardConfirmationState.awaitingApproval,
        message:
            'Review the text with the shopkeeper before adding it to the queue.',
      );
    }
    if (_voiceCapture.message != null) {
      _message = _voiceCapture.message;
    }
    notifyListeners();
  }

  String _syncMessage(QueueSyncResult result) {
    if (!result.attemptedSync) {
      return 'There are no pending transcripts to sync.';
    }
    final parts = <String>[];
    if (result.synced > 0) {
      parts.add('${result.synced} synced');
    }
    if (result.needsReview > 0) {
      parts.add('${result.needsReview} need review');
    }
    if (result.pending > 0) {
      parts.add('${result.pending} still pending');
    }
    return '${parts.join(', ')}.';
  }
}
