import 'package:flutter/foundation.dart';

/// Produces a numeric voice embedding from a short-lived, on-device sample.
///
/// Implementations must discard the sample before this future completes. The
/// feature receives only the numeric embedding; it never receives raw audio.
typedef SpeakerEmbeddingProvider = Future<List<double>?> Function();

/// The payload accepted by the `/v1/enroll-speaker` contract.
class SpeakerEnrollmentRequest {
  SpeakerEnrollmentRequest({required List<double> embedding})
    : embedding = List<double>.unmodifiable(embedding) {
    if (this.embedding.isEmpty) {
      throw ArgumentError.value(embedding, 'embedding', 'must not be empty');
    }
    if (this.embedding.any((value) => !value.isFinite)) {
      throw ArgumentError.value(
        embedding,
        'embedding',
        'must contain finite numeric values only',
      );
    }
  }

  /// This intentionally excludes an audio payload and the optional UI label.
  final List<double> embedding;

  Map<String, Object> toJson() => {'embedding': embedding};
}

class SpeakerEnrollmentReceipt {
  const SpeakerEnrollmentReceipt({this.speakerId, this.message});

  final String? speakerId;
  final String? message;
}

abstract interface class SpeakerEnrollmentGateway {
  Future<SpeakerEnrollmentReceipt> enroll(SpeakerEnrollmentRequest request);
}

enum SpeakerEnrollmentStatus { idle, enrolling, enrolled, unavailable, failed }

/// UI state for consented voice-profile enrollment.
///
/// A display label is used only for the current UI message. It is never added
/// to the embedding request or persisted by this controller.
class SpeakerEnrollmentController extends ChangeNotifier {
  SpeakerEnrollmentController({
    required SpeakerEmbeddingProvider embeddingProvider,
    required SpeakerEnrollmentGateway gateway,
  }) : _embeddingProvider = embeddingProvider,
       _gateway = gateway;

  factory SpeakerEnrollmentController.unavailable() {
    return SpeakerEnrollmentController(
      embeddingProvider: _unavailableEmbeddingProvider,
      gateway: const _UnavailableSpeakerEnrollmentGateway(),
    );
  }

  final SpeakerEmbeddingProvider _embeddingProvider;
  final SpeakerEnrollmentGateway _gateway;

  SpeakerEnrollmentStatus _status = SpeakerEnrollmentStatus.idle;
  SpeakerEnrollmentReceipt? _receipt;
  String? _message;

  SpeakerEnrollmentStatus get status => _status;
  SpeakerEnrollmentReceipt? get receipt => _receipt;
  String? get message => _message;
  bool get isEnrolling => _status == SpeakerEnrollmentStatus.enrolling;

  Future<bool> enroll({required String displayName}) async {
    final cleanName = displayName.trim();
    if (cleanName.isEmpty) {
      _status = SpeakerEnrollmentStatus.failed;
      _message = 'Add a label before enrolling a voice profile.';
      notifyListeners();
      return false;
    }

    _status = SpeakerEnrollmentStatus.enrolling;
    _receipt = null;
    _message = null;
    notifyListeners();

    try {
      final embedding = await _embeddingProvider();
      if (embedding == null || embedding.isEmpty) {
        _status = SpeakerEnrollmentStatus.unavailable;
        _message = 'Voice-profile capture is not available in this build.';
        return false;
      }

      final receipt = await _gateway.enroll(
        SpeakerEnrollmentRequest(embedding: embedding),
      );
      _receipt = receipt;
      _status = SpeakerEnrollmentStatus.enrolled;
      _message = receipt.message ?? '$cleanName\'s voice profile is enrolled.';
      return true;
    } on ArgumentError {
      _status = SpeakerEnrollmentStatus.failed;
      _message = 'The voice profile could not be validated. Please try again.';
      return false;
    } catch (_) {
      _status = SpeakerEnrollmentStatus.failed;
      _message =
          'Voice-profile enrollment could not finish. No audio was saved.';
      return false;
    } finally {
      notifyListeners();
    }
  }

  void reset() {
    _status = SpeakerEnrollmentStatus.idle;
    _receipt = null;
    _message = null;
    notifyListeners();
  }
}

Future<List<double>?> _unavailableEmbeddingProvider() async => null;

class _UnavailableSpeakerEnrollmentGateway implements SpeakerEnrollmentGateway {
  const _UnavailableSpeakerEnrollmentGateway();

  @override
  Future<SpeakerEnrollmentReceipt> enroll(SpeakerEnrollmentRequest request) {
    throw StateError('Speaker enrollment is not configured.');
  }
}
