import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../../../core/config.dart';
import '../../../core/security/secure_store.dart';

class SubscriptionApiException implements Exception {
  const SubscriptionApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CheckoutSession {
  const CheckoutSession({required this.keyId, required this.subscriptionId});
  final String keyId;
  final String subscriptionId;
}

class SubscriptionService {
  SubscriptionService(this._secure, [http.Client? client])
      : _client = client ?? http.Client();

  final SecureStore _secure;
  final http.Client _client;
  StreamSubscription<String>? _fcmSubscription;

  Uri _uri(String path) => Uri.parse('${AppConfig.subscriptionApiUrl}$path');

  Future<Map<String, dynamic>> register(String name, String? phone,
      {String? fcmToken}) async {
    _configured();
    fcmToken ??= await _fcmToken();
    final response = await _client.post(_uri('/v1/install'),
        headers: _headers(),
        body: jsonEncode({
          'installId': await _secure.deviceId(),
          'name': name,
          if (phone != null) 'phone': phone,
          if (fcmToken != null) 'fcmToken': fcmToken,
        }));
    final data = _decode(response);
    await _secure.write(SecureStore.subscriptionToken, data['token'] as String);
    await _cache(data);
    return data;
  }

  Future<void> updateFcmToken(String token) async {
    _decode(await _authorized(
        'POST', '/v1/notifications/token', {'fcmToken': token}));
  }

  Future<void> startFcmTokenSync() async {
    if (_fcmSubscription != null || !AppConfig.subscriptionConfigured) return;
    try {
      final token = await _fcmToken();
      if (token != null &&
          await _secure.read(SecureStore.subscriptionToken) != null) {
        await updateFcmToken(token);
      }
      _fcmSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) async {
          try {
            await updateFcmToken(token);
          } catch (_) {
            // A later app start retries with the current token.
          }
        },
      );
    } catch (_) {
      // Firebase is optional until google-services.json is configured.
    }
  }

  Future<String?> _fcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> status() async {
    final data = _decode(await _authorized('GET', '/v1/subscriptions/status'));
    await _cache(data, verified: true);
    return data;
  }

  Future<CheckoutSession> createSubscription() async {
    final data = _decode(await _authorized('POST', '/v1/subscriptions'));
    await _cache(data);
    return CheckoutSession(
      keyId: data['keyId'] as String,
      subscriptionId: data['subscriptionId'] as String,
    );
  }

  Future<Map<String, dynamic>> link(String id) async {
    final data = _decode(await _authorized(
        'POST', '/v1/subscriptions/link', {'subscriptionId': id.trim()}));
    await _cache(data, verified: true);
    return data;
  }

  Future<Map<String, dynamic>> cancel() async {
    final data = _decode(await _authorized('POST', '/v1/subscriptions/cancel'));
    await _cache(data, verified: true);
    return data;
  }

  Future<http.Response> _authorized(String method, String path,
      [Map<String, dynamic>? body]) async {
    _configured();
    final token = await _secure.read(SecureStore.subscriptionToken);
    if (token == null) {
      throw const SubscriptionApiException('Registration is not complete.');
    }
    final headers = _headers(token);
    if (method == 'GET') return _client.get(_uri(path), headers: headers);
    return _client.post(_uri(path),
        headers: headers, body: jsonEncode(body ?? const {}));
  }

  Map<String, String> _headers([String? token]) => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = data['error'] as Map<String, dynamic>?;
      throw SubscriptionApiException(
          error?['message'] as String? ?? 'Subscription request failed.');
    }
    return data;
  }

  Future<void> _cache(Map<String, dynamic> data,
      {bool verified = false}) async {
    final values = {
      SecureStore.subscriptionCustomerId: data['customerId'],
      SecureStore.subscriptionId: data['subscriptionId'],
      SecureStore.subscriptionStatus: data['status'],
    };
    for (final entry in values.entries) {
      if (entry.value is String) {
        await _secure.write(entry.key, entry.value as String);
      }
    }
    if (verified) {
      await _secure.write(SecureStore.subscriptionVerifiedAt,
          '${DateTime.now().millisecondsSinceEpoch}');
    }
  }

  Future<Map<String, String>> cached() async => {
        'status': await _secure.read(SecureStore.subscriptionStatus) ?? 'none',
        'subscriptionId': await _secure.read(SecureStore.subscriptionId) ?? '',
        'verifiedAt':
            await _secure.read(SecureStore.subscriptionVerifiedAt) ?? '0',
      };

  void _configured() {
    if (!AppConfig.subscriptionConfigured) {
      throw const SubscriptionApiException(
          'Subscription service is not configured in this build.');
    }
  }
}
