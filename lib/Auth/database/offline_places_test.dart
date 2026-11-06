import 'package:flutter/foundation.dart';

import 'offline_places_database.dart';

Future<void> testOfflinePlaces({
  required double latitude,
  required double longitude,
}) async {
  try {
    debugPrint(
      '==============================',
    );

    debugPrint(
      'TESTING OFFLINE PLACES DATABASE',
    );

    final places =
    await OfflinePlacesDatabase.getNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
      radiusKm: 10,
    );

    debugPrint(
      'PLACES FOUND: ${places.length}',
    );

    for (final place in places.take(10)) {
      debugPrint(
        '${place.type} | '
            '${place.name} | '
            '${place.distanceKm.toStringAsFixed(2)} km',
      );
    }

    debugPrint(
      '==============================',
    );
  } catch (e, stackTrace) {
    debugPrint(
      'OFFLINE DATABASE ERROR: $e',
    );

    debugPrint('$stackTrace');
  }
}