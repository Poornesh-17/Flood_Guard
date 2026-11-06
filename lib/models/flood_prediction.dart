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
    final rawProb = json['probability'] ?? json['prob'] ?? json['risk_index'] ?? json['riskIndex'];
    double prob = 0.0;
    if (rawProb is num) {
      prob = rawProb.toDouble();
    } else if (rawProb != null) {
      prob = double.tryParse(rawProb.toString()) ?? 0.0;
    }

    if (prob <= 1.0 && prob > 0) {
      prob *= 100;
    }

    if (prob < 5.0) {
      prob = 5.0;
    }

    final rawRiskIndex = json['risk_index'] ?? json['riskIndex'];
    int rIndex;
    if (rawRiskIndex is num) {
      rIndex = rawRiskIndex.round();
      if (rIndex <= 1 && prob > 1) {
        rIndex = prob.round();
      }
    } else {
      rIndex = prob.round();
    }

    if (rIndex < 5) {
      rIndex = 5;
    }

    return FloodPrediction(
      risk: (json['risk_level'] ?? json['risk'] ?? 'LOW')
          .toString()
          .toUpperCase(),
      probability: prob,
      waterLevel: ((json['waterLevel'] ?? 0) as num).toDouble(),
      dangerLevel: ((json['dangerLevel'] ?? 0) as num).toDouble(),
      rainfall: ((json['rainfall'] ?? 0) as num).toDouble(),
      rainfallTrend: (json['rainfallTrend'] ?? 'Stable').toString(),
      riskIndex: rIndex,
      riskColor: (json['risk_color'] ?? json['riskColor'] ?? 'green')
          .toString()
          .toLowerCase(),
    );
  }
}