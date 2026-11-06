
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class DamageAssessmentMapScreen extends StatefulWidget {
  final LatLng? initialCenter;

  const DamageAssessmentMapScreen({
    super.key,
    this.initialCenter,
  });

  @override
  State<DamageAssessmentMapScreen> createState() =>
      _DamageAssessmentMapScreenState();
}

class _DamageAssessmentMapScreenState
extends State<DamageAssessmentMapScreen> {

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

static const Color red = Color(0xFFFF2525);
static const Color orange = Color(0xFFFF922E);
static const Color yellow = Color(0xFFFFD43B);
static const Color green = Color(0xFF20C957);
static const Color grey = Color(0xFF9E9E9E);

List<Map<String, dynamic>> assessments = [];

bool isLoading = true;
String? errorMessage;

Timer? refreshTimer;

@override
void initState() {
super.initState();

fetchAssessments();

// Automatically refresh every 10 seconds.
refreshTimer = Timer.periodic(
const Duration(seconds: 10),
(_) => fetchAssessments(),
);
}

@override
void dispose() {
refreshTimer?.cancel();
super.dispose();
}

// ============================================================
// FETCH ASSESSMENTS FROM PYTHON API
// ============================================================

Future<void> fetchAssessments() async {

try {
final activeUrl = await getActiveBaseUrl();

final response = await http
    .get(
Uri.parse('$activeUrl/assessments'),
)
    .timeout(const Duration(seconds: 10));

if (response.statusCode != 200) {
throw Exception('Server error: ${response.statusCode}');
}

final result = jsonDecode(response.body);

if (result['success'] != true) {
throw Exception('Unable to retrieve assessments.');
}

final List records = result['assessments'] ?? [];

final loadedAssessments = records
    .map((item) => Map<String, dynamic>.from(item))
    .where((item) =>
item['latitude'] is num &&
item['longitude'] is num)
    .toList();

if (!mounted) return;

setState(() {
assessments = loadedAssessments;
isLoading = false;
errorMessage = null;
});

} catch (e) {

if (!mounted) return;

setState(() {
isLoading = false;
errorMessage = e.toString();
});

}
}

// ============================================================
// DAMAGE COLOUR
// ============================================================

Color getDamageColor(Map<String, dynamic> data) {

final status =
(data['analysis_status'] ?? 'pending_ai_model')
    .toString()
    .toLowerCase();

// AI has not analysed this assessment yet.
if (status != 'completed' &&
status != 'complete' &&
status != 'success') {
return grey;
}

final level =
(data['damageLevel'] ?? '').toString().toUpperCase();

final severity =
(data['severity'] ?? '').toString().toUpperCase();

if ([
'FULL_DAMAGE',
'DESTROYED',
'SEVERE',
'HIGH',
'CRITICAL',
].any((value) =>
level.contains(value) || severity == value)) {
return red;
}

if ([
'PARTIAL_DAMAGE',
'MODERATE',
'MEDIUM',
].any((value) =>
level.contains(value) || severity == value)) {
return orange;
}

if ([
'MINOR_DAMAGE',
'MINOR',
'LOW',
].any((value) =>
level.contains(value) || severity == value)) {
return yellow;
}

if ([
'UNDAMAGED',
'NO_DAMAGE',
'NO VISIBLE DAMAGE',
].any((value) =>
level.contains(value) || severity == value)) {
return green;
}

return grey;
}

String getDamageLabel(Map<String, dynamic> data) {

final status =
(data['analysis_status'] ?? 'pending_ai_model')
    .toString()
    .toLowerCase();

if (status != 'completed' &&
status != 'complete' &&
status != 'success') {
return 'Pending AI Analysis';
}

final level =
(data['damageLevel'] ?? '').toString().toUpperCase();

final severity =
(data['severity'] ?? '').toString().toUpperCase();

if (level.contains('FULL') ||
level.contains('DESTROYED') ||
severity == 'HIGH' ||
severity == 'SEVERE' ||
severity == 'CRITICAL') {
return 'Severe Damage';
}

if (level.contains('PARTIAL') ||
severity == 'MODERATE' ||
severity == 'MEDIUM') {
return 'Moderate Damage';
}

if (level.contains('MINOR') ||
severity == 'MINOR' ||
severity == 'LOW') {
return 'Minor Damage';
}

if (level.contains('UNDAMAGED') ||
level.contains('NO_DAMAGE') ||
level.contains('NO VISIBLE DAMAGE')) {
return 'No Visible Damage';
}

return 'Classification Unavailable';
}

// ============================================================
// BUILD MAP MARKER
// ============================================================

Widget buildMarker(Color color) {

return Container(
width: 42,
height: 42,
alignment: Alignment.center,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: color.withOpacity(0.20),
),
child: Container(
width: 13,
height: 13,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: color.withOpacity(0.6),
blurRadius: 8,
spreadRadius: 2,
),
],
),
),
);
}

// ============================================================
// SHOW DAMAGE DETAILS
// ============================================================

void showDamageDetails(Map<String, dynamic> data) {

final color = getDamageColor(data);

final label = getDamageLabel(data);

final latitude =
(data['latitude'] as num).toDouble();

final longitude =
(data['longitude'] as num).toDouble();

final imagePath =
(data['imageUrl'] ?? '').toString();

final imageUrl = imagePath.startsWith('http')
? imagePath
    : '$baseUrl$imagePath';

final details =
(data['details'] ?? 'No additional details available.')
    .toString();

final priority =
(data['inspectionPriority'] ?? 'Not assigned')
    .toString();

showModalBottomSheet(
context: context,
backgroundColor: const Color(0xFF191214),
isScrollControlled: true,
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(
top: Radius.circular(22),
),
),
builder: (context) {

return SafeArea(
child: Padding(
padding: const EdgeInsets.all(20),
child: SingleChildScrollView(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [

Center(
child: Container(
width: 42,
height: 4,
decoration: BoxDecoration(
color: Colors.white30,
borderRadius: BorderRadius.circular(10),
),
),
),

const SizedBox(height: 20),

Row(
children: [

Container(
width: 13,
height: 13,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
),
),

const SizedBox(width: 10),

Expanded(
child: Text(
label,
style: const TextStyle(
color: Colors.white,
fontSize: 18,
fontWeight: FontWeight.bold,
),
),
),
],
),

const SizedBox(height: 18),

if (imagePath.isNotEmpty)
ClipRRect(
borderRadius: BorderRadius.circular(14),
child: Image.network(
imageUrl,
height: 190,
width: double.infinity,
fit: BoxFit.cover,
errorBuilder: (_, __, ___) {
return const SizedBox(
height: 100,
child: Center(
child: Text(
'Image unavailable',
style: TextStyle(
color: Colors.white70,
),
),
),
);
},
),
),

const SizedBox(height: 18),

Text(
'Assessment: $label',
style: TextStyle(
color: color,
fontWeight: FontWeight.bold,
),
),

const SizedBox(height: 12),

Text(
'GPS: ${latitude.toStringAsFixed(6)}, '
'${longitude.toStringAsFixed(6)}',
style: const TextStyle(
color: Colors.white70,
fontSize: 13,
),
),

const SizedBox(height: 12),

Text(
'Inspection Priority: $priority',
style: const TextStyle(
color: Colors.white70,
),
),

const SizedBox(height: 12),

Text(
details,
style: const TextStyle(
color: Colors.white,
height: 1.5,
),
),

const SizedBox(height: 20),

SizedBox(
width: double.infinity,
child: ElevatedButton(
onPressed: () => Navigator.pop(context),
style: ElevatedButton.styleFrom(
backgroundColor: color,
foregroundColor: Colors.black,
),
child: const Text('Close'),
),
),
],
),
),
),
);
},
);
}

// ============================================================
// MAP LEGEND
// ============================================================

Widget legendItem(Color color, String label) {

return Row(
mainAxisSize: MainAxisSize.min,
children: [

Container(
width: 12,
height: 12,
decoration: BoxDecoration(
color: color,
shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: color.withOpacity(0.5),
blurRadius: 5,
spreadRadius: 2,
),
],
),
),

const SizedBox(width: 10),

Text(
label,
style: const TextStyle(
color: Colors.white,
fontSize: 11,
fontWeight: FontWeight.bold,
),
),
],
);
}

Widget buildLegend() {

return Positioned(
left: 16,
bottom: 24,
child: Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.85),
borderRadius: BorderRadius.circular(10),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [

legendItem(red, 'SEVERE'),

const SizedBox(height: 9),

legendItem(orange, 'MODERATE'),

const SizedBox(height: 9),

legendItem(yellow, 'MINOR'),

const SizedBox(height: 9),

legendItem(green, 'NO VISIBLE DAMAGE'),

const SizedBox(height: 9),

legendItem(grey, 'PENDING ANALYSIS'),
],
),
),
);
}

// ============================================================
// BUILD MAP
// ============================================================

@override
Widget build(BuildContext context) {

final markers = <Marker>[];

for (final data in assessments) {

final latitude =
(data['latitude'] as num).toDouble();

final longitude =
(data['longitude'] as num).toDouble();

if (latitude < -90 ||
latitude > 90 ||
longitude < -180 ||
longitude > 180) {
continue;
}

final color = getDamageColor(data);

markers.add(
Marker(
point: LatLng(latitude, longitude),
width: 42,
height: 42,
child: GestureDetector(
onTap: () => showDamageDetails(data),
child: buildMarker(color),
),
),
);
}

return Scaffold(
body: Stack(
children: [

// MAP
FlutterMap(
  options: MapOptions(
    initialCenter: widget.initialCenter ?? const LatLng(15.3173, 75.7139),
    initialZoom: 7,
    minZoom: 5,
    maxZoom: 19,
  ),
children: [

TileLayer(
urlTemplate:
'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
userAgentPackageName:
'com.floodwatch.floodguard',
maxZoom: 19,
),

MarkerLayer(
markers: markers,
),
],
),

// MAP TITLE
Positioned(
top: MediaQuery.of(context).padding.top + 12,
left: 16,
right: 16,
child: Center(
child: Container(
padding: const EdgeInsets.symmetric(
horizontal: 16,
vertical: 10,
),
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.85),
borderRadius: BorderRadius.circular(10),
),
child: const Text(
'DISASTER DAMAGE MAP',
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold,
fontSize: 13,
letterSpacing: 1,
),
),
),
),
),

// REFRESH BUTTON
Positioned(
top: MediaQuery.of(context).padding.top + 65,
right: 16,
child: FloatingActionButton.small(
heroTag: 'damage_map_refresh',
backgroundColor: Colors.black87,
foregroundColor: Colors.white,
onPressed: () {
fetchAssessments();
},
child: const Icon(Icons.refresh),
),
),

// LEGEND
buildLegend(),

// LOADING
if (isLoading)
const Center(
child: CircularProgressIndicator(),
),

// ERROR
if (errorMessage != null)
Positioned(
top: MediaQuery.of(context).padding.top + 110,
left: 20,
right: 20,
child: Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: Colors.black87,
borderRadius: BorderRadius.circular(10),
),
child: Text(
'Unable to load assessments.\n$errorMessage',
style: const TextStyle(
color: Colors.redAccent,
fontSize: 12,
),
),
),
),

// EMPTY STATE
if (!isLoading &&
errorMessage == null &&
assessments.isEmpty)
Positioned(
top: MediaQuery.of(context).padding.top + 110,
left: 20,
right: 20,
child: Center(
child: Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: Colors.black87,
borderRadius: BorderRadius.circular(10),
),
child: const Text(
'No damage assessments uploaded yet.',
style: TextStyle(
color: Colors.white70,
fontSize: 12,
),
),
),
),
),
],
),
);
}
}

