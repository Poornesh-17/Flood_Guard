import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/resource_allocation_service.dart';

class ResourceAllocationScreen extends StatefulWidget {
  const ResourceAllocationScreen({super.key});

  @override
  State<ResourceAllocationScreen> createState() => _ResourceAllocationScreenState();
}

class _ResourceAllocationScreenState extends State<ResourceAllocationScreen> {
  static const Color background = Color(0xFF0B0708);
  static const Color card = Color(0xFF181113);
  static const Color cardBorder = Color(0xFF342629);
  static const Color red = Color(0xFFEF5350);
  static const Color orange = Color(0xFFFFB74D);
  static const Color green = Color(0xFFA3E2A4);
  static const Color muted = Color(0xFFAAAAAA);

  final ResourceAllocationService _service = ResourceAllocationService.instance;
  final MapController _mapController = MapController();

  List<AffectedLocation> _locations = [];
  AvailableResources _availableResources = AvailableResources();
  AllocationSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _service.loadAllocationData();
    _locations = data['locations'] as List<AffectedLocation>;
    _availableResources = data['available_resources'] as AvailableResources;
    _recalculate();
    setState(() => _isLoading = false);
  }

  void _recalculate() {
    _summary = _service.calculateSummary(
      locations: _locations,
      availableResources: _availableResources,
    );
  }

  Future<void> _saveData() async {
    await _service.saveAllocationData(
      locations: _locations,
      availableResources: _availableResources,
    );
  }

  void _showEditResourcesDialog() {
    final boatsCtrl = TextEditingController(text: _availableResources.boats.toString());
    final foodCtrl = TextEditingController(text: _availableResources.foodPacks.toString());
    final medCtrl = TextEditingController(text: _availableResources.medicalKits.toString());
    final tentsCtrl = TextEditingController(text: _availableResources.tents.toString());
    final teamsCtrl = TextEditingController(text: _availableResources.rescueTeams.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: red),
            SizedBox(width: 10),
            Text('Emergency Available Resources', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Emergency teams can enter total available rescue inventory to calculate shortages.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _buildField('Rescue Boats', boatsCtrl, Icons.sailing),
              _buildField('Food & Water Packs', foodCtrl, Icons.fastfood_outlined),
              _buildField('Medical Kits', medCtrl, Icons.medical_services_outlined),
              _buildField('Shelter Tents', tentsCtrl, Icons.holiday_village_outlined),
              _buildField('Rescue Personnel Teams', teamsCtrl, Icons.groups_outlined),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                _availableResources.boats = int.tryParse(boatsCtrl.text) ?? _availableResources.boats;
                _availableResources.foodPacks = int.tryParse(foodCtrl.text) ?? _availableResources.foodPacks;
                _availableResources.medicalKits = int.tryParse(medCtrl.text) ?? _availableResources.medicalKits;
                _availableResources.tents = int.tryParse(tentsCtrl.text) ?? _availableResources.tents;
                _availableResources.rescueTeams = int.tryParse(teamsCtrl.text) ?? _availableResources.rescueTeams;
                _recalculate();
              });
              await _saveData();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('SAVE RESOURCES'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: red, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: muted, fontSize: 13),
          filled: true,
          fillColor: background,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: red),
          ),
        ),
      ),
    );
  }

  void _showDispatchDialog(LocationAllocationResult res) {
    final boatsCtrl = TextEditingController(text: res.location.allocatedBoats.toString());
    final foodCtrl = TextEditingController(text: res.location.allocatedFoodPacks.toString());
    final medCtrl = TextEditingController(text: res.location.allocatedMedicalKits.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Dispatch to ${res.location.name}', style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Required Boats: ${res.requirements.boats} | Shortage: ${res.shortage.boats}',
                  style: const TextStyle(color: orange, fontSize: 12)),
              const SizedBox(height: 12),
              _buildField('Allocated Boats', boatsCtrl, Icons.sailing),
              _buildField('Allocated Food Packs', foodCtrl, Icons.fastfood_outlined),
              _buildField('Allocated Medical Kits', medCtrl, Icons.medical_services_outlined),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: red, foregroundColor: Colors.white),
            onPressed: () async {
              setState(() {
                res.location.allocatedBoats = int.tryParse(boatsCtrl.text) ?? res.location.allocatedBoats;
                res.location.allocatedFoodPacks = int.tryParse(foodCtrl.text) ?? res.location.allocatedFoodPacks;
                res.location.allocatedMedicalKits = int.tryParse(medCtrl.text) ?? res.location.allocatedMedicalKits;
                _recalculate();
              });
              await _saveData();
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Resource dispatch updated for ${res.location.name}')),
                );
              }
            },
            child: const Text('CONFIRM ALLOCATION'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _summary == null) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(child: CircularProgressIndicator(color: red)),
      );
    }

    final sum = _summary!;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('AI Resource Allocation', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Enter Emergency Resources',
            icon: const Icon(Icons.edit_note, color: red),
            onPressed: _showEditResourcesDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI INSIGHT BANNER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF230D10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: red.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, color: red, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AI PRIORITIZATION ENGINE',
                            style: TextStyle(color: red, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text(sum.aiInsights, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // OVERVIEW STAT CARDS
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatCard('AFFECTED LOCATIONS', '${sum.totalLocations}', Icons.location_on_outlined, red),
                _buildStatCard('TOTAL POPULATION', '${sum.totalAffectedPopulation}', Icons.people_outline, orange),
                _buildStatCard('BOAT SHORTAGE', '${sum.totalShortages.boats}', Icons.sailing, red),
                _buildStatCard('FOOD SHORTAGE', '${sum.totalShortages.foodPacks}', Icons.fastfood_outlined, orange),
              ],
            ),

            const SizedBox(height: 20),

            // AVAILABLE INVENTORY BAR
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Available Resource Inventory',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      InkWell(
                        onTap: _showEditResourcesDialog,
                        child: const Text('EDIT RESOURCES',
                            style: TextStyle(color: red, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _inventoryBadge('Rescue Boats', '${_availableResources.boats}', Icons.sailing),
                      _inventoryBadge('Food Packs', '${_availableResources.foodPacks}', Icons.fastfood_outlined),
                      _inventoryBadge('Medical Kits', '${_availableResources.medicalKits}', Icons.medical_services_outlined),
                      _inventoryBadge('Tents', '${_availableResources.tents}', Icons.holiday_village_outlined),
                      _inventoryBadge('Teams', '${_availableResources.rescueTeams}', Icons.groups_outlined),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // MAP VIEW
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(15.3173, 75.7139),
                    initialZoom: 6.8,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.floodwatch.floodguard',
                    ),
                    MarkerLayer(
                      markers: sum.rankedLocations.map((res) {
                        final color = res.location.riskLevel == 'HIGH'
                            ? red
                            : (res.location.riskLevel == 'MODERATE' ? orange : green);
                        return Marker(
                          point: LatLng(res.location.latitude, res.location.longitude),
                          width: 40,
                          height: 40,
                          child: GestureDetector(
                            onTap: () => _showDispatchDialog(res),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text('#${res.aiRank}',
                                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text('AI Priority Ranked Allocation List',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Ranked by flood risk level, affected population scale, and resource shortages.',
                style: TextStyle(color: muted, fontSize: 12)),

            const SizedBox(height: 14),

            // RANKED LIST
            ...sum.rankedLocations.map((res) => _buildLocationCard(res)),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: (MediaQuery.of(context).size.width - 44) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 9, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryBadge(String title, String val, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: red, size: 16),
        const SizedBox(width: 5),
        Text('$title: ', style: const TextStyle(color: muted, fontSize: 12)),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildLocationCard(LocationAllocationResult res) {
    final loc = res.location;
    final req = res.requirements;
    final short = res.shortage;

    final riskColor = loc.riskLevel == 'HIGH' ? red : (loc.riskLevel == 'MODERATE' ? orange : green);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: res.aiRank == 1 ? red.withOpacity(0.8) : cardBorder, width: res.aiRank == 1 ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: res.aiRank == 1 ? red : cardBorder,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('#${res.aiRank} PRIORITY',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(loc.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(loc.riskLevel,
                    style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text('Status: ${loc.status} · Inundation: ${loc.inundationDepthM} m',
              style: const TextStyle(color: muted, fontSize: 12)),

          const SizedBox(height: 12),

          // SHORTAGE METRICS
          Row(
            children: [
              _shortageBox('Affected Pop', '${loc.affectedPopulation}', Icons.people_outline, Colors.white),
              const SizedBox(width: 8),
              _shortageBox('Boats Shortage', '${short.boats} / ${req.boats}', Icons.sailing, short.boats > 0 ? red : green),
              const SizedBox(width: 8),
              _shortageBox('Food Shortage', '${short.foodPacks} / ${req.foodPacks}', Icons.fastfood_outlined, short.foodPacks > 0 ? orange : green),
            ],
          ),

          const SizedBox(height: 12),

          // AI RECOMMENDATION RATIONALE
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: red, size: 16),
                    const SizedBox(width: 6),
                    Text('AI Score: ${res.priorityScore} / 100',
                        style: const TextStyle(color: red, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(res.aiRecommendation, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showDispatchDialog(res),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: const Text('DISPATCH RESOURCES TO LOCATION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortageBox(String title, String val, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: muted, fontSize: 9)),
            const SizedBox(height: 2),
            Text(val, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
