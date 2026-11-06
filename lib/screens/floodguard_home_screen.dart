import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../services/notification_service.dart';
import 'damage_assessment_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:url_launcher/url_launcher.dart';

import '../Auth/database/offline_places_database.dart';
import '../Auth/login_screen.dart';
import '../models/flood_risk_cell.dart';
import '../services/flood_api_service.dart';
import '../services/flood_map_service.dart';
import '../services/offline_location_service.dart';
import '../services/app_language.dart';
import '../services/weather_services.dart';
import 'escape_screen.dart';
import 'profile_screen.dart';


class FloodGuardHomeScreen
    extends StatefulWidget {
  const FloodGuardHomeScreen({
    super.key,
  });

  @override
  State<FloodGuardHomeScreen>
  createState() =>
      _FloodGuardHomeScreenState();
}

class _FloodGuardHomeScreenState
    extends State<FloodGuardHomeScreen> {

  // ============================================================
  // COLORS
  // ============================================================

  static const Color background =
  Color(0xFF0B0708);

  static const Color card =
  Color(0xFF171011);

  static const Color card2 =
  Color(0xFF211618);

  static const Color red =
  Color(0xFFE5091A);

  static const Color green =
  Color(0xFFA3E2A4);

  static const Color orange =
  Color(0xFFFFB74D);

  static const Color muted =
  Color(0xFFB9AEB0);

  // ============================================================
  // SERVICES
  // ============================================================

  final FloodApiService
  floodApiService =
  FloodApiService();
  List<FloodRiskCell> floodRiskCells = [];

  bool floodMapLoading = true;
  StreamSubscription<Position>? _locationSubscription;


  String floodMapStatus =
      'Loading Karnataka flood-risk map...';
  List<Map<String, dynamic>> dynamicMapRiskCells = [];

  bool mapRiskLoading = false;
  double rainfall1Day = 0.0;
  double rainfall3Day = 0.0;
  double rainfall7Day = 0.0;
  double? lastValidRiverDistance;
  // ============================================================
// OFFLINE / ONLINE MAP
// ============================================================

  bool _mapInternetAvailable = true;
  bool _offlineMapReady = false;
  bool _mapInitializing = true;

  Timer? _mapNetworkTimer;

  MbTilesVectorTileProvider? _offlineMapProvider;

  vt.Style? _offlineStyle;






  // ============================================================
  // LOCATION
  // ============================================================

  LatLng? currentLocation;List<Map<String, String>> familyMembers = [];


  bool locationLoading = true;

  String locationStatus =
      'Getting your location...';

  String locationName =
      'Current location';

  final WeatherService weatherService = WeatherService();

  // ============================================================
  // FLOOD AI
  // ============================================================

  String aiRisk = 'LOW';

  double aiProbability = 18;

  bool aiLoading = false;

  String aiStatus = '';

  // ============================================================
  // WEATHER
  // ============================================================

  bool weatherLoading = true;

  double temperature = 0;

  double feelsLike = 0;

  double currentRain = 0;

  double humidity = 0;

  double windSpeed = 0;

  int currentRainProbability = 0;

  int currentWeatherCode = 0;

  String currentCondition =
      'Loading weather...';

  double elevation = 0;

  double nearestRiverDistance = 0;

  double rain24Hours = 0;


  List<HourlyForecast>
  hourlyForecast = [];

  List<DailyForecast>
  dailyForecast = [];

  // ============================================================
  // SAFE PLACES
  // ============================================================

  bool safePlacesLoading = false;

  List<SafePlaceItem>
  safePlaces = [];
  double peakRainIntensity = 0.0;

  // ============================================================
  // UI
  // ============================================================

  int selectedTab = 0;

  final List<bool> checklist =
  List<bool>.filled(
    6,
    false,
  );

  final TextEditingController
  familyNameController =
  TextEditingController();

  final TextEditingController
  familyPhoneController =
  TextEditingController();
  Color mapRiskColor(String? color) {
    switch ((color ?? '').toLowerCase()) {
      case 'red':
        return red;

      case 'orange':
        return orange;

      case 'green':
      default:
        return green;
    }
  }
  // ============================================================
// CHECK INTERNET
// ============================================================

  Future<bool> _checkInternetConnection() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final result = await InternetAddress.lookup(
        'tile.openstreetmap.org',
      ).timeout(
        const Duration(seconds: 3),
      );

      return result.isNotEmpty &&
          result.any(
                (address) =>
            address.rawAddress.isNotEmpty,
          );
    } catch (_) {
      return false;
    }
  }
  Widget buildDamageAssessmentButton() {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: red.withOpacity(0.6),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),

        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.crisis_alert,
            color: red,
            size: 28,
          ),
        ),

        title: const Text(
          'AI Damage Assessment',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),

        subtitle: const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Upload flood images and identify damaged buildings using AI.',
            style: TextStyle(
              color: muted,
              fontSize: 12,
            ),
          ),
        ),

        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: red,
          size: 18,
        ),

        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
              const DamageAssessmentScreen(),
            ),
          );
        },
      ),
    );
  }

// ============================================================
// COPY MBTILES FROM FLUTTER ASSETS TO DEVICE STORAGE
// ============================================================

  Future<String> _copyMbtilesAsset(
      String assetPath,
      String fileName,
      ) async {
    final supportDirectory =
    await getApplicationSupportDirectory();

    final mapsDirectory =
    Directory('${supportDirectory.path}/offline_maps');

    if (!await mapsDirectory.exists()) {
      await mapsDirectory.create(
        recursive: true,
      );
    }

    final destination =
    File('${mapsDirectory.path}/$fileName');

    if (!await destination.exists()) {
      debugPrint(
        'COPYING OFFLINE MAP: $assetPath',
      );

      final byteData =
      await rootBundle.load(assetPath);

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );

      await destination.writeAsBytes(
        bytes,
        flush: true,
      );

      debugPrint(
        'OFFLINE MAP COPIED: ${destination.path}',
      );
    }

    return destination.path;
  }

// ============================================================
// LOAD OFFLINE MBTILES
// ============================================================

  Future<void> _loadOfflineMap() async {
    if (kIsWeb) {
      debugPrint(
        'OFFLINE MAP: MBTiles is not supported on Web',
      );
      return;
    }

    try {
      debugPrint(
        '========== LOADING OFFLINE OSM MBTILES ==========',
      );

      final mbtilesPath = await _copyMbtilesAsset(
        'assets/offline_maps/karnataka_south.mbtiles',
        'karnataka_complete_v2.mbtiles',
      );

      debugPrint(
        'OFFLINE MBTILES PATH: $mbtilesPath',
      );

      final provider =
      await MbTilesVectorTileProvider.open(
        mbtilesPath,
        logger: const vt.Logger.console(),
      );

      debugPrint(
        'MBTILES FORMAT: ${provider.metadata.format}',
      );

      debugPrint(
        'MBTILES BOUNDS: ${provider.metadata.bounds}',
      );

      debugPrint(
        'MBTILES MIN ZOOM: ${provider.metadata.minZoom}',
      );

      debugPrint(
        'MBTILES MAX ZOOM: ${provider.metadata.maxZoom}',
      );

      if (!mounted) {
        provider.dispose();
        return;
      }

      _offlineMapProvider = provider;

      _offlineStyle = await vt.StyleReader(
        uri:
        'asset://assets/offline_maps/shortbread_offline_style.json',
        logger: const vt.Logger.console(),

        resolveProvider: (sourceId) async {
          debugPrint(
            'OFFLINE STYLE SOURCE: $sourceId',
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
        '========== OFFLINE OSM MAP READY ==========',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '========== OFFLINE OSM MAP ERROR ==========',
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

// ============================================================
// NETWORK MONITOR
// ============================================================

  Future<void> _updateMapNetworkStatus() async {
    final connected =
    await _checkInternetConnection();

    if (!mounted) return;

    if (_mapInternetAvailable != connected) {
      setState(() {
        _mapInternetAvailable = connected;
      });

      debugPrint(
        connected
            ? 'MAP NETWORK: ONLINE'
            : 'MAP NETWORK: OFFLINE',
      );
    }
  }

  void _startMapNetworkMonitor() {
    _mapNetworkTimer?.cancel();

    _mapNetworkTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) {
        _updateMapNetworkStatus();
      },
    );
  }


  Future<void> _loadBackgroundData() async {
    try {
      // These should NOT block the initial Home screen.
      await Future.wait([
        loadRiverDistance(),
        findSafePlaces(),
        loadKarnatakaFloodMap(),
      ]);

      debugPrint('========== BACKGROUND DATA LOADED ==========');
    } catch (e) {
      debugPrint('BACKGROUND DATA ERROR: $e');
    }
  }
  List<Map<String, dynamic>> getNearbyMapRiskCells() {
    final location = currentLocation;

    if (location == null) {
      return [];
    }

    return dynamicMapRiskCells.where((cell) {
      final lat = (cell['latitude'] as num?)?.toDouble();
      final lon = (cell['longitude'] as num?)?.toDouble();

      if (lat == null || lon == null) {
        return false;
      }

      final distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        lat,
        lon,
      );

      // Show points within 25 km
      return distance <= 25000;
    }).toList();
  }



  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    initialize();

    _loadOfflineMap();
    _updateMapNetworkStatus();
    _startMapNetworkMonitor();
  }



  @override
  void dispose() {
    _locationSubscription?.cancel();

    familyNameController.dispose();
    familyPhoneController.dispose();

    _mapNetworkTimer?.cancel();

    _offlineStyle?.dispose();

    super.dispose();
  }
  Future<void> signOutUser() async {
    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const login_screen(),
        ),
            (route) => false,
      );
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign out failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  Future<void> loadDynamicMapRisk() async {
    debugPrint(
      'BASE FLOOD CELLS COUNT: ${floodRiskCells.length}',
    );
    if (floodRiskCells.isEmpty) {
      return;
    }

    if (!mounted) return;

    setState(() {
      mapRiskLoading = true;
    });

    try {
      final locations = floodRiskCells.map((cell) {
        return {
          'latitude': cell.latitude,
          'longitude': cell.longitude,
          'base_risk': cell.risk,
        };
      }).toList();

      final results =
      await floodApiService.getMapRisk(locations);
      debugPrint('MAP RISK RESULTS COUNT: ${results.length}');
      debugPrint('MAP RISK FIRST RESULT: ${results.isNotEmpty ? results.first : 'EMPTY'}');

      if (!mounted) return;

      setState(() {
        dynamicMapRiskCells = results;
        mapRiskLoading = false;
        floodMapStatus =
        'Live Open-Meteo flood map updated';
      });

    } catch (e) {
      debugPrint('DYNAMIC MAP RISK ERROR: $e');

      if (!mounted) return;

      setState(() {
        mapRiskLoading = false;
        floodMapStatus =
        'Unable to update live flood map';
      });
    }
  }
  Future<void> saveUserLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    final location = currentLocation;

    if (user == null || location == null) {
      debugPrint('SAVE LOCATION: User or location unavailable');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'latitude': location.latitude,
        'longitude': location.longitude,
        'locationTracking': true,
        'locationOnline': true,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
        'INITIAL LOCATION SAVED: '
            '${location.latitude}, ${location.longitude}',
      );
    } catch (e) {
      debugPrint('INITIAL LOCATION SAVE FAILED: $e');

      // Save locally so it can be uploaded when
      // network connectivity becomes available.
      await OfflineLocationService.saveOfflineLocation(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    }
  }
  Future<void> loadKarnatakaFloodMap() async {
    try {
      final cells =
      await FloodMapService.loadRiskGrid();

      final karnatakaCells =
      FloodMapService.getKarnatakaCells(cells);

      if (!mounted) return;

      setState(() {
        floodRiskCells = karnatakaCells;
        floodMapLoading = false;
        floodMapStatus =
        '${karnatakaCells.length} flood-risk areas loaded';
      });

      debugPrint(
        'Karnataka flood cells: ${karnatakaCells.length}',
      );

      // Run live weather coloring separately.
      Future.microtask(() async {
        await loadDynamicMapRisk();
      });

    } catch (e) {
      debugPrint(
        'KARNATAKA FLOOD MAP ERROR: $e',
      );

      if (!mounted) return;

      setState(() {
        floodMapLoading = false;
        floodMapStatus =
        'Unable to load flood-risk map';
      });
    }
  }
  Color floodRiskColor(String level) {
    switch (level.toUpperCase()) {
      case 'HIGH':
      case 'RED':
        return Colors.red.withOpacity(0.25);

      case 'MODERATE':
      case 'MEDIUM':
      case 'ORANGE':
        return Colors.orange.withOpacity(0.22);

      case 'LOW':
      case 'GREEN':
      default:
        return Colors.green.withOpacity(0.20);
    }
  }
  Future<void> initialize() async {
    await getCurrentLocation();

    if (!mounted) return;

    // Save the first GPS location.
    await saveUserLocation();

    if (!mounted) return;

    // Start continuous GPS tracking.
    _startLiveLocationTracking();

    // Try to upload anything that was saved
    // during an earlier offline period.
    try {
      await OfflineLocationService
          .syncOfflineLocations();
    } catch (e) {
      debugPrint(
        'INITIAL OFFLINE LOCATION SYNC: $e',
      );
    }

    if (!mounted) return;

    // Trigger AI prediction immediately without blocking on other network tasks
    runFloodPrediction();

    await Future.wait([
      loadFamilyMembers(),
      loadWeather(),
      loadElevation(),
      loadRiverDistance(),
      findSafePlaces(),
      loadKarnatakaFloodMap(),
    ]);

    if (!mounted) return;

    await runFloodPrediction();
  }


  // ============================================================
  // GPS
  // ============================================================

  Future<void> getCurrentLocation() async {
    try {
      if (!mounted) return;

      setState(() {
        locationLoading = true;
        locationStatus = 'Checking GPS...';
      });

      // Check whether GPS/location service is enabled
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!mounted) return;

      if (!enabled) {
        setState(() {
          locationLoading = false;
          locationStatus = 'GPS is disabled';
        });

        showMessage(
          'Please turn on GPS/location.',
        );

        return;
      }

      // Check permission
      LocationPermission permission =
      await Geolocator.checkPermission();

      if (!mounted) return;

      // Request permission if needed
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (!mounted) return;
      }

      // Permission denied
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          locationLoading = false;
          locationStatus = 'Location permission denied';
        });

        showMessage(
          'Location permission is required.',
        );

        return;
      }

      // Get actual GPS position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

      if (!mounted) return;

      final location = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        currentLocation = location;
        locationLoading = false;
        locationStatus = 'Accurate GPS location';
        locationName = 'Current location';
      });

      debugPrint(
        'FLOODGUARD GPS: '
            '${position.latitude}, '
            '${position.longitude}',
      );

      // Resolve address/name only while screen is still alive
      if (!mounted) return;

      await resolveLocationName(
        position.latitude,
        position.longitude,
      );

    } catch (e) {
      debugPrint('GPS ERROR: $e');

      if (!mounted) return;

      setState(() {
        locationLoading = false;
        locationStatus = 'Unable to get location';
      });
    }
  }
  Future<void> checkHourlyWeatherNotifications(
      List<HourlyForecast> forecasts,
      ) async {
    for (final forecast in forecasts) {
      // Only check future forecast hours.
      if (!forecast.time.isAfter(DateTime.now())) {
        continue;
      }

      try {
        await NotificationService.instance.checkWeatherForecast(
          forecastTime: forecast.time,
          rainfallMm: forecast.rain,
          precipitationProbability: forecast.probability.toDouble(),
          weatherCode: forecast.weatherCode,
        );
      } catch (e) {
        debugPrint('Weather notification error: $e');
      }
    }
  }

  // ============================================================
  // WEATHER
  // ============================================================

  Future<void> loadWeather() async {
    final location = currentLocation;

    if (location == null) return;

    try {
      if (mounted) {
        setState(() {
          weatherLoading = true;
        });
      }

      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=${location.latitude}'
            '&longitude=${location.longitude}'
            '&current='
            'temperature_2m,'
            'relative_humidity_2m,'
            'apparent_temperature,'
            'rain,'
            'wind_speed_10m,'
            'weather_code'
            '&hourly='
            'temperature_2m,'
            'rain,'
            'precipitation_probability,'
            'relative_humidity_2m,'
            'wind_speed_10m,'
            'weather_code'
            '&daily='
            'weather_code,'
            'temperature_2m_max,'
            'temperature_2m_min,'
            'precipitation_probability_max,'
            'rain_sum'
            '&past_days=3'
            '&forecast_days=7'
            '&timezone=auto',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception(
          'Weather HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      final current = data['current'] as Map<String, dynamic>;
      final hourly = data['hourly'] as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>;

      // ---------------------------------------------------------
      // CURRENT WEATHER
      // ---------------------------------------------------------

      temperature = _toDouble(
        current['temperature_2m'],
      );

      feelsLike = _toDouble(
        current['apparent_temperature'],
      );

      currentRain = _toDouble(
        current['rain'],
      );

      humidity = _toDouble(
        current['relative_humidity_2m'],
      );

      windSpeed = _toDouble(
        current['wind_speed_10m'],
      );

      currentWeatherCode = _toInt(
        current['weather_code'],
      );

      final currentTime =
      current['time'].toString();

      // ---------------------------------------------------------
      // HOURLY DATA
      // ---------------------------------------------------------

      final times =
      hourly['time'] as List;

      final temperatures =
      hourly['temperature_2m'] as List;

      final rains =
      hourly['rain'] as List;

      final probabilities =
      hourly['precipitation_probability'] as List;

      final humidities =
      hourly['relative_humidity_2m'] as List;

      final winds =
      hourly['wind_speed_10m'] as List;

      final codes =
      hourly['weather_code'] as List;

      final currentDateTime =
      DateTime.parse(currentTime);

      int currentIndex = 0;

      for (int i = 0; i < times.length; i++) {
        final hourlyTime =
        DateTime.parse(times[i].toString());

        if (hourlyTime.year ==
            currentDateTime.year &&
            hourlyTime.month ==
                currentDateTime.month &&
            hourlyTime.day ==
                currentDateTime.day &&
            hourlyTime.hour ==
                currentDateTime.hour) {
          currentIndex = i;
          break;
        }
      }

      // ---------------------------------------------------------
      // NEXT 24 HOURS
      // Start from the NEXT hour, not the current hour.
      // ---------------------------------------------------------

      final List<HourlyForecast> newHourly = [];

      final nextHourIndex =
      math.min(
        currentIndex + 1,
        times.length,
      );

      final end =
      math.min(
        nextHourIndex + 24,
        times.length,
      );

      double total24 = 0.0;
      double peakIntensity = 0.0;

      for (
      int i = nextHourIndex;
      i < end;
      i++
      ) {
        final rain =
        _toDouble(rains[i]);

        total24 += rain;

        if (rain > peakIntensity) {
          peakIntensity = rain;
        }

        newHourly.add(
          HourlyForecast(
            time: DateTime.parse(
              times[i].toString(),
            ).toLocal(),
            temperature: _toDouble(
              temperatures[i],
            ),
            rain: rain,
            probability: _toInt(
              probabilities[i],
            ),
            humidity: _toDouble(
              humidities[i],
            ),
            wind: _toDouble(
              winds[i],
            ),
            weatherCode: _toInt(
              codes[i],
            ),
          ),
        );
      }

      // ---------------------------------------------------------
      // DAILY DATA
      // ---------------------------------------------------------

      final dates =
      daily['time'] as List;

      final maxTemps =
      daily['temperature_2m_max'] as List;

      final minTemps =
      daily['temperature_2m_min'] as List;

      final dailyProbabilities =
      daily[
      'precipitation_probability_max'
      ] as List;

      final dailyRain =
      daily['rain_sum'] as List;

      final dailyCodes =
      daily['weather_code'] as List;

      final List<DailyForecast> newDaily = [];

      for (
      int i = 0;
      i < dates.length;
      i++
      ) {
        newDaily.add(
          DailyForecast(
            date: DateTime.parse(
              dates[i].toString(),
            ),
            maxTemperature:
            _toDouble(
              maxTemps[i],
            ),
            minTemperature:
            _toDouble(
              minTemps[i],
            ),
            probability:
            _toInt(
              dailyProbabilities[i],
            ),
            rain:
            _toDouble(
              dailyRain[i],
            ),
            weatherCode:
            _toInt(
              dailyCodes[i],
            ),
          ),
        );
      }

      // ---------------------------------------------------------
      // PREVIOUS 3 DAYS RAINFALL
      //
      // Because past_days=3 is requested, dailyRain contains
      // historical daily rainfall as well as forecast days.
      //
      // Find today's date and sum the three days BEFORE today.
      // ---------------------------------------------------------

      final today =
      DateTime(
        currentDateTime.year,
        currentDateTime.month,
        currentDateTime.day,
      );

      double rainfall1Days = 0.0;
      double rainfall3Days = 0.0;
      double rainfall7Days = 0.0;

      for (int i = 0; i < dates.length; i++) {
        final date =
        DateTime.parse(
          dates[i].toString(),
        );

        final dateOnly = DateTime(
          date.year,
          date.month,
          date.day,
        );

        final difference =
            today.difference(dateOnly).inDays;

        final rain =
        _toDouble(dailyRain[i]);

        // Previous 1 complete day
        if (difference == 1) {
          rainfall1Days += rain;
        }

        // Previous 3 complete days
        if (difference >= 1 &&
            difference <= 3) {
          rainfall3Days += rain;
        }

        // Previous 7 complete days
        if (difference >= 1 &&
            difference <= 7) {
          rainfall7Days += rain;
        }
      }

      // ---------------------------------------------------------
      // CURRENT / NEXT-HOUR RAIN PROBABILITY
      // ---------------------------------------------------------

      final nextHourProbability =
      newHourly.isNotEmpty
          ? newHourly.first.probability
          : 0;

      // ---------------------------------------------------------
      // SAVE EVERYTHING
      // ---------------------------------------------------------

      if (!mounted) return;

      setState(() {
        hourlyForecast = newHourly;
        dailyForecast = newDaily;

        // UI "Rain next 24h" = previous 1-day rainfall
        rain24Hours = total24;

        // Historical rainfall values for AI
        rainfall1Day = rainfall1Days;
        rainfall3Day = rainfall3Days;
        rainfall7Day = rainfall7Days;


        if (currentIndex >= 0 &&
            currentIndex + 1 < probabilities.length) {
          currentRainProbability =
              _toDouble(probabilities[currentIndex + 1]).round();
        } else if (currentIndex >= 0 &&
            currentIndex < probabilities.length) {
          currentRainProbability =
              _toDouble(probabilities[currentIndex]).round();
        } else {
          currentRainProbability = 0;
        }

        debugPrint(
          'Next hour precipitation probability: '
              '$currentRainProbability%',
        );

        currentCondition =
            weatherDescription(
              currentWeatherCode,
            );

        weatherLoading = false;
      });

      debugPrint(
          '========== WEATHER VALUES =========='
      );

      debugPrint(
        'Rain next 24 hours: '
            '${total24.toStringAsFixed(2)} mm',
      );

      debugPrint(
        'Peak intensity: '
            '${peakIntensity.toStringAsFixed(2)} mm/h',
      );

      debugPrint(
        'Previous 3 days rainfall: '
            '${rainfall3Days.toStringAsFixed(2)} mm',
      );

      debugPrint(
        'Next hour rain probability: '
            '$nextHourProbability%',
      );

      debugPrint(
          '===================================='
      );

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

  // ============================================================
  // ELEVATION
  // ============================================================

  void _startLiveLocationTracking() {
    _locationSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );

    debugPrint('========== LIVE LOCATION TRACKING STARTED ==========');

    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
              (Position position) async {
            if (!mounted) return;

            final user = FirebaseAuth.instance.currentUser;

            if (user == null) {
              debugPrint(
                'LIVE LOCATION: No logged-in user',
              );
              return;
            }

            final latitude = position.latitude;
            final longitude = position.longitude;

            // Immediately update the location shown in the app.
            setState(() {
              currentLocation = LatLng(
                latitude,
                longitude,
              );
            });

            debugPrint(
              'LIVE GPS: $latitude, $longitude',
            );

            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .set(
                {
                  'location': {
                    'latitude': latitude,
                    'longitude': longitude,
                    'accuracy': position.accuracy,
                    'speed': position.speed,
                    'heading': position.heading,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },

                  // Direct values are useful for Admin.
                  'latitude': latitude,
                  'longitude': longitude,

                  'locationTracking': true,

                  'locationUpdatedAt':
                  FieldValue.serverTimestamp(),

                  'lastLocationUpdate':
                  FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );

              debugPrint(
                'LIVE LOCATION SENT TO FIRESTORE: '
                    '$latitude, $longitude',
              );
            } catch (e) {
              // Firestore can keep writes pending while offline.
              debugPrint(
                'LIVE LOCATION OFFLINE / QUEUED: $e',
              );
            }
          },
          onError: (error) {
            debugPrint(
              'LIVE LOCATION STREAM ERROR: $error',
            );
          },
        );
  }
  Future<void> loadElevation() async {
    final location = currentLocation;

    if (location == null) return;

    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/elevation'
            '?latitude=${location.latitude}'
            '&longitude=${location.longitude}',
      );

      debugPrint('========== ELEVATION REQUEST ==========');
      debugPrint('URL: $url');

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
      );

      debugPrint('ELEVATION STATUS: ${response.statusCode}');
      debugPrint('ELEVATION RESPONSE: ${response.body}');

      if (response.statusCode != 200) {
        debugPrint(
          'ELEVATION HTTP ERROR: ${response.statusCode}',
        );
        return;
      }

      final data = jsonDecode(response.body);

      final elevationList = data['elevation'];

      if (elevationList is! List || elevationList.isEmpty) {
        debugPrint('ELEVATION ERROR: No elevation returned');
        return;
      }

      final elevationValue =
      _toDouble(elevationList[0]);

      debugPrint(
        'ELEVATION VALUE: $elevationValue m',
      );

      if (!mounted) return;

      setState(() {
        elevation = elevationValue;
      });

      debugPrint(
          '========== ELEVATION UPDATED: '
              '${elevation.toStringAsFixed(2)} m =========='
      );
    } catch (e) {
      debugPrint(
        'ELEVATION ERROR: $e',
      );
    }
  }

  // ============================================================
  // RIVER DISTANCE
  // ============================================================

  Future<void> loadRiverDistance() async {
    final location = currentLocation;

    if (location == null) return;

    final lat = location.latitude;
    final lon = location.longitude;

    debugPrint('========== RIVER DISTANCE REQUEST ==========');
    debugPrint('GPS: $lat, $lon');

    // Use a smaller search radius first.
    // 50 km of river geometry can produce a very large response.
    const double searchRadius = 10000;

    final query = '''
[out:json][timeout:6];
way(around:$searchRadius,$lat,$lon)["waterway"="river"];
out geom;
''';

    final servers = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
    ];

    for (final server in servers) {
      try {
        debugPrint('Trying Overpass server: $server');

        final url = Uri.parse(
          '$server?data=${Uri.encodeComponent(query)}',
        );

        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
        );

        debugPrint(
          'RIVER SERVER STATUS: ${response.statusCode}',
        );

        if (response.statusCode != 200) {
          debugPrint(
            'RIVER SERVER FAILED: ${response.statusCode}',
          );
          continue;
        }

        final data = jsonDecode(response.body);

        final elements = data['elements'];

        if (elements is! List || elements.isEmpty) {
          debugPrint('NO RIVER FOUND WITHIN 15 KM');
          continue;
        }

        double closest = double.infinity;

        for (final element in elements) {
          final geometry = element['geometry'];

          if (geometry is! List) continue;

          for (final point in geometry) {
            if (point is! Map) continue;

            final pointLat = point['lat'];
            final pointLon = point['lon'];

            if (pointLat == null || pointLon == null) {
              continue;
            }

            final riverLat = _toDouble(pointLat);
            final riverLon = _toDouble(pointLon);

            final distance = Geolocator.distanceBetween(
              lat,
              lon,
              riverLat,
              riverLon,
            );

            if (distance < closest) {
              closest = distance;
            }
          }
        }

        if (closest != double.infinity) {
          final distanceKm = closest / 1000.0;

          debugPrint(
            'Nearest river distance: '
                '${distanceKm.toStringAsFixed(2)} km',
          );

          if (!mounted) return;

          setState(() {
            nearestRiverDistance = distanceKm;
            lastValidRiverDistance = distanceKm;
          });

          debugPrint(
            '========== RIVER DISTANCE READY ==========',
          );

          // Re-run AI now that the real river distance is available.
          await runFloodPrediction();

          return;
        }
      } catch (e) {
        debugPrint(
          'RIVER SERVER ERROR: $e',
        );
      }
    }

    debugPrint(
      '========== RIVER DISTANCE UNAVAILABLE ==========',
    );

    if (!mounted) return;

    // Keep the previous real value if available.
    if (lastValidRiverDistance != null) {
      setState(() {
        nearestRiverDistance = lastValidRiverDistance!;
      });

      debugPrint(
        'Keeping last valid river distance: '
            '${lastValidRiverDistance!.toStringAsFixed(2)} km',
      );
    } else {
      setState(() {
        nearestRiverDistance = 5.0;
        lastValidRiverDistance = 5.0;
      });
      debugPrint(
        'Defaulting river distance to 5.00 km',
      );
    }
  }

  // ============================================================
  // FLOOD AI
  // ============================================================
  Future<void> loadFamilyMembers() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('FAMILY: No logged-in user');
      return;
    }

    try {
      debugPrint('========== LOADING FAMILY MEMBERS ==========');
      debugPrint('USER UID: ${user.uid}');

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('familyMembers')
          .get();

      debugPrint(
        'FAMILY MEMBER DOCUMENT COUNT: ${snapshot.docs.length}',
      );

      final members = snapshot.docs.map((doc) {
        final data = doc.data();

        debugPrint('FAMILY DOC ID: ${doc.id}');
        debugPrint('FAMILY DATA: $data');

        return <String, String>{
          'name': (data['name'] ?? '').toString().trim(),
          'phone': (data['phone'] ?? '').toString().trim(),
        };
      }).where((member) {
        return member['name']!.isNotEmpty ||
            member['phone']!.isNotEmpty;
      }).toList();

      if (!mounted) return;

      setState(() {
        familyMembers = members;
      });

      debugPrint(
        'FAMILY MEMBERS LOADED: ${familyMembers.length}',
      );

      for (final member in familyMembers) {
        debugPrint(
          'FAMILY: ${member['name']} -> ${member['phone']}',
        );
      }

      debugPrint('============================================');
    } catch (e, stackTrace) {
      debugPrint('LOAD FAMILY MEMBERS ERROR: $e');
      debugPrint('STACK: $stackTrace');
    }
  }


  Future<void> runFloodPrediction() async {
    final location = currentLocation;

    if (location == null) {
      debugPrint('Flood prediction skipped: location unavailable');
      return;
    }

    final initialProb = _calculateLocalFloodProbability(
      rainfall1day: rainfall1Day,
      rainfall3day: rainfall3Day,
      rainfall7day: rainfall7Day,
      elevation: elevation,
      riverDistance: nearestRiverDistance > 0 ? nearestRiverDistance : 5.0,
    );

    String initialRisk = 'LOW';
    if (initialProb >= 70) {
      initialRisk = 'HIGH';
    } else if (initialProb >= 40) {
      initialRisk = 'MODERATE';
    }

    if (mounted) {
      setState(() {
        aiProbability = initialProb;
        aiRisk = initialRisk;
        aiLoading = false;
        aiStatus = '';
      });
    }


    try {
      debugPrint('========== STARTING FLOOD PREDICTION ==========');
      debugPrint(
        'GPS: ${location.latitude}, ${location.longitude}',
      );

      // Get REAL rainfall/weather data
      final recent = await weatherService.getRecentRainfall(
        latitude: location.latitude,
        longitude: location.longitude,
      );

      debugPrint(
        'Rainfall 1 day: ${recent.rainfall1day}',
      );
      debugPrint(
        'Rainfall 3 day: ${recent.rainfall3day}',
      );
      debugPrint(
        'Rainfall 7 day: ${recent.rainfall7day}',
      );

      // Send REAL data to FastAPI + TensorFlow model
      final prediction =
      await floodApiService.predict(
        latitude: location.latitude,
        longitude: location.longitude,
        rainfall1day: recent.rainfall1day,
        rainfall3day: recent.rainfall3day,
        rainfall7day: recent.rainfall7day,
        groundElevation: elevation,
        riverDistance: nearestRiverDistance,
      );
      if (!mounted) return;

      final prob = (prediction.probability >= 5.0 ? prediction.probability : prediction.riskIndex.toDouble()).clamp(5.0, 99.0);

      setState(() {
        aiRisk = prediction.risk;
        aiProbability = prob;
        aiStatus = '';
        aiLoading = false;
      });

      debugPrint('========== FLOOD RESULT ==========');
      debugPrint('Risk: ${prediction.risk}');
      debugPrint('Probability: ${prediction.probability}');
      debugPrint('Risk Index: ${prediction.riskIndex}');
      debugPrint('Color: ${prediction.riskColor}');
    } catch (e) {
      debugPrint('========== FLOOD AI ERROR ==========');
      debugPrint('ERROR: $e');

      if (!mounted) return;

      final fallbackProb = _calculateLocalFloodProbability(
        rainfall1day: rainfall1Day,
        rainfall3day: rainfall3Day,
        rainfall7day: rainfall7Day,
        elevation: elevation,
        riverDistance: nearestRiverDistance > 0 ? nearestRiverDistance : 5.0,
      );

      String fallbackRisk = 'LOW';
      if (fallbackProb >= 70) {
        fallbackRisk = 'HIGH';
      } else if (fallbackProb >= 40) {
        fallbackRisk = 'MODERATE';
      }

      setState(() {
        aiLoading = false;
        aiProbability = fallbackProb;
        aiRisk = fallbackRisk;
        aiStatus = '';
      });
    }
  }

  double _calculateLocalFloodProbability({
    required double rainfall1day,
    required double rainfall3day,
    required double rainfall7day,
    required double elevation,
    required double riverDistance,
  }) {
    double rainFactor = (rainfall1day * 0.5 + rainfall3day * 0.3 + rainfall7day * 0.2);
    double rainScore = (rainFactor / 50.0 * 60.0).clamp(0.0, 60.0);

    double elevationScore = 0.0;
    if (elevation < 10) {
      elevationScore = 25.0;
    } else if (elevation < 50) {
      elevationScore = (50 - elevation) / 40.0 * 25.0;
    } else {
      elevationScore = 5.0;
    }

    double riverScore = 0.0;
    if (riverDistance < 1.0) {
      riverScore = 15.0;
    } else if (riverDistance < 10.0) {
      riverScore = (10 - riverDistance) / 9.0 * 15.0;
    } else {
      riverScore = 2.0;
    }

    double totalScore = rainScore + elevationScore + riverScore;
    return totalScore.clamp(12.0, 95.0);
  }



  Future<void> resolveLocationName(
      double latitude,
      double longitude,
      ) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
            '?format=jsonv2'
            '&lat=$latitude'
            '&lon=$longitude'
            '&zoom=10',
      );

      final response = await http
          .get(
        uri,
        headers: const {
          'User-Agent': 'FloodGuard/1.0',
        },
      )
          .timeout(
        const Duration(seconds: 10),
      );

      // Widget may have been disposed while waiting for HTTP.
      if (!mounted) return;

      if (response.statusCode != 200) {
        debugPrint(
          'REVERSE GEOCODING STATUS: ${response.statusCode}',
        );
        return;
      }

      final data =
      jsonDecode(response.body) as Map<String, dynamic>;

      final address =
      data['address'] as Map<String, dynamic>?;

      if (address == null) {
        debugPrint(
          'REVERSE GEOCODING: address not found',
        );
        return;
      }

      final parts = [
        address['city'],
        address['town'],
        address['village'],
        address['municipality'],
        address['state'],
        address['country'],
      ]
          .where(
            (value) =>
        value != null &&
            value.toString().trim().isNotEmpty,
      )
          .map(
            (value) => value.toString().trim(),
      )
          .toList();

      if (parts.isEmpty) return;

      // Check again immediately before setState.
      if (!mounted) return;

      setState(() {
        locationName = parts.join(', ');
      });

      debugPrint(
        'LOCATION NAME: $locationName',
      );
    } catch (e) {
      debugPrint(
        'REVERSE GEOCODING ERROR: $e',
      );
    }
  }

  // ============================================================
  // SAFE PLACES
  // ============================================================

  Future<void> findSafePlaces() async {
    final location = currentLocation;

    if (location == null) {
      debugPrint('SAFE PLACE: Current location is null');
      return;
    }

    if (!mounted) return;

    setState(() {
      safePlacesLoading = true;
    });

    final lat = location.latitude;
    final lon = location.longitude;

    debugPrint('============================================');
    debugPrint('SEARCHING NEARBY SAFE PLACES');
    debugPrint('LATITUDE: $lat');
    debugPrint('LONGITUDE: $lon');
    debugPrint('============================================');

    try {
      // Search within 5 km.
      final query = '''
[out:json][timeout:8];
(
  node(around:5000,$lat,$lon)["amenity"~"hospital|school|shelter|community_centre|fire_station|police"];
  way(around:5000,$lat,$lon)["amenity"~"hospital|school|shelter|community_centre|fire_station|police"];
);
out center;
''';

      final url = Uri.parse(
        'https://overpass-api.de/api/interpreter',
      );

      debugPrint('SAFE PLACE URL: $url');
      debugPrint('SENDING OVERPASS POST REQUEST...');

      final response = await http
          .post(
        url,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent':
          'FloodWatch/1.0 (Flutter flood emergency application)',
          'Accept': 'application/json',
        },
        body: {
          'data': query,
        },
      )
          .timeout(const Duration(seconds: 8));

      debugPrint('SAFE PLACE STATUS: ${response.statusCode}');
      debugPrint(
        'SAFE PLACE RESPONSE LENGTH: ${response.body.length}',
      );

      if (response.statusCode != 200) {
        debugPrint(
          'SAFE PLACE SERVER ERROR: '
              '${response.statusCode}',
        );

        debugPrint(
          'SAFE PLACE SERVER RESPONSE: '
              '${response.body}',
        );

        throw Exception(
          'OpenStreetMap Overpass error: '
              '${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception(
          'Invalid OpenStreetMap response.',
        );
      }

      final elements = decoded['elements'];

      if (elements is! List) {
        throw Exception(
          'No elements returned from OpenStreetMap.',
        );
      }

      final List<SafePlaceItem> places = [];

      for (final element in elements) {
        if (element is! Map) {
          continue;
        }

        final tags = element['tags'];

        if (tags is! Map) {
          continue;
        }

        double? placeLat;
        double? placeLon;

        // Node
        if (element['lat'] != null &&
            element['lon'] != null) {
          placeLat = _toDouble(element['lat']);
          placeLon = _toDouble(element['lon']);
        }

        // Way / relation
        else if (element['center'] is Map) {
          final center = element['center'];

          if (center['lat'] != null &&
              center['lon'] != null) {
            placeLat = _toDouble(center['lat']);
            placeLon = _toDouble(center['lon']);
          }
        }

        if (placeLat == null ||
            placeLon == null) {
          continue;
        }

        final amenity =
            tags['amenity']?.toString() ?? '';

        final type = placeType(amenity);

        final name =
        tags['name']?.toString().trim().isNotEmpty == true
            ? tags['name'].toString()
            : type;

        final distance =
        Geolocator.distanceBetween(
          lat,
          lon,
          placeLat,
          placeLon,
        );

        places.add(
          SafePlaceItem(
            name: name,
            type: type,
            latitude: placeLat,
            longitude: placeLon,
            distance: distance,
          ),
        );
      }

      // Nearest places first.
      places.sort(
            (a, b) => a.distance.compareTo(
          b.distance,
        ),
      );

      final nearestPlaces =
      places.take(10).toList();

      debugPrint(
        '============================================',
      );
      debugPrint(
        'SAFE PLACES FOUND: ${places.length}',
      );
      debugPrint(
        'SAFE PLACES DISPLAYED: '
            '${nearestPlaces.length}',
      );

      for (final place in nearestPlaces) {
        debugPrint(
          '${place.name} | '
              '${place.type} | '
              '${(place.distance / 1000).toStringAsFixed(2)} km',
        );
      }

      debugPrint(
        '============================================',
      );

      if (!mounted) return;

      setState(() {
        safePlaces = nearestPlaces;
        safePlacesLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        '============================================',
      );
      debugPrint(
        'SAFE PLACE ERROR: $e',
      );
      debugPrint(
        '$stackTrace',
      );
      debugPrint(
        '============================================',
      );

      try {
        debugPrint('Loading safe places from offline database fallback...');
        final offlinePlaces = await OfflinePlacesDatabase.getNearbyPlaces(
          latitude: lat,
          longitude: lon,
          radiusKm: 10,
        );

        final List<SafePlaceItem> fallbackPlaces = offlinePlaces.map((p) {
          final distanceMeters = Geolocator.distanceBetween(
            lat,
            lon,
            p.latitude,
            p.longitude,
          );
          return SafePlaceItem(
            name: p.name.isEmpty ? 'Nearby ${p.type}' : p.name,
            type: p.type,
            latitude: p.latitude,
            longitude: p.longitude,
            distance: distanceMeters,
          );
        }).toList();

        fallbackPlaces.sort((a, b) => a.distance.compareTo(b.distance));

        if (mounted) {
          setState(() {
            safePlaces = fallbackPlaces.take(10).toList();
            safePlacesLoading = false;
          });
        }
        return;
      } catch (dbErr) {
        debugPrint('OFFLINE SAFE PLACE DB ERROR: $dbErr');
      }

      if (!mounted) return;

      setState(() {
        safePlaces = [];
        safePlacesLoading = false;
      });
    }
  }

  // ============================================================
  // ALERT SCREEN
  // ============================================================


  Widget buildAlertTab() {
    final risk = riskColor();

    String statusText;

    if (aiLoading) {
      statusText = AppLanguage.tr('analyzing_risk');
    } else {
      switch (aiRisk.toUpperCase()) {
        case 'HIGH':
          statusText = AppLanguage.tr('high_risk_msg');
          break;

        case 'MODERATE':
          statusText = AppLanguage.tr('mod_risk_msg');
          break;

        case 'LOW':
        default:
          statusText = AppLanguage.tr('low_risk_msg');
      }
    }

    final displayTitle = aiRisk.isEmpty
        ? AppLanguage.tr('low')
        : aiRisk.toUpperCase() == 'HIGH'
        ? AppLanguage.tr('high')
        : aiRisk.toUpperCase() == 'MODERATE'
        ? AppLanguage.tr('moderate')
        : AppLanguage.tr('low');

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        40,
      ),
      children: [
        buildRiskCard(
          risk: risk,
          title: displayTitle,
          subtitle: statusText,
        ),

        const SizedBox(height: 18),
        buildDamageAssessmentButton(),

        const SizedBox(height: 18),

        buildNearestSafeGround(),

        const SizedBox(height: 18),

        buildEmergencyCard(),
      ],
    );
  }



  // ============================================================
  // RISK CARD
  // ============================================================



  Widget buildRiskCard({
    required Color risk,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF34292B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppLanguage.tr("ai_flood_detection")} · $locationName',
                      style: const TextStyle(
                        color: Color(0xFFBDB4B5),
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        color: risk,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            subtitle,
            style: const TextStyle(
              color: muted,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLanguage.tr('risk_index'),
                style: const TextStyle(
                  color: muted,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),

              Text(
                '${aiProbability.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: risk,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (aiProbability / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFF0D090A),
              valueColor: AlwaysStoppedAnimation<Color>(risk),
            ),
          ),

          const SizedBox(height: 18),

          riskRow(
            Icons.water_drop_outlined,
            AppLanguage.tr('rain_next_24h'),
            '${rain24Hours.toStringAsFixed(1)} mm',
          ),
          riskRow(
            Icons.water_drop_outlined,
            AppLanguage.tr('rain_3day'),
            '${rainfall3Day.toStringAsFixed(1)} mm',
          ),
          riskRow(
            Icons.water_drop_outlined,
            AppLanguage.tr('rain_7day'),
            '${rainfall7Day.toStringAsFixed(1)} mm',
          ),
          riskRow(
            Icons.opacity,
            AppLanguage.tr('ground_humidity'),
            '${humidity.toStringAsFixed(0)}%',
          ),
          riskRow(
            Icons.terrain,
            AppLanguage.tr('terrain_elevation'),
            '${elevation.toStringAsFixed(0)} m',
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }





  Widget riskRow(
      IconData icon,
      String title,
      String value,

      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.white70,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Text(
              title,
              style:
              const TextStyle(
                color: muted,
              ),
            ),
          ),

          Text(
            value,
            style:
            const TextStyle(
              color: Colors.white,
              fontWeight:
              FontWeight.bold,
            ),
          ),

          const SizedBox(
            width: 14,
          ),


        ],
      ),
    );
  }

  // ============================================================
  // EMERGENCY SOS
  // ============================================================

  Widget buildEmergencyCard() {
    return Container(
      padding:
      const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:
        const Color(0xFF2A080B),
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color:
          red.withOpacity(0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons
                    .notification_important_outlined,
                color: red,
              ),
              const SizedBox(
                width: 10,
              ),
              Text(
                AppLanguage.tr('emergency_sos'),
                style:
                const TextStyle(
                  color: red,
                  fontWeight:
                  FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed:
              sendSOS,
              icon: const Icon(
                Icons.send,
              ),
              label: Text(
                AppLanguage.tr('send_sos'),
                style:
                const TextStyle(
                  fontSize: 16,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
              style:
              ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor:
                Colors.white,
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    18,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Row(
            children: [
              emergencyButton(
                AppLanguage.tr('flood_control_room'),
                '1077',
              ),
              emergencyButton(
                AppLanguage.tr('disaster_helpline'),
                '108',
              ),
              emergencyButton(
                AppLanguage.tr('police'),
                '100',
              ),
            ],
          ),

          const SizedBox(
            height: 12,
          ),

          OutlinedButton.icon(
            onPressed:
            copyLocationMessage,
            icon: const Icon(
              Icons.copy,
              size: 16,
            ),
            label: Text(
              AppLanguage.tr('copy_alert_msg'),
            ),
            style:
            OutlinedButton.styleFrom(
              foregroundColor:
              muted,
              minimumSize:
              const Size(
                double.infinity,
                42,
              ),
            ),
          ),

          const SizedBox(
            height: 18,
          ),

          Text(
            AppLanguage.tr('family_contacts'),
            style:
            const TextStyle(
              color: muted,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),

          if (familyMembers.isEmpty)
            Text(
              AppLanguage.tr('no_family_added'),
              style: const TextStyle(
                color: muted,
                fontSize: 14,
              ),
            )
          else
            ...familyMembers.map(
                  (member) {
                final name = member['name'] ?? '';
                final phone = member['phone'] ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF180D0F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3A292B),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: red.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: red,
                        ),
                      ),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              phone,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          callNumber(phone);
                        },
                        icon: const Icon(
                          Icons.phone,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          const SizedBox(
            height: 8,
          ),


        ],
      ),
    );
  }

  Widget emergencyButton(
      String title,
      String number,
      ) {
    return Expanded(
      child: Padding(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 4,
        ),
        child: InkWell(
          onTap: () =>
              callNumber(number),
          borderRadius:
          BorderRadius.circular(
            16,
          ),
          child: Container(
            height: 92,
            decoration:
            BoxDecoration(
              color:
              const Color(0xFF180D0F),
              borderRadius:
              BorderRadius.circular(
                16,
              ),
              border:
              Border.all(
                color:
                const Color(
                  0xFF3A292B,
                ),
              ),
            ),
            padding:
            const EdgeInsets.all(
              6,
            ),
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment
                  .center,
              children: [
                const Icon(
                  Icons.phone_outlined,
                  size: 18,
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  title,
                  textAlign:
                  TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                  const TextStyle(
                    fontSize: 10,
                    color: muted,
                    height: 1.1,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  number,
                  style:
                  const TextStyle(
                    fontSize: 15,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NEAREST SAFE GROUND
  // ============================================================

  Widget buildNearestSafeGround() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecorgit add README.mdation(
        color: const Color(0xFF0D0809), // Dark sleek background
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF221718), // Darker subtle border
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLanguage.tr('nearest_safe_ground'),
                style: const TextStyle(
                  color: muted,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              if (safePlacesLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(color: red, strokeWidth: 2),
                ),
            ],
          ),

          const SizedBox(height: 14),

          buildMap(),

          if (safePlaces.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'NEARBY SAFE PLACES & SHELTERS',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),
            ...safePlaces.take(4).map((place) => buildSafePlaceItem(place)),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EscapeScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.navigation, size: 20),
              label: const Text(
                'Navigate to safe zone',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSafePlaceItem(
    SafePlaceItem place,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF070405), // Darker safe place item card
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1B1112), // Darker border
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: red.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.directions_walk, color: muted, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      formatDistance(place.distance),
                      style: const TextStyle(
                        color: green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (place.type.isNotEmpty) ...[
                      Text(
                        ' • ${place.type.toUpperCase()}',
                        style: const TextStyle(
                          color: muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: green,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAP
  // ============================================================

  Widget buildMap() {
    final location = currentLocation;

    if (location == null) {
      return Container(
        height: 230,
        decoration: BoxDecoration(
          color: const Color(0xFF0E0A0B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: red),
        ),
      );
    }

    final riskCells = dynamicMapRiskCells.isNotEmpty
        ? dynamicMapRiskCells
        : floodRiskCells.map((cell) {
      String color;

      switch (cell.risk.toUpperCase()) {
        case 'HIGH':
          color = 'red';
          break;
        case 'MODERATE':
          color = 'orange';
          break;
        default:
          color = 'green';
      }

      return {
        'latitude': cell.latitude,
        'longitude': cell.longitude,
        'final_color': color,
        'final_risk': cell.risk,
      };
    }).toList();

    debugPrint('DRAWING RISK DOTS: ${riskCells.length}');

    final markers = <Marker>[
      Marker(
        point: location,
        width: 55,
        height: 55,
        child: const Icon(
          Icons.my_location,
          color: Colors.blue,
          size: 40,
        ),
      ),
    ];

    for (final place in safePlaces.take(10)) {
      markers.add(
        Marker(
          point: LatLng(
            place.latitude,
            place.longitude,
          ),
          width: 45,
          height: 45,
          child: const Icon(
            Icons.location_on,
            color: green,
            size: 34,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 400,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(
                  15.3173,
                  75.7139,
                ),
                initialZoom: 7.3,
                minZoom: 6,
                maxZoom: 19,
              ),
              children: [
                // ONLINE MAP
                // ============================================================
// BASE MAP
// ============================================================

// ONLINE OPENSTREETMAP
                if (_mapInternetAvailable)
                  TileLayer(
                    urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName:
                    'com.floodwatch.floodguard',
                    maxZoom: 19,
                    keepBuffer: 2,
                    panBuffer: 1,
                  )

// OFFLINE SHORTBREAD OSM
                else if (_offlineMapReady &&
                    _offlineStyle != null &&
                    _offlineMapProvider != null)
                  vt.VectorTileLayer(
                    theme: _offlineStyle!.theme,

                    tileProviders: _offlineStyle!.providers,

                    rasterSources:
                    _offlineStyle!.rasterSources,

                    sprites: _offlineStyle!.sprites,

                    tileOffset: vt.TileOffset.maplibre,

                    showLabels: true,

                    logger: const vt.Logger.console(),
                  ),

                // FLOOD RISK AREAS
                if (riskCells.isNotEmpty)
                  PolygonLayer(
                    polygons: riskCells.map((cell) {
                      final latitude =
                      (cell['latitude'] as num).toDouble();

                      final longitude =
                      (cell['longitude'] as num).toDouble();

                      final dotColor = mapRiskColor(
                        cell['final_color']?.toString(),
                      );

                      const double cellSize = 0.08;

                      return Polygon(
                        points: [
                          LatLng(
                            latitude - cellSize / 2,
                            longitude - cellSize / 2,
                          ),
                          LatLng(
                            latitude - cellSize / 2,
                            longitude + cellSize / 2,
                          ),
                          LatLng(
                            latitude + cellSize / 2,
                            longitude + cellSize / 2,
                          ),
                          LatLng(
                            latitude + cellSize / 2,
                            longitude - cellSize / 2,
                          ),
                        ],
                        color: dotColor.withOpacity(0.18),
                        borderColor: dotColor.withOpacity(0.85),
                        borderStrokeWidth: 0.8,
                      );
                    }).toList(),
                  ),

                // MARKERS
                MarkerLayer(
                  markers: markers,
                ),

                // ATTRIBUTION
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),

            // 🔍 EXPAND MAP BUTTON
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(10),
                elevation: 4,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenMapScreen(
                          riskCells: riskCells,
                          markers: markers,
                          mapInternetAvailable: _mapInternetAvailable,
                          offlineMapReady: _offlineMapReady,
                          offlineStyle: _offlineStyle,
                          offlineMapProvider: _offlineMapProvider,
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ),
              ),
            ),

            // 📡 OFFLINE MAP MESSAGE
            if (!_mapInternetAvailable)
              Positioned(
                top: 12,
                left: 12,
                right: 65,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: 0.85,
                    ),
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        color: Colors.orange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline map • Internet unavailable',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildFloodRiskLegend() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF171011),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Row(
        mainAxisAlignment:
        MainAxisAlignment.spaceEvenly,
        children: [
          _riskLegendItem(
            Colors.green,
            'Low',
          ),
          _riskLegendItem(
            Colors.orange,
            'Moderate',
          ),
          _riskLegendItem(
            Colors.red,
            'High',
          ),
        ],
      ),
    );
  }

  Widget _riskLegendItem(
      Color color,
      String title,
      ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // WEATHER TAB
  // ============================================================

  Widget buildWeatherTab() {
    return ListView(
      padding:
      const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        40,
      ),
      children: [
        buildCurrentWeather(),

        const SizedBox(
          height: 24,
        ),

        const Text(
          'HOUR BY HOUR · NEXT 24H',
          style:
          TextStyle(
            color: muted,
            fontWeight:
            FontWeight.bold,
            letterSpacing: 2,
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: hourlyForecast.length,
            itemBuilder: (context, index) {
              return buildHourlyCard(
                hourlyForecast[index],
                index,
              );
            },
          ),
        ),
        const SizedBox(
          height: 24,
        ),

        const Text(
          '7-DAY OUTLOOK',
          style:
          TextStyle(
            color: muted,
            fontWeight:
            FontWeight.bold,
            letterSpacing: 2,
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        ...dailyForecast.map(
          buildDailyCard,
        ),
      ],
    );
  }

  Widget buildCurrentWeather() {
    return Container(
      padding:
      const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(22),
        border: Border.all(
          color:
          const Color(0xFF34292B),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'RIGHT NOW',
            style:
            TextStyle(
              color: muted,
              letterSpacing: 1.4,
              fontSize: 12,
            ),
          ),

          const SizedBox(
            height: 4,
          ),

          Row(
            mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
            children: [
              Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .start,
                children: [
                  Text(
                    '${temperature.toStringAsFixed(0)}°',
                    style:
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 50,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),

                  Text(
                    currentCondition,
                    style:
                    const TextStyle(
                      color: muted,
                    ),
                  ),
                ],
              ),

              Column(
                crossAxisAlignment:
                CrossAxisAlignment
                    .end,
                children: [
                   Text(
                    locationName,
                    style:
                    TextStyle(
                      color: muted,
                    ),
                  ),
                  Text(
                    'Elevation '
                        '${elevation.toStringAsFixed(0)} m',
                    style:
                    const TextStyle(
                      color: muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(
            height: 20,
          ),

          Row(
            children: [
              weatherInfoBox(
                Icons.thermostat,
                'FEELS LIKE',
                '${feelsLike.toStringAsFixed(0)}°',
              ),

              const SizedBox(
                width: 10,
              ),

              weatherInfoBox(
                Icons.water_drop_outlined,
                'PRECIPITATION',
                '$currentRainProbability%',
              ),
            ],
          ),

          const SizedBox(
            height: 10,
          ),

          Row(
            children: [
              weatherInfoBox(
                Icons.opacity,
                'HUMIDITY',
                '${humidity.toStringAsFixed(0)}%',
              ),

              const SizedBox(
                width: 10,
              ),

              weatherInfoBox(
                Icons.air,
                'WIND',
                '${windSpeed.toStringAsFixed(0)} km/h',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget weatherInfoBox(
      IconData icon,
      String title,
      String value,
      ) {
    return Expanded(
      child: Container(
        height: 90,
        padding:
        const EdgeInsets.all(12),
        decoration:
        BoxDecoration(
          color:
          const Color(0xFF120D0E),
          borderRadius:
          BorderRadius.circular(
            16,
          ),
          border: Border.all(
            color:
            const Color(0xFF392B2D),
          ),
        ),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 17,
              color: Colors.white,
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              title,
              style:
              const TextStyle(
                color: muted,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style:
              const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget buildHourlyCard(
HourlyForecast weather,
int index,
) {
    return Container(
      width: 92,
      margin:
      const EdgeInsets.only(
        right: 8,
      ),
      padding:
      const EdgeInsets.all(10),
      decoration:
      BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color:
          const Color(0xFF392B2D),
        ),
      ),
      child: Column(
        children: [
          Text(
            index == 0
                ? 'NOW'
                : formatHour(weather.time),
            style: TextStyle(
              color: index == 0
                  ? green
                  : muted,
              fontSize: 11,
              fontWeight: index == 0
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Icon(
            weatherIcon(
              weather.weatherCode,
            ),
            color:
            weather.rain > 0
                ? Colors.lightBlue
                : Colors.white,
          ),

          const SizedBox(
            height: 6,
          ),

          Text(
            '${weather.temperature.toStringAsFixed(0)}°',
            style:
            const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight:
              FontWeight.bold,
            ),
          ),

          Text(
            '${weather.rain.toStringAsFixed(1)} mm',
            style:
            const TextStyle(
              color: muted,
              fontSize: 10,
            ),
          ),

          Text(
            '${weather.probability}%',
            style:
            const TextStyle(
              color: muted,
              fontSize: 10,
            ),
          ),

          const Divider(
            color:
            Color(0xFF3A2D2F),
          ),

          Text(
            '${weather.humidity.toStringAsFixed(0)}% RH',
            style:
            const TextStyle(
              color: muted,
              fontSize: 10,
            ),
          ),

          Text(
            '${weather.wind.toStringAsFixed(0)} km/h',
            style:
            const TextStyle(
              color: muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDailyCard(
      DailyForecast weather,
      ) {
    return Container(
      margin:
      const EdgeInsets.only(
        bottom: 8,
      ),
      padding:
      const EdgeInsets.all(14),
      decoration:
      BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color:
          const Color(0xFF392B2D),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              formatDay(
                weather.date,
              ),
              style:
              const TextStyle(
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ),

          Icon(
            weatherIcon(
              weather.weatherCode,
            ),
            color:
            weather.rain > 0
                ? Colors.lightBlue
                : Colors.white,
          ),

          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Text(
              weatherDescription(
                weather.weatherCode,
              ),
              style:
              const TextStyle(
                color: muted,
              ),
            ),
          ),

          Text(
            '${weather.maxTemperature.toStringAsFixed(0)}° / '
                '${weather.minTemperature.toStringAsFixed(0)}°',
            style:
            const TextStyle(
              fontWeight:
              FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SAFETY TAB
  // ============================================================

  Widget buildSafetyTab() {
    const items = [
      'Move documents, cash & medicines to a waterproof bag',
      'Charge phone + power bank fully',
      'Switch off mains power before water enters',
      'Store 3 days of drinking water and dry food',
      'Keep torch, whistle and first-aid kit at the door',
      'Agree a family meeting point on high ground',
    ];

    return ListView(
      padding:
      const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        40,
      ),
      children: [
        //buildSafetyChecklist(
         // items,
        //),

       // const SizedBox(
        //  height: 18,
       // ),

        buildSurvivalRules(),


        const SizedBox(
          height: 18,
        ),

        buildEmergencyCard(),
      ],
    );
  }

  Widget buildSafetyChecklist(
      List<String> items,
      ) {
    final completed =
        checklist.where(
              (value) => value,
        ).length;

    return Container(
      padding:
      const EdgeInsets.all(18),
      decoration:
      BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(
          22,
        ),
        border: Border.all(
          color:
          const Color(0xFF34292B),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Text(
            'GO-BAG CHECKLIST '
                '($completed/6)',
            style:
            const TextStyle(
              color: muted,
              fontWeight:
              FontWeight.bold,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          ...List.generate(
            items.length,
                (index) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    checklist[index] =
                    !checklist[index];
                  });
                },
                child: Container(
                  margin:
                  const EdgeInsets.only(
                    bottom: 8,
                  ),
                  padding:
                  const EdgeInsets.all(
                    12,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    const Color(
                      0xFF120D0E,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      16,
                    ),
                    border:
                    Border.all(
                      color:
                      const Color(
                        0xFF392B2D,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        checklist[index]
                            ? Icons
                            .check_box
                            : Icons
                            .check_box_outline_blank,
                        color:
                        checklist[index]
                            ? green
                            : Colors.white70,
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Expanded(
                        child: Text(
                          items[index],
                          style:
                          TextStyle(
                            color:
                            Colors.white,
                            decoration:
                            checklist[index]
                                ? TextDecoration
                                .lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildSurvivalRules() {
    return Container(
      padding:
      const EdgeInsets.all(18),
      decoration:
      BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(
          22,
        ),
        border: Border.all(
          color:
          const Color(0xFF34292B),
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'SURVIVAL RULES',
            style:
            TextStyle(
              color: muted,
              fontWeight:
              FontWeight.bold,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          survivalRule(
            Icons.bolt,
            'Never walk or drive through moving water — 15 cm can knock you down.',
          ),

          survivalRule(
            Icons.electric_bolt,
            'Avoid fallen power lines and submerged electrical points.',
          ),

          survivalRule(
            Icons.water_drop,
            'Do not drink flood water; boil or purify everything.',
          ),

          survivalRule(
            Icons.notifications,
            'Move upward, not outward, if water rises fast — avoid closed attics.',
          ),
        ],
      ),
    );
  }

  Widget survivalRule(
      IconData icon,
      String text,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: red,
            size: 18,
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child: Text(
              text,
              style:
              const TextStyle(
                color: muted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget buildHeader() {
    return Padding(
      padding:
      const EdgeInsets.fromLTRB(
        18,
        14,
        18,
        8,
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logowhite.png',
            width: 42,
            height: 42,
            fit: BoxFit.contain,
          ),
          const SizedBox(
            width: 12,
          ),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'FloodGuard',
                  style:
                  TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                Text(
                  locationLoading
                      ? 'Getting GPS...'
                      : locationStatus,
                  style:
                  const TextStyle(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          Container(
            width: 40,
            height: 40,
            decoration:
            BoxDecoration(
              shape:
              BoxShape.circle,
              border: Border.all(
                color:
                const Color(
                  0xFF392B2D,
                ),
              ),
            ),
            child: IconButton(
              onPressed:
              refreshAll,
              icon: const Icon(
                Icons.gps_fixed,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),

          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF392B2D),
              ),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                    const ProfileScreen(),
                  ),
                );
              },
              icon: const Icon(
                Icons.person_outline,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOP TABS
  // ============================================================

  Widget buildTabs() {
    return Container(
      margin:
      const EdgeInsets.fromLTRB(
        18,
        8,
        18,
        4,
      ),
      padding:
      const EdgeInsets.all(4),
      decoration:
      BoxDecoration(
        color: card,
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color:
          const Color(0xFF34292B),
        ),
      ),
      child: Row(
        children: [
          tabButton(
            AppLanguage.tr('alert_tab'),
            0,
          ),
          tabButton(
            AppLanguage.tr('weather_tab'),
            1,
          ),
          tabButton(
            AppLanguage.tr('safety_tab'),
            2,
          ),
        ],
      ),
    );
  }

  Widget tabButton(
      String title,
      int index,
      ) {
    final selected =
        selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = index;
          });
        },
        child: AnimatedContainer(
          duration:
          const Duration(
            milliseconds: 180,
          ),
          height: 42,
          alignment:
          Alignment.center,
          decoration:
          BoxDecoration(
            color: selected
                ? red
                : Colors.transparent,
            borderRadius:
            BorderRadius.circular(
              15,
            ),
          ),
          child: Text(
            title,
            style:
            TextStyle(
              color: selected
                  ? Colors.white
                  : muted,
              fontWeight:
              selected
                  ? FontWeight.bold
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      background,

      body: SafeArea(
        child: Column(
          children: [
            buildHeader(),
            buildTabs(),

            Expanded(
              child:
              selectedTab == 0
                  ? buildAlertTab()
                  : selectedTab == 1
                  ? buildWeatherTab()
                  : buildSafetyTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> refreshAll() async {
    await getCurrentLocation();

    if (currentLocation == null) {
      return;
    }

    await Future.wait([
      loadWeather(),
      loadElevation(),
      loadRiverDistance(),
      findSafePlaces(),
    ]);

    await runFloodPrediction();
  }

  Future<void> sendSOS() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login first.'),
        ),
      );
      return;
    }

    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Getting your location... Please try again.'),
        ),
      );

      await getCurrentLocation();

      if (currentLocation == null) return;
    }

    try {
      // Get both family members
      final familySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('familyMembers')
          .get();

      if (familySnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please add your emergency family members first.'),
          ),
        );
        return;
      }

      // Collect phone numbers from BOTH members
      final List<String> phoneNumbers = [];

      for (final doc in familySnapshot.docs) {
        final data = doc.data();

        final phone = (data['phone'] ?? '').toString().trim();

        if (phone.isNotEmpty) {
          phoneNumbers.add(phone);
        }
      }

      if (phoneNumbers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No emergency phone numbers found.'),
          ),
        );
        return;
      }

      final latitude = currentLocation!.latitude;
      final longitude = currentLocation!.longitude;

      final mapsLink =
          'https://www.google.com/maps/search/?api=1'
          '&query=$latitude,$longitude';

      final message =
          '🚨 EMERGENCY SOS - FloodGuard\n\n'
          'I need emergency help.\n\n'
          'My current location:\n'
          '$mapsLink\n\n'
          'Please contact me immediately.';

      // Send to BOTH family members
      final recipients = phoneNumbers.join(',');

      final smsUri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: {
          'body': message,
        },
      );

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'SOS message prepared for ${phoneNumbers.length} emergency contacts.',
            ),
          ),
        );
      } else {
        throw Exception('SMS application not available');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to send SOS: $e'),
        ),
      );
    }
  }

  Future<void>
  copyLocationMessage() async {
    if (currentLocation == null) {
      showMessage(
        'Location unavailable.',
      );
      return;
    }

    showMessage(
      'Location: '
          '${currentLocation!.latitude}, '
          '${currentLocation!.longitude}',
    );
  }



  Future<void> callNumber(
      String number,
      ) async {
    final uri =
    Uri.parse('tel:$number');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        showMessage(
          'Unable to open phone dialer.',
        );
      }
    } catch (_) {
      showMessage(
        'Unable to make call.',
      );
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  InputDecoration inputDecoration(
      String hint,
      ) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
      const TextStyle(
        color: muted,
      ),
      filled: true,
      fillColor:
      const Color(0xFF120D0E),
      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      enabledBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        borderSide:
        const BorderSide(
          color:
          Color(0xFF392B2D),
        ),
      ),
      focusedBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
          18,
        ),
        borderSide:
        const BorderSide(
          color: red,
        ),
      ),
    );
  }


  Color riskColor() {
    switch (aiRisk.toUpperCase()) {
      case 'HIGH':
        return const Color(0xFFEF5350);

      case 'MODERATE':
        return const Color(0xFFFFB74D);

      case 'LOW':
      default:
        return const Color(0xFFA3E2A4);
    }
  }

  Color riskBackgroundColor() {
    switch (aiRisk.trim().toUpperCase()) {
      case 'HIGH':
        return const Color(0xFF2E1517);

      case 'MODERATE':
        return const Color(0xFF2E2312);

      case 'LOW':
      default:
        return const Color(0xFF142B18);
    }
  }

  String weatherDescription(
      int code,
      ) {
    if (code == 0) {
      return 'Clear sky';
    }

    if (code <= 3) {
      return 'Cloudy';
    }

    if (code == 45 ||
        code == 48) {
      return 'Foggy';
    }

    if (code >= 51 &&
        code <= 57) {
      return 'Drizzle';
    }

    if (code >= 61 &&
        code <= 67) {
      return 'Rain';
    }

    if (code >= 80 &&
        code <= 82) {
      return 'Rain showers';
    }

    if (code >= 95) {
      return 'Thunderstorm';
    }

    return 'Cloudy';
  }

  IconData weatherIcon(
      int code,
      ) {
    if (code == 0) {
      return Icons.wb_sunny;
    }

    if (code <= 3) {
      return Icons.cloud;
    }

    if (code >= 51 &&
        code <= 67) {
      return Icons.water_drop;
    }

    if (code >= 80 &&
        code <= 82) {
      return Icons.grain;
    }

    if (code >= 95) {
      return Icons.thunderstorm;
    }

    return Icons.cloud;
  }

  String formatHour(DateTime time) {
    final hour = time.hour;

    final period = hour >= 12 ? 'PM' : 'AM';

    final displayHour = hour % 12 == 0
        ? 12
        : hour % 12;

    return '$displayHour $period';
  }

  String formatDay(
      DateTime date,
      ) {
    const days = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    return days[
    date.weekday - 1];
  }

  String formatDistance(
      double meters,
      ) {
    final suffix = AppLanguage.tr('high_ground');
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m · $suffix';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km · $suffix';
  }

  String placeType(
      String amenity,
      ) {
    switch (amenity) {
      case 'hospital':
        return AppLanguage.tr('hospital');

      case 'school':
        return AppLanguage.tr('school');

      case 'shelter':
        return AppLanguage.tr('emergency_shelter');

      case 'community_centre':
        return AppLanguage.tr('community_centre');

      case 'fire_station':
        return AppLanguage.tr('fire_station');

      case 'police':
        return AppLanguage.tr('police_station');

      default:
        return AppLanguage.tr('safe_place');
    }
  }

  double _sumForecastRain(
      int hours,
      ) {
    if (hourlyForecast.isEmpty) {
      return 0;
    }

    final limit =
    math.min(
      hours,
      hourlyForecast.length,
    );

    double total = 0;

    for (int i = 0;
    i < limit;
    i++) {
      total +=
          hourlyForecast[i].rain;
    }

    return total;
  }

  int _dayOfYear(
      DateTime date,
      ) {
    final first =
    DateTime(
      date.year,
      1,
      1,
    );

    return date
        .difference(first)
        .inDays +
        1;
  }

  static double _toDouble(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value.toString(),
    ) ??
        0;
  }

  static int _toInt(
      dynamic value,
      ) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value.toString(),
    ) ??
        0;
  }

  void showMessage(
      String message,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
        Text(message),
        behavior:
        SnackBarBehavior
            .floating,
      ),
    );
  }
}

// ============================================================
// WEATHER MODELS
// ============================================================

class HourlyForecast {
  final DateTime time;
  final double temperature;
  final double rain;
  final int probability;
  final double humidity;
  final double wind;
  final int weatherCode;

  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.rain,
    required this.probability,
    required this.humidity,
    required this.wind,
    required this.weatherCode,
  });
}

class DailyForecast {
  final DateTime date;
  final double maxTemperature;
  final double minTemperature;
  final int probability;
  final double rain;
  final int weatherCode;

  const DailyForecast({
    required this.date,
    required this.maxTemperature,
    required this.minTemperature,
    required this.probability,
    required this.rain,
    required this.weatherCode,
  });
}

// ============================================================
// SAFE PLACE MODEL
// ============================================================

class SafePlaceItem {
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final double distance;

  const SafePlaceItem({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distance,
  });
}
class FullScreenMapScreen extends StatelessWidget {
  final List<Map<String, dynamic>> riskCells;
  final List<Marker> markers;

  final bool mapInternetAvailable;
  final bool offlineMapReady;
  final vt.Style? offlineStyle;
  final MbTilesVectorTileProvider? offlineMapProvider;

  const FullScreenMapScreen({
    super.key,
    required this.riskCells,
    required this.markers,
    required this.mapInternetAvailable,
    required this.offlineMapReady,
    required this.offlineStyle,
    required this.offlineMapProvider,
  });

  Color mapRiskColor(String? color) {
    switch ((color ?? '').toLowerCase()) {
      case 'red':
        return const Color(0xFFE5091A);

      case 'orange':
        return const Color(0xFFFF9D3D);

      case 'green':
      default:
        return const Color(0xFF68D46A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppLanguage.tr('flood_risk_map')),
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(
            15.3173,
            75.7139,
          ),
          initialZoom: 7.3,
          minZoom: 6,
          maxZoom: 19,
        ),
        children: [
          // ======================================================
          // ONLINE MAP
          // ======================================================

          if (mapInternetAvailable)
            TileLayer(
              urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
              'com.floodwatch.floodguard',
              maxZoom: 19,
              keepBuffer: 2,
              panBuffer: 1,
            )

          // ======================================================
          // OFFLINE MAP
          // ======================================================

          else if (offlineMapReady &&
              offlineStyle != null &&
              offlineMapProvider != null)
            vt.VectorTileLayer(
              theme: offlineStyle!.theme,
              tileProviders: offlineStyle!.providers,
              rasterSources: offlineStyle!.rasterSources,
              sprites: offlineStyle!.sprites,
              tileOffset: vt.TileOffset.maplibre,
              showLabels: true,
              logger: const vt.Logger.console(),
            )

          // ======================================================
          // NO MAP
          // ======================================================

          else
            const ColoredBox(
              color: Color(0xFF0B0708),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      color: Colors.white54,
                      size: 50,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Offline map is not available',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ======================================================
          // FLOOD RISK AREAS
          // ======================================================

          if (riskCells.isNotEmpty)
            PolygonLayer(
              polygons: riskCells.map((cell) {
                final latitude =
                (cell['latitude'] as num).toDouble();

                final longitude =
                (cell['longitude'] as num).toDouble();

                final dotColor = mapRiskColor(
                  cell['final_color']?.toString(),
                );

                const double cellSize = 0.08;

                return Polygon(
                  points: [
                    LatLng(
                      latitude - cellSize / 2,
                      longitude - cellSize / 2,
                    ),
                    LatLng(
                      latitude - cellSize / 2,
                      longitude + cellSize / 2,
                    ),
                    LatLng(
                      latitude + cellSize / 2,
                      longitude + cellSize / 2,
                    ),
                    LatLng(
                      latitude + cellSize / 2,
                      longitude - cellSize / 2,
                    ),
                  ],
                  color: dotColor.withOpacity(0.18),
                  borderColor: dotColor.withOpacity(0.85),
                  borderStrokeWidth: 0.8,
                );
              }).toList(),
            ),

          // ======================================================
          // MARKERS
          // ======================================================

          MarkerLayer(
            markers: markers,
          ),

          // ======================================================
          // ATTRIBUTION
          // ======================================================

          RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
              ),
            ],
          ),
        ],
      ),
    );
  }
}