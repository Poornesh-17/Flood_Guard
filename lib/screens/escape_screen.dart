import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../services/app_language.dart';
import '../services/offline_routing_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_map_vector_tiles_mbtiles/flutter_map_vector_tiles_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../Auth/database/offline_places_database.dart';

import '../models/flood_risk_cell.dart';
import '../services/flood_map_service.dart';
import '../services/weather_services.dart';
class EscapeScreen extends StatefulWidget {
  const EscapeScreen({super.key});

  @override
  State<EscapeScreen> createState() =>
      _EscapeScreenState();
}

class _EscapeScreenState extends State<EscapeScreen> {
  // ==========================================================
  // LOCATION
  // ==========================================================
  final MapController _mapController = MapController();

  MbTilesVectorTileProvider? _offlineMapProvider;
  vt.Style? _offlineStyle;

  bool _offlineMapReady = false;
  bool _mapInternetAvailable = false;
  bool _mapInitializing = true;

  Timer? _mapNetworkTimer;
  LatLng? currentLocation;

  bool locationLoading = true;
  Map<String, dynamic>? routeRisk;

  void _fitMapToRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        _mapController.move(points.first, 15);
        return;
      }
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    } catch (e) {
      debugPrint('Error fitting camera to route: $e');
    }
  }

  // ==========================================================
  // WEATHER
  // ==========================================================

  final WeatherService weatherService =
  WeatherService();
  final OfflineRoutingService offlineRoutingService =
  OfflineRoutingService();
  WeatherData? weatherData;

  bool weatherLoading = true;


  // ==========================================================
  // FLOOD MODEL / MAP
  // ==========================================================

  final FloodMapService floodMapService =
  FloodMapService();

  List<FloodRiskCell> floodRiskCells = [];

  bool floodMapLoading = true;

  double floodProbability = 0.0;

  bool showFloodOverlay = false;

  // ==========================================================
  // ROUTE
  // ==========================================================

  bool routeLoading = false;

  List<LatLng> escapeRoute = [];

  // ==========================================================
  // FLOODED ROADS
  //
  // Kept empty because your TensorFlow model currently
  // predicts flood-risk areas, not individual road closures.
  // ==========================================================

  final List<LatLng> floodedRoad = [];

  // ==========================================================
  // SAFE PLACES
  // ==========================================================

  List<SafePlace> safePlaces = [];

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    getCurrentLocation();

    _loadOfflineMap();

    _updateMapNetworkStatus();

    _startMapNetworkMonitor();

    loadFloodRiskMap();
  }
  Future<bool> createOfflineRoute(
      SafePlace destination,
      ) async {
    if (currentLocation == null) {
      debugPrint(
        'OFFLINE ROUTING: GPS location unavailable.',
      );

      return false;
    }

    try {
      final start = currentLocation!;

      debugPrint(
        '========================================',
      );
      debugPrint(
        'OFFLINE A* ROUTING',
      );
      debugPrint(
        'START: '
            '${start.latitude}, ${start.longitude}',
      );
      debugPrint(
        'DESTINATION: '
            '${destination.latitude}, '
            '${destination.longitude}',
      );
      debugPrint(
        '========================================',
      );

      final result =
      await offlineRoutingService.findRoute(
        start: start,
        destination: LatLng(
          destination.latitude,
          destination.longitude,
        ),
      );

      if (result == null) {
        debugPrint(
          'OFFLINE ROUTING: No route returned.',
        );

        return false;
      }

      if (result.points.isEmpty) {
        debugPrint(
          'OFFLINE ROUTING: Route has no points.',
        );

        return false;
      }

      final risk =
      evaluateRouteRisk(
        result.points,
      );

      debugPrint(
        '========================================',
      );
      debugPrint(
        '✅ OFFLINE ROUTE FOUND',
      );
      debugPrint(
        'ROUTE POINTS: ${result.points.length}',
      );
      debugPrint(
        'DISTANCE: '
            '${result.distanceKm.toStringAsFixed(2)} km',
      );
      debugPrint(
        'NODES VISITED: ${result.visitedNodes}',
      );
      debugPrint(
        'ROUTE RISK: $risk',
      );
      debugPrint(
        '========================================',
      );

      if (!mounted) {
        return false;
      }

      setState(() {
        escapeRoute =
        List<LatLng>.from(result.points);

        routeRisk = risk;
      });

      if (result.points.isNotEmpty) {
        _fitMapToRoute(result.points);
      }

      showMessage(
        'Offline route found '
            '(${result.distanceKm.toStringAsFixed(2)} km).',
      );

      return true;
    } catch (e, stackTrace) {
      debugPrint(
        '========================================',
      );
      debugPrint(
        'OFFLINE ROUTING ERROR',
      );
      debugPrint(
        '$e',
      );
      debugPrint(
        '$stackTrace',
      );
      debugPrint(
        '========================================',
      );

      return false;
    }
  }
  Future<void> _loadOfflineMap() async {
    if (kIsWeb) {
      debugPrint(
        'ESCAPE OFFLINE MAP: Web is not supported.',
      );
      return;
    }

    try {
      debugPrint(
        '========================================',
      );
      debugPrint(
        'LOADING ESCAPE OFFLINE OSM MAP',
      );

      final mbtilesPath =
      await _copyMbtilesAsset(
        'assets/offline_maps/karnataka_south.mbtiles',
        'karnataka_complete_v3.mbtiles',
      );

      debugPrint(
        'ESCAPE MBTILES PATH: $mbtilesPath',
      );

      final provider =
      await MbTilesVectorTileProvider.open(
        mbtilesPath,
        logger: const vt.Logger.console(),
      );

      debugPrint(
        'ESCAPE MBTILES FORMAT: '
            '${provider.metadata.format}',
      );

      debugPrint(
        'ESCAPE MBTILES BOUNDS: '
            '${provider.metadata.bounds}',
      );

      debugPrint(
        'ESCAPE MBTILES ZOOM: '
            '${provider.metadata.minZoom} - '
            '${provider.metadata.maxZoom}',
      );

      if (!mounted) {
        provider.dispose();
        return;
      }

      _offlineMapProvider = provider;

      _offlineStyle =
      await vt.StyleReader(
        uri:
        'asset://assets/offline_maps/shortbread_offline_style.json',
        logger: const vt.Logger.console(),
        resolveProvider: (sourceId) async {
          debugPrint(
            'ESCAPE STYLE SOURCE: $sourceId',
          );

          if (sourceId == 'shortbread') {
            return provider;
          }

          return null;
        },
      ).read();

      if (!mounted) return;

      setState(() {
        _offlineMapReady = true;
        _mapInitializing = false;
      });

      debugPrint(
        '========================================',
      );
      debugPrint(
        'ESCAPE OFFLINE OSM MAP READY',
      );
      debugPrint(
        '========================================',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '========================================',
      );
      debugPrint(
        'ESCAPE OFFLINE MAP ERROR',
      );
      debugPrint('$e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _offlineMapReady = false;
        _mapInitializing = false;
      });
    }
  }
  Future<bool> _checkInternetConnection() async {
    if (kIsWeb) return true;

    try {
      final response = await http.get(
        Uri.parse(
          'https://tile.openstreetmap.org/1/1/1.png',
        ),
        headers: {
          'User-Agent': 'FloodGuard/1.0',
        },
      ).timeout(
        const Duration(seconds: 5),
      );

      return response.statusCode == 200 &&
          response.bodyBytes.isNotEmpty;
    } catch (e) {
      debugPrint('MAP TILE CONNECTION ERROR: $e');
      return false;
    }
  }
  void _startMapNetworkMonitor() {
    _mapNetworkTimer?.cancel();

    _mapNetworkTimer =
        Timer.periodic(
          const Duration(seconds: 10),
              (_) {
            _updateMapNetworkStatus();
          },
        );
  }
  Future<void> _updateMapNetworkStatus() async {
    final connected =
    await _checkInternetConnection();

    if (!mounted) return;

    setState(() {
      _mapInternetAvailable = connected;
    });

    debugPrint(
      'ESCAPE MAP INTERNET: $connected',
    );
  }
  Future<String> _copyMbtilesAsset(
      String assetPath,
      String fileName,
      ) async {
    final supportDirectory =
    await getApplicationSupportDirectory();

    final mapsDirectory =
    Directory(
      '${supportDirectory.path}/offline_maps',
    );

    if (!await mapsDirectory.exists()) {
      await mapsDirectory.create(
        recursive: true,
      );
    }

    final destination =
    File('${mapsDirectory.path}/$fileName');

    if (!await destination.exists()) {
      debugPrint(
        'COPYING ESCAPE OFFLINE MAP...',
      );

      final byteData =
      await rootBundle.load(assetPath);

      final bytes =
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      await destination.writeAsBytes(
        bytes,
        flush: true,
      );

      debugPrint(
        'ESCAPE OFFLINE MAP COPIED: '
            '${destination.path}',
      );
    }

    return destination.path;
  }
  Future<bool> hasInternetConnection() async {
    final connected = await _checkInternetConnection();
    if (connected) return true;

    try {
      final result = await InternetAddress.lookup(
        'overpass-api.de',
      ).timeout(
        const Duration(seconds: 3),
      );

      return result.isNotEmpty &&
          result.any(
                (address) => address.rawAddress.isNotEmpty,
          );
    } catch (_) {
      return false;
    }
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
  String getRiskAtPoint(LatLng point) {
    for (final cell in floodRiskCells) {
      final insideLatitude =
          point.latitude >=
              math.min(
                cell.latitude,
                cell.latitude2,
              ) &&
              point.latitude <=
                  math.max(
                    cell.latitude,
                    cell.latitude2,
                  );

      final insideLongitude =
          point.longitude >=
              math.min(
                cell.longitude,
                cell.longitude2,
              ) &&
              point.longitude <=
                  math.max(
                    cell.longitude,
                    cell.longitude2,
                  );

      if (insideLatitude && insideLongitude) {
        return cell.risk.toLowerCase();
      }
    }

    return 'unknown';
  }
  Map<String, dynamic> evaluateRouteRisk(
      List<LatLng> route,
      ) {
    int red = 0;
    int orange = 0;
    int green = 0;
    int unknown = 0;

    for (final point in route) {
      final risk = getRiskAtPoint(point);

      switch (risk) {
        case 'red':
          red++;
          break;

        case 'orange':
          orange++;
          break;

        case 'green':
          green++;
          break;

        default:
          unknown++;
      }
    }

    final total =
        red + orange + green + unknown;

    final redPercentage =
    total == 0
        ? 0.0
        : red / total;

    final orangePercentage =
    total == 0
        ? 0.0
        : orange / total;

    return {
      'red': red,
      'orange': orange,
      'green': green,
      'unknown': unknown,
      'redPercentage': redPercentage,
      'orangePercentage': orangePercentage,
      'dangerous':
      redPercentage >= 0.20,
      'warning':
      orangePercentage >= 0.30,
    };
  }

  // ==========================================================
  // GPS
  // ==========================================================

  Future<void> getCurrentLocation() async {
    try {
      final serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          locationLoading = false;
        });

        showMessage(
          'Please turn on Location/GPS.',
        );

        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
        await Geolocator.requestPermission();
      }

      if (permission ==
          LocationPermission.denied ||
          permission ==
              LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          locationLoading = false;
        });

        showMessage(
          'Location permission is required.',
        );

        return;
      }

      final position =
      await Geolocator.getCurrentPosition(
        locationSettings:
        const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        currentLocation = LatLng(
          position.latitude,
          position.longitude,
        );

        locationLoading = false;
      });

      debugPrint(
        'CURRENT GPS: '
            '${position.latitude}, '
            '${position.longitude}',
      );

      // Get weather for ACTUAL GPS location.
      await loadWeather();
    } catch (e) {
      debugPrint(
        'LOCATION ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        locationLoading = false;
      });

      showMessage(
        'Unable to get current location.',
      );
    }
  }
  Widget buildRouteRiskCard() {
    if (routeRisk == null) {
      return const SizedBox.shrink();
    }

    final red =
    routeRisk!['red'] as int;

    final orange =
    routeRisk!['orange'] as int;

    final green =
    routeRisk!['green'] as int;

    final dangerous =
    routeRisk!['dangerous'] as bool;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        top: 18,
      ),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151111),
        borderRadius:
        BorderRadius.circular(20),
        border: Border.all(
          color: dangerous
              ? Colors.red
              : Colors.green,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dangerous
                    ? Icons.warning_rounded
                    : Icons.verified_rounded,
                color: dangerous
                    ? Colors.red
                    : Colors.green,
              ),
              const SizedBox(
                width: 10,
              ),
              Text(
                dangerous
                    ? AppLanguage.tr('route_has_risk')
                    : AppLanguage.tr('route_risk_acceptable'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 14,
          ),

          Text(
            '🔴 ${AppLanguage.tr("high_risk_areas")}: $red',
            style: const TextStyle(
              color: Colors.red,
            ),
          ),

          const SizedBox(
            height: 6,
          ),

          Text(
            '🟠 ${AppLanguage.tr("medium_risk_areas")}: $orange',
            style: const TextStyle(
              color: Colors.orange,
            ),
          ),

          const SizedBox(
            height: 6,
          ),

          Text(
            '🟢 ${AppLanguage.tr("low_risk_areas")}: $green',
            style: const TextStyle(
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // WEATHER
  // ==========================================================

  Future<void> loadWeather() async {
    if (currentLocation == null) {
      return;
    }

    try {
      final weather =
      await weatherService.getWeather(
        latitude:
        currentLocation!.latitude,
        longitude:
        currentLocation!.longitude,
      );

      if (!mounted) return;

      setState(() {
        weatherData = weather;
        weatherLoading = false;
      });

      debugPrint(
        'RAINFALL: ${weather.rainfall}',
      );

      debugPrint(
        'RAIN PROBABILITY: '
            '${weather.precipitationProbability}',
      );

      debugPrint(
        'WEATHER CODE: '
            '${weather.weatherCode}',
      );

      updateFloodMapVisibility();
    } catch (e) {
      debugPrint(
        'WEATHER ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        weatherLoading = false;
      });
    }
  }

  // ==========================================================
  // FLOOD OVERLAY VISIBILITY
  // ==========================================================

  void updateFloodMapVisibility() {
    if (!mounted) return;

    final dangerousWeather =
        weatherData != null &&
            (
                weatherData!.isHeavyRain ||
                    weatherData!.isExtremeWeather
            );

    final significantFloodRisk =
        floodProbability >= 0.40;

    setState(() {
      showFloodOverlay =
          dangerousWeather &&
              significantFloodRisk;
    });

    debugPrint(
      'SHOW FLOOD OVERLAY: '
          '$showFloodOverlay',
    );
  }

  // ==========================================================
  // FLOOD MAP
  // ==========================================================

  Future<void> loadFloodRiskMap() async {
    try {
      final cells =
      await floodMapService
          .loadFloodRiskGrid();

      if (!mounted) return;

      setState(() {
        floodRiskCells = cells;
        floodMapLoading = false;
      });

      debugPrint(
        'Loaded '
            '${cells.length} flood-risk cells.',
      );
    } catch (e) {
      debugPrint(
        'FLOOD MAP ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        floodMapLoading = false;
      });
    }
  }

  // ==========================================================
  // FLOOD COLORS
  // ==========================================================

  Color floodRiskColor(
      String risk,
      ) {
    switch (risk.toLowerCase()) {
      case 'red':
        return Colors.red.withOpacity(0.40);

      case 'orange':
        return Colors.orange.withOpacity(0.40);

      case 'green':
        return Colors.green.withOpacity(0.25);

      default:
        return Colors.transparent;
    }
  }

  Color floodRiskBorderColor(
      String risk,
      ) {
    switch (risk.toLowerCase()) {
      case 'red':
        return Colors.red;

      case 'orange':
        return Colors.orange;

      case 'green':
        return Colors.green;

      default:
        return Colors.transparent;
    }
  }
  String getOfflinePlaceType(
      String type,
      ) {
    switch (type) {
      case 'hospital':
        return 'Hospital';

      case 'clinic':
        return 'Clinic';

      case 'pharmacy':
        return 'Pharmacy';

      case 'doctors':
        return 'Doctor';

      case 'police':
        return 'Police Station';

      case 'fire_station':
        return 'Fire Station';

      case 'shelter':
        return 'Shelter';

      case 'community_centre':
        return 'Community Centre';

      default:
        return 'Safe Place';
    }
  }


  Future<List<SafePlace>> findOnlineSafePlaces(
      double lat,
      double lon,
      ) async {
    debugPrint('========== ONLINE SAFE PLACE SEARCH ==========');
    debugPrint('GPS: $lat, $lon');

    final query = '''
[out:json][timeout:10];
(
  node(around:5000,$lat,$lon)["amenity"~"shelter|hospital|school|community_centre|fire_station|police|college|temple|church|hall|clinic"];
  way(around:5000,$lat,$lon)["amenity"~"shelter|hospital|school|community_centre|fire_station|police|college|temple|church|hall|clinic"];
);
out center;
''';

    final servers = <String>[
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
    ];

    http.Response? response;

    for (int attempt = 0; attempt < servers.length; attempt++) {
      final server = servers[attempt];

      if (attempt > 0) {
        debugPrint('OVERPASS RETRY: waiting 2 seconds...');
        await Future.delayed(const Duration(seconds: 2));
      }

      try {
        debugPrint(
          'OVERPASS ATTEMPT ${attempt + 1}/${servers.length}: $server',
        );

        final result = await http.post(
          Uri.parse(server),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'FloodGuard/1.0',
          },
          body: {
            'data': query,
          },
        ).timeout(const Duration(seconds: 8));

        debugPrint('OVERPASS STATUS: ${result.statusCode}');

        if (result.statusCode == 200) {
          response = result;
          debugPrint('OVERPASS SERVER SUCCESS: $server');
          break;
        }

        debugPrint(
          'OVERPASS SERVER FAILED: HTTP ${result.statusCode}',
        );

        debugPrint(
          'RESPONSE: ${result.body.length > 300
              ? result.body.substring(0, 300)
              : result.body}',
        );
      } catch (e) {
        debugPrint('OVERPASS SERVER ERROR ($server): $e');
      }
    }

    if (response == null) {
      debugPrint('ALL OVERPASS SERVERS FAILED.');

      throw Exception(
        'Online safe places are temporarily unavailable. Please try again later.',
      );
    }

    // Parse successful Overpass response.
    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final elements = data['elements'] as List<dynamic>? ?? [];

    final places = <SafePlace>[];
    final seen = <String>{};

    for (final element in elements) {
      final map = element as Map<String, dynamic>;

      double? placeLat;
      double? placeLon;

      if (map['lat'] != null && map['lon'] != null) {
        placeLat = (map['lat'] as num).toDouble();
        placeLon = (map['lon'] as num).toDouble();
      } else if (map['center'] is Map) {
        final center = Map<String, dynamic>.from(map['center']);

        if (center['lat'] != null && center['lon'] != null) {
          placeLat = (center['lat'] as num).toDouble();
          placeLon = (center['lon'] as num).toDouble();
        }
      }

      if (placeLat == null || placeLon == null) {
        continue;
      }

      final tags = map['tags'] as Map<String, dynamic>? ?? {};

      final amenity = tags['amenity']?.toString() ?? '';

      final key = '${map['type']}_${map['id']}';

      if (!seen.add(key)) {
        continue;
      }

      final distanceMeters = Geolocator.distanceBetween(
        lat,
        lon,
        placeLat,
        placeLon,
      );

      places.add(
        SafePlace(
          name: tags['name']?.toString() ?? 'Nearby Safe Place',
          latitude: placeLat,
          longitude: placeLon,
          distance: formatDistance(distanceMeters),
          type: getPlaceType(amenity),
        ),
      );
    }

    places.sort((a, b) {
      return parseDistanceMeters(a.distance)
          .compareTo(parseDistanceMeters(b.distance));
    });

    debugPrint('ONLINE PLACES FOUND: ${places.length}');
    debugPrint('========== ONLINE SEARCH COMPLETED ==========');

    return places;
  }



  // ==========================================================
  // FIND NEARBY SAFE PLACES
  //
  // Uses OpenStreetMap Overpass.
  // No Bengaluru coordinates.
  // Uses actual GPS.
  // ==========================================================
  Future<List<SafePlace>> findOfflineSafePlaces(
      double lat,
      double lon,
      ) async {
    debugPrint(
      '========================================',
    );

    debugPrint(
      'OFFLINE SAFE PLACE DATABASE SEARCH',
    );

    debugPrint(
      'GPS: $lat, $lon',
    );

    final offlinePlaces =
    await OfflinePlacesDatabase.getNearbyPlaces(
      latitude: lat,
      longitude: lon,
      radiusKm: 10,
    );

    final places = <SafePlace>[];

    for (final place in offlinePlaces) {
      places.add(
        SafePlace(
          name: place.name.isEmpty
              ? 'Nearby ${getOfflinePlaceType(place.type)}'
              : place.name,
          latitude: place.latitude,
          longitude: place.longitude,
          distance:
          formatDistance(
            place.distanceKm * 1000,
          ),
          type:
          getOfflinePlaceType(
            place.type,
          ),
        ),
      );
    }

    places.sort(
          (a, b) {
        final aDistance =
        parseDistanceMeters(
          a.distance,
        );

        final bDistance =
        parseDistanceMeters(
          b.distance,
        );

        return aDistance.compareTo(
          bDistance,
        );
      },
    );

    debugPrint(
      'OFFLINE PLACES FOUND: ${places.length}',
    );

    return places;
  }
  Future<void> findSafePlaces() async {

    if (currentLocation == null) {
      showMessage('Waiting for your GPS location...');
      return;
    }

    if (routeLoading) return;

    setState(() {
      routeLoading = true;
      escapeRoute = [];
      routeRisk = null;
      safePlaces = [];
    });

    try {
      final lat = currentLocation!.latitude;
      final lon = currentLocation!.longitude;

      debugPrint('========================================');
      debugPrint('SEARCHING NEARBY SAFE PLACES');
      debugPrint('GPS: $lat, $lon');
      debugPrint('========================================');

      final internetAvailable = await hasInternetConnection();

      debugPrint('INTERNET AVAILABLE: $internetAvailable');

      // ========================================================
      // ONLINE MODE
      // ========================================================

      if (internetAvailable) {
        debugPrint('ONLINE MODE ACTIVATED');

        List<SafePlace> onlinePlaces = [];

        try {
          debugPrint('SEARCHING ONLINE SAFE PLACES...');

          onlinePlaces = await findOnlineSafePlaces(lat, lon);

          debugPrint('ONLINE PLACES FOUND: ${onlinePlaces.length}');
        } catch (e) {
          debugPrint('ONLINE SAFE PLACE SEARCH FAILED: $e');
          debugPrint('Falling back to offline safe places...');
          onlinePlaces = await findOfflineSafePlaces(lat, lon);
        }

        if (!mounted) return;

        if (onlinePlaces.isEmpty) {
          debugPrint('No online places returned, loading offline safe places fallback...');
          onlinePlaces = await findOfflineSafePlaces(lat, lon);
        }

        if (onlinePlaces.isEmpty) {
          setState(() {
            safePlaces = [];
          });

          showMessage('No nearby safe places found within 10 km.');
          return;
        }

        setState(() {
          safePlaces = onlinePlaces.take(10).toList();
        });

        showMessage(
          '${onlinePlaces.length > 10 ? 10 : onlinePlaces.length} '
              'nearby places found online.',
        );

        // ======================================================
        // ONLINE WALKING ROUTING ONLY
        // ======================================================

        final destinations = onlinePlaces.take(5).toList();

        for (final destination in destinations) {
          if (!mounted) return;

          debugPrint('========================================');
          debugPrint('TRYING ONLINE WALKING ROUTE');
          debugPrint('DESTINATION: ${destination.name}');
          debugPrint(
            'DESTINATION GPS: '
                '${destination.latitude}, ${destination.longitude}',
          );
          debugPrint('========================================');

          debugPrint('CALLING ONLINE ROUTING FUNCTION NOW');

          final onlineRouteFound =
          await createFloodAwareWalkingRoute(destination);

          debugPrint('ONLINE ROUTING FUNCTION RESULT: $onlineRouteFound');
          if (onlineRouteFound) {
            debugPrint('ONLINE WALKING ROUTE SUCCESSFUL');

            if (mounted) {
              showMessage(
                'Online walking route found to ${destination.name}.',
              );
            }

            return;
          }

          debugPrint(
            'ONLINE ROUTE NOT FOUND: ${destination.name}',
          );
        }

        // Fallback to offline routing if online routing servers are unreachable
        debugPrint('All online routing endpoints failed. Trying offline routing fallback...');
        if (onlinePlaces.isNotEmpty) {
          final offlineRouteFound = await createOfflineRoute(onlinePlaces.first);
          if (offlineRouteFound) {
            if (mounted) {
              showMessage(
                'Offline route found to ${onlinePlaces.first.name}.',
              );
            }
            return;
          }

          debugPrint('Offline routing tiles unavailable for location. Generating direct evacuation route...');
          final destination = onlinePlaces.first;
          final directRouteFound = createDirectFallbackRoute(
            currentLocation!,
            LatLng(destination.latitude, destination.longitude),
          );
          if (directRouteFound) {
            if (mounted) {
              showMessage(
                'Evacuation route found to ${destination.name}.',
              );
            }
            return;
          }
        }

        showMessage(
          'Online places found, but online walking routes are unavailable.',
        );

        return;
      }

      // ========================================================
      // OFFLINE MODE
      // ========================================================

      debugPrint('========================================');
      debugPrint('NO INTERNET: OFFLINE MODE ACTIVATED');
      debugPrint('========================================');

      final offlinePlaces = await findOfflineSafePlaces(lat, lon);

      debugPrint('OFFLINE PLACES FOUND: ${offlinePlaces.length}');

      if (!mounted) return;

      setState(() {
        safePlaces = offlinePlaces.take(10).toList();
      });

      if (offlinePlaces.isEmpty) {
        showMessage('No nearby offline places found within 10 km.');
        return;
      }

      showMessage(
        '${offlinePlaces.length > 10 ? 10 : offlinePlaces.length} '
            'nearby places found offline.',
      );

      // ========================================================
      // OFFLINE WALKING ROUTING ONLY
      // ========================================================

      final destination = offlinePlaces.first;

      debugPrint('========================================');
      debugPrint('STARTING OFFLINE ROUTING');
      debugPrint('DESTINATION: ${destination.name}');
      debugPrint(
        'DESTINATION GPS: '
            '${destination.latitude}, ${destination.longitude}',
      );
      debugPrint('========================================');

      final offlineRouteFound =
      await createOfflineRoute(destination);

      if (!offlineRouteFound) {
        createDirectFallbackRoute(
          currentLocation!,
          LatLng(destination.latitude, destination.longitude),
        );
        showMessage('Evacuation route found to ${destination.name}.');
      }
    } catch (e, stackTrace) {
      debugPrint('========================================');
      debugPrint('SAFE PLACE / ROUTING ERROR');
      debugPrint('$e');
      debugPrint('$stackTrace');
      debugPrint('========================================');

      if (mounted) {
        showMessage('Unable to calculate evacuation route.');
      }
    } finally {
      if (mounted) {
        setState(() {
          routeLoading = false;
        });
      }
    }
  }
  // ==========================================================
  // DISTANCE FORMAT
  // ==========================================================

  String formatDistance(
      double meters,
      ) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  double parseDistanceMeters(
      String distance,
      ) {
    final value =
        double.tryParse(
          distance
              .replaceAll(
            ' km',
            '',
          )
              .replaceAll(
            ' m',
            '',
          ),
        ) ??
            0;

    if (distance.contains('km')) {
      return value * 1000;
    }

    return value;
  }

  // ==========================================================
  // PLACE TYPE
  // ==========================================================

  String getPlaceType(
      String amenity,
      ) {
    switch (amenity) {
      case 'shelter':
        return 'Shelter';

      case 'hospital':
        return 'Hospital';

      case 'school':
        return 'School';

      case 'community_centre':
        return 'Community Centre';

      case 'fire_station':
        return 'Fire Station';

      case 'police':
        return 'Police Station';
      case 'college':
        return 'College';
      case 'hall':
        return 'Community_Hall';
      case 'church':
        return 'Church';
      case 'temple':
        return 'Temple';

      default:
        return 'Safe Place';
    }
  }

  // ==========================================================
  // WALKING ROUTE
  //
  // Uses current GPS as START.
  // Uses nearest safe place as DESTINATION.
  // ==========================================================

  List<LatLng> _decodePolyline(String encoded) {
    final poly = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  bool createDirectFallbackRoute(LatLng start, LatLng destination) {
    final routePoints = <LatLng>[];
    const steps = 15;
    for (int i = 0; i <= steps; i++) {
      final fraction = i / steps;
      final lat = start.latitude + (destination.latitude - start.latitude) * fraction;
      final lon = start.longitude + (destination.longitude - start.longitude) * fraction;
      routePoints.add(LatLng(lat, lon));
    }

    final risk = evaluateRouteRisk(routePoints);

    if (!mounted) return false;

    setState(() {
      escapeRoute = routePoints;
      routeRisk = risk;
    });

    _fitMapToRoute(routePoints);
    return true;
  }

  Future<bool> createFloodAwareWalkingRoute(
      SafePlace destination,
      ) async {
    debugPrint('========== ROUTING FUNCTION ENTERED ==========');

    if (currentLocation == null) {
      debugPrint('ROUTING STOPPED: GPS IS NULL');
      return false;
    }

    final start = currentLocation!;
    debugPrint('ROUTING START: ${start.latitude}, ${start.longitude}');
    debugPrint('ROUTING DESTINATION: ${destination.name}');

    final candidateUrls = <String>[
      'https://router.project-osrm.org/route/v1/foot/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true',
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true',
      'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true',
      'https://routing.openstreetmap.de/routed-car/route/v1/driving/${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&steps=true',
    ];

    for (int i = 0; i < candidateUrls.length; i++) {
      final urlString = candidateUrls[i];
      final url = Uri.parse(urlString);
      debugPrint('ROUTING TRY ${i + 1}/${candidateUrls.length}: $urlString');

      try {
        final response = await http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ).timeout(const Duration(seconds: 15));

        debugPrint('ROUTING HTTP STATUS: ${response.statusCode}');

        if (response.statusCode != 200) {
          debugPrint('ROUTING HTTP FAILED (${response.statusCode}): ${response.body}');
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;

        debugPrint('ROUTING API CODE: ${data['code']}');

        if (data['code'] != 'Ok') {
          debugPrint('ROUTING ERROR CODE: ${data['code']} - ${data['message']}');
          continue;
        }

        final routes = data['routes'] as List<dynamic>?;

        if (routes == null || routes.isEmpty) {
          debugPrint('No routes returned by server.');
          continue;
        }

        final route = routes.first as Map<String, dynamic>;
        final rawGeometry = route['geometry'];

        final routePoints = <LatLng>[];

        if (rawGeometry is Map) {
          final coordinates = rawGeometry['coordinates'] as List<dynamic>?;
          if (coordinates != null) {
            for (final coordinate in coordinates) {
              final point = coordinate as List<dynamic>;
              routePoints.add(
                LatLng(
                  (point[1] as num).toDouble(),
                  (point[0] as num).toDouble(),
                ),
              );
            }
          }
        } else if (rawGeometry is String) {
          routePoints.addAll(_decodePolyline(rawGeometry));
        }

        if (routePoints.isEmpty) {
          debugPrint('Parsed route points list is empty.');
          continue;
        }

        final risk = evaluateRouteRisk(routePoints);

        if (!mounted) return false;

        setState(() {
          escapeRoute = routePoints;
          routeRisk = risk;
        });

        _fitMapToRoute(routePoints);

        debugPrint('ONLINE ROUTE SUCCESS: ${routePoints.length} points');
        debugPrint('ROUTE DISTANCE: ${route['distance']} metres');
        debugPrint('ROUTE DURATION: ${route['duration']} seconds');

        return true;
      } catch (e) {
        debugPrint('ROUTING TRY ${i + 1} EXCEPTION: $e');
      }
    }

    debugPrint('========== ALL ONLINE ROUTING ENDPOINTS FAILED ==========');
    return false;
  }


  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      const Color(0xFF090707),

      appBar: AppBar(
        backgroundColor:
        const Color(0xFF090707),

        foregroundColor:
        Colors.white,

        elevation: 0,

        title: Text(
          AppLanguage.tr('navigate_safe_zone'),
          style: const TextStyle(
            fontWeight:
            FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding:
        const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          30,
        ),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [
            buildStatusCard(),

            const SizedBox(
              height: 18,
            ),

            buildMap(),

            const SizedBox(
              height: 18,
            ),

            buildRouteInfo(),

            const SizedBox(
              height: 0,
            ),
            buildRouteRiskCard(),
            const SizedBox(
              height: 18,
            ),

            buildTurnByTurn(),

            const SizedBox(
              height: 18,
            ),

            buildShelters(),

            const SizedBox(
              height: 18,
            ),


          ],
        ),
      ),
    );
  }

  // ==========================================================
  // STATUS CARD
  // ==========================================================

  Widget buildStatusCard() {
    final floodActive =
        showFloodOverlay;

    return Container(
      width: double.infinity,

      padding:
      const EdgeInsets.all(18),

      decoration:
      BoxDecoration(
        color:
        const Color(0xFF171010),

        borderRadius:
        BorderRadius.circular(20),

        border: Border.all(
          color:
          const Color(0xFF302626),
        ),
      ),

      child: Row(
        children: [
          Icon(
            floodActive
                ? Icons.warning_rounded
                : Icons.check_circle_outline,

            color: floodActive
                ? Colors.red
                : Colors.white,

            size: 30,
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  floodActive
                      ? AppLanguage.tr('flood_risk_detected')
                      : AppLanguage.tr('passable_area'),

                  style:
                  const TextStyle(
                    color:
                    Colors.white,

                    fontSize: 16,

                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 5,
                ),

                Text(
                  floodActive
                      ? AppLanguage.tr('follow_safest_route')
                      : AppLanguage.tr('no_flood_warning'),

                  style:
                  const TextStyle(
                    color:
                    Color(0xFFA9A0A0),

                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MAP
  // ==========================================================

  Widget buildMap() {
    final location =
        currentLocation;

    if (location == null) {
      return Container(
        height: 420,

        width:
        double.infinity,

        decoration:
        BoxDecoration(
          color:
          const Color(0xFF151111),

          borderRadius:
          BorderRadius.circular(20),
        ),

        child:
        const Center(
          child:
          CircularProgressIndicator(
            color:
            Colors.red,
          ),
        ),
      );
    }

    return Container(
      width:
      double.infinity,

      decoration:
      BoxDecoration(
        color:
        Colors.white,

        borderRadius:
        BorderRadius.circular(20),

        border: Border.all(
          color:
          const Color(0xFF302626),
        ),
      ),

      child: Column(
        children: [
          ClipRRect(
            borderRadius:
            const BorderRadius.vertical(
              top:
              Radius.circular(20),
            ),

            child: SizedBox(
              height: 420,

              child: FlutterMap(
                mapController: _mapController,
                options:
                MapOptions(
                  initialCenter:
                  location,

                  initialZoom:
                  12.5,

                  minZoom:
                  5,

                  maxZoom:
                  19,
                ),

                children: [
                  // ==================================================
                  // OPENSTREETMAP
                  // ==================================================

                  if (_mapInternetAvailable)
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/'
                          '{z}/{x}/{y}.png',
                      userAgentPackageName:
                      'com.example.floodwatch',
                      maxZoom: 19,
                      keepBuffer: 2,
                      panBuffer: 1,
                    )
                  else if (_offlineMapReady &&
                      _offlineStyle != null &&
                      _offlineMapProvider != null)
                    vt.VectorTileLayer(
                      theme:
                      _offlineStyle!.theme,
                      tileProviders:
                      _offlineStyle!.providers,
                      rasterSources:
                      _offlineStyle!.rasterSources,
                      sprites:
                      _offlineStyle!.sprites,
                      tileOffset:
                      vt.TileOffset.maplibre,
                      showLabels: true,
                      logger:
                      const vt.Logger.console(),
                    )
                  else
                    Container(
                      color:
                      const Color(0xFFE8E4D8),
                      child:
                      const Center(
                        child:
                        CircularProgressIndicator(
                          color: Colors.red,
                        ),
                      ),
                    ),

                  // ==================================================
                  // FLOOD RISK
                  // ==================================================

                  if (showFloodOverlay)
                    PolygonLayer(
                      polygons:
                      floodRiskCells
                          .map(
                            (cell) {
                          return Polygon(
                            points: [
                              LatLng(
                                cell.latitude,
                                cell.longitude,
                              ),

                              LatLng(
                                cell.latitude2,
                                cell.longitude,
                              ),

                              LatLng(
                                cell.latitude2,
                                cell.longitude2,
                              ),

                              LatLng(
                                cell.latitude,
                                cell.longitude2,
                              ),
                            ],

                            color:
                            floodRiskColor(
                              cell.risk,
                            ),

                            borderColor:
                            floodRiskBorderColor(
                              cell.risk,
                            ),

                            borderStrokeWidth:
                            0.5,
                          );
                        },
                      ).toList(),
                    ),

                  // ==================================================
                  // WALKING ROUTE
                  // ==================================================

                  if (escapeRoute.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points:
                          escapeRoute,

                          strokeWidth:
                          6,

                          color:
                          const Color(
                            0xFF1565C0,
                          ),
                        ),
                      ],
                    ),

                  // ==================================================
                  // FLOODED ROAD
                  // ==================================================

                  if (floodedRoad.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points:
                          floodedRoad,

                          strokeWidth:
                          6,

                          color:
                          Colors.red,
                        ),
                      ],
                    ),

                  // ==================================================
                  // MARKERS
                  // ==================================================

                  MarkerLayer(
                    markers: [
                      // USER LOCATION
                      Marker(
                        point:
                        location,

                        width:
                        35,

                        height:
                        35,

                        child:
                        Container(
                          width:
                          30,

                          height:
                          30,

                          decoration:
                          BoxDecoration(
                            color:
                            const Color(
                              0xFF1976D2,
                            ),

                            shape:
                            BoxShape.circle,

                            border:
                            Border.all(
                              color:
                              Colors.white,

                              width:
                              4,
                            ),

                            boxShadow: const [
                              BoxShadow(
                                color:
                                Colors.black26,

                                blurRadius:
                                6,
                              ),
                            ],
                          ),

                          child:
                          const Icon(
                            Icons.navigation,

                            color:
                            Colors.white,

                            size:
                            15,
                          ),
                        ),
                      ),

                      // SAFE PLACES
                      ...safePlaces.map(
                            (place) {
                          return Marker(
                            point:
                            LatLng(
                              place.latitude,
                              place.longitude,
                            ),

                            width:
                            35,

                            height:
                            35,

                            child:
                            Container(
                              decoration:
                              BoxDecoration(
                                color:
                                const Color(
                                  0xFF188038,
                                ),

                                shape:
                                BoxShape.circle,

                                border:
                                Border.all(
                                  color:
                                  Colors.white,

                                  width:
                                  3,
                                ),

                                boxShadow:
                                const [
                                  BoxShadow(
                                    color:
                                    Colors.black26,

                                    blurRadius:
                                    5,
                                  ),
                                ],
                              ),

                              child:
                              const Icon(
                                Icons.location_on,

                                color:
                                Colors.white,

                                size:
                                20,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ======================================================
          // LEGEND
          // ======================================================

          Container(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),

            color:
            Colors.white,

            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.center,

              children: [
                Row(
                  children: [
                    Container(
                      width:
                      18,

                      height:
                      18,

                      decoration:
                      const BoxDecoration(
                        color:
                        Color(
                          0xFF1976D2,
                        ),

                        shape:
                        BoxShape.circle,
                      ),
                    ),

                    const SizedBox(
                      width: 7,
                    ),

                    Text(
                      AppLanguage.tr('your_location'),

                      style:
                      const TextStyle(
                        color:
                        Colors.black87,

                        fontSize:
                        13,

                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  width: 25,
                ),

                Row(
                  children: [
                    Container(
                      width:
                      18,

                      height:
                      18,

                      decoration:
                      const BoxDecoration(
                        color:
                        Color(
                          0xFF188038,
                        ),

                        shape:
                        BoxShape.circle,
                      ),
                    ),

                    const SizedBox(
                      width: 7,
                    ),

                    Text(
                      AppLanguage.tr('safe_places'),

                      style:
                      const TextStyle(
                        color:
                        Colors.black87,

                        fontSize:
                        13,

                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ======================================================
          // FIND SAFE PLACES
          // ======================================================

          Padding(
            padding:
            const EdgeInsets.fromLTRB(
              18,
              0,
              18,
              18,
            ),

            child:
            SizedBox(
              width:
              double.infinity,

              height:
              52,

              child:
              ElevatedButton.icon(
                onPressed:
                routeLoading
                    ? null
                    : findSafePlaces,

                style:
                ElevatedButton.styleFrom(
                  backgroundColor:
                  const Color(
                    0xFF111111,
                  ),

                  foregroundColor:
                  Colors.white,

                  elevation:
                  0,

                  shape:
                  RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),
                ),

                icon:
                routeLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                  CircularProgressIndicator(
                    strokeWidth:
                    2,

                    color:
                    Colors.white,
                  ),
                )
                    : const Icon(
                  Icons.shield,
                  size: 21,
                ),

                label:
                Text(
                  routeLoading
                      ? AppLanguage.tr('searching_safe_places')
                      : AppLanguage.tr('find_safe_places'),

                  style:
                  const TextStyle(
                    fontSize:
                    14,

                    fontWeight:
                    FontWeight.bold,

                    letterSpacing:
                    0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ROUTE INFORMATION
  // ==========================================================

  Widget buildRouteInfo() {
    return Container(
      width:
      double.infinity,

      padding:
      const EdgeInsets.all(20),

      decoration:
      BoxDecoration(
        color:
        const Color(0xFF151111),

        borderRadius:
        BorderRadius.circular(22),

        border:
        Border.all(
          color:
          const Color(0xFF302626),
        ),
      ),

      child: Row(
        children: [
          const Icon(
            Icons.route,

            color:
            Color(0xFFFF1728),

            size:
            30,
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child:
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  AppLanguage.tr('safest_route'),

                  style:
                  const TextStyle(
                    color:
                    Colors.white,

                    fontSize:
                    16,

                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 5,
                ),

                Text(
                  escapeRoute.isEmpty
                      ? AppLanguage.tr('find_safe_places')
                      : AppLanguage.tr('route_found_msg'),

                  style:
                  const TextStyle(
                    color:
                    Color(0xFFA9A0A0),

                    fontSize:
                    13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TURN BY TURN
  // ==========================================================

  Widget buildTurnByTurn() {
    return Container(
      width:
      double.infinity,

      padding:
      const EdgeInsets.all(20),

      decoration:
      BoxDecoration(
        color:
        const Color(0xFF151111),

        borderRadius:
        BorderRadius.circular(22),

        border:
        Border.all(
          color:
          const Color(0xFF302626),
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(
                Icons.navigation,

                color:
                Color(0xFFFF1728),
              ),

              const SizedBox(
                width: 10,
              ),

              Text(
                AppLanguage.tr('turn_by_turn'),

                style:
                const TextStyle(
                  color:
                  Colors.white,

                  fontSize:
                  17,

                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 22,
          ),

          if (escapeRoute.isEmpty)
            Text(
              AppLanguage.tr('press_find_safe_places'),

              style:
              const TextStyle(
                color:
                Color(0xFFA9A0A0),

                fontSize:
                13,
              ),
            )
          else ...[
            buildStep(
              '1',
              AppLanguage.tr('start_gps'),
              AppLanguage.tr('start'),
            ),

            buildStep(
              '2',
              AppLanguage.tr('follow_blue_route'),
              AppLanguage.tr('continue'),
            ),

            buildStep(
              '3',
              AppLanguage.tr('continue_safe_place'),
              AppLanguage.tr('continue'),
            ),

            buildStep(
              '4',
              AppLanguage.tr('arrive_destination'),
              AppLanguage.tr('destination'),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // ROUTE STEP
  // ==========================================================

  Widget buildStep(
      String number,
      String description,
      String distance,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 20,
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Container(
            width:
            32,

            height:
            32,

            alignment:
            Alignment.center,

            decoration:
            const BoxDecoration(
              color:
              Color(0xFFFF1728),

              shape:
              BoxShape.circle,
            ),

            child:
            Text(
              number,

              style:
              const TextStyle(
                color:
                Colors.white,

                fontWeight:
                FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child:
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  description,

                  style:
                  const TextStyle(
                    color:
                    Colors.white,

                    fontSize:
                    14,

                    height:
                    1.4,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  distance,

                  style:
                  const TextStyle(
                    color:
                    Color(0xFF8E8585),

                    fontSize:
                    12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SHELTERS
  // ==========================================================

  Widget buildShelters() {
    return Container(
      width:
      double.infinity,

      padding:
      const EdgeInsets.all(20),

      decoration:
      BoxDecoration(
        color:
        const Color(0xFF151111),

        borderRadius:
        BorderRadius.circular(22),

        border:
        Border.all(
          color:
          const Color(0xFF302626),
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              const Icon(
                Icons.home_work,

                color:
                Color(0xFFFF1728),
              ),

              const SizedBox(
                width: 10,
              ),

              Text(
                AppLanguage.tr('nearby_shelters'),

                style:
                const TextStyle(
                  color:
                  Colors.white,

                  fontSize:
                  17,

                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          if (safePlaces.isEmpty)
            Text(
              AppLanguage.tr('no_safe_places'),

              style:
              const TextStyle(
                color:
                Color(0xFFA9A0A0),

                fontSize:
                13,
              ),
            ),

          ...safePlaces.map(
                (place) {
              return Padding(
                padding:
                const EdgeInsets.only(
                  bottom: 10,
                ),

                child:
                buildShelter(
                  place,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SHELTER CARD
  // ==========================================================

  Widget buildShelter(
      SafePlace place,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(15),

      decoration:
      BoxDecoration(
        color:
        const Color(0xFF211A1A),

        borderRadius:
        BorderRadius.circular(16),
      ),

      child: Row(
        children: [
          Container(
            width:
            44,

            height:
            44,

            decoration:
            const BoxDecoration(
              color:
              Color(0xFFFF1728),

              shape:
              BoxShape.circle,
            ),

            child:
            const Icon(
              Icons.home,

              color:
              Colors.white,
            ),
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child:
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  place.name,

                  style:
                  const TextStyle(
                    color:
                    Colors.white,

                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  '${place.distance} · ${place.type}',

                  style:
                  const TextStyle(
                    color:
                    Color(0xFFA9A0A0),

                    fontSize:
                    12,
                  ),
                ),
              ],
            ),
          ),

          const Text(
            'NEARBY',

            style:
            TextStyle(
              color:
              Colors.greenAccent,

              fontWeight:
              FontWeight.bold,

              fontSize:
              12,
            ),
          ),
        ],
      ),
    );
  }
  @override
  void dispose() {
    _mapNetworkTimer?.cancel();

    _offlineStyle?.dispose();

    super.dispose();
  }

  // ==========================================================
  // SOS
  // ==========================================================


}

// ============================================================
// SAFE PLACE MODEL
// ============================================================

class SafePlace {
  final String name;

  final double latitude;

  final double longitude;

  final String distance;

  final String type;

  SafePlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.type,
  });
}