import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  static const String keyLanguage = 'user_preferred_language';

  // ValueNotifier to trigger app-wide UI rebuilds when language changes
  static final ValueNotifier<String> languageNotifier = ValueNotifier<String>('English');

  static String get currentLanguage => languageNotifier.value;

  static bool get isKannada => languageNotifier.value == 'ಕನ್ನಡ';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString(keyLanguage);
      if (savedLang != null && (savedLang == 'English' || savedLang == 'ಕನ್ನಡ')) {
        languageNotifier.value = savedLang;
      }
    } catch (e) {
      debugPrint('AppLanguage init error: $e');
    }
  }

  static Future<void> setLanguage(String lang) async {
    if (lang != 'English' && lang != 'ಕನ್ನಡ') return;
    languageNotifier.value = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyLanguage, lang);
    } catch (e) {
      debugPrint('AppLanguage setLanguage error: $e');
    }
  }

  static String tr(String key) {
    final isKn = isKannada;
    final String? translation = isKn ? _kannada[key] : _english[key];
    return translation ?? _english[key] ?? key;
  }

  // ============================================================
  // TRANSLATIONS DICTIONARY
  // ============================================================

  static const Map<String, String> _english = {
    // Navigation & Main Header
    'app_name': 'FloodGuard',
    'alert_tab': 'Alert',
    'weather_tab': 'Weather',
    'safety_tab': 'Safety',
    'getting_gps': 'Getting GPS...',
    'my_profile': 'My Profile',

    // Risk Card & AI
    'ai_flood_detection': 'AI FLOOD DETECTION',
    'risk_index': 'RISK INDEX',
    'low': 'LOW',
    'moderate': 'MODERATE',
    'high': 'HIGH',
    'low_risk_msg': 'Low flood risk detected near you',
    'mod_risk_msg': 'Moderate flood risk detected near you',
    'high_risk_msg': 'High flood risk detected near you',
    'analyzing_risk': 'Analyzing flood risk...',
    'rain_next_24h': 'Rain next 24h',
    'rain_3day': '3-day rainfall',
    'rain_7day': '7-day rainfall',
    'ground_humidity': 'Ground humidity',
    'terrain_elevation': 'Terrain elevation',

    // Emergency SOS
    'emergency_sos': 'EMERGENCY SOS',
    'send_sos': 'Send SOS to family',
    'flood_control_room': 'Flood control room',
    'disaster_helpline': 'Disaster helpline',
    'police': 'Police',
    'copy_alert_msg': 'Copy alert message with my location',
    'family_contacts': 'FAMILY CONTACTS',
    'no_family_added': 'No family members added.',

    // Safe Ground & Navigation
    'nearest_safe_ground': 'NEAREST SAFE GROUND',
    'navigate_safe_zone': 'Navigate to safe zone',
    'find_safe_places': 'FIND NEARBY SAFE PLACES',
    'searching_safe_places': 'SEARCHING...',
    'safest_route': 'Safest route',
    'route_found_msg': 'Walking route to the nearest mapped safe place.',
    'offline_map_msg': 'Offline map • Internet unavailable',

    // Weather Screen
    'right_now': 'RIGHT NOW',
    'feels_like': 'FEELS LIKE',
    'precipitation': 'PRECIPITATION',
    'humidity': 'HUMIDITY',
    'wind': 'WIND',
    'hour_by_hour': 'HOUR BY HOUR · NEXT 24H',
    'seven_day_outlook': '7-DAY OUTLOOK',
    'now': 'NOW',

    // Survival Rules
    'survival_rules': 'SURVIVAL RULES',
    'rule_1': 'Never walk or drive through moving water — 15 cm can knock you down.',
    'rule_2': 'Avoid fallen power lines and submerged electrical points.',
    'rule_3': 'Do not drink flood water; boil or purify everything.',
    'rule_4': 'Move upward, not outward, if water rises fast — avoid closed attics.',

    // Profile & Settings
    'registration_details': 'REGISTRATION DETAILS',
    'mobile_number': 'Mobile number',
    'preferred_language': 'Preferred language',
    'gender': 'Gender',
    'state': 'State',
    'emergency_family': 'EMERGENCY FAMILY MEMBERS',
    'add_family': 'ADD FAMILY MEMBERS',
    'manage_family': 'MANAGE FAMILY MEMBERS',
    'alert_settings': 'ALERT SETTINGS',
    'flood_alerts': 'Flood risk alerts',
    'flood_alerts_sub': 'Receive flood warning notifications',
    'weather_alerts': 'Weather alerts',
    'weather_alerts_sub': 'Weather and rainfall updates',
    'help_support': 'HELP & SUPPORT',
    'help': 'Help',
    'how_to_use': 'How to use FloodGuard',
    'about_app': 'About FloodGuard',
    'app_info': 'App information and version',
    'sign_out': 'Sign out',
    'sign_out_sub': 'Sign out of this account',
    'edit_profile': 'Edit profile',
    'save': 'Save',
    'cancel': 'Cancel',
    'full_name': 'Full name',

    // Weather conditions
    'clear_sky': 'Clear sky',
    'cloudy': 'Cloudy',
    'foggy': 'Foggy',
    'drizzle': 'Drizzle',
    'rain': 'Rain',
    'rain_showers': 'Rain showers',
    'thunderstorm': 'Thunderstorm',

    // Map & Legends
    'your_location': 'Your location',
    'safe_places': 'Safe places',
    'flood_risk_map': 'Flood Risk Map',
    'high_ground': 'high ground',

    // Place Types
    'hospital': 'Hospital',
    'school': 'School',
    'emergency_shelter': 'Emergency Shelter',
    'community_centre': 'Community Centre',
    'fire_station': 'Fire Station',
    'police_station': 'Police Station',
    'safe_place': 'Safe Place',

    // Escape & Route Screen
    'turn_by_turn': 'Turn-by-turn',
    'press_find_safe_places': 'Press "FIND NEARBY SAFE PLACES" to calculate your route.',
    'start_gps': 'Start from your current GPS location.',
    'follow_blue_route': 'Follow the blue walking route.',
    'continue_safe_place': 'Continue toward the nearest safe place.',
    'arrive_destination': 'Arrive at the safe place.',
    'nearby_shelters': 'Nearby shelters',
    'no_safe_places': 'No safe places loaded yet.',
    'start': 'Start',
    'continue': 'Continue',
    'destination': 'Destination',
    'passable_area': 'Your area is passable',
    'follow_safest_route': 'Follow the safest available route.',
    'no_flood_warning': 'No active flood warning detected.',
    'flood_risk_detected': 'Flood risk detected',
    'route_risk_acceptable': 'Route risk is acceptable',
    'route_has_risk': 'Route has flood risk',
    'high_risk_areas': 'High risk areas',
    'medium_risk_areas': 'Medium risk areas',
    'low_risk_areas': 'Low risk areas',
  };

  static const Map<String, String> _kannada = {
    // Navigation & Main Header
    'app_name': 'ಫ್ಲಡ್ ಗಾರ್ಡ್',
    'alert_tab': 'ಎಚ್ಚರಿಕೆ',
    'weather_tab': 'ಹವಾಮಾನ',
    'safety_tab': 'ಸುರಕ್ಷತೆ',
    'getting_gps': 'ಜಿಪಿಎಸ್ ಪಡೆಯಲಾಗುತ್ತಿದೆ...',
    'my_profile': 'ನನ್ನ ಪ್ರೊಫೈಲ್',

    // Risk Card & AI
    'ai_flood_detection': 'ಎಐ ಪ್ರವಾಹ ಪತ್ತೆ',
    'risk_index': 'ಅಪಾಯದ ಸೂಚ್ಯಂಕ',
    'low': 'ಕಡಿಮೆ',
    'moderate': 'ಮಧ್ಯಮ',
    'high': 'ಹೆಚ್ಚು',
    'low_risk_msg': 'ನಿಮ್ಮ ಹತ್ತಿರ ಕಡಿಮೆ ಪ್ರವಾಹ ಅಪಾಯ ಪತ್ತೆಯಾಗಿದೆ',
    'mod_risk_msg': 'ನಿಮ್ಮ ಹತ್ತಿರ ಮಧ್ಯಮ ಪ್ರವಾಹ ಅಪಾಯ ಪತ್ತೆಯಾಗಿದೆ',
    'high_risk_msg': 'ನಿಮ್ಮ ಹತ್ತಿರ ಹೆಚ್ಚಿನ ಪ್ರವಾಹ ಅಪಾಯ ಪತ್ತೆಯಾಗಿದೆ',
    'analyzing_risk': 'ಪ್ರವಾಹದ ಅಪಾಯವನ್ನು ವಿಶ್ಲೇಷಿಸಲಾಗುತ್ತಿದೆ...',
    'rain_next_24h': 'ಮುಂದಿನ 24 ಗಂಟೆಗಳ ಮಳೆ',
    'rain_3day': '3 ದಿನಗಳ ಮಳೆ',
    'rain_7day': '7 ದಿನಗಳ ಮಳೆ',
    'ground_humidity': 'ನೆಲದ ತೇವಾಂಶ',
    'terrain_elevation': 'ಭೂಪ್ರದೇಶದ ಎತ್ತರ',

    // Emergency SOS
    'emergency_sos': 'ತುರ್ತು ಎಸ್.ಒ.ಎಸ್',
    'send_sos': 'ಕುಟುಂಬಕ್ಕೆ ತುರ್ತು ಸಂದೇಶ ಕಳುಹಿಸಿ',
    'flood_control_room': 'ಪ್ರವಾಹ ನಿಯಂತ್ರಣ ಕೊಠಡಿ',
    'disaster_helpline': 'ವಿಪತ್ತು ಸಹಾಯವಾಣಿ',
    'police': 'ಪೋಲೀಸ್',
    'copy_alert_msg': 'ನನ್ನ ಸ್ಥಳದೊಂದಿಗೆ ಎಚ್ಚರಿಕೆ ಸಂದೇಶ ನಕಲಿಸಿ',
    'family_contacts': 'ಕುಟುಂಬದ ಸಂಪರ್ಕಗಳು',
    'no_family_added': 'ಯಾವುದೇ ಕುಟುಂಬ ಸದಸ್ಯರನ್ನು ಸೇರಿಸಲಾಗಿಲ್ಲ.',

    // Safe Ground & Navigation
    'nearest_safe_ground': 'ಹತ್ತಿರದ ಸುರಕ್ಷಿತ ಸ್ಥಳ',
    'navigate_safe_zone': 'ಸುರಕ್ಷಿತ ವಲಯಕ್ಕೆ ಸಾಗಿ',
    'find_safe_places': 'ಹತ್ತಿರದ ಸುರಕ್ಷಿತ ಸ್ಥಳಗಳನ್ನು ಹುಡುಕಿ',
    'searching_safe_places': 'ಹುಡುಕಲಾಗುತ್ತಿದೆ...',
    'safest_route': 'ಅತ್ಯಂತ ಸುರಕ್ಷಿತ ಮಾರ್ಗ',
    'route_found_msg': 'ಹತ್ತಿರದ ಸುರಕ್ಷಿತ ಸ್ಥಳಕ್ಕೆ ಕಾಲ್ನಡಿಗೆ ಮಾರ್ಗ.',
    'offline_map_msg': 'ಆಫ್‌ಲೈನ್ ನಕ್ಷೆ • ಇಂಟರ್ನೆಟ್ ಲಭ್ಯವಿಲ್ಲ',

    // Weather Screen
    'right_now': 'ಈಗಿನ ಹವಾಮಾನ',
    'feels_like': 'ಅನಿಸುವ ತಾಪಮಾನ',
    'precipitation': 'ಮಳೆಯ ಮುನ್ಸೂಚನೆ',
    'humidity': 'ತೇವಾಂಶ',
    'wind': 'ಗಾಳಿಯ ವೇಗ',
    'hour_by_hour': 'ಗಂಟೆಯಿಡೀ · ಮುಂದಿನ 24 ಗಂಟೆ',
    'seven_day_outlook': '7 ದಿನಗಳ ಹವಾಮಾನ ಮುನ್ಸೂಚನೆ',
    'now': 'ಈಗ',

    // Survival Rules
    'survival_rules': 'ಬದುಕುಳಿಯುವ ನಿಯಮಗಳು',
    'rule_1': 'ಹರಿಯುವ ನೀರಿನಲ್ಲಿ ನಡೆಯಬೇಡಿ ಅಥವಾ ಚಾಲನೆ ಮಾಡಬೇಡಿ — 15 ಸೆಂ.ಮೀ ನೀರು ನಿಮ್ಮನ್ನು ಕೆಳಗೆ ಉರುಳಿಸಬಹುದು.',
    'rule_2': 'ಬಿದ್ದ ವಿದ್ಯುತ್ ತಂತಿಗಳು ಮತ್ತು ನೀರಿನಲ್ಲಿ ಮುಳುಗಿರುವ ವಿದ್ಯುತ್ ಪಾಯಿಂಟ್‌ಗಳಿಂದ ದೂರವಿರಿ.',
    'rule_3': 'ಪ್ರವಾಹದ ನೀರನ್ನು ಕುಡಿಯಬೇಡಿ; ಎಲ್ಲವನ್ನೂ ಕುದಿಸಿ ಅಥವಾ ಶುದ್ಧೀಕರಿಸಿ.',
    'rule_4': 'ನೀರು ವೇಗವಾಗಿ ಹೆಚ್ಚಾದರೆ ಮೇಲಕ್ಕೆ ಸಾಗಿ — ಮುಚ್ಚಿದ ಕೊಟ್ಟಡಿಗಳನ್ನು தவிர்க்கಿ.',

    // Profile & Settings
    'registration_details': 'ನೋಂದಣಿ ವಿವರಗಳು',
    'mobile_number': 'ಮೊಬೈಲ್ ಸಂಖ್ಯೆ',
    'preferred_language': 'ಆದ್ಯತೆಯ ಭಾಷೆ',
    'gender': 'ಲಿಂಗ',
    'state': 'ರಾಜ್ಯ',
    'emergency_family': 'ತುರ್ತು ಕುಟುಂಬ ಸದಸ್ಯರು',
    'add_family': 'ಕುಟುಂಬದ ಸದಸ್ಯರನ್ನು ಸೇರಿಸಿ',
    'manage_family': 'ಕುಟುಂಬ ನಿರ್ವಹಣೆ',
    'alert_settings': 'ಎಚ್ಚರಿಕೆ ಸಂರಚನೆಗಳು',
    'flood_alerts': 'ಪ್ರವಾಹ ಅಪಾಯದ ಎಚ್ಚರಿಕೆಗಳು',
    'flood_alerts_sub': 'ಪ್ರವಾಹ ಮುನ್ನೆಚ್ಚರಿಕೆ ಸೂಚನೆಗಳನ್ನು ಪಡೆಯಿರಿ',
    'weather_alerts': 'ಹವಾಮಾನ ಎಚ್ಚರಿಕೆಗಳು',
    'weather_alerts_sub': 'ಹವಾಮಾನ ಮತ್ತು ಮಳೆಯ ನವೀಕರಣಗಳು',
    'help_support': 'ಸಹಾಯ ಮತ್ತು ಬೆಂಬಲ',
    'help': 'ಸಹಾಯ',
    'how_to_use': 'ಫ್ಲಡ್ ಗಾರ್ಡ್ ಹೇಗೆ ಬಳಸುವುದು',
    'about_app': 'ಫ್ಲಡ್ ಗಾರ್ಡ್ ಬಗ್ಗೆ',
    'app_info': 'ಅಪ್ಲಿಕೇಶನ್ ಮಾಹಿತಿ ಮತ್ತು ಆವೃತ್ತಿ',
    'account': 'ಖಾತೆ',
    'sign_out': 'ಸೈನ್ ಔಟ್',
    'sign_out_sub': 'ಈ ಖಾತೆಯಿಂದ ಸೈನ್ ಔಟ್ ಮಾಡಿ',
    'edit_profile': 'ಪ್ರೊಫೈಲ್ ಸಂಪಾದಿಸಿ',
    'save': 'ಉಳಿಸಿ',
    'cancel': 'ರದ್ದುಮಾಡಿ',
    'full_name': 'ಪೂರ್ಣ ಹೆಸರು',

    // Weather conditions
    'clear_sky': 'ನಿರ್ಮಲ ಆಕಾಶ',
    'cloudy': 'ಮೋಡ ಕವಿದ ವಾತಾವರಣ',
    'foggy': 'ಮಂಜು ಮುಸುಕಿದ',
    'drizzle': 'ಸಣ್ಣ ಮಳೆ',
    'rain': 'ಮಳೆ',
    'rain_showers': 'ಮಳೆಯ ಸಿಂಚನ',
    'thunderstorm': 'ಸಿಡಿಲು ಸಹಿತ ಮಳೆ',

    // Map & Legends
    'your_location': 'ನಿಮ್ಮ ಸ್ಥಳ',
    'safe_places': 'ಸುರಕ್ಷಿತ ಸ್ಥಳಗಳು',
    'flood_risk_map': 'ಪ್ರವಾಹ ಅಪಾಯದ ನಕ್ಷೆ',
    'high_ground': 'ಎತ್ತರದ ಪ್ರದೇಶ',

    // Place Types
    'hospital': 'ಆಸ್ಪತ್ರೆ',
    'school': 'ಶಾಲೆ',
    'emergency_shelter': 'ತುರ್ತು ಆಶ್ರಯ ತಾಣ',
    'community_centre': 'ಸಮುದಾಯ ಭವನ',
    'fire_station': 'ಅಗ್ನಿಶಾಮಕ ಠಾಣೆ',
    'police_station': 'ಪೋಲೀಸ್ ಠಾಣೆ',
    'safe_place': 'ಸುರಕ್ಷಿತ ಸ್ಥಳ',

    // Escape & Route Screen
    'turn_by_turn': 'ಹಂತ ಹಂತದ ದಾರಿ ಮುನ್ನೋಟ',
    'press_find_safe_places': 'ಮಾರ್ಗವನ್ನು ಲೆಕ್ಕಹಾಕಲು "ಹತ್ತಿರದ ಸುರಕ್ಷಿತ ಸ್ಥಳಗಳನ್ನು ಹುಡುಕಿ" ಒತ್ತಿರಿ.',
    'start_gps': 'ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ಸ್ಥಳದಿಂದ ಪ್ರಾರಂಭಿಸಿ.',
    'follow_blue_route': 'ನೀಲಿ ಬಣ್ಣದ ಕಾಲ್ನಡಿಗೆ ಮಾರ್ಗವನ್ನು ಅನುಸರಿಸಿ.',
    'continue_safe_place': 'ಹತ್ತಿರದ ಸುರಕ್ಷಿತ ಸ್ಥಳದ ಕಡೆಗೆ ಮುಂದುವರಿಯಿರಿ.',
    'arrive_destination': 'ಸುರಕ್ಷಿತ ಸ್ಥಳವನ್ನು ತಲುಪಿ.',
    'nearby_shelters': 'ಹತ್ತಿರದ ಆಶ್ರಯ ತಾಣಗಳು',
    'no_safe_places': 'ಇನ್ನೂ ಯಾವುದೇ ಸುರಕ್ಷಿತ ಸ್ಥಳಗಳು ಲೋಡ್ ಆಗಿಲ್ಲ.',
    'start': 'ಪ್ರಾರಂಭ',
    'continue': 'ಮುಂದುವರಿಯಿರಿ',
    'destination': 'ತಲುಪುವ ಸ್ಥಳ',
    'passable_area': 'ನಿಮ್ಮ ಪ್ರದೇಶ ಸಂಚಾರಕ್ಕೆ ಸೂಕ್ತವಾಗಿದೆ',
    'follow_safest_route': 'ಲಭ್ಯವಿರುವ ಅತ್ಯಂತ ಸುರಕ್ಷಿತ ಮಾರ್ಗವನ್ನು ಅನುಸರಿಸಿ.',
    'no_flood_warning': 'ಯಾವುದೇ ಸಕ್ರಿಯ ಪ್ರವಾಹ ಮುನ್ನೆಚ್ಚರಿಕೆ ಕಂಡುಬಂದಿಲ್ಲ.',
    'flood_risk_detected': 'ಪ್ರವಾಹ ಅಪಾಯ ಪತ್ತೆಯಾಗಿದೆ',
    'route_risk_acceptable': 'ಮಾರ್ಗದ ಅಪಾಯವು ಸ್ವೀಕಾರಾರ್ಹವಾಗಿದೆ',
    'route_has_risk': 'ಮಾರ್ಗದಲ್ಲಿ ಪ್ರವಾಹದ ಅಪಾಯವಿದೆ',
    'high_risk_areas': 'ಹೆಚ್ಚಿನ ಅಪಾಯದ ಪ್ರದೇಶಗಳು',
    'medium_risk_areas': 'ಮಧ್ಯಮ ಅಪಾಯದ ಪ್ರದೇಶಗಳು',
    'low_risk_areas': 'ಕಡಿಮೆ ಅಪಾಯದ ಪ್ರದೇಶಗಳು',
  };
}
