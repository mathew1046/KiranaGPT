import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/ingest_models.dart';
import 'package:kirana_gpt/core/api/kirana_api_client.dart';
import 'package:kirana_gpt/core/queue/transcript_queue.dart';

class TranscriptRepository {
  TranscriptRepository({
    required this.queue,
    required TranscriptIngestGateway ingestGateway,
  }) : _syncService = TranscriptSyncService(
         queue: queue,
         ingestGateway: ingestGateway,
       );

  factory TranscriptRepository.forTesting({
    required TranscriptQueue queue,
    required TranscriptIngestGateway ingestGateway,
  }) {
    return TranscriptRepository(queue: queue, ingestGateway: ingestGateway);
  }

  static Future<TranscriptRepository> createDefault({
    required ApiConfiguration configuration,
  }) async {
    final store = await SharedPreferencesTranscriptQueueStore.create();
    final queue = TranscriptQueue(store: store);
    return TranscriptRepository(
      queue: queue,
      ingestGateway: KiranaApiClient(configuration: configuration),
    );
  }

  final TranscriptQueue queue;
  final TranscriptSyncService _syncService;

  Future<List<QueuedTranscript>> loadQueue() => queue.list();

  Future<QueuedTranscript> addManualTranscript(String transcript) {
    return queue.enqueue(transcript: transcript);
  }

  Future<QueueSyncResult> syncPending() => _syncService.syncPending();

  Future<void> retryNeedsReview() => queue.retryNeedsReview();

  Future<void> removeSynced() => queue.removeSynced();
}

class TranscriptSyncService {
  TranscriptSyncService({
    required this.queue,
    required TranscriptIngestGateway ingestGateway,
  }) : _ingestGateway = ingestGateway;

  final TranscriptQueue queue;
  final TranscriptIngestGateway _ingestGateway;
  Future<QueueSyncResult>? _inFlight;

  Future<QueueSyncResult> syncPending() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final sync = _syncPending();
    _inFlight = sync;
    return sync.whenComplete(() => _inFlight = null);
  }

  Future<QueueSyncResult> _syncPending() async {
    final pending = (await queue.list())
        .where((row) => row.syncState == TranscriptSyncState.pending)
        .toList(growable: false);
    if (pending.isEmpty) {
      return const QueueSyncResult();
    }

    final ids = pending.map((row) => row.clientEventId).toList(growable: false);
    await queue.markSyncing(ids);

    try {
      final response = await _ingestGateway.ingest(
        IngestRequest(
          items: pending
              .map(
                (row) => IngestItem(
                  clientEventId: row.clientEventId,
                  transcript: row.transcript,
                  capturedAt: row.capturedAt,
                  locale: row.locale,
                  speakerId: row.speakerId,
                ),
              )
              .toList(growable: false),
        ),
      );

      final updates = <String, QueueResultUpdate>{};
      final expectedIds = ids.toSet();
      var synced = 0;
      var needsReview = 0;
      for (final result in response.items) {
        if (!expectedIds.contains(result.clientEventId) ||
            updates.containsKey(result.clientEventId)) {
          continue;
        }
        switch (result.status) {
          case IngestItemStatus.synced:
          case IngestItemStatus.duplicate:
            updates[result.clientEventId] = const QueueResultUpdate(
              syncState: TranscriptSyncState.synced,
            );
            synced += 1;
          case IngestItemStatus.needsReview:
            updates[result.clientEventId] = QueueResultUpdate(
              syncState: TranscriptSyncState.needsReview,
              reason: result.reason ?? 'This transcript needs review.',
            );
            needsReview += 1;
        }
      }

      final returnedIds = updates.keys.toSet();
      for (final id in ids.where((id) => !returnedIds.contains(id))) {
        updates[id] = const QueueResultUpdate(
          syncState: TranscriptSyncState.pending,
          reason: 'The service did not return a result for this transcript.',
        );
      }
      await queue.applyResults(updates);

      return QueueSyncResult(
        attempted: pending.length,
        synced: synced,
        needsReview: needsReview,
        pending: pending.length - synced - needsReview,
      );
    } on KiranaApiException catch (error) {
      await queue.restorePending(ids, reason: error.message);
      return QueueSyncResult(
        attempted: pending.length,
        pending: pending.length,
        message: error.message,
      );
    } catch (_) {
      const message = 'Sync could not finish. Your transcript stays queued.';
      await queue.restorePending(ids, reason: message);
      return QueueSyncResult(
        attempted: pending.length,
        pending: pending.length,
        message: message,
      );
    }
  }
}

class QueueSyncResult {
  const QueueSyncResult({
    this.attempted = 0,
    this.synced = 0,
    this.needsReview = 0,
    this.pending = 0,
    this.message,
  });

  final int attempted;
  final int synced;
  final int needsReview;
  final int pending;
  final String? message;

  bool get attemptedSync => attempted > 0;
}
