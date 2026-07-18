/// Compile-time configuration for the KiranaGPT API.
///
/// The OpenAI key belongs only to the backend environment and is never passed
/// to this client.
class ApiConfiguration {
  const ApiConfiguration({required this.baseUri});

  factory ApiConfiguration.fromEnvironment() {
    const baseUrl = String.fromEnvironment(
      'KIRANA_API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );
    return ApiConfiguration(baseUri: Uri.parse(baseUrl));
  }

  final Uri baseUri;

  Uri endpoint(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$base$normalizedPath',
    ).replace(queryParameters: queryParameters);
  }
}
