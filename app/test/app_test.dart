import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_gpt/app.dart';
import 'package:kirana_gpt/core/api/ingest_models.dart';
import 'package:kirana_gpt/core/api/kirana_api_client.dart';
import 'package:kirana_gpt/core/queue/transcript_queue.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';

void main() {
  testWidgets('shows the web-safe manual transcript fallback', (tester) async {
    final repository = TranscriptRepository.forTesting(
      queue: TranscriptQueue(store: InMemoryTranscriptQueueStore()),
      ingestGateway: _NoopGateway(),
    );

    await tester.pumpWidget(KiranaApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Add an approved ledger update'), findsOneWidget);
    expect(find.byKey(const Key('manual-transcript-field')), findsOneWidget);
    expect(
      find.text(
        'Only text is saved locally. Audio is never stored or uploaded.',
      ),
      findsOneWidget,
    );
  });
}

class _NoopGateway implements TranscriptIngestGateway {
  @override
  Future<IngestResponse> ingest(IngestRequest request) async {
    return const IngestResponse(items: []);
  }
}
