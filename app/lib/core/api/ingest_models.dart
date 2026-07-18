import 'dart:convert';

/// Payload accepted by `POST /v1/ingest`.
class IngestRequest {
  const IngestRequest({required this.items});

  final List<IngestItem> items;

  Map<String, Object?> toJson() => {
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  String encode() => jsonEncode(toJson());
}

/// A text-only client event. Audio is intentionally not represented here.
class IngestItem {
  const IngestItem({
    required this.clientEventId,
    required this.transcript,
    this.capturedAt,
    this.speakerId,
    this.locale,
  });

  final String clientEventId;
  final String transcript;
  final DateTime? capturedAt;
  final String? speakerId;
  final String? locale;

  Map<String, Object?> toJson() {
    _validateUuid(clientEventId, 'client_event_id');
    final cleanTranscript = transcript.trim();
    if (cleanTranscript.isEmpty || cleanTranscript.runes.length > 4000) {
      throw ArgumentError.value(
        transcript,
        'transcript',
        'must contain between 1 and 4000 characters',
      );
    }
    if (speakerId case final value? when value.isNotEmpty) {
      _validateUuid(value, 'speaker_id');
    }

    return {
      'client_event_id': clientEventId,
      'transcript': cleanTranscript,
      if (capturedAt != null)
        'captured_at': capturedAt!.toUtc().toIso8601String(),
      if (speakerId != null && speakerId!.isNotEmpty) 'speaker_id': speakerId,
      if (locale != null && locale!.isNotEmpty) 'locale': locale,
    };
  }
}

class IngestResponse {
  const IngestResponse({required this.items});

  factory IngestResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'Ingest response did not include an items list.',
      );
    }

    return IngestResponse(
      items: rawItems
          .map((item) {
            if (item is! Map) {
              throw const FormatException(
                'An ingest result was not an object.',
              );
            }
            return IngestItemResult.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
          })
          .toList(growable: false),
    );
  }

  final List<IngestItemResult> items;
}

enum IngestItemStatus {
  synced('synced'),
  needsReview('needs_review'),
  duplicate('duplicate');

  const IngestItemStatus(this.value);

  final String value;

  static IngestItemStatus fromWire(Object? value) {
    return switch (value) {
      'synced' => IngestItemStatus.synced,
      'needs_review' => IngestItemStatus.needsReview,
      'duplicate' => IngestItemStatus.duplicate,
      _ => throw FormatException('Unsupported ingest status: $value'),
    };
  }
}

enum IngestRoute {
  primary('primary'),
  escalated('escalated'),
  offline('offline');

  const IngestRoute(this.value);

  final String value;

  static IngestRoute fromWire(Object? value) {
    return switch (value) {
      'primary' => IngestRoute.primary,
      'escalated' => IngestRoute.escalated,
      'offline' => IngestRoute.offline,
      _ => throw FormatException('Unsupported ingest route: $value'),
    };
  }
}

class IngestItemResult {
  const IngestItemResult({
    required this.clientEventId,
    required this.status,
    required this.route,
    this.ledgerEntryId,
    this.reason,
  });

  factory IngestItemResult.fromJson(Map<String, dynamic> json) {
    final clientEventId = json['client_event_id'];
    final rawStatus = json['status'];
    final rawRoute = json['route'];
    if (clientEventId is! String || clientEventId.isEmpty) {
      throw const FormatException(
        'An ingest result was missing client_event_id.',
      );
    }
    if (rawStatus is! String || rawStatus.isEmpty) {
      throw const FormatException('An ingest result was missing status.');
    }
    if (rawRoute is! String || rawRoute.isEmpty) {
      throw const FormatException('An ingest result was missing route.');
    }

    return IngestItemResult(
      clientEventId: clientEventId,
      status: IngestItemStatus.fromWire(rawStatus),
      route: IngestRoute.fromWire(rawRoute),
      ledgerEntryId: json['ledger_entry_id'] as String?,
      reason: json['reason'] as String?,
    );
  }

  final String clientEventId;
  final IngestItemStatus status;
  final IngestRoute route;
  final String? ledgerEntryId;
  final String? reason;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

void _validateUuid(String value, String fieldName) {
  if (!_uuidPattern.hasMatch(value)) {
    throw ArgumentError.value(value, fieldName, 'must be a UUID string');
  }
}
