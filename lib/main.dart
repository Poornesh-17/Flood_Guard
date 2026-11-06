import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/app_language.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message,
    ) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint(
    'Background notification received: ${message.messageId}',
  );
}




Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLanguage.init();

  // Initialize Firebase before starting the app.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  // Register background notification handling.
  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  // Start the UI without waiting for notification initialization.
  runApp(const FloodGuardApp());

  // Initialize notifications separately so they don't block startup.
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Notification initialization error: $e');
  }
}

