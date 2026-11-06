import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class OfflineRoad {
  final int id;
  final String osmId;
  final String name;
  final String fclass;
  final String oneway;
  final String geometry;

  const OfflineRoad({
    required this.id,
    required this.osmId,
    required this.name,
    required this.fclass,
    required this.oneway,
    required this.geometry,
  });
}

class OfflineRoadsDatabase {
  static Database? _database;

  static const String _assetPath =
      'assets/offline_roads.db';

  static const String _databaseFileName =
      'offline_roads_v1.db';

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
        'Offline road routing is not supported on Web.',
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
        'COPYING OFFLINE ROADS DATABASE...',
      );

      final data =
      await rootBundle.load(_assetPath);

      final bytes =
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      await file.writeAsBytes(
        bytes,
        flush: true,
      );

      debugPrint(
        'OFFLINE ROADS DATABASE COPIED',
      );
    }

    final db = await openDatabase(
      databasePath,
      readOnly: true,
    );

    debugPrint(
      'OFFLINE ROADS DATABASE OPENED',
    );

    return db;
  }

  static Future<List<OfflineRoad>> getNearbyRoads({
    required double latitude,
    required double longitude,
    double radiusKm = 2,
  }) async {
    final db = await database;

    final latDelta =
        radiusKm / 111.0;

    final longitudeFactor =
    cos(latitude * pi / 180).abs();

    final safeLongitudeFactor =
    longitudeFactor < 0.01
        ? 0.01
        : longitudeFactor;

    final lonDelta =
        radiusKm /
            (111.0 * safeLongitudeFactor);

    final minLat =
        latitude - latDelta;

    final maxLat =
        latitude + latDelta;

    final minLon =
        longitude - lonDelta;

    final maxLon =
        longitude + lonDelta;

    final rows = await db.rawQuery(
      '''
      SELECT
        id,
        osm_id,
        name,
        fclass,
        oneway,
        geometry
      FROM roads
      WHERE geometry != ''
      ''',
    );

    final roads = <OfflineRoad>[];

    for (final row in rows) {
      final geometry =
          row['geometry']?.toString() ?? '';

      if (geometry.isEmpty) {
        continue;
      }

      // Quick textual bounding-box check
      // is intentionally avoided here because
      // geometry is stored as a polyline.
      //
      // The routing engine will perform the
      // actual nearest-road filtering.

      roads.add(
        OfflineRoad(
          id: row['id'] as int,
          osmId:
          row['osm_id']?.toString() ?? '',
          name:
          row['name']?.toString() ?? '',
          fclass:
          row['fclass']?.toString() ?? '',
          oneway:
          row['oneway']?.toString() ?? '',
          geometry: geometry,
        ),
      );
    }

    debugPrint(
      'OFFLINE ROAD RECORDS LOADED: '
          '${roads.length}',
    );

    return roads;
  }

  static Future<void> close() async {
    await _database?.close();

    _database = null;
  }
}