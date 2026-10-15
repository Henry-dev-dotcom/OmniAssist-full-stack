import 'error_codes.dart';

class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
    this.details = const {},
    this.requestId,
    this.retryable = false,
  });

  /// Builds an error from the API envelope `{"error": {...}}`.
  factory AppError.fromEnvelope(Map<String, dynamic> json) {
    final e = (json['error'] as Map<String, dynamic>?) ?? const {};
    return AppError(
      code: ErrorCode.fromWire(e['code'] as String?),
      message: (e['message'] as String?) ?? 'Something went wrong.',
      details: (e['details'] as Map<String, dynamic>?) ?? const {},
      requestId: e['request_id'] as String?,
      retryable: (e['retryable'] as bool?) ?? false,
    );
  }

  final ErrorCode code;
  final String message;
  final Map<String, dynamic> details;
  final String? requestId;
  final bool retryable;

  @override
  String toString() => 'AppError(${code.wire}: $message)';
}
