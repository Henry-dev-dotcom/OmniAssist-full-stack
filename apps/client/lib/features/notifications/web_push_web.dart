import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web Push in the browser (decision 0006). The service worker (web/sw.js) shows them.
bool get pushSupported =>
    web.window.hasProperty('PushManager'.toJS).toDart &&
    web.window.navigator.hasProperty('serviceWorker'.toJS).toDart;

/// 'granted', 'denied', 'default', or 'unsupported'.
String get pushPermission =>
    pushSupported ? web.Notification.permission : 'unsupported';

String _b64(JSArrayBuffer? key) =>
    base64Url.encode(key!.toDart.asUint8List()).replaceAll('=', '');

Uint8List _decode(String b64url) =>
    base64Url.decode(b64url.padRight((b64url.length + 3) ~/ 4 * 4, '='));

/// Asks for permission (call from a tap) and subscribes. Returns the subscription in
/// PushSubscription.toJSON() shape, or null if the user said no.
Future<Map<String, Object>?> subscribePush(String vapidPublicKey) async {
  if (!pushSupported) return null;
  final answer = (await web.Notification.requestPermission().toDart).toDart;
  if (answer != 'granted') return null;
  final reg = await web.window.navigator.serviceWorker.ready.toDart;
  final sub = await reg.pushManager
      .subscribe(
        web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: _decode(vapidPublicKey).toJS,
        ),
      )
      .toDart;
  return {
    'endpoint': sub.endpoint,
    'keys': {
      'p256dh': _b64(sub.getKey('p256dh')),
      'auth': _b64(sub.getKey('auth')),
    },
  };
}

/// This device's current push address, if it has one.
Future<String?> currentPushEndpoint() async {
  if (!pushSupported) return null;
  final reg = await web.window.navigator.serviceWorker.ready.toDart;
  return (await reg.pushManager.getSubscription().toDart)?.endpoint;
}

/// Stops push on this device; returns the endpoint that was removed.
Future<String?> unsubscribePush() async {
  if (!pushSupported) return null;
  final reg = await web.window.navigator.serviceWorker.ready.toDart;
  final sub = await reg.pushManager.getSubscription().toDart;
  if (sub == null) return null;
  final endpoint = sub.endpoint;
  await sub.unsubscribe().toDart;
  return endpoint;
}
