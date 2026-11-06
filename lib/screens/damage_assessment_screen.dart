import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'damage_assessment_map_screen.dart';
import '../services/resource_allocation_service.dart';
import 'resource_allocation_screen.dart';

class DamageAssessmentScreen extends StatefulWidget {
  final LatLng? initialCenter;

  const DamageAssessmentScreen({
    super.key,
    this.initialCenter,
  });

  static Future<String> getActiveBaseUrl({bool forceRefresh = false}) =>
      _DamageAssessmentScreenState.getActiveBaseUrl(forceRefresh: forceRefresh);

  @override
  State<DamageAssessmentScreen> createState() =>
      _DamageAssessmentScreenState();
}

class _DamageAssessmentScreenState
    extends State<DamageAssessmentScreen> {
  static const Color background = Color(0xFF0B0708);
  static const Color card = Color(0xFF191214);
  static const Color red = Color(0xFFEF5350);
  static const Color orange = Color(0xFFFFB74D);
  static const Color green = Color(0xFFA3E2A4);
  static const Color muted = Color(0xFFAAAAAA);

  static String? _cachedBaseUrl;

  static Future<String> getActiveBaseUrl({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedBaseUrl != null) return _cachedBaseUrl!;

    final List<String> candidates;
    if (kIsWeb) {
      candidates = ['http://127.0.0.1:8000', 'http://localhost:8000'];
    } else if (Platform.isAndroid) {
      candidates = [
        'http://192.168.1.5:8000',
        'http://10.0.2.2:8000',
        'http://127.0.0.1:8000',
        'http://192.168.1.3:8000',
        'http://192.168.1.2:8000',
        'http://192.168.1.4:8000',
        'http://192.168.1.6:8000',
        'http://192.168.1.100:8000',
        'http://192.168.0.100:8000',
        'http://192.168.0.101:8000',
        'http://localhost:8000',
      ];
    } else {
      candidates = ['http://127.0.0.1:8000', 'http://localhost:8000'];
    }

    final completer = Completer<String>();
    int pending = candidates.length;

    for (final url in candidates) {
      http.get(Uri.parse('$url/')).timeout(const Duration(seconds: 3)).then((res) {
        if (res.statusCode == 200 && !completer.isCompleted) {
          _cachedBaseUrl = url;
          completer.complete(url);
        } else {
          pending--;
          if (pending == 0 && !completer.isCompleted) {
            completer.complete(
              Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000',
            );
          }
        }
      }).catchError((_) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(
            Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000',
          );
        }
      });
    }

    return completer.future;
  }

  static String get baseUrl {
    return _cachedBaseUrl ??
        (Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000');
  }

  final ImagePicker _picker = ImagePicker();
  final MapController _mapController = MapController();

  File? beforeImage;
  File? afterImage;

  Position? currentPosition;

  bool compareMode = true;
  bool isGettingLocation = false;
  bool isUploading = false;
  bool isLoadingAssessments = false;

  List<Map<String, dynamic>> assessments = [];

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Timer? _refreshTimer;
  AllocationSummary? _allocationSummary;

  Future<void> _loadAllocationData() async {
    final data = await ResourceAllocationService.instance.loadAllocationData();
    var locs = data['locations'] as List<AffectedLocation>;
    final avail = data['available_resources'] as AvailableResources;

    if (assessments.isNotEmpty) {
      locs = ResourceAllocationService.instance.syncWithImageAssessments(
        assessments,
        locs,
      );
    }

    final summary = ResourceAllocationService.instance.calculateSummary(
      locations: locs,
      availableResources: avail,
    );
    if (mounted) {
      setState(() {
        _allocationSummary = summary;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadAssessments();

    // Auto-refresh assessments every 8 seconds so dots from all users appear live
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => loadAssessments(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        getCurrentLocation();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // LOAD ASSESSMENTS FROM PYTHON API
  // ============================================================

  Future<void> loadAssessments() async {
    setState(() {
      isLoadingAssessments = true;
    });

    try {
      final activeUrl = await getActiveBaseUrl();
      final response = await http
          .get(Uri.parse('$activeUrl/assessments'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> records = decoded is Map<String, dynamic>
            ? (decoded['assessments'] as List<dynamic>? ?? [])
            : (decoded is List ? decoded : []);

        if (!mounted) return;

        setState(() {
          assessments = records
              .where((item) =>
                  item is Map &&
                  item['latitude'] != null &&
                  item['longitude'] != null)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });

        await _loadAllocationData();
      } else {
        throw Exception('Unable to load assessments.');
      }
    } catch (e) {
      _cachedBaseUrl = null;
      debugPrint('Assessment loading error: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingAssessments = false;
        });
      }
    }
  }

  // ============================================================
  // DAMAGE COLOUR
  // ============================================================

  Color getDamageColor(Map<String, dynamic> item) {
    final status =
        (item['analysis_status'] ?? '').toString().toLowerCase();

    if (status != 'completed' &&
        status != 'complete' &&
        status != 'success') {
      return Colors.grey;
    }

    final severity =
        (item['severity'] ?? '').toString().toUpperCase();

    final damage =
        (item['damageLevel'] ?? '').toString().toUpperCase();

    if (severity == 'HIGH' ||
        severity == 'SEVERE' ||
        severity == 'CRITICAL' ||
        damage.contains('FULL') ||
        damage.contains('SEVERE')) {
      return red;
    }

    if (severity == 'MODERATE' ||
        severity == 'MEDIUM' ||
        damage.contains('PARTIAL') ||
        damage.contains('MODERATE')) {
      return orange;
    }

    if (severity == 'LOW' ||
        severity == 'MINOR' ||
        damage.contains('MINOR')) {
      return Colors.yellow;
    }

    if (severity == 'NONE' ||
        severity == 'NO DAMAGE' ||
        severity == 'UNDAMAGED' ||
        damage.contains('NO_BUILDING') ||
        damage.contains('NO_DAMAGE') ||
        damage.contains('UNDAMAGED') ||
        damage.contains('NO VISIBLE')) {
      return green;
    }

    return Colors.grey;
  }

  String getDamageLabel(Map<String, dynamic> item) {
    final status =
        (item['analysis_status'] ?? '').toString().toLowerCase();

    if (status != 'completed' &&
        status != 'complete' &&
        status != 'success') {
      return 'Pending AI Analysis';
    }

    final damage = (item['damageLevel'] ?? '').toString().toUpperCase();
    final severity = (item['severity'] ?? '').toString().toUpperCase();

    if (damage.contains('NO_BUILDING')) {
      return 'No Building Detected';
    }

    if (severity == 'NONE' ||
        severity == 'NO DAMAGE' ||
        damage.contains('NO_DAMAGE') ||
        damage.contains('UNDAMAGED') ||
        damage.contains('NO VISIBLE')) {
      return 'No Building Damage';
    }

    if (severity == 'HIGH' ||
        severity == 'SEVERE' ||
        damage.contains('SEVERE') ||
        damage.contains('FULL')) {
      return 'Severe Damage';
    }

    if (severity == 'MODERATE' ||
        severity == 'MEDIUM' ||
        damage.contains('MODERATE') ||
        damage.contains('PARTIAL')) {
      return 'Moderate Damage';
    }

    if (severity == 'LOW' ||
        severity == 'MINOR' ||
        damage.contains('MINOR')) {
      return 'Minor Damage';
    }

    return (item['severity'] ?? item['damageLevel'] ?? 'Unknown').toString();
  }

  // ============================================================
  // SHOW ASSESSMENT DETAILS
  // ============================================================

  void showDamageDetails(Map<String, dynamic> item) {
    final color = getDamageColor(item);

    final lat = _parseDouble(item['latitude']) ?? 0.0;
    final lon = _parseDouble(item['longitude']) ?? 0.0;

    final severity = getDamageLabel(item);

    final priority =
        item['inspectionPriority'] ?? 'Not yet assigned';

    final details =
        item['details'] ?? 'Waiting for AI damage analysis.';

    String? resolveUrl(dynamic raw) {
      if (raw == null) return null;
      final str = raw.toString().trim();
      if (str.isEmpty) return null;
      if (str.startsWith('http://') || str.startsWith('https://')) return str;
      if (str.startsWith('damage_assessment_uploads/')) {
        final filename = str.split('/').last;
        return '$baseUrl/uploads/$filename';
      }
      final clean = str.startsWith('/') ? str : '/$str';
      return '$baseUrl$clean';
    }

    final afterImageUrl = resolveUrl(
      item['imageUrl'] ?? item['image_url'] ?? item['after_image'],
    );
    final beforeImageUrl = resolveUrl(
      item['beforeImageUrl'] ?? item['before_image'],
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Building Damage Assessment',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                if (beforeImageUrl != null && afterImageUrl != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BEFORE FLOOD',
                              style: TextStyle(
                                color: muted,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                beforeImageUrl,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) => Container(
                                  height: 120,
                                  color: background,
                                  alignment: Alignment.center,
                                  child: const Text('Photo unavailable',
                                      style: TextStyle(color: muted, fontSize: 11)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AFTER FLOOD',
                              style: TextStyle(
                                color: red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                afterImageUrl,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, err, st) => Container(
                                  height: 120,
                                  color: background,
                                  alignment: Alignment.center,
                                  child: const Text('Photo unavailable',
                                      style: TextStyle(color: muted, fontSize: 11)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (afterImageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      afterImageUrl,
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 120,
                          color: background,
                          alignment: Alignment.center,
                          child: const Text(
                            'Image unavailable',
                            style: TextStyle(color: muted),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Text(
                  'Status: $severity',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Inspection Priority: $priority',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'GPS Coordinates: '
                  '${lat.toStringAsFixed(5)}, '
                  '${lon.toStringAsFixed(5)}',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  details,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> pickImage(bool isBefore) async {
    ImageSource? source;

    if (!isBefore) {
      // After-flood image must be captured using live camera.
      source = ImageSource.camera;
    } else {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: card,
        builder: (context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.camera_alt,
                    color: red,
                  ),
                  title: const Text(
                    'Take Photo with Camera',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () =>
                      Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library,
                    color: red,
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () =>
                      Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          );
        },
      );
    }

    if (source == null) return;

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image == null || !mounted) return;

      setState(() {
        if (isBefore) {
          beforeImage = File(image.path);
        } else {
          afterImage = File(image.path);
        }
      });

      await getCurrentLocation();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to capture photo: $e'),
        ),
      );
    }
  }

  // ============================================================
  // GPS LOCATION
  // ============================================================

  Future<void> getCurrentLocation() async {
    if (isGettingLocation) return;

    setState(() {
      isGettingLocation = true;
    });

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('Please enable location services.');
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission not granted.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      setState(() {
        currentPosition = position;
      });

      try {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          12.0,
        );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isGettingLocation = false;
        });
      }
    }
  }

  // ============================================================
  // UPLOAD IMAGES TO PYTHON FASTAPI BACKEND
  // ============================================================

  Future<void> uploadAssessment() async {
    if (afterImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please capture an after-flood photograph using the camera.',
          ),
        ),
      );
      return;
    }

    if (compareMode && beforeImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a before-flood photograph.',
          ),
        ),
      );
      return;
    }

    if (currentPosition == null) {
      await getCurrentLocation();
      if (currentPosition == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to capture GPS location. Please check location settings.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      isUploading = true;
    });

    try {
      final activeUrl = await getActiveBaseUrl();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$activeUrl/assessments'),
      );

      request.fields['mode'] =
          compareMode ? 'before_after' : 'after_only';

      request.fields['latitude'] =
          currentPosition!.latitude.toString();

      request.fields['longitude'] =
          currentPosition!.longitude.toString();

      request.files.add(
        await http.MultipartFile.fromPath(
          'after_image',
          afterImage!.path,
        ),
      );

      if (compareMode && beforeImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'before_image',
            beforeImage!.path,
          ),
        );
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 25),
      );

      final response =
          await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        dynamic result;
        try {
          result = jsonDecode(response.body);
        } catch (_) {}

        if (!mounted) return;

        setState(() {
          beforeImage = null;
          afterImage = null;
        });

        await loadAssessments();

        if (!mounted) return;

        final message = (result is Map && result['message'] != null)
            ? result['message'].toString()
            : 'Photographs uploaded successfully. Waiting for AI analysis.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(
          'Upload failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      _cachedBaseUrl = null;
      debugPrint('Damage assessment upload error: $e');

      if (!mounted) return;

      String errorMsg = e.toString();
      if (errorMsg.contains('TimeoutException') ||
          errorMsg.contains('SocketException') ||
          errorMsg.contains('Connection refused')) {
        errorMsg =
            'Cannot connect to backend server.\n'
            'Please ensure the Python backend is running and your device is on the same network.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
        });
      }
    }
  }

  // ============================================================
  // EMBEDDED DAMAGE MAP
  // ============================================================

  Widget buildEmbeddedDamageMap() {
    final defaultCenter = currentPosition != null
        ? LatLng(
            currentPosition!.latitude,
            currentPosition!.longitude,
          )
        : widget.initialCenter ??
            const LatLng(15.3173, 75.7139);

    final Map<String, int> locationCounts = {};
    final markers = assessments.map((item) {
      final baseLat = _parseDouble(item['latitude']);
      final baseLon = _parseDouble(item['longitude']);
      if (baseLat == null || baseLon == null) return null;

      final key = '${baseLat.toStringAsFixed(4)},${baseLon.toStringAsFixed(4)}';
      final count = locationCounts[key] ?? 0;
      locationCounts[key] = count + 1;

      double lat = baseLat;
      double lon = baseLon;
      if (count > 0) {
        final angle = count * 1.25;
        final radius = count * 0.00035;
        lat += radius * math.cos(angle);
        lon += radius * math.sin(angle);
      }

      final color = getDamageColor(item);

      return Marker(
        point: LatLng(lat, lon),
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => showDamageDetails(item),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.65),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              14,
              10,
              10,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.map_outlined,
                  color: red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Disaster Damage Assessment Map',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: loadAssessments,
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            DamageAssessmentMapScreen(
                          initialCenter: currentPosition != null
                              ? LatLng(
                                  currentPosition!.latitude,
                                  currentPosition!.longitude,
                                )
                              : defaultCenter,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'FULLSCREEN',
                    style: TextStyle(
                      color: red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 240,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(22),
              ),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: defaultCenter,
                      initialZoom: 7,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.floodwatch.floodguard',
                        maxZoom: 19,
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),

                  if (isLoadingAssessments)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: CircularProgressIndicator(
                        color: red,
                        strokeWidth: 2,
                      ),
                    ),

                  if (assessments.isEmpty &&
                      !isLoadingAssessments)
                    const Center(
                      child: Card(
                        color: Color(0xDD191214),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No damage assessments submitted yet.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _buildLegendItem(red, 'Severe'),
                _buildLegendItem(orange, 'Moderate'),
                _buildLegendItem(Colors.yellow, 'Minor'),
                _buildLegendItem(green, 'No damage'),
                _buildLegendItem(Colors.grey, 'Pending'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // IMAGE UPLOAD CARD
  // ============================================================

  Widget imageUploadCard({
    required String title,
    required String description,
    required File? image,
    required VoidCallback onTap,
  }) {
    final isAfter = title.contains('After');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: red.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isAfter)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Live Camera Only',
                    style: TextStyle(
                      color: red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            description,
            style: const TextStyle(
              color: muted,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 14),

          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white24,
                ),
              ),
              child: image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        image,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_a_photo_outlined,
                          color: red,
                          size: 38,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isAfter
                              ? 'Tap to Capture Live Photo'
                              : 'Tap to Upload Photo',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          isAfter
                              ? 'Camera Capture Required'
                              : 'Camera or Gallery',
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'AI Damage Assessment',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildEmbeddedDamageMap(),

            const SizedBox(height: 24),

            const Text(
              'Assess Flood Damage',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Capture flood-affected building photographs to evaluate visible damage and map affected locations.',
              style: TextStyle(
                color: muted,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              'Select Assessment Mode',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: true,
                    groupValue: compareMode,
                    activeColor: red,
                    title: const Text(
                      'Before + After Comparison',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Compare a pre-flood photograph with a new post-flood camera photo.',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          compareMode = value;
                        });
                      }
                    },
                  ),

                  RadioListTile<bool>(
                    value: false,
                    groupValue: compareMode,
                    activeColor: red,
                    title: const Text(
                      'After-Only Assessment',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Assess visible flood impact using a live camera photo.',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          compareMode = value;
                          beforeImage = null;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            if (compareMode) ...[
              imageUploadCard(
                title: 'Before Flood Image',
                description:
                    'Select an old photograph taken before flooding.',
                image: beforeImage,
                onTap: () => pickImage(true),
              ),
              const SizedBox(height: 18),
            ],

            imageUploadCard(
              title: 'After Flood Image',
              description:
                  'Capture a live photograph of the affected building.',
              image: afterImage,
              onTap: () => pickImage(false),
            ),

            const SizedBox(height: 22),

            // GPS CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: red),
                      SizedBox(width: 8),
                      Text(
                        'Assessment GPS Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  if (isGettingLocation)
                    const Text(
                      'Capturing GPS location...',
                      style: TextStyle(color: muted),
                    )
                  else if (currentPosition != null)
                    Text(
                      'GPS Coordinates: '
                      '${currentPosition!.latitude.toStringAsFixed(5)}, '
                      '${currentPosition!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Colors.white,
                        height: 1.5,
                      ),
                    )
                  else
                    const Text(
                      'Location will be captured when you take a photo.',
                      style: TextStyle(color: muted),
                    ),

                  const SizedBox(height: 12),

                  TextButton.icon(
                    onPressed: isGettingLocation
                        ? null
                        : getCurrentLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Refresh GPS Location'),
                    style: TextButton.styleFrom(
                      foregroundColor: red,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // UPLOAD BUTTON
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    isUploading ? null : uploadAssessment,
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(
                  isUploading
                      ? 'Uploading Photographs...'
                      : 'Submit Damage Assessment',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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

            const SizedBox(height: 28),

            // EMERGENCY RESOURCE ALLOCATION & AI PRIORITY DECISION SYSTEM
            buildResourceAllocationSection(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static const Color cardBorder = Color(0xFF342629);

  Widget buildResourceAllocationSection() {
    final sum = _allocationSummary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: red.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: red, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI RESOURCE ALLOCATION SYSTEM',
                      style: TextStyle(
                        color: red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Emergency Resource & Decision Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: Colors.white12),
          const SizedBox(height: 14),

          // STEP 1: FloodGuard identifies flood-affected locations
          _buildAllocationStep(
            stepNumber: '1',
            title: 'Flood-Affected Locations Identified',
            description: sum != null
                ? 'FloodGuard identified ${sum.totalLocations} active flood-affected regions across Karnataka.'
                : 'Identifies active flood-affected locations.',
            badgeText: sum != null ? '${sum.totalLocations} Locations' : 'Active',
            badgeColor: red,
            icon: Icons.location_city_outlined,
          ),

          const SizedBox(height: 14),

          // STEP 2: Risk Levels and Affected Population
          _buildAllocationStep(
            stepNumber: '2',
            title: 'Flood-Risk Levels & Population Data',
            description: sum != null
                ? 'Collected risk levels & ${sum.totalAffectedPopulation} affected residents.'
                : 'Collects flood-risk levels and population data.',
            badgeText: sum != null ? '${sum.totalAffectedPopulation} Residents' : 'Pop Data',
            badgeColor: orange,
            icon: Icons.people_outline,
          ),

          const SizedBox(height: 14),

          // STEP 3: Emergency teams enter available resources
          _buildAllocationStep(
            stepNumber: '3',
            title: 'Emergency Team Resource Inventory',
            description: sum != null
                ? 'Emergency teams registered ${sum.availableResources.boats} boats, ${sum.availableResources.foodPacks} food packs & ${sum.availableResources.rescueTeams} rescue teams.'
                : 'Emergency teams enter available resources.',
            badgeText: 'Manage Inventory',
            badgeColor: Colors.blue,
            icon: Icons.inventory_2_outlined,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResourceAllocationScreen()),
              ).then((_) => _loadAllocationData());
            },
          ),

          const SizedBox(height: 14),

          // STEP 4: System calculates resource shortages
          _buildAllocationStep(
            stepNumber: '4',
            title: 'Calculated Resource Shortages',
            description: sum != null
                ? 'Calculated deficit: ${sum.totalShortages.boats} boats missing, ${sum.totalShortages.foodPacks} food packs missing & ${sum.totalShortages.medicalKits} medical kits missing.'
                : 'System calculates resource shortages.',
            badgeText: sum != null ? '${sum.totalShortages.boats} Boats Short' : 'Shortage',
            badgeColor: red,
            icon: Icons.calculate_outlined,
          ),

          const SizedBox(height: 14),

          // STEP 5: AI recommends location priority
          _buildAllocationStep(
            stepNumber: '5',
            title: 'AI Priority Location Recommendation',
            description: sum != null
                ? 'AI Engine recommends prioritizing "${sum.topPriorityLocation}" (#1 Priority Target) for first resource deployment.'
                : 'AI recommends location resource priority.',
            badgeText: sum != null ? 'Rank #1 Target' : 'AI Priority',
            badgeColor: green,
            icon: Icons.psychology_outlined,
          ),

          const SizedBox(height: 14),

          // STEP 6: Authority Allocation Decisions
          _buildAllocationStep(
            stepNumber: '6',
            title: 'Authority Allocation & Decision Insights',
            description: 'Authorities can review AI insights, confirm dispatch orders, and manage resource distribution.',
            badgeText: 'Authority Action',
            badgeColor: red,
            icon: Icons.admin_panel_settings_outlined,
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ResourceAllocationScreen(),
                  ),
                ).then((_) => _loadAllocationData());
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text(
                'OPEN RESOURCE ALLOCATION & AI INSIGHTS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationStep({
    required String stepNumber,
    required String title,
    required String description,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: red.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text(
                stepNumber,
                style: const TextStyle(
                  color: red,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
