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
/// Supplying a [voiceCapture] enables a host-provided, transient native
/// recognizer. Without one (and always on web), the dashboard safely falls back
/// to manual transcript entry.
List<KiranaDestination> kiranaVoiceDashboardDestinations({
  required TranscriptRepository repository,
  VoiceCapturePort? voiceCapture,
  SpeakerEnrollmentController? speakerEnrollmentController,
}) {
  return [
    KiranaDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      builder: (_) => KiranaDashboardPage(
        repository: repository,
        voiceCapture: voiceCapture,
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
