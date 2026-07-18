import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/api/manual_analysis_models.dart';
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
  String? _lastAnalyzedVoiceTranscript;

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
    final isProcessing = _voiceCaptureController.isProcessing;
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
              const Text(
                'Record an update to analyze it automatically, or type one to analyze manually.',
              ),
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
                onPressed:
                    _controller.isSaving ||
                        _controller.isApproving ||
                        isProcessing
                    ? null
                    : _toggleVoiceCapture,
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
                      ? 'Stop recording'
                      : 'Record update',
                ),
              ),
              OutlinedButton.icon(
                key: const Key('analyze-manual-transcript-button'),
                onPressed:
                    _controller.isSaving ||
                        _controller.isApproving ||
                        _textController.text.trim().isEmpty
                    ? null
                    : _analyzeTranscript,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  _controller.isSaving ? 'Analyzing…' : 'Analyze typed update',
                ),
              ),
              if (_controller.proposal case final proposal?) ...[
                const SizedBox(height: 18),
                _ReviewCard(
                  proposal: proposal,
                  approving: _controller.isApproving,
                  onDiscard: _controller.isApproving
                      ? null
                      : _controller.discardProposal,
                  onApprove: _controller.isApproving ? null : _approveProposal,
                ),
              ],
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

  Future<void> _analyzeTranscript() async {
    await _controller.analyzeTranscript(_textController.text);
  }

  Future<void> _toggleVoiceCapture() async {
    if (!_voiceCaptureController.isCapturing) {
      // A new recording may legitimately transcribe to the same words as a
      // prior recording, so it still needs a fresh analysis request.
      _lastAnalyzedVoiceTranscript = null;
    }
    await _voiceCaptureController.toggleListening();
  }

  Future<void> _approveProposal() async {
    final approved = await _controller.approveProposal();
    if (approved && mounted) {
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
      if (transcript != _lastAnalyzedVoiceTranscript) {
        _lastAnalyzedVoiceTranscript = transcript;
        // The transcript is already visible and remains editable. Send this
        // one completed recording to analysis immediately so the next screen
        // is the review/approval step.
        _analyzeTranscript();
      }
    }
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (mounted) setState(() {});
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.proposal,
    required this.approving,
    required this.onDiscard,
    required this.onApprove,
  });

  final ManualAnalysisProposal proposal;
  final bool approving;
  final VoidCallback? onDiscard;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (proposal.customerName != null) 'Customer: ${proposal.customerName}',
      if (proposal.amount != null) 'Amount: ₹${proposal.amount}',
      if (proposal.itemName != null) 'Item: ${proposal.itemName}',
      if (proposal.quantity != null)
        'Quantity: ${proposal.quantity}${proposal.unit == null ? '' : ' ${proposal.unit}'}',
      if (proposal.description != null) proposal.description!,
    ];
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review AI judgement',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Chip(label: Text(proposal.operation.replaceAll('_', ' '))),
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(detail),
              ),
            ),
            const SizedBox(height: 6),
            Text('Confidence: ${(proposal.confidence * 100).round()}%'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: onDiscard, child: const Text('Discard')),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: Text(approving ? 'Saving…' : 'Approve & save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
