import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineLocationService {
  static const String _queueKey = 'offline_location_queue';

  /// Save a GPS location locally.
  static Future<void> saveOfflineLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? speed,
    double? heading,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final queue = await _getQueue();

    queue.add({
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy ?? 0,
      'speed': speed ?? 0,
      'heading': heading ?? 0,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    // Keep the queue from growing forever.
    // Approximately 24 hours at one point/minute.
    if (queue.length > 1500) {
      queue.removeRange(
        0,
        queue.length - 1500,
      );
    }

    await prefs.setString(
      _queueKey,
      jsonEncode(queue),
    );

    debugPrint(
      'OFFLINE LOCATION SAVED: '
          '$latitude, $longitude',
    );
  }

  /// Upload all locally stored locations to Firebase.
  static Future<void> syncOfflineLocations() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint(
        'OFFLINE LOCATION SYNC: No logged-in user',
      );
      return;
    }

    final queue = await _getQueue();

    if (queue.isEmpty) {
      return;
    }

    debugPrint(
      'OFFLINE LOCATION SYNC STARTED: '
          '${queue.length} locations',
    );

    final firestore = FirebaseFirestore.instance;

    final batch = firestore.batch();

    final historyCollection = firestore
        .collection('users')
        .doc(user.uid)
        .collection('locationHistory');

    int count = 0;

    for (final location in queue) {
      final docRef = historyCollection.doc();

      final timestamp =
      DateTime.tryParse(
        location['timestamp']?.toString() ?? '',
      );

      batch.set(
        docRef,
        {
          'latitude': location['latitude'],
          'longitude': location['longitude'],
          'accuracy': location['accuracy'],
          'speed': location['speed'],
          'heading': location['heading'],
          'timestamp': timestamp == null
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(timestamp),
        },
      );

      count++;

      // Firestore batches have a write limit.
      if (count == 450) {
        await batch.commit();

        debugPrint(
          'OFFLINE LOCATION BATCH UPLOADED: $count',
        );

        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }

    // Remove uploaded locations only after
    // Firebase successfully accepted them.
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_queueKey);

    debugPrint(
      'OFFLINE LOCATION SYNC COMPLETE',
    );
  }

  static Future<List<Map<String, dynamic>>> _getQueue() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_queueKey);

    if (value == null || value.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
      )
          .toList();
    } catch (e) {
      debugPrint(
        'OFFLINE LOCATION QUEUE ERROR: $e',
      );

      return [];
    }
  }
}