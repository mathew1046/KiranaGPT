class ManualAnalysisProposal {
  const ManualAnalysisProposal({
    required this.id,
    required this.operation,
    required this.entryType,
    required this.customerName,
    required this.amount,
    required this.description,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.confidence,
  });

  factory ManualAnalysisProposal.fromJson(Map<String, dynamic> json) {
    final proposal = json['proposal'];
    final proposalId = json['proposal_id'];
    if (json['status'] == 'needs_review') {
      throw ManualAnalysisNeedsReviewException(json['reason']?.toString());
    }
    if (json['status'] != 'ready' ||
        proposal is! Map ||
        proposalId is! String) {
      throw const FormatException('The assistant could not prepare a review.');
    }
    final values = proposal.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    return ManualAnalysisProposal(
      id: proposalId,
      operation: values['operation']?.toString() ?? 'unknown',
      entryType: values['entry_type']?.toString(),
      customerName: values['customer_name']?.toString(),
      amount: values['amount']?.toString(),
      description: values['description']?.toString(),
      itemName: values['item_name']?.toString(),
      quantity: values['quantity']?.toString(),
      unit: values['unit']?.toString(),
      confidence: (values['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String operation;
  final String? entryType;
  final String? customerName;
  final String? amount;
  final String? description;
  final String? itemName;
  final String? quantity;
  final String? unit;
  final double confidence;
}

/// A safe reason returned by the preview endpoint when it cannot make a
/// reviewable proposal. The original transcript remains only on the device.
class ManualAnalysisNeedsReviewException implements Exception {
  const ManualAnalysisNeedsReviewException(String? reason)
    : reason = reason ?? 'unknown';

  final String reason;

  String get message => switch (reason) {
    'model_unavailable' =>
      'Analysis is unavailable right now. Your recording text is still here.',
    'invalid_model_output' =>
      'Analysis needs another try. Your recording text is still here.',
    'confidence_below_threshold' =>
      'Please clarify the update, then analyze it again.',
    'escalation_failed' =>
      'Analysis could not resolve the update. Your recording text is still here.',
    _ => 'Analysis needs review. Your recording text is still here.',
  };
}
