import 'package:flutter/foundation.dart';
import 'package:kirana_gpt/core/api/ingest_models.dart';
import 'package:kirana_gpt/core/api/manual_analysis_models.dart';
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
  bool _isApproving = false;
  ManualAnalysisProposal? _proposal;

  List<QueuedTranscript> get items => List.unmodifiable(_items);
  String? get message => _message;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isSyncing => _isSyncing;
  bool get isApproving => _isApproving;
  ManualAnalysisProposal? get proposal => _proposal;

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

  /// Ask GPT-5.5 for a reviewable operation without changing shop data.
  Future<bool> analyzeTranscript(String transcript) async {
    _isSaving = true;
    _message = null;
    _proposal = null;
    notifyListeners();
    try {
      _proposal = await _repository.previewManualAnalysis(transcript);
      _message = 'Review the proposed update, then approve it to save.';
      return true;
    } on ArgumentError {
      _message = 'Enter an update before asking the assistant to analyze it.';
      return false;
    } catch (_) {
      _message = 'Analysis could not finish. The recording text is still here.';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> approveProposal() async {
    final proposal = _proposal;
    if (proposal == null || _isApproving) return false;
    _isApproving = true;
    _message = null;
    notifyListeners();
    try {
      final result = await _repository.approveManualAnalysis(proposal.id);
      if (result.status == IngestItemStatus.synced ||
          result.status == IngestItemStatus.duplicate) {
        _proposal = null;
        _message = 'Approved update saved to the shop records.';
        return true;
      }
      _message = 'The proposal could not be saved. Please analyze it again.';
      return false;
    } catch (_) {
      _message = 'Approval could not reach the backend. Nothing was changed.';
      return false;
    } finally {
      _isApproving = false;
      notifyListeners();
    }
  }

  void discardProposal() {
    _proposal = null;
    _message = 'Proposal discarded. No shop records were changed.';
    notifyListeners();
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
