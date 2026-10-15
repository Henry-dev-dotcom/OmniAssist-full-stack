/// Hands a reminder to the operating system. The platform plugin is [TBD]; until one is
/// added, the app uses [NoopGateway] and every reminder still lands in the in-app center.
abstract interface class NotificationGateway {
  /// False when the user denied (or has not yet granted) system notifications.
  Future<bool> isPermitted();
  Future<void> show({
    required String id,
    required String title,
    required String urgency,
  });
}

class NoopGateway implements NotificationGateway {
  const NoopGateway();
  @override
  Future<bool> isPermitted() async => false;
  @override
  Future<void> show({
    required String id,
    required String title,
    required String urgency,
  }) async {}
}
