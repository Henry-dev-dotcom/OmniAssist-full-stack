// Native builds and tests: push needs a platform plugin there (decision 0006).
bool get pushSupported => false;
String get pushPermission => 'unsupported';
Future<Map<String, Object>?> subscribePush(String vapidPublicKey) async => null;
Future<String?> currentPushEndpoint() async => null;
Future<String?> unsubscribePush() async => null;
