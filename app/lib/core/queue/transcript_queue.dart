import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

enum TranscriptSyncState {
  pending('pending'),
  syncing('syncing'),
  needsReview('needs_review'),
  synced('synced');

  const TranscriptSyncState(this.value);

  final String value;

  static TranscriptSyncState fromWire(Object? value) {
    return switch (value) {
      'syncing' => TranscriptSyncState.syncing,
      'needs_review' => TranscriptSyncState.needsReview,
      'synced' => TranscriptSyncState.synced,
      _ => TranscriptSyncState.pending,
    };
  }
}

/// A local, text-only queue row. It deliberately has no audio field.
class QueuedTranscript {
  const QueuedTranscript({
    required this.clientEventId,
    required this.transcript,
    required this.capturedAt,
    required this.syncState,
    required this.attemptCount,
    this.locale,
    this.speakerId,
    this.lastAttemptAt,
    this.reviewReason,
  });

  factory QueuedTranscript.fromJson(Map<String, dynamic> json) {
    final clientEventId = json['client_event_id'];
    final transcript = json['transcript'];
    final capturedAt = json['captured_at'];
    if (clientEventId is! String ||
        clientEventId.isEmpty ||
        transcript is! String ||
        transcript.isEmpty ||
        capturedAt is! String) {
      throw const FormatException('A queued transcript row was invalid.');
    }

    final parsedCapturedAt = DateTime.tryParse(capturedAt);
    if (parsedCapturedAt == null) {
      throw const FormatException(
        'A queued transcript had an invalid timestamp.',
      );
    }

    final lastAttempt = json['last_attempt_at'];
    return QueuedTranscript(
      clientEventId: clientEventId,
      transcript: transcript,
      capturedAt: parsedCapturedAt.toUtc(),
      syncState: TranscriptSyncState.fromWire(json['sync_state']),
      attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
      locale: json['locale'] as String?,
      speakerId: json['speaker_id'] as String?,
      lastAttemptAt: lastAttempt is String
          ? DateTime.tryParse(lastAttempt)?.toUtc()
          : null,
      reviewReason: json['review_reason'] as String?,
    );
  }

  final String clientEventId;
  final String transcript;
  final DateTime capturedAt;
  final TranscriptSyncState syncState;
  final int attemptCount;
  final String? locale;
  final String? speakerId;
  final DateTime? lastAttemptAt;
  final String? reviewReason;

  Map<String, Object?> toJson() => {
    'client_event_id': clientEventId,
    'transcript': transcript,
    'captured_at': capturedAt.toUtc().toIso8601String(),
    'sync_state': syncState.value,
    'attempt_count': attemptCount,
    if (locale != null && locale!.isNotEmpty) 'locale': locale,
    if (speakerId != null && speakerId!.isNotEmpty) 'speaker_id': speakerId,
    if (lastAttemptAt != null)
      'last_attempt_at': lastAttemptAt!.toUtc().toIso8601String(),
    if (reviewReason != null && reviewReason!.isNotEmpty)
      'review_reason': reviewReason,
  };

  QueuedTranscript copyWith({
    TranscriptSyncState? syncState,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? reviewReason,
    bool clearReviewReason = false,
  }) {
    return QueuedTranscript(
      clientEventId: clientEventId,
      transcript: transcript,
      capturedAt: capturedAt,
      syncState: syncState ?? this.syncState,
      attemptCount: attemptCount ?? this.attemptCount,
      locale: locale,
      speakerId: speakerId,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      reviewReason: clearReviewReason
          ? null
          : reviewReason ?? this.reviewReason,
    );
  }
}

/// The queue table boundary. A native SQLite implementation can replace this
/// store later without changing queue/sync code; the included preferences store
/// runs on both Android and web.
abstract interface class TranscriptQueueStore {
  Future<List<String>> readRows();

  Future<void> writeRows(List<String> rows);
}

class SharedPreferencesTranscriptQueueStore implements TranscriptQueueStore {
  SharedPreferencesTranscriptQueueStore._(this._preferences);

  static const _storageKey = 'kirana_gpt.transcript_queue.v1';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesTranscriptQueueStore> create() async {
    return SharedPreferencesTranscriptQueueStore._(
      await SharedPreferences.getInstance(),
    );
  }

  @override
  Future<List<String>> readRows() async {
    final serialized = _preferences.getString(_storageKey);
    if (serialized == null || serialized.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(serialized);
    if (decoded is! List || decoded.any((row) => row is! String)) {
      throw const FormatException('The local transcript queue was malformed.');
    }
    return decoded.cast<String>();
  }

  @override
  Future<void> writeRows(List<String> rows) {
    return _preferences.setString(_storageKey, jsonEncode(rows));
  }
}

/// Test-friendly in-memory implementation with the same row semantics.
class InMemoryTranscriptQueueStore implements TranscriptQueueStore {
  InMemoryTranscriptQueueStore([List<String>? initialRows])
    : _rows = List<String>.of(initialRows ?? const []);

  List<String> _rows;

  @override
  Future<List<String>> readRows() async => List<String>.of(_rows);

  @override
  Future<void> writeRows(List<String> rows) async {
    _rows = List<String>.of(rows);
  }
}

typedef QueueClock = DateTime Function();
typedef ClientEventIdGenerator = String Function();

class TranscriptQueue {
  TranscriptQueue({
    required TranscriptQueueStore store,
    QueueClock? clock,
    ClientEventIdGenerator? idGenerator,
  }) : _store = store,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _idGenerator = idGenerator ?? _defaultId;

  final TranscriptQueueStore _store;
  final QueueClock _clock;
  final ClientEventIdGenerator _idGenerator;

  Future<List<QueuedTranscript>> list() async {
    final rows = await _read();
    rows.sort((left, right) => right.capturedAt.compareTo(left.capturedAt));
    return rows;
  }

  Future<QueuedTranscript> enqueue({
    required String transcript,
    String? locale,
    String? speakerId,
  }) async {
    final cleanTranscript = transcript.trim();
    if (cleanTranscript.isEmpty) {
      throw ArgumentError.value(transcript, 'transcript', 'must not be empty');
    }
    if (cleanTranscript.runes.length > 4000) {
      throw ArgumentError.value(
        transcript,
        'transcript',
        'must not exceed 4000 characters',
      );
    }

    final rows = await _read();
    final queued = QueuedTranscript(
      clientEventId: _idGenerator(),
      transcript: cleanTranscript,
      capturedAt: _clock().toUtc(),
      syncState: TranscriptSyncState.pending,
      attemptCount: 0,
      locale: locale?.trim().isEmpty ?? true ? null : locale?.trim(),
      speakerId: speakerId?.trim().isEmpty ?? true ? null : speakerId?.trim(),
    );
    rows.add(queued);
    await _write(rows);
    return queued;
  }

  Future<void> markSyncing(Iterable<String> clientEventIds) {
    final ids = clientEventIds.toSet();
    return _update((row) {
      if (!ids.contains(row.clientEventId)) {
        return row;
      }
      return row.copyWith(
        syncState: TranscriptSyncState.syncing,
        attemptCount: row.attemptCount + 1,
        lastAttemptAt: _clock().toUtc(),
        clearReviewReason: true,
      );
    });
  }

  Future<void> restorePending(
    Iterable<String> clientEventIds, {
    String? reason,
  }) {
    final ids = clientEventIds.toSet();
    return _update((row) {
      if (!ids.contains(row.clientEventId)) {
        return row;
      }
      return row.copyWith(
        syncState: TranscriptSyncState.pending,
        reviewReason: reason,
      );
    });
  }

  Future<void> applyResults(Map<String, QueueResultUpdate> updates) {
    return _update((row) {
      final update = updates[row.clientEventId];
      if (update == null) {
        return row;
      }
      return row.copyWith(
        syncState: update.syncState,
        reviewReason: update.reason,
        clearReviewReason: update.reason == null,
      );
    });
  }

  Future<void> retryNeedsReview() {
    return _update((row) {
      if (row.syncState != TranscriptSyncState.needsReview) {
        return row;
      }
      return row.copyWith(
        syncState: TranscriptSyncState.pending,
        clearReviewReason: true,
      );
    });
  }

  Future<void> removeSynced() async {
    final rows = await _read();
    await _write(
      rows
          .where((row) => row.syncState != TranscriptSyncState.synced)
          .toList(growable: false),
    );
  }

  Future<void> _update(
    QueuedTranscript Function(QueuedTranscript row) transform,
  ) async {
    final rows = await _read();
    await _write(rows.map(transform).toList(growable: false));
  }

  Future<List<QueuedTranscript>> _read() async {
    final encodedRows = await _store.readRows();
    return encodedRows
        .map((encoded) {
          final decoded = jsonDecode(encoded);
          if (decoded is! Map) {
            throw const FormatException('A local queue row was not an object.');
          }
          return QueuedTranscript.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: true);
  }

  Future<void> _write(List<QueuedTranscript> rows) {
    return _store.writeRows(
      rows.map((row) => jsonEncode(row.toJson())).toList(growable: false),
    );
  }

  static String _defaultId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class QueueResultUpdate {
  const QueueResultUpdate({required this.syncState, this.reason});

  final TranscriptSyncState syncState;
  final String? reason;
}
