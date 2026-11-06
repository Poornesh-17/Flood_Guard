class FloodRiskCell {
  final double latitude;
  final double longitude;
  final double latitude2;
  final double longitude2;
  final double probability;
  final String risk;

  const FloodRiskCell({
    required this.latitude,
    required this.longitude,
    required this.latitude2,
    required this.longitude2,
    required this.probability,
    required this.risk,
  });

  factory FloodRiskCell.fromJson(Map<String, dynamic> json) {
    final latitude = _toDouble(json['latitude']);
    final longitude = _toDouble(json['longitude']);

    final latitude2 = _toDouble(
      json['latitude2'] ?? json['lat2'] ?? json['latitude_max'],
    );

    final longitude2 = _toDouble(
      json['longitude2'] ?? json['lon2'] ?? json['longitude_max'],
    );

    final probability = _toDouble(
      json['probability'] ??
          json['risk_index'] ??
          json['riskIndex'] ??
          json['score'],
    );

    String risk = (
        json['risk'] ??
            json['risk_level'] ??
            json['riskLevel'] ??
            json['level'] ??
            ''
    ).toString().toUpperCase();

    if (risk.isEmpty) {
      if (probability >= 70) {
        risk = 'HIGH';
      } else if (probability >= 40) {
        risk = 'MODERATE';
      } else {
        risk = 'LOW';
      }
    }

    return FloodRiskCell(
      latitude: latitude,
      longitude: longitude,
      latitude2: latitude2,
      longitude2: longitude2,
      probability: probability,
      risk: risk,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0.0;
  }
}