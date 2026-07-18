/// Compile-time configuration for the KiranaGPT API.
///
/// Secrets are intentionally not read from a checked-in file or embedded in
/// source. Supply the app's backend key with `--dart-define=KIRANA_APP_API_KEY`
/// when running a trusted development build. The OpenAI key belongs only to the
/// backend environment and must never be passed to this client.
class ApiConfiguration {
  const ApiConfiguration({required this.baseUri, required this.apiKey});

  factory ApiConfiguration.fromEnvironment() {
    const baseUrl = String.fromEnvironment(
      'KIRANA_API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    const apiKey = String.fromEnvironment('KIRANA_APP_API_KEY');

    return ApiConfiguration(baseUri: Uri.parse(baseUrl), apiKey: apiKey);
  }

  final Uri baseUri;
  final String apiKey;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  Uri endpoint(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$base$normalizedPath',
    ).replace(queryParameters: queryParameters);
  }
}
