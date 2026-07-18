import 'package:kirana_gpt/core/queue/transcript_queue.dart';

class DashboardQueueStatus {
  const DashboardQueueStatus({
    this.pending = 0,
    this.syncing = 0,
    this.needsReview = 0,
    this.synced = 0,
  });

  factory DashboardQueueStatus.fromItems(Iterable<QueuedTranscript> items) {
    var pending = 0;
    var syncing = 0;
    var needsReview = 0;
    var synced = 0;

    for (final item in items) {
      switch (item.syncState) {
        case TranscriptSyncState.pending:
          pending += 1;
        case TranscriptSyncState.syncing:
          syncing += 1;
        case TranscriptSyncState.needsReview:
          needsReview += 1;
        case TranscriptSyncState.synced:
          synced += 1;
      }
    }
    return DashboardQueueStatus(
      pending: pending,
      syncing: syncing,
      needsReview: needsReview,
      synced: synced,
    );
  }

  final int pending;
  final int syncing;
  final int needsReview;
  final int synced;

  int get total => pending + syncing + needsReview + synced;
  int get waitingForAction => pending + needsReview;
}

enum DashboardConfirmationState { awaitingApproval, queued }

/// A text-only confirmation card. It mirrors the currently reviewable ledger
/// update and deliberately has no link to a recording or audio file.
class DashboardConfirmation {
  const DashboardConfirmation({
    required this.transcript,
    required this.state,
    required this.message,
  });

  final String transcript;
  final DashboardConfirmationState state;
  final String message;
}
