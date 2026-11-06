import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class AffectedLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String riskLevel; // HIGH, MODERATE, LOW
  final int affectedPopulation;
  final double inundationDepthM;
  final String status;
  int allocatedBoats;
  int allocatedFoodPacks;
  int allocatedMedicalKits;
  int allocatedTents;
  int allocatedTeams;

  AffectedLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.riskLevel,
    required this.affectedPopulation,
    required this.inundationDepthM,
    required this.status,
    this.allocatedBoats = 0,
    this.allocatedFoodPacks = 0,
    this.allocatedMedicalKits = 0,
    this.allocatedTents = 0,
    this.allocatedTeams = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'risk_level': riskLevel,
        'affected_population': affectedPopulation,
        'inundation_depth_m': inundationDepthM,
        'status': status,
        'allocated_boats': allocatedBoats,
        'allocated_food_packs': allocatedFoodPacks,
        'allocated_medical_kits': allocatedMedicalKits,
        'allocated_tents': allocatedTents,
        'allocated_teams': allocatedTeams,
      };

  factory AffectedLocation.fromJson(Map<String, dynamic> json) {
    return AffectedLocation(
      id: json['id']?.toString() ?? 'loc_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name']?.toString() ?? 'Unknown Location',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 15.3173,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 75.7139,
      riskLevel: json['risk_level']?.toString().toUpperCase() ?? 'MODERATE',
      affectedPopulation: (json['affected_population'] as num?)?.toInt() ?? 1000,
      inundationDepthM: (json['inundation_depth_m'] as num?)?.toDouble() ?? 1.0,
      status: json['status']?.toString() ?? 'Active Flood Watch',
      allocatedBoats: (json['allocated_boats'] as num?)?.toInt() ?? 0,
      allocatedFoodPacks: (json['allocated_food_packs'] as num?)?.toInt() ?? 0,
      allocatedMedicalKits: (json['allocated_medical_kits'] as num?)?.toInt() ?? 0,
      allocatedTents: (json['allocated_tents'] as num?)?.toInt() ?? 0,
      allocatedTeams: (json['allocated_teams'] as num?)?.toInt() ?? 0,
    );
  }
}

class AvailableResources {
  int boats;
  int foodPacks;
  int medicalKits;
  int tents;
  int rescueTeams;

  AvailableResources({
    this.boats = 45,
    this.foodPacks = 40000,
    this.medicalKits = 500,
    this.tents = 2500,
    this.rescueTeams = 35,
  });

  Map<String, dynamic> toJson() => {
        'boats': boats,
        'food_packs': foodPacks,
        'medical_kits': medicalKits,
        'tents': tents,
        'rescue_teams': rescueTeams,
      };

  factory AvailableResources.fromJson(Map<String, dynamic> json) {
    return AvailableResources(
      boats: (json['boats'] as num?)?.toInt() ?? 45,
      foodPacks: (json['food_packs'] as num?)?.toInt() ?? 40000,
      medicalKits: (json['medical_kits'] as num?)?.toInt() ?? 500,
      tents: (json['tents'] as num?)?.toInt() ?? 2500,
      rescueTeams: (json['rescue_teams'] as num?)?.toInt() ?? 35,
    );
  }
}

class ResourceRequirement {
  final int boats;
  final int foodPacks;
  final int medicalKits;
  final int tents;
  final int rescueTeams;

  const ResourceRequirement({
    required this.boats,
    required this.foodPacks,
    required this.medicalKits,
    required this.tents,
    required this.rescueTeams,
  });
}

class ResourceShortage {
  final int boats;
  final int foodPacks;
  final int medicalKits;
  final int tents;
  final int rescueTeams;

  const ResourceShortage({
    required this.boats,
    required this.foodPacks,
    required this.medicalKits,
    required this.tents,
    required this.rescueTeams,
  });
}

class LocationAllocationResult {
  final AffectedLocation location;
  final ResourceRequirement requirements;
  final ResourceShortage shortage;
  final double priorityScore;
  final int aiRank;
  final String aiRecommendation;

  LocationAllocationResult({
    required this.location,
    required this.requirements,
    required this.shortage,
    required this.priorityScore,
    required this.aiRank,
    required this.aiRecommendation,
  });
}

class AllocationSummary {
  final int totalLocations;
  final int totalAffectedPopulation;
  final AvailableResources availableResources;
  final ResourceShortage totalShortages;
  final String topPriorityLocation;
  final List<LocationAllocationResult> rankedLocations;
  final String aiInsights;

  AllocationSummary({
    required this.totalLocations,
    required this.totalAffectedPopulation,
    required this.availableResources,
    required this.totalShortages,
    required this.topPriorityLocation,
    required this.rankedLocations,
    required this.aiInsights,
  });
}

class ResourceAllocationService {
  static final ResourceAllocationService instance = ResourceAllocationService._();
  ResourceAllocationService._();

  static const String _storageKey = 'floodguard_resource_allocation_data_v1';

  // Default initial locations in Karnataka
  static final List<AffectedLocation> defaultLocations = [
    AffectedLocation(
      id: 'loc_belagavi',
      name: 'Belagavi District (Krishna Basin)',
      latitude: 15.8497,
      longitude: 74.4977,
      riskLevel: 'HIGH',
      affectedPopulation: 18500,
      inundationDepthM: 2.4,
      status: 'Critical Flood Inundation',
      allocatedBoats: 15,
      allocatedFoodPacks: 14000,
      allocatedMedicalKits: 180,
      allocatedTents: 900,
      allocatedTeams: 10,
    ),
    AffectedLocation(
      id: 'loc_bagalkot',
      name: 'Bagalkot (Ghataprabha Basin)',
      latitude: 16.1853,
      longitude: 75.6961,
      riskLevel: 'HIGH',
      affectedPopulation: 12400,
      inundationDepthM: 1.9,
      status: 'Severe Submersion',
      allocatedBoats: 10,
      allocatedFoodPacks: 9500,
      allocatedMedicalKits: 120,
      allocatedTents: 600,
      allocatedTeams: 7,
    ),
    AffectedLocation(
      id: 'loc_uttara_kannada',
      name: 'Karwar & Uttara Kannada',
      latitude: 14.8153,
      longitude: 74.1302,
      riskLevel: 'HIGH',
      affectedPopulation: 9800,
      inundationDepthM: 1.6,
      status: 'Coastal Flash Floods',
      allocatedBoats: 8,
      allocatedFoodPacks: 7000,
      allocatedMedicalKits: 90,
      allocatedTents: 450,
      allocatedTeams: 5,
    ),
    AffectedLocation(
      id: 'loc_raichur',
      name: 'Raichur (Tungabhadra Overflow)',
      latitude: 16.2076,
      longitude: 77.3463,
      riskLevel: 'MODERATE',
      affectedPopulation: 7200,
      inundationDepthM: 1.1,
      status: 'River Water Overspill',
      allocatedBoats: 5,
      allocatedFoodPacks: 5500,
      allocatedMedicalKits: 70,
      allocatedTents: 350,
      allocatedTeams: 4,
    ),
    AffectedLocation(
      id: 'loc_dharwad',
      name: 'Dharwad Rural Zone',
      latitude: 15.4589,
      longitude: 75.0078,
      riskLevel: 'MODERATE',
      affectedPopulation: 4500,
      inundationDepthM: 0.8,
      status: 'Heavy Rain Waterlogging',
      allocatedBoats: 3,
      allocatedFoodPacks: 3800,
      allocatedMedicalKits: 45,
      allocatedTents: 220,
      allocatedTeams: 2,
    ),
    AffectedLocation(
      id: 'loc_kodagu',
      name: 'Madikeri / Kodagu Valley',
      latitude: 12.4244,
      longitude: 75.7382,
      riskLevel: 'LOW',
      affectedPopulation: 2100,
      inundationDepthM: 0.4,
      status: 'Monsoon Alert Watch',
      allocatedBoats: 2,
      allocatedFoodPacks: 2200,
      allocatedMedicalKits: 30,
      allocatedTents: 120,
      allocatedTeams: 1,
    ),
  ];

  static AvailableResources defaultAvailableResources = AvailableResources(
    boats: 45,
    foodPacks: 45000,
    medicalKits: 550,
    tents: 2800,
    rescueTeams: 32,
  );

  // Load locations and available resources from local cache / state
  Future<Map<String, dynamic>> loadAllocationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        final locList = (data['locations'] as List<dynamic>?)
                ?.map((e) => AffectedLocation.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            defaultLocations;
        final avail = data['available_resources'] != null
            ? AvailableResources.fromJson(Map<String, dynamic>.from(data['available_resources'] as Map))
            : defaultAvailableResources;
        return {
          'locations': locList,
          'available_resources': avail,
        };
      }
    } catch (e) {
      debugPrint('Load allocation data error: $e');
    }
    return {
      'locations': defaultLocations,
      'available_resources': defaultAvailableResources,
    };
  }

  // Save locations and available resources
  Future<void> saveAllocationData({
    required List<AffectedLocation> locations,
    required AvailableResources availableResources,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'locations': locations.map((e) => e.toJson()).toList(),
        'available_resources': availableResources.toJson(),
      };
      await prefs.setString(_storageKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Save allocation data error: $e');
    }
  }

  // Calculate local requirements
  ResourceRequirement calculateRequirement(AffectedLocation loc) {
    final riskMult = loc.riskLevel == 'HIGH' ? 1.3 : (loc.riskLevel == 'MODERATE' ? 1.1 : 1.0);
    final pop = loc.affectedPopulation;

    final reqBoats = ((pop / 120.0) * riskMult).round();
    final reqFood = (pop * 2);
    final reqMedical = ((pop / 40.0) * riskMult).round();
    final reqTents = ((pop / 8.0) * riskMult).round();
    final reqTeams = ((pop / 300.0) * riskMult).round();

    return ResourceRequirement(
      boats: reqBoats < 1 ? 1 : reqBoats,
      foodPacks: reqFood < 100 ? 100 : reqFood,
      medicalKits: reqMedical < 10 ? 10 : reqMedical,
      tents: reqTents < 20 ? 20 : reqTents,
      rescueTeams: reqTeams < 1 ? 1 : reqTeams,
    );
  }

  // Generate full AI Allocation Summary
  AllocationSummary calculateSummary({
    required List<AffectedLocation> locations,
    required AvailableResources availableResources,
  }) {
    final List<LocationAllocationResult> list = [];
    int totalPop = 0;

    int totalShortBoats = 0;
    int totalShortFood = 0;
    int totalShortMed = 0;
    int totalShortTents = 0;
    int totalShortTeams = 0;

    for (final loc in locations) {
      totalPop += loc.affectedPopulation;
      final req = calculateRequirement(loc);

      final shortBoats = (req.boats - loc.allocatedBoats).clamp(0, 999999);
      final shortFood = (req.foodPacks - loc.allocatedFoodPacks).clamp(0, 999999);
      final shortMed = (req.medicalKits - loc.allocatedMedicalKits).clamp(0, 999999);
      final shortTents = (req.tents - loc.allocatedTents).clamp(0, 999999);
      final shortTeams = (req.rescueTeams - loc.allocatedTeams).clamp(0, 999999);

      totalShortBoats += shortBoats;
      totalShortFood += shortFood;
      totalShortMed += shortMed;
      totalShortTents += shortTents;
      totalShortTeams += shortTeams;

      // Calculate AI Priority Score (0 - 100)
      final riskScore = loc.riskLevel == 'HIGH' ? 40.0 : (loc.riskLevel == 'MODERATE' ? 25.0 : 10.0);
      final popScore = ((loc.affectedPopulation / 20000.0) * 35.0).clamp(0.0, 35.0);
      
      final boatRatio = (shortBoats / req.boats).clamp(0.0, 1.0);
      final foodRatio = (shortFood / req.foodPacks).clamp(0.0, 1.0);
      final medRatio = (shortMed / req.medicalKits).clamp(0.0, 1.0);
      final shortageRatio = (boatRatio + foodRatio + medRatio) / 3.0;
      final shortageScore = (shortageRatio * 25.0).clamp(0.0, 25.0);

      final priorityScore = (riskScore + popScore + shortageScore).roundToDouble();

      String aiRec;
      if (priorityScore >= 75.0) {
        aiRec = 'URGENT AI RECOMMENDATION: Priority 1 target for emergency dispatch. Heavy shortage of rescue boats (${shortBoats} missing) & food packs for ${loc.affectedPopulation} affected people.';
      } else if (priorityScore >= 50.0) {
        aiRec = 'HIGH AI RECOMMENDATION: Secondary priority. Deploy additional food packs (${shortFood} deficit) and medical supplies.';
      } else {
        aiRec = 'STANDARD AI RECOMMENDATION: Maintain current supply line. Monitor flood water levels.';
      }

      list.add(LocationAllocationResult(
        location: loc,
        requirements: req,
        shortage: ResourceShortage(
          boats: shortBoats,
          foodPacks: shortFood,
          medicalKits: shortMed,
          tents: shortTents,
          rescueTeams: shortTeams,
        ),
        priorityScore: priorityScore,
        aiRank: 0,
        aiRecommendation: aiRec,
      ));
    }

    // Rank descending by priorityScore
    list.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));

    final List<LocationAllocationResult> rankedList = [];
    for (int i = 0; i < list.length; i++) {
      final item = list[i];
      rankedList.add(LocationAllocationResult(
        location: item.location,
        requirements: item.requirements,
        shortage: item.shortage,
        priorityScore: item.priorityScore,
        aiRank: i + 1,
        aiRecommendation: item.aiRecommendation,
      ));
    }

    final topLoc = rankedList.isNotEmpty ? rankedList.first.location.name : 'None';
    final insights = rankedList.isNotEmpty
        ? 'AI Decision Engine evaluated ${rankedList.length} flood-affected locations. "$topLoc" is ranked #1 Priority for immediate resource allocation.'
        : 'No affected locations identified.';

    return AllocationSummary(
      totalLocations: rankedList.length,
      totalAffectedPopulation: totalPop,
      availableResources: availableResources,
      totalShortages: ResourceShortage(
        boats: totalShortBoats,
        foodPacks: totalShortFood,
        medicalKits: totalShortMed,
        tents: totalShortTents,
        rescueTeams: totalShortTeams,
      ),
      topPriorityLocation: topLoc,
      rankedLocations: rankedList,
      aiInsights: insights,
    );
  }
}
