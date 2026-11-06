import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class OfflinePlace {
  final int id;
  final String osmId;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final double distanceKm;

  const OfflinePlace({
    required this.id,
    required this.osmId,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
  });
}

class OfflinePlacesDatabase {
  static Database? _database;

  static const String _assetPath =
      'assets/offline_places.db';

  static const String _databaseFileName =
      'offline_places_v1.db';

  static Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  static Future<Database> _openDatabase() async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Offline SQLite places are not supported on Web.',
      );
    }

    final directory =
    await getApplicationSupportDirectory();

    final databasePath = p.join(
      directory.path,
      _databaseFileName,
    );

    final file = File(databasePath);

    if (!await file.exists()) {
      debugPrint(
        'COPYING OFFLINE PLACES DATABASE...',
      );

      final data =
      await rootBundle.load(_assetPath);

      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      await file.writeAsBytes(
        bytes,
        flush: true,
      );

      debugPrint(
        'OFFLINE DATABASE COPIED',
      );
    }

    final db = await openDatabase(
      databasePath,
      readOnly: true,
    );

    debugPrint(
      'OFFLINE PLACES DATABASE OPENED',
    );

    return db;
  }

  static Future<List<OfflinePlace>> getNearbyPlaces({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
    String? type,
  }) async {
    final db = await database;

    // Approximate bounding box first.
    final latDelta = radiusKm / 111.0;

    final longitudeFactor =
    cos(latitude * pi / 180).abs();

    final safeLongitudeFactor =
    longitudeFactor < 0.01
        ? 0.01
        : longitudeFactor;

    final lonDelta =
        radiusKm /
            (111.0 * safeLongitudeFactor);

    final minLat = latitude - latDelta;
    final maxLat = latitude + latDelta;
    final minLon = longitude - lonDelta;
    final maxLon = longitude + lonDelta;

    String where = '''
      latitude BETWEEN ? AND ?
      AND longitude BETWEEN ? AND ?
    ''';

    final List<dynamic> args = [
      minLat,
      maxLat,
      minLon,
      maxLon,
    ];

    if (type != null && type.isNotEmpty) {
      where += ' AND type = ?';
      args.add(type);
    }

    final rows = await db.query(
      'places',
      columns: [
        'id',
        'osm_id',
        'name',
        'type',
        'latitude',
        'longitude',
      ],
      where: where,
      whereArgs: args,
    );

    final places = <OfflinePlace>[];

    for (final row in rows) {
      final placeLatitude =
      (row['latitude'] as num).toDouble();

      final placeLongitude =
      (row['longitude'] as num).toDouble();

      final distance = _distanceKm(
        latitude,
        longitude,
        placeLatitude,
        placeLongitude,
      );

      if (distance <= radiusKm) {
        places.add(
          OfflinePlace(
            id: row['id'] as int,
            osmId: row['osm_id'].toString(),
            name:
            (row['name'] ?? '').toString(),
            type: row['type'].toString(),
            latitude: placeLatitude,
            longitude: placeLongitude,
            distanceKm: distance,
          ),
        );
      }
    }

    places.sort(
          (a, b) => a.distanceKm.compareTo(
        b.distanceKm,
      ),
    );

    return places;
  }

  static Future<List<OfflinePlace>>
  getNearbyHospitals({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) {
    return getNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      type: 'hospital',
    );
  }

  static Future<List<OfflinePlace>>
  getNearbyPoliceStations({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) {
    return getNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      type: 'police',
    );
  }

  static Future<List<OfflinePlace>>
  getNearbyFireStations({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) {
    return getNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      type: 'fire_station',
    );
  }

  static Future<List<OfflinePlace>>
  getNearbyShelters({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) {
    return getNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
      type: 'shelter',
    );
  }

  static double _distanceKm(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const earthRadius = 6371.0;

    final dLat =
        (lat2 - lat1) * pi / 180;

    final dLon =
        (lon2 - lon1) * pi / 180;

    final a =
        sin(dLat / 2) *
            sin(dLat / 2) +
            cos(lat1 * pi / 180) *
                cos(lat2 * pi / 180) *
                sin(dLon / 2) *
                sin(dLon / 2);

    final c =
        2 *
            atan2(
              sqrt(a),
              sqrt(1 - a),
            );

    return earthRadius * c;
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}