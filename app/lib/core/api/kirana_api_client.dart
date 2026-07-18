import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/ingest_models.dart';

abstract interface class TranscriptIngestGateway {
  Future<IngestResponse> ingest(IngestRequest request);
}

/// Small, injectable client for the KiranaGPT HTTP API.
///
/// It owns only transport and serialization. Domain code decides how a server
/// result changes local queue state.
class KiranaApiClient implements TranscriptIngestGateway {
  KiranaApiClient({
    required this.configuration,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _httpClient = httpClient ?? http.Client();

  final ApiConfiguration configuration;
  final http.Client _httpClient;
  final Duration requestTimeout;

  @override
  Future<IngestResponse> ingest(IngestRequest request) async {
    try {
      final response = await _postJson('/v1/ingest', request.toJson());
      return IngestResponse.fromJson(response);
    } on FormatException {
      throw const ApiResponseFormatException();
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    try {
      final response = await _httpClient
          .post(
            configuration.endpoint(path),
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiHttpException(statusCode: response.statusCode);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const ApiResponseFormatException();
      }

      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on ApiHttpException {
      rethrow;
    } on FormatException {
      throw const ApiResponseFormatException();
    } on TimeoutException {
      throw const ApiUnavailableException();
    } on http.ClientException {
      throw const ApiUnavailableException();
    }
  }

  void close() => _httpClient.close();
}

sealed class KiranaApiException implements Exception {
  const KiranaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiUnavailableException extends KiranaApiException {
  const ApiUnavailableException()
    : super(
        'The KiranaGPT service is unavailable. Your transcript stays queued.',
      );
}

class ApiResponseFormatException extends KiranaApiException {
  const ApiResponseFormatException()
    : super(
        'The service returned an unexpected response. Your transcript stays queued.',
      );
}

class ApiHttpException extends KiranaApiException {
  const ApiHttpException({required this.statusCode})
    : super('The service could not sync this transcript (HTTP $statusCode).');

  final int statusCode;
}
