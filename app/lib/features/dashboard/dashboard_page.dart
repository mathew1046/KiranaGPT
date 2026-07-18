import 'package:flutter/material.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_controller.dart';
import 'package:kirana_gpt/features/dashboard/dashboard_models.dart';
import 'package:kirana_gpt/features/voice/voice_capture.dart';
import 'package:kirana_gpt/features/voice/voice_capture_controller.dart';

/// A concise view of the capture, local-queue, and confirmation workflow.
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
    // VAD remains active for the lifetime of this foreground dashboard.
    Future<void>.microtask(_controller.startContinuousCapture);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 640 ? 32.0 : 16.0;
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  40,
                ),
                children: [
                  _DashboardHeader(
                    isLoading: _controller.isLoading,
                    onRefresh: _controller.load,
                  ),
                  if (_controller.message case final message?) ...[
                    const SizedBox(height: 16),
                    _DashboardNotice(message: message),
                  ],
                  const SizedBox(height: 20),
                  _CaptureStatusCard(
                    controller: _controller,
                    transcriptController: _transcriptController,
                    onCapture: _controller.beginCapture,
                    onTranscriptChanged: _controller.updateTranscript,
                  ),
                  const SizedBox(height: 16),
                  _QueueStatusCard(
                    status: _controller.queueStatus,
                    isSyncing: _controller.isSyncing,
                    onSync: _controller.syncQueue,
                  ),
                  const SizedBox(height: 16),
                  _ConfirmationCard(
                    confirmation: _controller.confirmation,
                    isQueueing: _controller.isQueueing,
                    onApprove: _approve,
                    onDismiss: _controller.dismissConfirmation,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _approve() async {
    final added = await _controller.queueApprovedTranscript();
    if (added && mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  void _refresh() {
    final draft = _controller.voiceCapture.draftTranscript ?? '';
    if (_transcriptController.text != draft) {
      _transcriptController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Today at a glance',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Capture text, confirm it with the shopkeeper, then queue it safely.',
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _CaptureStatusCard extends StatelessWidget {
  const _CaptureStatusCard({
    required this.controller,
    required this.transcriptController,
    required this.onCapture,
    required this.onTranscriptChanged,
  });

  final DashboardController controller;
  final TextEditingController transcriptController;
  final Future<void> Function() onCapture;
  final ValueChanged<String> onTranscriptChanged;

  @override
  Widget build(BuildContext context) {
    final voice = controller.voiceCapture;
    final manualOnly =
        voice.availability == VoiceCaptureAvailability.manualOnly;
    final captureLabel = manualOnly
        ? 'Use manual entry'
        : voice.isCapturing
        ? 'Stop listening'
        : 'Start listening';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    manualOnly ? Icons.keyboard_alt_outlined : Icons.mic_none,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture status',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(_captureStatusLabel(voice.status, manualOnly)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('dashboard-transcript-field'),
              controller: transcriptController,
              enabled: !controller.isQueueing,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onTranscriptChanged,
              decoration: const InputDecoration(
                labelText: 'Approved transcript',
                hintText: 'Type or review what the shopkeeper said',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  key: const Key('dashboard-capture-button'),
                  onPressed: controller.isQueueing || voice.isCapturing
                      ? null
                      : onCapture,
                  icon: voice.isCapturing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          manualOnly
                              ? Icons.edit_note_outlined
                              : Icons.mic_none,
                        ),
                  label: Text(captureLabel),
                ),
                if (manualOnly)
                  const _InfoChip(
                    icon: Icons.privacy_tip_outlined,
                    label: 'No audio saved',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _captureStatusLabel(VoiceCaptureStatus status, bool manualOnly) {
    switch (status) {
      case VoiceCaptureStatus.ready:
        return manualOnly
            ? 'Manual text entry is ready'
            : 'Starting continuous listening';
      case VoiceCaptureStatus.capturing:
        return 'Listening continuously; speech turns are transcribed automatically';
      case VoiceCaptureStatus.manualEntry:
        return 'Type the approved transcript';
      case VoiceCaptureStatus.transcriptReady:
        return 'Transcript ready for confirmation';
      case VoiceCaptureStatus.cancelled:
        return 'Capture was cancelled';
      case VoiceCaptureStatus.failed:
        return 'Use manual text entry instead';
    }
  }
}

class _QueueStatusCard extends StatelessWidget {
  const _QueueStatusCard({
    required this.status,
    required this.isSyncing,
    required this.onSync,
  });

  final DashboardQueueStatus status;
  final bool isSyncing;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Queue status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${status.total} total'),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QueueMetric(
                  label: 'Pending',
                  value: status.pending,
                  icon: Icons.schedule,
                ),
                _QueueMetric(
                  label: 'Syncing',
                  value: status.syncing,
                  icon: Icons.sync,
                ),
                _QueueMetric(
                  label: 'Review',
                  value: status.needsReview,
                  icon: Icons.rate_review_outlined,
                ),
                _QueueMetric(
                  label: 'Synced',
                  value: status.synced,
                  icon: Icons.cloud_done_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('dashboard-sync-button'),
              onPressed: isSyncing ? null : onSync,
              icon: isSyncing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(isSyncing ? 'Syncing…' : 'Sync queue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.confirmation,
    required this.isQueueing,
    required this.onApprove,
    required this.onDismiss,
  });

  final DashboardConfirmation? confirmation;
  final bool isQueueing;
  final Future<void> Function() onApprove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final item = confirmation;
    final isQueued = item?.state == DashboardConfirmationState.queued;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: item == null
            ? const _EmptyConfirmation()
            : Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isQueued
                              ? Icons.check_circle_outline
                              : Icons.fact_check_outlined,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isQueued ? 'Queued confirmation' : 'Confirm update',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (isQueued)
                          IconButton(
                            tooltip: 'Dismiss confirmation',
                            onPressed: onDismiss,
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(item.message),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(item.transcript),
                      ),
                    ),
                    if (!isQueued) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('dashboard-approve-button'),
                        onPressed: isQueueing ? null : onApprove,
                        icon: isQueueing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_task_outlined),
                        label: Text(
                          isQueueing ? 'Queueing…' : 'Approve and queue',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _EmptyConfirmation extends StatelessWidget {
  const _EmptyConfirmation();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.fact_check_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirmation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'A captured or typed transcript will appear here for approval.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QueueMetric extends StatelessWidget {
  const _QueueMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text('$value $label'),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
