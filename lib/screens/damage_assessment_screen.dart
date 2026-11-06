import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'damage_assessment_map_screen.dart';

class DamageAssessmentScreen extends StatefulWidget {
  final LatLng? initialCenter;

  const DamageAssessmentScreen({
    super.key,
    this.initialCenter,
  });

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

  static Future<String> getActiveBaseUrl() async {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;

    final List<String> candidates;
    if (kIsWeb) {
      candidates = ['http://127.0.0.1:8000'];
    } else if (Platform.isAndroid) {
      candidates = [
        'http://10.0.2.2:8000',
        'http://192.168.1.3:8000',
        'http://192.168.1.5:8000',
        'http://192.168.0.100:8000',
        'http://127.0.0.1:8000',
      ];
    } else {
      candidates = ['http://127.0.0.1:8000'];
    }

    for (final url in candidates) {
      try {
        final res = await http
            .get(Uri.parse('$url/'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          _cachedBaseUrl = url;
          return url;
        }
      } catch (_) {}
    }

    _cachedBaseUrl = Platform.isAndroid
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
    return _cachedBaseUrl!;
  }

  static String get baseUrl {
    return _cachedBaseUrl ??
        (Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000');
  }

  final ImagePicker _picker = ImagePicker();

  File? beforeImage;
  File? afterImage;

  Position? currentPosition;

  bool compareMode = true;
  bool isGettingLocation = false;
  bool isUploading = false;
  bool isLoadingAssessments = false;

  List<Map<String, dynamic>> assessments = [];

  @override
  void initState() {
    super.initState();
    loadAssessments();

    if (widget.initialCenter != null) {
      // Use the location supplied by the previous screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          getCurrentLocation();
        }
      });
    }
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
        final result = jsonDecode(response.body);

        final List<dynamic> records = result['assessments'] ?? [];

        if (!mounted) return;

        setState(() {
          assessments = records
              .where((item) =>
          item['latitude'] != null &&
              item['longitude'] != null)
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        });
      } else {
        throw Exception('Unable to load assessments.');
      }
    } catch (e) {
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
        damage.contains('NO_DAMAGE') ||
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

    return (item['severity'] ?? item['damageLevel'] ?? 'Unknown')
        .toString();
  }

  // ============================================================
  // SHOW ASSESSMENT DETAILS
  // ============================================================

  void showDamageDetails(Map<String, dynamic> item) {
    final color = getDamageColor(item);

    final lat = (item['latitude'] as num).toDouble();
    final lon = (item['longitude'] as num).toDouble();

    final severity = getDamageLabel(item);

    final priority =
        item['inspectionPriority'] ?? 'Not yet assigned';

    final details =
        item['details'] ?? 'Waiting for AI damage analysis.';

    final imagePath = item['imageUrl'];

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

                if (imagePath != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      '$baseUrl$imagePath',
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
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
        final result = jsonDecode(response.body);

        if (!mounted) return;

        setState(() {
          beforeImage = null;
          afterImage = null;
        });

        await loadAssessments();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  'Photographs uploaded successfully. Waiting for AI analysis.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(
          'Upload failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
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

    final markers = assessments.map((item) {
      final lat = (item['latitude'] as num).toDouble();
      final lon = (item['longitude'] as num).toDouble();

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
                  color: color.withOpacity(0.65),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

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
                    options: MapOptions(
                      initialCenter: widget.initialCenter ??
                          const LatLng(15.3173, 75.7139),
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
          color: red.withOpacity(0.35),
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
                    color: red.withOpacity(0.2),
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
                      setState(() {
                        compareMode = value!;
                      });
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
                      setState(() {
                        compareMode = value!;
                        beforeImage = null;
                      });
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

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
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
                                : widget.initialCenter,
                          ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.map_outlined,
                  color: Colors.white,
                ),
                label: const Text(
                  'DISASTER DAMAGE ASSESSMENT MAP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Colors.white38,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}