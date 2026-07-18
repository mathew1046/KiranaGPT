import 'package:flutter/material.dart';
import 'package:kirana_gpt/core/queue/transcript_queue.dart';
import 'package:kirana_gpt/data/transcript_repository.dart';
import 'package:kirana_gpt/features/manual_entry/manual_entry_controller.dart';

/// Web-safe fallback for approving and syncing a transcript without recording.
class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({required this.repository, super.key});

  final TranscriptRepository repository;

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  late final ManualEntryController _controller;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _controller = ManualEntryController(repository: widget.repository)
      ..addListener(_refresh)
      ..load();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    _textController.dispose();
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
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  40,
                ),
                children: [
                  const _PageIntro(),
                  const SizedBox(height: 24),
                  _ComposerCard(
                    controller: _textController,
                    isSaving: _controller.isSaving,
                    isSyncing: _controller.isSyncing,
                    onAdd: _addTranscript,
                    onSync: _controller.sync,
                  ),
                  if (_controller.message case final message?) ...[
                    const SizedBox(height: 16),
                    _MessageBanner(message: message),
                  ],
                  const SizedBox(height: 28),
                  _QueueHeader(
                    items: _controller.items,
                    isSyncing: _controller.isSyncing,
                    onSync: _controller.sync,
                    onRetryReview: _controller.retryNeedsReview,
                    onClearSynced: _controller.clearSynced,
                  ),
                  const SizedBox(height: 12),
                  if (_controller.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_controller.items.isEmpty)
                    const _EmptyQueue()
                  else
                    ..._controller.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _QueueItem(item: item),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addTranscript() async {
    final added = await _controller.addTranscript(_textController.text);
    if (added && mounted) {
      _textController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add an approved ledger update', style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Type what was said, review it with the shopkeeper, then sync when the service is available.',
            style: textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _ComposerCard extends StatelessWidget {
  const _ComposerCard({
    required this.controller,
    required this.isSaving,
    required this.isSyncing,
    required this.onAdd,
    required this.onSync,
  });

  final TextEditingController controller;
  final bool isSaving;
  final bool isSyncing;
  final Future<void> Function() onAdd;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manual transcript',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Only text is saved locally. Audio is never stored or uploaded.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('manual-transcript-field'),
              controller: controller,
              enabled: !isSaving,
              minLines: 3,
              maxLines: 7,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Approved transcript',
                hintText: 'e.g. Meena paid 500 rupees for the rice order.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('queue-transcript-button'),
                  onPressed: isSaving ? null : onAdd,
                  icon: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_task_outlined),
                  label: Text(isSaving ? 'Saving…' : 'Queue transcript'),
                ),
                OutlinedButton.icon(
                  key: const Key('sync-queue-button'),
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
          ],
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

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

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.items,
    required this.isSyncing,
    required this.onSync,
    required this.onRetryReview,
    required this.onClearSynced,
  });

  final List<QueuedTranscript> items;
  final bool isSyncing;
  final Future<void> Function() onSync;
  final Future<void> Function() onRetryReview;
  final Future<void> Function() onClearSynced;

  @override
  Widget build(BuildContext context) {
    final pending = items
        .where((item) => item.syncState == TranscriptSyncState.pending)
        .length;
    final review = items
        .where((item) => item.syncState == TranscriptSyncState.needsReview)
        .length;
    final synced = items
        .where((item) => item.syncState == TranscriptSyncState.synced)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Transcript queue',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (synced > 0)
              IconButton(
                tooltip: 'Clear synced transcripts',
                onPressed: onClearSynced,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(label: '$pending pending', icon: Icons.schedule),
            if (review > 0)
              _CountChip(
                label: '$review need review',
                icon: Icons.rate_review_outlined,
              ),
            if (synced > 0)
              _CountChip(
                label: '$synced synced',
                icon: Icons.cloud_done_outlined,
              ),
            if (review > 0)
              TextButton.icon(
                onPressed: isSyncing ? null : onRetryReview,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Retry review items'),
              ),
            if (pending > 0)
              TextButton.icon(
                onPressed: isSyncing ? null : onSync,
                icon: const Icon(Icons.sync),
                label: const Text('Sync pending'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.cloud_queue_outlined, size: 36),
            SizedBox(height: 12),
            Text('No transcripts are waiting to sync.'),
          ],
        ),
      ),
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.item});

  final QueuedTranscript item;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.reviewReason;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.transcript,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                _StateChip(state: item.syncState),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Captured ${_formatDateTime(item.capturedAt)} · ${item.attemptCount} sync attempts',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TranscriptSyncState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, textColor) = switch (state) {
      TranscriptSyncState.pending => (
        'Pending',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TranscriptSyncState.syncing => (
        'Syncing',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      TranscriptSyncState.needsReview => (
        'Needs review',
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      TranscriptSyncState.synced => (
        'Synced',
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color,
      labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      side: BorderSide.none,
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final minutes = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month, ${local.hour}:$minutes';
}
