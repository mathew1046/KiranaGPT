import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/theme/kirana_theme.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/manual_entry/manual_entry_page.dart';
import 'package:kirana_gpt/ui/adaptive_shell.dart';

/// The root app accepts additive destinations so feature branches can register
/// voice and dashboard views without changing the queue foundation.
class KiranaApp extends StatelessWidget {
  const KiranaApp({
    required this.repository,
    this.additionalDestinations = const [],
    super.key,
  });

  final TranscriptRepository repository;
  final List<KiranaDestination> additionalDestinations;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KiranaGPT',
      debugShowCheckedModeBanner: false,
      theme: KiranaTheme.light(),
      darkTheme: KiranaTheme.dark(),
      themeMode: ThemeMode.system,
      home: AdaptiveShell(
        destinations: [
          KiranaDestination(
            label: 'Manual entry',
            icon: Icons.edit_note_outlined,
            selectedIcon: Icons.edit_note,
            builder: (_) => ManualEntryPage(repository: repository),
          ),
          ...additionalDestinations,
        ],
      ),
    );
  }
}
