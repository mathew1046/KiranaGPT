import 'package:flutter/widgets.dart';
import 'package:kirana_gpt/app.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = await TranscriptRepository.createDefault(
    configuration: ApiConfiguration.fromEnvironment(),
  );

  runApp(KiranaApp(repository: repository));
}
