import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/ingest_models.dart';
import 'package:kirana_gpt/core/api/kirana_api_client.dart';
import 'package:kirana_gpt/core/api/manual_analysis_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KiranaApiClient', () {
    test(
      'serializes a text-only ingest payload without app authorization',
      () async {
        final httpClient = MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.toString(), 'https://ledger.example/v1/ingest');
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers['content-type'], contains('application/json'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {
            'items': [
              {
                'client_event_id': '00000000-0000-4000-8000-000000000001',
                'transcript': 'Meena paid 500 rupees.',
                'captured_at': '2026-07-19T10:15:00.000Z',
                'locale': 'en-IN',
              },
            ],
          });
          expect(jsonEncode(body), isNot(contains('audio')));

          return http.Response(
            jsonEncode({
              'items': [
                {
                  'client_event_id': '00000000-0000-4000-8000-000000000001',
                  'status': 'synced',
                  'ledger_entry_id': 'ledger-9',
                  'route': 'primary',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        });
        final api = KiranaApiClient(
          configuration: ApiConfiguration(
            baseUri: Uri.parse('https://ledger.example/'),
          ),
          httpClient: httpClient,
        );

        final response = await api.ingest(
          IngestRequest(
            items: [
              IngestItem(
                clientEventId: '00000000-0000-4000-8000-000000000001',
                transcript: 'Meena paid 500 rupees.',
                capturedAt: DateTime.utc(2026, 7, 19, 10, 15),
                locale: 'en-IN',
              ),
            ],
          ),
        );

        expect(response.items, hasLength(1));
        expect(response.items.single.status, IngestItemStatus.synced);
        expect(response.items.single.route, IngestRoute.primary);
        expect(response.items.single.ledgerEntryId, 'ledger-9');
      },
    );

    test('parses a needs-review result without creating a local mutation', () {
      final response = IngestResponse.fromJson({
        'items': [
          {
            'client_event_id': '00000000-0000-4000-8000-000000000002',
            'status': 'needs_review',
            'route': 'escalated',
            'reason': 'Customer name is ambiguous.',
          },
        ],
      });

      expect(response.items.single.status, IngestItemStatus.needsReview);
      expect(response.items.single.reason, 'Customer name is ambiguous.');
    });

    test(
      'keeps the preview reason when analysis cannot prepare a proposal',
      () {
        expect(
          () => ManualAnalysisProposal.fromJson({
            'status': 'needs_review',
            'route': 'offline',
            'reason': 'model_unavailable',
          }),
          throwsA(
            isA<ManualAnalysisNeedsReviewException>()
                .having((error) => error.reason, 'reason', 'model_unavailable')
                .having(
                  (error) => error.message,
                  'message',
                  contains('unavailable'),
                ),
          ),
        );
      },
    );
  });
}
