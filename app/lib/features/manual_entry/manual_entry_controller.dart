import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/core/queue/transcript_queue.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';

class ManualEntryController extends ChangeNotifier {
  ManualEntryController({required TranscriptRepository repository})
    : _repository = repository;

  final TranscriptRepository _repository;

  List<QueuedTranscript> _items = const [];
  String? _message;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isSyncing = false;

  List<QueuedTranscript> get items => List.unmodifiable(_items);
  String? get message => _message;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isSyncing => _isSyncing;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _items = await _repository.loadQueue();
    } catch (_) {
      _message = 'Could not open the local transcript queue.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addTranscript(String transcript) async {
    _isSaving = true;
    _message = null;
    notifyListeners();
    try {
      await _repository.addManualTranscript(transcript);
      _items = await _repository.loadQueue();
      _message =
          'Transcript queued. It will stay on this device until sync succeeds.';
      return true;
    } on ArgumentError {
      _message = 'Enter the approved transcript before adding it to the queue.';
      return false;
    } catch (_) {
      _message = 'Could not save the transcript locally.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Sends one approved manual update through the GPT-5.5 backend workflow.
  ///
  /// The repository first writes the transcript to the local queue, so a
  /// temporary network failure never loses a recorded update. Successful sync
  /// means the backend validated the model JSON and persisted the operation.
  Future<bool> analyzeTranscript(String transcript) async {
    _isSaving = true;
    _isSyncing = true;
    _message = null;
    notifyListeners();
    try {
      final queued = await _repository.addManualTranscript(transcript);
      final result = await _repository.syncPending();
      _items = await _repository.loadQueue();
      final updated = _items.where(
        (item) => item.clientEventId == queued.clientEventId,
      );
      final state = updated.isEmpty ? null : updated.first.syncState;
      if (state == TranscriptSyncState.synced) {
        _message = 'Update analyzed by GPT-5.5 and saved.';
        return true;
      }
      _message = result.message ?? _syncMessage(result);
      return false;
    } on ArgumentError {
      _message = 'Enter an update before asking the assistant to analyze it.';
      return false;
    } catch (_) {
      _message =
          'Analysis could not finish. The transcript stays queued safely.';
      _items = await _repository.loadQueue();
      return false;
    } finally {
      _isSaving = false;
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (_isSyncing) {
      return;
    }
    _isSyncing = true;
    _message = null;
    notifyListeners();
    try {
      final result = await _repository.syncPending();
      _items = await _repository.loadQueue();
      _message = result.message ?? _syncMessage(result);
    } catch (_) {
      _message = 'Sync could not finish. Your transcript remains queued.';
      _items = await _repository.loadQueue();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> retryNeedsReview() async {
    await _repository.retryNeedsReview();
    _items = await _repository.loadQueue();
    _message =
        'Review items moved back to pending. Check the transcript, then sync.';
    notifyListeners();
  }

  Future<void> clearSynced() async {
    await _repository.removeSynced();
    _items = await _repository.loadQueue();
    _message = 'Synced transcript history cleared from this device.';
    notifyListeners();
  }

  String _syncMessage(QueueSyncResult result) {
    if (!result.attemptedSync) {
      return 'There are no pending transcripts to sync.';
    }
    final fragments = <String>[];
    if (result.synced > 0) {
      fragments.add('${result.synced} synced');
    }
    if (result.needsReview > 0) {
      fragments.add('${result.needsReview} need review');
    }
    if (result.pending > 0) {
      fragments.add('${result.pending} still pending');
    }
    return '${fragments.join(', ')}.';
  }
}
