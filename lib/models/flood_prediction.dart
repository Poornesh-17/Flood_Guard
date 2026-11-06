class FloodPrediction {
  final String risk;
  final double probability;
  final double waterLevel;
  final double dangerLevel;
  final double rainfall;
  final String rainfallTrend;

  // Values returned by FastAPI
  final int riskIndex;
  final String riskColor;

  const FloodPrediction({
    required this.risk,
    required this.probability,
    required this.waterLevel,
    required this.dangerLevel,
    required this.rainfall,
    required this.rainfallTrend,
    required this.riskIndex,
    required this.riskColor,
  });

  factory FloodPrediction.fromJson(
      Map<String, dynamic> json,
      ) {
    return FloodPrediction(
      // Backend returns:
      // "risk_level": "LOW/MODERATE/HIGH"
      risk: (json['risk_level'] ?? 'LOW')
          .toString()
          .toUpperCase(),

      // Backend returns 0.4037
      // Convert to 40.37 for the UI
      probability:
      ((json['probability'] ?? 0) as num).toDouble() * 100,

      // Not currently returned by your /predict endpoint
      waterLevel:
      ((json['waterLevel'] ?? 0) as num).toDouble(),

      dangerLevel:
      ((json['dangerLevel'] ?? 0) as num).toDouble(),

      rainfall:
      ((json['rainfall'] ?? 0) as num).toDouble(),

      rainfallTrend:
      (json['rainfallTrend'] ?? 'Stable').toString(),

      // Backend returns:
      // "risk_index": 40
      riskIndex:
      ((json['risk_index'] ?? 0) as num).toInt(),

      // Backend returns:
      // "risk_color": "orange"
      riskColor:
      (json['risk_color'] ?? '').toString().toLowerCase(),
    );
  }
}