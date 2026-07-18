import 'package:flutter/material.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_page.dart';
import 'package:kirana_gpt/features/shop/database_view_page.dart';
import 'package:kirana_gpt/features/shop/stock_credits_page.dart';
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
  required ApiConfiguration configuration,
  VoiceCapturePort Function()? voiceCaptureFactory,
}) {
  return [
    KiranaDestination(
      label: 'Manual CRUD',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note,
      builder: (_) => StockCreditsPage(configuration: configuration),
    ),
    KiranaDestination(
      label: 'Database view',
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage,
      builder: (_) => DatabaseViewPage(configuration: configuration),
    ),
    KiranaDestination(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      builder: (_) => KiranaDashboardPage(
        repository: repository,
        voiceCapture: voiceCaptureFactory?.call(),
      ),
    ),
  ];
}
