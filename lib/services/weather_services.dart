import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;


class HourlyWeatherForecast {
  final DateTime time;
  final double rainfall;
  final double precipitationProbability;
  final int weatherCode;

  const HourlyWeatherForecast({
    required this.time,
    required this.rainfall,
    required this.precipitationProbability,
    required this.weatherCode,
  });
}

class WeatherData {
  final double rainfall;
  final double precipitationProbability;
  final int weatherCode;
  final List<HourlyWeatherForecast> hourlyForecasts;

  const WeatherData({
    required this.rainfall,
    required this.precipitationProbability,
    required this.weatherCode,
    this.hourlyForecasts = const [],
  });

  bool get isHeavyRain =>
      rainfall >= 10 || precipitationProbability >= 70;

  bool get isExtremeWeather =>
      weatherCode == 95 ||
          weatherCode == 96 ||
          weatherCode == 99;
}



class WeatherService {
  // Prevent repeated requests from hitting Open-Meteo too quickly.
  DateTime? _lastWeatherRequest;
  WeatherData? _cachedWeather;

  DateTime? _lastRainfallRequest;
  RecentRainfall? _cachedRainfall;


  Future<WeatherData> getWeather({
    required double latitude,
    required double longitude,
  }) async {
    if (_cachedWeather != null &&
        _lastWeatherRequest != null &&
        DateTime.now().difference(_lastWeatherRequest!) <
            const Duration(seconds: 60)) {
      return _cachedWeather!;
    }

    final uri = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'current': 'precipitation,weather_code',
        'hourly':
        'precipitation_probability,precipitation,weather_code',
        'forecast_days': '2',
        'timezone': 'auto',
      },
    );

    final response = await _getWithRetry(uri);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final hourly = data['hourly'] as Map<String, dynamic>;

    final currentRainfall =
        (current['precipitation'] as num?)?.toDouble() ?? 0.0;

    final currentWeatherCode =
        (current['weather_code'] as num?)?.toInt() ?? 0;

    final times = hourly['time'] as List<dynamic>? ?? [];
    final rainfallValues =
        hourly['precipitation'] as List<dynamic>? ?? [];
    final probabilities =
        hourly['precipitation_probability'] as List<dynamic>? ?? [];
    final weatherCodes =
        hourly['weather_code'] as List<dynamic>? ?? [];

    final forecasts = <HourlyWeatherForecast>[];

    for (var i = 0; i < times.length; i++) {
      forecasts.add(
        HourlyWeatherForecast(
          time: DateTime.parse(times[i].toString()),
          rainfall: i < rainfallValues.length
              ? (rainfallValues[i] as num?)?.toDouble() ?? 0.0
              : 0.0,
          precipitationProbability: i < probabilities.length
              ? (probabilities[i] as num?)?.toDouble() ?? 0.0
              : 0.0,
          weatherCode: i < weatherCodes.length
              ? (weatherCodes[i] as num?)?.toInt() ?? 0
              : 0,
        ),
      );
    }

    final now = DateTime.now();
    final next24Hours = forecasts.where((forecast) {
      return !forecast.time.isBefore(now) &&
          !forecast.time.isAfter(now.add(const Duration(hours: 24)));
    }).toList();

    double maxRainfall = currentRainfall;
    double maxProbability = 0.0;

    for (final forecast in next24Hours) {
      if (forecast.rainfall > maxRainfall) {
        maxRainfall = forecast.rainfall;
      }
      if (forecast.precipitationProbability > maxProbability) {
        maxProbability = forecast.precipitationProbability;
      }
    }

    final result = WeatherData(
      rainfall: maxRainfall,
      precipitationProbability: maxProbability,
      weatherCode: currentWeatherCode,
      hourlyForecasts: forecasts,
    );

    _cachedWeather = result;
    _lastWeatherRequest = DateTime.now();

    return result;
  }



  /// Gets recent rainfall totals for the previous
  /// 24, 72 and 168 hours.
  ///
  /// These values are sent to the existing FloodWatch
  /// AI backend.
  Future<RecentRainfall> getRecentRainfall({
    required double latitude,
    required double longitude,
  }) async {
    // Don't repeatedly call Open-Meteo.
    //
    // The AI prediction does not need a new weather request
    // every time the Flutter widget rebuilds.
    if (_cachedRainfall != null &&
        _lastRainfallRequest != null &&
        DateTime.now().difference(_lastRainfallRequest!) <
            const Duration(minutes: 5)) {
      return _cachedRainfall!;
    }

    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
          '?latitude=$latitude'
          '&longitude=$longitude'
          '&hourly=rain'
          '&past_days=7'
          '&forecast_days=0'
          '&timezone=auto',
    );

    final response = await _getWithRetry(uri);

    final data =
    jsonDecode(response.body)
    as Map<String, dynamic>;

    final hourly =
    data['hourly'] as Map<String, dynamic>;

    final values =
    (hourly['rain'] as List<dynamic>? ?? [])
        .map(
          (v) =>
      (v as num?)?.toDouble() ?? 0.0,
    )
        .toList();

    final times =
    (hourly['time'] as List<dynamic>? ?? [])
        .map(
          (v) => DateTime.parse(v.toString()),
    )
        .toList();

    final now = DateTime.now();

    double sumSince(Duration duration) {
      final cutoff = now.subtract(duration);

      double total = 0.0;

      for (
      var i = 0;
      i < values.length && i < times.length;
      i++
      ) {
        final time = times[i];

        if (!time.isAfter(now) &&
            !time.isBefore(cutoff)) {
          total += values[i];
        }
      }

      return total;
    }

    final result = RecentRainfall(
      rainfall1day:
      sumSince(const Duration(hours: 24)),
      rainfall3day:
      sumSince(const Duration(hours: 72)),
      rainfall7day:
      sumSince(const Duration(hours: 168)),
    );

    _cachedRainfall = result;
    _lastRainfallRequest = DateTime.now();

    return result;
  }

  /// Handles Open-Meteo temporary 429 responses.
  ///
  /// We wait before retrying instead of immediately sending
  /// another request.
  Future<http.Response> _getWithRetry(
      Uri uri,
      ) async {
    const maxAttempts = 3;

    for (var attempt = 1;
    attempt <= maxAttempts;
    attempt++) {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return response;
      }

      if (response.statusCode == 429 &&
          attempt < maxAttempts) {
        final waitSeconds = attempt * 5;

        print(
          'Open-Meteo rate limit (429). '
              'Waiting $waitSeconds seconds...',
        );

        await Future.delayed(
          Duration(seconds: waitSeconds),
        );

        continue;
      }

      throw Exception(
        'Weather request failed: '
            '${response.statusCode}',
      );
    }

    throw Exception(
      'Weather request failed after retries.',
    );
  }
}

class RecentRainfall {
  final double rainfall1day;
  final double rainfall3day;
  final double rainfall7day;

  const RecentRainfall({
    required this.rainfall1day,
    required this.rainfall3day,
    required this.rainfall7day,
  });
}