import 'dart:convert';

import 'package:kirana_gpt/core/api/ingest_models.dart';
import 'package:kirana_gpt/core/api/kirana_api_client.dart';
import 'package:kirana_gpt/core/queue/transcript_queue.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptQueue', () {
    test('persists a transcript row without an audio field', () async {
      final store = InMemoryTranscriptQueueStore();
      final queue = TranscriptQueue(
        store: store,
        clock: () => DateTime.utc(2026, 7, 19, 12),
        idGenerator: () => '00000000-0000-4000-8000-000000000010',
      );

      final item = await queue.enqueue(
        transcript: '  Arjun bought two rice bags.  ',
        locale: 'en-IN',
      );

      final rows = await store.readRows();
      final encoded = jsonDecode(rows.single) as Map<String, dynamic>;
      expect(item.transcript, 'Arjun bought two rice bags.');
      expect(
        encoded['client_event_id'],
        '00000000-0000-4000-8000-000000000010',
      );
      expect(encoded['transcript'], 'Arjun bought two rice bags.');
      expect(encoded.containsKey('audio'), isFalse);
      expect(encoded.containsKey('audio_path'), isFalse);
      expect(encoded['sync_state'], 'pending');
    });

    test(
      'maps mixed ingest results into synced and needs-review states',
      () async {
        const ids = [
          '00000000-0000-4000-8000-000000000011',
          '00000000-0000-4000-8000-000000000012',
        ];
        var id = 0;
        final queue = TranscriptQueue(
          store: InMemoryTranscriptQueueStore(),
          clock: () => DateTime.utc(2026, 7, 19, 12),
          idGenerator: () => ids[id++],
        );
        await queue.enqueue(transcript: 'Ravi paid 200.');
        await queue.enqueue(transcript: 'Someone gave money.');
        final gateway = _Gateway(
          response: const IngestResponse(
            items: [
              IngestItemResult(
                clientEventId: '00000000-0000-4000-8000-000000000011',
                status: IngestItemStatus.synced,
                route: IngestRoute.primary,
              ),
              IngestItemResult(
                clientEventId: '00000000-0000-4000-8000-000000000012',
                status: IngestItemStatus.needsReview,
                route: IngestRoute.escalated,
                reason: 'Customer name is ambiguous.',
              ),
            ],
          ),
        );
        final service = TranscriptSyncService(
          queue: queue,
          ingestGateway: gateway,
        );

        final result = await service.syncPending();
        final items = await queue.list();

        expect(result.synced, 1);
        expect(result.needsReview, 1);
        expect(gateway.lastRequest?.items, hasLength(2));
        expect(
          items.where((item) => item.clientEventId == ids[0]).single.syncState,
          TranscriptSyncState.synced,
        );
        expect(
          items.where((item) => item.clientEventId == ids[1]).single.syncState,
          TranscriptSyncState.needsReview,
        );
      },
    );

    test(
      'keeps a transcript pending when the service is unavailable',
      () async {
        final queue = TranscriptQueue(
          store: InMemoryTranscriptQueueStore(),
          idGenerator: () => '00000000-0000-4000-8000-000000000013',
        );
        await queue.enqueue(transcript: 'Sita took one oil packet.');
        final service = TranscriptSyncService(
          queue: queue,
          ingestGateway: _UnavailableGateway(),
        );

        final result = await service.syncPending();
        final item = (await queue.list()).single;

        expect(result.pending, 1);
        expect(result.message, contains('unavailable'));
        expect(item.syncState, TranscriptSyncState.pending);
        expect(item.reviewReason, contains('unavailable'));
      },
    );
  });
}

class _Gateway implements TranscriptIngestGateway {
  _Gateway({required this.response});

  final IngestResponse response;
  IngestRequest? lastRequest;

  @override
  Future<IngestResponse> ingest(IngestRequest request) async {
    lastRequest = request;
    return response;
  }
}

class _UnavailableGateway implements TranscriptIngestGateway {
  @override
  Future<IngestResponse> ingest(IngestRequest request) {
    throw const ApiUnavailableException();
  }
}
