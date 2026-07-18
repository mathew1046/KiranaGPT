import 'package:flutter/material.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_page.dart';
import 'package:kirana_gpt/features/voice/speaker_enrollment_controller.dart';
import 'package:kirana_gpt/features/voice/speaker_enrollment_page.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';
import 'package:kirana_gpt/ui/adaptive_shell.dart';

/// Add these to [KiranaApp.additionalDestinations] from the host app:
///
/// ```dart
/// additionalDestinations: kiranaVoiceDashboardDestinations(
///   repository: repository,
/// ),
/// ```
///
/// Supplying a [voiceCaptureFactory] creates one recorder per dashboard
/// instance, preventing a disposed microphone session from being reused after
/// navigation or a rebuild.
List<KiranaDestination> kiranaVoiceDashboardDestinations({
  required TranscriptRepository repository,
  VoiceCapturePort Function()? voiceCaptureFactory,
  SpeakerEnrollmentController? speakerEnrollmentController,
}) {
  return [
    KiranaDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      builder: (_) => KiranaDashboardPage(
        repository: repository,
        voiceCapture: voiceCaptureFactory?.call(),
      ),
    ),
    KiranaDestination(
      label: 'Voice profile',
      icon: Icons.record_voice_over_outlined,
      selectedIcon: Icons.record_voice_over,
      builder: (_) =>
          SpeakerEnrollmentPage(controller: speakerEnrollmentController),
    ),
  ];
}
