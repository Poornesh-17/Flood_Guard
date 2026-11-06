import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FloodPrediction {
  final String risk;
  final double probability;
  final int riskIndex;
  final String riskColor;
  final Map<String, dynamic> raw;

  const FloodPrediction({
    required this.risk,
    required this.probability,
    required this.riskIndex,
    required this.riskColor,
    required this.raw,
  });

  factory FloodPrediction.fromJson(Map<String, dynamic> data) {
    debugPrint('========== PARSING FLOOD RESPONSE ==========');
    debugPrint('RAW RESPONSE: $data');

    final rawProbability = data['probability'];

    double probability = 0.0;

    if (rawProbability is num) {
      probability = rawProbability.toDouble();
    } else if (rawProbability != null) {
      probability = double.tryParse(
        rawProbability.toString(),
      ) ??
          0.0;
    }

    // Backend gives 0.4037.
    // UI needs 40.37.
    if (probability <= 1.0) {
      probability *= 100.0;
    }

    probability = probability.clamp(0.0, 100.0);

    final risk =
    (data['risk_level'] ?? data['risk'] ?? 'LOW')
        .toString()
        .toUpperCase();

    int riskIndex;

    final rawRiskIndex = data['risk_index'];

    if (rawRiskIndex is num) {
      riskIndex = rawRiskIndex.round();
    } else {
      riskIndex = probability.round();
    }

    riskIndex = riskIndex.clamp(0, 100);

    String riskColor =
    (data['risk_color'] ?? '').toString().toLowerCase();

    if (riskColor.isEmpty) {
      switch (risk) {
        case 'HIGH':
          riskColor = 'red';
          break;
        case 'MODERATE':
        case 'MEDIUM':
          riskColor = 'orange';
          break;
        default:
          riskColor = 'green';
          break;
      }
    }

    debugPrint('PARSED PROBABILITY: $probability%');
    debugPrint('PARSED RISK INDEX: $riskIndex');
    debugPrint('PARSED RISK: $risk');
    debugPrint('PARSED COLOR: $riskColor');
    debugPrint('============================================');

    return FloodPrediction(
      risk: risk,
      probability: probability,
      riskIndex: riskIndex,
      riskColor: riskColor,
      raw: data,
    );
  }
}

class FloodApiService {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';

    // Android emulator
    return 'http://192.168.1.3:8000';
  }
  Future<List<Map<String, dynamic>>> getMapRisk(
      List<Map<String, dynamic>> locations,
      ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/map-risk'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'locations': locations,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Map risk API failed: ${response.statusCode}\n${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    if (data['success'] != true) {
      throw Exception('Map risk API returned an unsuccessful response.');
    }

    return List<Map<String, dynamic>>.from(
      data['locations'] ?? [],
    );
  }

  Future<FloodPrediction> predict({
    required double latitude,
    required double longitude,
    required double rainfall1day,
    required double rainfall3day,
    required double rainfall7day,
    required double groundElevation,
    required double riverDistance,
  }) async {
    final body = {
      'latitude': latitude,
      'longitude': longitude,
      'rainfall_1day': rainfall1day.clamp(0, double.infinity),
      'rainfall_3day': rainfall3day.clamp(0, double.infinity),
      'rainfall_7day': rainfall7day.clamp(0, double.infinity),
      'ground_elevation_m': groundElevation,
      'river_distance_km': riverDistance.clamp(0, double.infinity),
    };

    debugPrint('========== FLOOD API REQUEST ==========');
    debugPrint('URL: $baseUrl/predict');
    debugPrint('BODY: ${jsonEncode(body)}');

    final response = await http
        .post(
      Uri.parse('$baseUrl/predict'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    )
        .timeout(const Duration(seconds: 3));

    debugPrint('========== FLOOD API RESPONSE ==========');
    debugPrint('STATUS: ${response.statusCode}');
    debugPrint('BODY: ${response.body}');

    if (response.statusCode != 200) {
      throw Exception(
        'Flood API ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid flood API response.');
    }

    final prediction = FloodPrediction.fromJson(decoded);

    debugPrint('========== FLOOD PREDICTION ==========');
    debugPrint('Risk: ${prediction.risk}');
    debugPrint('Probability: ${prediction.probability}');
    debugPrint('Risk index: ${prediction.riskIndex}');
    debugPrint('Risk color: ${prediction.riskColor}');

    return prediction;
  }
}