import 'package:flutter/material.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_controller.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';
import 'package:kirana_gpt/features/voice/voice_capture_controller.dart';

/// The shopkeeper's single-screen workflow: record, review, then sync.
class KiranaDashboardPage extends StatefulWidget {
  const KiranaDashboardPage({
    required this.repository,
    this.voiceCapture,
    super.key,
  });

  final TranscriptRepository repository;
  final VoiceCapturePort? voiceCapture;

  @override
  State<KiranaDashboardPage> createState() => _KiranaDashboardPageState();
}

class _KiranaDashboardPageState extends State<KiranaDashboardPage> {
  late final VoiceCaptureController _voiceCaptureController;
  late final DashboardController _controller;
  late final TextEditingController _transcriptController;

  @override
  void initState() {
    super.initState();
    _voiceCaptureController = VoiceCaptureController(
      capturePort: widget.voiceCapture,
    );
    _controller =
        DashboardController(
            repository: widget.repository,
            voiceCapture: _voiceCaptureController,
          )
          ..addListener(_refresh)
          ..load();
    _transcriptController = TextEditingController();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    _voiceCaptureController.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = _controller.voiceCapture;
    final manualOnly =
        voice.availability == VoiceCaptureAvailability.manualOnly;
    final isRecording = voice.isCapturing;
    final isProcessing = voice.isProcessing;
    final pending = _controller.queueStatus.pending;
    final confirmation = _controller.confirmation;

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'KiranaGPT',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _controller.isLoading ? null : _controller.load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Shop update',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(_statusText(voice.status, manualOnly)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('dashboard-capture-button'),
                        onPressed:
                            _controller.isQueueing || manualOnly || isProcessing
                            ? null
                            : _controller.beginCapture,
                        icon: Icon(
                          isProcessing
                              ? Icons.hourglass_top
                              : isRecording
                              ? Icons.stop
                              : Icons.mic,
                        ),
                        label: Text(
                          isProcessing
                              ? 'Processing audio…'
                              : isRecording
                              ? 'Stop and process'
                              : 'Record update',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('dashboard-transcript-field'),
                        controller: _transcriptController,
                        enabled: !_controller.isQueueing,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: _controller.updateTranscript,
                        decoration: const InputDecoration(
                          labelText: 'Review transcript',
                          hintText: 'Record an update or type it here',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('dashboard-approve-button'),
                        onPressed: _controller.isQueueing ? null : _approve,
                        child: Text(
                          _controller.isQueueing ? 'Saving…' : 'Approve update',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('dashboard-sync-button'),
                onPressed: _controller.isSyncing ? null : _controller.syncQueue,
                icon: const Icon(Icons.sync),
                label: Text(
                  _controller.isSyncing
                      ? 'Syncing…'
                      : 'Sync $pending pending update${pending == 1 ? '' : 's'}',
                ),
              ),
              if (_controller.message case final message?) ...[
                const SizedBox(height: 12),
                _Notice(message: message),
              ],
              if (confirmation != null) ...[
                const SizedBox(height: 12),
                _Notice(message: confirmation.message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final added = await _controller.queueApprovedTranscript();
    if (added && mounted) FocusScope.of(context).unfocus();
  }

  void _refresh() {
    final draft = _controller.voiceCapture.draftTranscript ?? '';
    if (_transcriptController.text != draft) {
      _transcriptController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    if (mounted) setState(() {});
  }

  String _statusText(VoiceCaptureStatus status, bool manualOnly) {
    if (manualOnly) return 'Type the update, then approve it.';
    return switch (status) {
      VoiceCaptureStatus.ready => 'Tap record, speak, then tap stop.',
      VoiceCaptureStatus.capturing => 'Recording now. Tap stop when finished.',
      VoiceCaptureStatus.processing => 'Processing your recording…',
      VoiceCaptureStatus.transcriptReady =>
        'Transcript ready. Check it before approving.',
      VoiceCaptureStatus.cancelled => 'No recording was sent.',
      VoiceCaptureStatus.failed => 'Recording failed. You can type the update.',
      VoiceCaptureStatus.manualEntry => 'Type the update, then approve it.',
    };
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}
