import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';

/// The phone sends one user-controlled WAV recording over TLS.
///
/// The OpenAI API key remains on the backend and is never sent to the phone.
abstract interface class VoiceTranscriptionGateway {
  Future<String> transcribeWav(Uint8List wavBytes);
}

class KiranaVoiceTranscriptionClient implements VoiceTranscriptionGateway {
  KiranaVoiceTranscriptionClient({
    required this.configuration,
    this.requestTimeout = const Duration(seconds: 20),
  });

  final ApiConfiguration configuration;
  final Duration requestTimeout;

  @override
  Future<String> transcribeWav(Uint8List wavBytes) async {
    if (wavBytes.isEmpty) {
      throw const VoiceTranscriptionException('No speech was detected.');
    }

    final request =
        http.MultipartRequest('POST', configuration.endpoint('/v1/transcribe'))
          ..headers['accept'] = 'application/json'
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              wavBytes,
              filename: 'utterance.wav',
              contentType: MediaType('audio', 'wav'),
            ),
          );

    try {
      final response = await request.send().timeout(requestTimeout);
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const VoiceTranscriptionException(
          'Speech transcription is temporarily unavailable.',
        );
      }
      final decoded = jsonDecode(body);
      final transcript = decoded is Map ? decoded['transcript'] : null;
      if (transcript is! String || transcript.trim().isEmpty) {
        throw const VoiceTranscriptionException('No speech was detected.');
      }
      return transcript.trim();
    } on VoiceTranscriptionException {
      rethrow;
    } on TimeoutException {
      throw const VoiceTranscriptionException(
        'Speech transcription timed out. Try again.',
      );
    } on http.ClientException {
      throw const VoiceTranscriptionException(
        'Could not reach the transcription service.',
      );
    } on FormatException {
      throw const VoiceTranscriptionException(
        'The transcription service returned an invalid response.',
      );
    }
  }
}

class VoiceTranscriptionException implements Exception {
  const VoiceTranscriptionException(this.message);

  final String message;
}
