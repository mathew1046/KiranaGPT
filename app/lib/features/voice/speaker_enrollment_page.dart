import 'package:flutter/material.dart';
import 'package:kirana_gpt/features/voice/speaker_enrollment_controller.dart';

/// Consent-first UI for a numeric speaker embedding.
///
/// It runs with an unavailable controller by default so the app remains safe
/// until a host supplies an on-device embedding provider and API gateway.
class SpeakerEnrollmentPage extends StatefulWidget {
  const SpeakerEnrollmentPage({this.controller, super.key});

  final SpeakerEnrollmentController? controller;

  @override
  State<SpeakerEnrollmentPage> createState() => _SpeakerEnrollmentPageState();
}

class _SpeakerEnrollmentPageState extends State<SpeakerEnrollmentPage> {
  late final SpeakerEnrollmentController _controller;
  late final bool _ownsController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? SpeakerEnrollmentController.unavailable();
    _controller.addListener(_refresh);
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    if (_ownsController) {
      _controller.dispose();
    }
    _nameController.dispose();
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
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  40,
                ),
                children: [
                  Text(
                    'Voice profile',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enroll a shopkeeper only with their consent. The app keeps no recording; an on-device adapter sends only a numeric voice embedding for enrollment.',
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enroll a speaker',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'The label stays on this screen and is not part of the voice-embedding request.',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('speaker-enrollment-name'),
                            controller: _nameController,
                            enabled: !_controller.isEnrolling,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Speaker label',
                              hintText: 'e.g. Shop owner',
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const Key('enroll-speaker-button'),
                            onPressed: _controller.isEnrolling ? null : _enroll,
                            icon: _controller.isEnrolling
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_outlined),
                            label: Text(
                              _controller.isEnrolling
                                  ? 'Enrolling…'
                                  : 'Enroll with consent',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_controller.message case final message?) ...[
                    const SizedBox(height: 16),
                    _EnrollmentNotice(
                      message: message,
                      status: _controller.status,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _enroll() async {
    await _controller.enroll(displayName: _nameController.text);
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _EnrollmentNotice extends StatelessWidget {
  const _EnrollmentNotice({required this.message, required this.status});

  final String message;
  final SpeakerEnrollmentStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final successful = status == SpeakerEnrollmentStatus.enrolled;
    final color = successful
        ? scheme.primaryContainer
        : scheme.secondaryContainer;
    final foreground = successful
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                successful ? Icons.verified_outlined : Icons.info_outline,
                color: foreground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: TextStyle(color: foreground)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
