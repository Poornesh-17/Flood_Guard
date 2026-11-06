import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/flood_risk_cell.dart';

class FloodMapService {
  static const String assetPath =
      'assets/karnataka_flood_risk_grid.json';

  // ------------------------------------------------------------
  // Load the complete flood-risk grid
  // ------------------------------------------------------------
  static Future<List<FloodRiskCell>> loadRiskGrid() async {
    final jsonString = await rootBundle.loadString(assetPath);

    final decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid Karnataka flood-risk JSON.');
    }

    final cells = decoded['cells'];

    if (cells is! List) {
      throw Exception(
        'Karnataka flood-risk JSON does not contain a cells list.',
      );
    }

    return cells
        .map(
          (cell) => FloodRiskCell.fromJson(
        Map<String, dynamic>.from(cell as Map),
      ),
    )
        .toList();
  }

  // ------------------------------------------------------------
  // Instance version
  // ------------------------------------------------------------
  Future<List<FloodRiskCell>> loadFloodRiskGrid() async {
    return loadRiskGrid();
  }

  // ------------------------------------------------------------
  // Keep only valid Karnataka grid cells
  // ------------------------------------------------------------
  static List<FloodRiskCell> getKarnatakaCells(
      List<FloodRiskCell> cells,
      ) {
    return cells.where((cell) {
      return cell.latitude >= 11.5 &&
          cell.latitude <= 18.5 &&
          cell.longitude >= 74.0 &&
          cell.longitude <= 78.7;
    }).toList();
  }
}