
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
NotificationService._();

static final NotificationService instance = NotificationService._();

final FirebaseMessaging _messaging = FirebaseMessaging.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

StreamSubscription<User?>? _authSubscription;
StreamSubscription<String>? _tokenSubscription;
StreamSubscription<RemoteMessage>? _messageSubscription;

bool _initialized = false;

static const AndroidNotificationChannel _channel =
AndroidNotificationChannel(
'floodguard_alerts',
'FloodGuard Alerts',
description: 'Weather and flood risk notifications',
importance: Importance.high,
);

// ============================================================
// INITIALIZATION
// ============================================================

Future<void> initialize() async {
if (_initialized) return;

_initialized = true;

try {
const androidSettings =
AndroidInitializationSettings('@mipmap/ic_launcher');

const settings = InitializationSettings(
android: androidSettings,
);

await _localNotifications.initialize(
settings,
);

final androidPlugin = _localNotifications
    .resolvePlatformSpecificImplementation<
AndroidFlutterLocalNotificationsPlugin>();

await androidPlugin?.createNotificationChannel(_channel);

final permission = await _messaging.requestPermission(
alert: true,
badge: true,
sound: true,
);

debugPrint(
'Notification permission: ${permission.authorizationStatus}',
);

_authSubscription =
FirebaseAuth.instance.authStateChanges().listen((user) {
if (user != null) {
_registerToken();
}
});

_tokenSubscription = _messaging.onTokenRefresh.listen((token) {
_saveToken(token);
});

_messageSubscription =
FirebaseMessaging.onMessage.listen((message) async {
final notification = message.notification;

if (notification == null) return;

await _showLocalNotification(
id: notification.hashCode,
title: notification.title ?? 'FloodGuard Alert',
body: notification.body ?? '',
);
});

FirebaseMessaging.onMessageOpenedApp.listen((message) {
debugPrint(
'Notification opened: ${message.messageId}',
);
});

final initialMessage = await _messaging.getInitialMessage();

if (initialMessage != null) {
debugPrint(
'App launched from notification: '
'${initialMessage.messageId}',
);
}

if (FirebaseAuth.instance.currentUser != null) {
await _registerToken();
}

debugPrint('FloodGuard NotificationService initialized.');
} catch (e, stackTrace) {
_initialized = false;

debugPrint('Notification initialization failed: $e');
debugPrint('$stackTrace');

rethrow;
}
}

// ============================================================
// USER PREFERENCES
// ============================================================

Future<bool> _isAlertEnabled(String field) async {
final user = FirebaseAuth.instance.currentUser;

// Do not send account-specific alerts when signed out.
if (user == null) return false;

try {
final document =
await _firestore.collection('users').doc(user.uid).get();

final data = document.data();

// Preserve the existing default: alerts enabled unless
// the user explicitly switches them off.
if (data == null || !data.containsKey(field)) {
return true;
}

return data[field] == true;
} catch (e) {
// Fail closed if preferences cannot be verified.
debugPrint('Unable to read $field preference: $e');
return false;
}
}

Future<bool> areWeatherAlertsEnabled() {
return _isAlertEnabled('weatherAlerts');
}

Future<bool> areFloodAlertsEnabled() {
return _isAlertEnabled('floodAlerts');
}

// ============================================================
// LOCAL NOTIFICATION HELPER
// ============================================================

  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
// ============================================================
// DUPLICATE PREVENTION
// ============================================================

Future<bool> _alreadySent(String key) async {
final preferences = await SharedPreferences.getInstance();
return preferences.getBool(key) ?? false;
}

Future<void> _markAsSent(String key) async {
final preferences = await SharedPreferences.getInstance();
await preferences.setBool(key, true);
}

String _hourKey(DateTime time) {
final local = time.toLocal();

return '${local.year}_'
'${local.month.toString().padLeft(2, '0')}_'
'${local.day.toString().padLeft(2, '0')}_'
'${local.hour.toString().padLeft(2, '0')}';
}

// ============================================================
// WEATHER ALERTS
// ============================================================

/// Sends a weather notification for an upcoming forecast hour.
///
/// Call this method from the home screen when hourly forecast
/// data is available.
///
/// Weather notifications are controlled ONLY by weatherAlerts.
///
/// Suggested trigger conditions:
/// - Precipitation probability >= 60%, OR
/// - Forecast rainfall >= 2 mm, OR
/// - Thunderstorm weather code >= 95.
Future<void> checkWeatherForecast({
required DateTime forecastTime,
required double rainfallMm,
required double precipitationProbability,
required int weatherCode,
}) async {
try {
if (!await areWeatherAlertsEnabled()) return;

final probability = precipitationProbability.clamp(0.0, 100.0);

final isRainExpected =
probability >= 60 || rainfallMm >= 2;

final isThunderstorm = weatherCode >= 95;

// Avoid sending notifications for every ordinary forecast.
if (!isRainExpected && !isThunderstorm) return;

final hourKey = _hourKey(forecastTime);
final notificationKey = 'weather_alert_$hourKey';

if (await _alreadySent(notificationKey)) return;

final timeText =
'${forecastTime.toLocal().hour.toString().padLeft(2, '0')}:'
'${forecastTime.toLocal().minute.toString().padLeft(2, '0')}';

final title = isThunderstorm
? '⛈️ Thunderstorm Alert'
    : '🌧️ Rain Forecast Alert';

final body = isThunderstorm
? 'A thunderstorm is forecast around $timeText. '
'Stay indoors and follow official weather advisories.'
    : 'Rain is forecast around $timeText. '
'Rainfall: ${rainfallMm.toStringAsFixed(1)} mm. '
'Rain probability: ${probability.toStringAsFixed(0)}%.';

// Mark only after showing successfully so a failed attempt
// can be retried later.
await _showLocalNotification(
id: 41001 + forecastTime.toLocal().hour,
title: title,
body: body,
);

await _markAsSent(notificationKey);

debugPrint('Weather alert sent for $forecastTime');
} catch (e) {
debugPrint('Weather alert error: $e');
}
}

// ============================================================
// FLOOD RISK ALERTS
// ============================================================

/// Displays an Orange or Red flood warning.
///
/// Accepted risk labels:
/// - ORANGE / MODERATE / MEDIUM -> Orange warning
/// - RED / HIGH -> Red warning
///
/// This method checks ONLY floodAlerts.
///
/// IMPORTANT:
/// expectedTime must come from a genuine future-risk forecast.
/// Passing the current prediction time does not create a
/// reliable two-hour forecast.
Future<void> showFloodRiskAlert({
required String risk,
required DateTime expectedTime,
}) async {
try {
if (!await areFloodAlertsEnabled()) return;

final normalizedRisk = risk.trim().toUpperCase();

final bool isRed =
normalizedRisk == 'RED' || normalizedRisk == 'HIGH';

final bool isOrange =
normalizedRisk == 'ORANGE' ||
normalizedRisk == 'MODERATE' ||
normalizedRisk == 'MEDIUM';

if (!isRed && !isOrange) return;

final now = DateTime.now();
final timeUntilRisk = expectedTime.difference(now);

// Ignore forecasts that have already passed.
if (timeUntilRisk.isNegative) return;

final hourKey = _hourKey(expectedTime);

final notificationKey =
'flood_alert_${isRed ? 'red' : 'orange'}_$hourKey';

if (await _alreadySent(notificationKey)) return;

final expectedTimeText =
'${expectedTime.toLocal().hour.toString().padLeft(2, '0')}:'
'${expectedTime.toLocal().minute.toString().padLeft(2, '0')}';

final title = isRed
? '🚨 RED FLOOD RISK WARNING'
    : '⚠️ ORANGE FLOOD RISK WARNING';

final body = isRed
? 'High flood risk is forecast for $expectedTimeText. '
'Move to a safer location if necessary and follow '
'official emergency instructions.'
    : 'Increased flood risk is forecast for $expectedTimeText. '
'Stay alert, monitor water levels, and follow '
'official advisories.';

await _showLocalNotification(
id: isRed ? 902 : 901,
title: title,
body: body,
);

await _markAsSent(notificationKey);

debugPrint(
'Flood alert sent: $normalizedRisk at $expectedTime',
);
} catch (e) {
debugPrint('Flood alert error: $e');
}
}

// ============================================================
// FCM TOKEN REGISTRATION
// ============================================================

Future<void> getFCMToken() async {
try {
await _messaging.requestPermission();

final token = await _messaging.getToken();

debugPrint('====================================');
debugPrint('FLOODGUARD FCM TOKEN:');
debugPrint('$token');
debugPrint('====================================');
} catch (e) {
debugPrint('Unable to get FCM token: $e');
}
}

Future<void> _registerToken() async {
try {
final token = await _messaging.getToken();
debugPrint('FLOODGUARD CURRENT DEVICE TOKEN: $token');

if (token != null) {
await _saveToken(token);
}
} catch (e) {
debugPrint('FCM token registration failed: $e');
}
}

Future<void> _saveToken(String token) async {
final user = FirebaseAuth.instance.currentUser;

if (user == null) return;

try {
await _firestore.collection('users').doc(user.uid).set({
'fcmTokens': FieldValue.arrayUnion([token]),
'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));
} catch (e) {
debugPrint('Unable to save FCM token: $e');
}
}

// ============================================================
// CLEANUP
// ============================================================

Future<void> dispose() async {
await _authSubscription?.cancel();
await _tokenSubscription?.cancel();
await _messageSubscription?.cancel();

_authSubscription = null;
_tokenSubscription = null;
_messageSubscription = null;

_initialized = false;
}
}

