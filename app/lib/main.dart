import 'package:flutter/widgets.dart';
import 'package:kirana_gpt/app.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/core/api/voice_transcription_client.dart';
import 'package:kirana_gpt/features/dashboard/kirana_feature_destinations.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configuration = ApiConfiguration.fromEnvironment();
  final repository = await TranscriptRepository.createDefault(
    configuration: configuration,
  );

  runApp(
    KiranaApp(
      repository: repository,
      additionalDestinations: kiranaVoiceDashboardDestinations(
        repository: repository,
        configuration: configuration,
        voiceCaptureFactory: () => TapToRecordVoiceCapture(
          transcriber: KiranaVoiceTranscriptionClient(
            configuration: configuration,
          ),
        ),
      ),
    ),
  );
}
