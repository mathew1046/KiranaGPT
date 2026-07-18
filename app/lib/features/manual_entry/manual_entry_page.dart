import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/api/api_configuration.dart';
import 'package:kirana_gpt/core/api/voice_transcription_client.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/manual_entry/manual_entry_controller.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';
import 'package:kirana_gpt/features/voice/voice_capture_controller.dart';

/// A compact fallback for typing or recording one ledger update.
class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({required this.repository, super.key});

  final TranscriptRepository repository;

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  late final ManualEntryController _controller;
  late final TextEditingController _textController;
  late final VoiceCaptureController _voiceCaptureController;

  @override
  void initState() {
    super.initState();
    _controller = ManualEntryController(repository: widget.repository)
      ..addListener(_refresh)
      ..load();
    _textController = TextEditingController();
    _voiceCaptureController = VoiceCaptureController(
      capturePort: TapToRecordVoiceCapture(
        transcriber: KiranaVoiceTranscriptionClient(
          configuration: ApiConfiguration.fromEnvironment(),
        ),
      ),
    )..addListener(_applyVoiceTranscript);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    _voiceCaptureController
      ..removeListener(_applyVoiceTranscript)
      ..dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = _voiceCaptureController.isCapturing;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Manual update',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text('Record or type one update, then queue it.'),
              const SizedBox(height: 20),
              TextField(
                key: const Key('manual-transcript-field'),
                controller: _textController,
                enabled: !_controller.isSaving,
                minLines: 4,
                maxLines: 6,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Update',
                  hintText: 'e.g. Meena paid 500 rupees.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('record-manual-transcript-button'),
                onPressed: _controller.isSaving
                    ? null
                    : _voiceCaptureController.toggleListening,
                icon: Icon(isRecording ? Icons.stop : Icons.mic),
                label: Text(isRecording ? 'Stop and process' : 'Record update'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('queue-transcript-button'),
                onPressed: _controller.isSaving ? null : _addTranscript,
                child: Text(_controller.isSaving ? 'Saving…' : 'Queue update'),
              ),
              TextButton.icon(
                key: const Key('sync-queue-button'),
                onPressed: _controller.isSyncing ? null : _controller.sync,
                icon: const Icon(Icons.sync),
                label: Text(
                  _controller.isSyncing ? 'Syncing…' : 'Sync pending updates',
                ),
              ),
              if (_voiceCaptureController.message case final voiceMessage?) ...[
                const SizedBox(height: 12),
                _Message(message: voiceMessage),
              ],
              if (_controller.message case final message?) ...[
                const SizedBox(height: 12),
                _Message(message: message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addTranscript() async {
    final added = await _controller.addTranscript(_textController.text);
    if (added && mounted) {
      _textController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  void _applyVoiceTranscript() {
    final transcript = _voiceCaptureController.draftTranscript;
    if (transcript != null && transcript.isNotEmpty) {
      _textController.value = TextEditingValue(
        text: transcript,
        selection: TextSelection.collapsed(offset: transcript.length),
      );
      if (_voiceCaptureController.isCapturing) {
        unawaited(_voiceCaptureController.stopListening());
      }
    }
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (mounted) setState(() {});
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(message, style: Theme.of(context).textTheme.bodyMedium);
  }
}
