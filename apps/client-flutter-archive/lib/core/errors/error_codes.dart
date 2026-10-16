/// Wire names must match packages/contracts/error_codes.md.
enum ErrorCode {
  validationError('VALIDATION_ERROR'),
  unauthenticated('UNAUTHENTICATED'),
  forbidden('FORBIDDEN'),
  notFound('NOT_FOUND'),
  versionConflict('VERSION_CONFLICT'),
  idempotencyKeyReused('IDEMPOTENCY_KEY_REUSED'),
  domainRuleViolation('DOMAIN_RULE_VIOLATION'),
  rateLimited('RATE_LIMITED'),
  dependencyUnavailable('DEPENDENCY_UNAVAILABLE'),
  internalError('INTERNAL_ERROR');

  const ErrorCode(this.wire);
  final String wire;

  /// Unknown codes from a newer server map to [internalError].
  static ErrorCode fromWire(String? value) => ErrorCode.values.firstWhere(
    (c) => c.wire == value,
    orElse: () => ErrorCode.internalError,
  );
}
