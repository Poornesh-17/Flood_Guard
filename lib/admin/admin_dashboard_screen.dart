import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/flood_risk_cell.dart';
import '../services/flood_api_service.dart';
import '../services/flood_map_service.dart';

// If this file is directly inside lib/, change the imports above to:
// import 'models/flood_risk_cell.dart';
// import 'services/flood_api_service.dart';
// import 'services/flood_map_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const Color bg = Color(0xFF101214);
  static const Color panel = Color(0xFF191C20);
  static const Color panel2 = Color(0xFF22262B);
  static const Color accent = Color(0xFFE53935);
  static const Color muted = Color(0xFF9CA3AF);

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FloodApiService floodApi = FloodApiService();
  final MapController _mapController = MapController();

  int selectedPage = 0;
  bool adminReady = false;
  String? adminError;

  bool _loadingGrid = false;
  String? _gridError;
  List<FloodRiskCell> _gridCells = [];
  Map<String, Map<String, dynamic>> _gridRisk = {};
  int _gridCompleted = 0;
  int _gridTotal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializeAdminDashboard();
    });
  }

  Future<void> initializeAdminDashboard() async {
    try {
      final user = auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => adminError = 'No authenticated Firebase user.');
        return;
      }

      final email = user.email?.trim().toLowerCase();

      // Keep this check aligned with your existing admin account.
      if (email != 'admin@gmail.com') {
        if (!mounted) return;
        setState(() {
          adminError = 'This account is not an admin account.';
        });
        return;
      }

      await user.getIdToken(true);

      if (!mounted) return;
      setState(() {
        adminReady = true;
        adminError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => adminError = 'Admin initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!adminReady) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: adminError == null
              ? const CircularProgressIndicator(color: accent)
              : Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              adminError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildPage()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 225,
      color: const Color(0xFF151719),
      child: Column(
        children: [
          const SizedBox(height: 26),
          const Icon(Icons.flood, color: accent, size: 42),
          const SizedBox(height: 9),
          const Text(
            'FLOODGUARD',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'ADMIN PANEL',
            style: TextStyle(color: muted, fontSize: 10, letterSpacing: 2),
          ),
          const SizedBox(height: 34),
          _menuItem(0, Icons.dashboard_outlined, 'Dashboard'),
          _menuItem(1, Icons.people_outline, 'Users'),
          _menuItem(2, Icons.map_outlined, 'Live User Map'),
          _menuItem(3, Icons.grid_view_rounded, 'Flood Risk'),
          _menuItem(4, Icons.sos_outlined, 'SOS Alerts'),
          const Spacer(),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.logout, color: muted),
            title: const Text('Logout', style: TextStyle(color: muted)),
            onTap: _logout,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _menuItem(int index, IconData icon, String title) {
    final selected = selectedPage == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? accent.withOpacity(.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected
            ? Border.all(color: accent.withOpacity(.25))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          size: 21,
          color: selected ? accent : muted,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: selected ? Colors.white : muted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onTap: () {
          setState(() => selectedPage = index);
          if (index == 3 && _gridCells.isEmpty) {
            _loadFloodGrid();
          }
        },
      ),
    );
  }

  Widget _buildPage() {
    switch (selectedPage) {
      case 1:
        return _buildUsersPage();
      case 2:
        return _buildUserMapPage();
      case 3:
        return _buildFloodRiskPage();
      case 4:
        return _buildSosPage();
      default:
        return _buildDashboardPage();
    }
  }

  Widget _pageShell(String title, Widget child, {Widget? action}) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (action != null) action,
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 17,
                backgroundColor: accent,
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Administrator',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildDashboardPage() {
    return _pageShell(
      'Dashboard',
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('Could not load users: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: accent));
          }

          final docs = snapshot.data!.docs;
          final high = docs.where((d) => _riskOf(d.data()) == 'HIGH').length;
          final moderate =
              docs.where((d) => _riskOf(d.data()) == 'MODERATE').length;
          final low = docs.where((d) => _riskOf(d.data()) == 'LOW').length;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _statCard('TOTAL USERS', '${docs.length}',
                        Icons.people_alt_outlined, Colors.blue),
                    _statCard('HIGH RISK', '$high',
                        Icons.warning_amber_rounded, Colors.red),
                    _statCard('MODERATE RISK', '$moderate',
                        Icons.error_outline, Colors.orange),
                    _statCard('LOW RISK', '$low',
                        Icons.check_circle_outline, Colors.green),
                  ],
                ),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 850;
                    final map = _panel(
                      'USER LOCATIONS',
                      SizedBox(height: 390, child: _usersMap(compact: true)),
                    );
                    final recent = _panel(
                      'RECENT USERS',
                      _recentUsers(docs),
                    );

                    if (narrow) {
                      return Column(
                        children: [
                          map,
                          const SizedBox(height: 18),
                          recent,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: map),
                        const SizedBox(width: 18),
                        Expanded(child: recent),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: color.withOpacity(.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: muted, fontSize: 10)),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 15),
          child,
        ],
      ),
    );
  }

  Widget _recentUsers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(15),
        child: Text('No users found', style: TextStyle(color: muted)),
      );
    }

    final recent = docs.reversed.take(6).toList();

    return Column(
      children: recent.map((doc) {
        final data = doc.data();
        final name = _text(data['name'], 'Unknown User');
        final risk = _riskOf(data);

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: _riskColor(risk),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _text(data['email'], _text(data['phoneNumber'], 'No contact info')),
            style: const TextStyle(color: muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _riskBadge(risk),
          onTap: () => _showUserInfo(doc.id, data),
        );
      }).toList(),
    );
  }

  Widget _buildUsersPage() {
    return _pageShell(
      'All Users',
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _message('Users error: ${snapshot.error}');
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: accent));
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _message('No users found.');

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _userCard(doc.id, doc.data());
            },
          );
        },
      ),
    );
  }

  Widget _userCard(String uid, Map<String, dynamic> data) {
    final location = _getUserLocation(data);
    final risk = _riskOf(data);
    final floodRisk = _mapOf(data['floodRisk']);
    final probability = _number(
      floodRisk['probability'] ?? data['probability'],
    );
    final probabilityPercent =
    probability == null ? null : (probability <= 1 ? probability * 100 : probability);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _riskColor(risk),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(data['name'], 'Unknown User'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _text(data['email'], 'No email'),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _riskBadge(risk),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit user',
                onPressed: () => _showEditUserDialog(uid, data),
                icon: const Icon(Icons.edit_outlined, color: accent),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 28),
          Wrap(
            spacing: 25,
            runSpacing: 13,
            children: [
              _adminInfo('Phone', data['phoneNumber']),
              _adminInfo('Login Type', data['loginType']),
              _adminInfo('Status', data['status']),
              _adminInfo('UID', uid),
              _adminInfo('Probability',
                  probabilityPercent == null ? null : '${probabilityPercent.toStringAsFixed(2)}%'),
              _adminInfo('Risk Index',
                  floodRisk['risk_index'] ?? floodRisk['riskIndex'] ??
                      data['risk_index'] ?? data['riskIndex']),
              _adminInfo('Elevation',
                  data['groundElevation'] ?? data['ground_elevation_m']),
              _adminInfo('River Distance',
                  data['riverDistance'] ?? data['river_distance_km']),
              _adminInfo('Latitude', location?.latitude),
              _adminInfo('Longitude', location?.longitude),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showUserInfo(uid, data),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('VIEW COMPLETE DATA'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminInfo(String title, dynamic value) {
    return SizedBox(
      width: 185,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: muted, fontSize: 10)),
          const SizedBox(height: 4),
          Text(
            _displayValue(value),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(
      String uid, Map<String, dynamic> data) async {
    final nameController =
    TextEditingController(text: _text(data['name'], ''));
    final phoneController =
    TextEditingController(text: _text(data['phoneNumber'], ''));

    List<QueryDocumentSnapshot<Map<String, dynamic>>> familyDocs = [];

    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('familyMembers')
          .get();
      familyDocs = snapshot.docs;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load family members: $e')),
        );
      }
    }

    if (!mounted) {
      nameController.dispose();
      phoneController.dispose();
      return;
    }

    final familyControllers = <Map<String, dynamic>>[];
    for (final doc in familyDocs.take(2)) {
      familyControllers.add({
        'id': doc.id,
        'name': TextEditingController(text: _text(doc.data()['name'], '')),
        'phone': TextEditingController(text: _text(doc.data()['phone'], '')),
      });
    }

    while (familyControllers.length < 2) {
      familyControllers.add({
        'id': null,
        'name': TextEditingController(),
        'phone': TextEditingController(),
      });
    }

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Edit User', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _editField(nameController, 'Name'),
                const SizedBox(height: 12),
                _editField(phoneController, 'Phone Number'),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Emergency Family Members',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < familyControllers.length; i++) ...[
                  _editField(
                    familyControllers[i]['name'] as TextEditingController,
                    'Family Member ${i + 1} Name',
                  ),
                  const SizedBox(height: 8),
                  _editField(
                    familyControllers[i]['phone'] as TextEditingController,
                    'Family Member ${i + 1} Phone',
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Flood AI values are system-generated and are not editable here.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (save == true) {
      try {
        await firestore.collection('users').doc(uid).set({
          'name': nameController.text.trim(),
          'phoneNumber': phoneController.text.trim(),
          'adminUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final familyCollection = firestore
            .collection('users')
            .doc(uid)
            .collection('familyMembers');

        for (final member in familyControllers) {
          final memberName =
          (member['name'] as TextEditingController).text.trim();
          final memberPhone =
          (member['phone'] as TextEditingController).text.trim();
          final id = member['id'] as String?;

          if (memberName.isEmpty && memberPhone.isEmpty) {
            if (id != null) {
              await familyCollection.doc(id).delete();
            }
          } else if (id == null) {
            await familyCollection.add({
              'name': memberName,
              'phone': memberPhone,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } else {
            await familyCollection.doc(id).set({
              'name': memberName,
              'phone': memberPhone,
            }, SetOptions(merge: true));
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User details updated.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $e')),
          );
        }
      }
    }

    nameController.dispose();
    phoneController.dispose();
    for (final member in familyControllers) {
      (member['name'] as TextEditingController).dispose();
      (member['phone'] as TextEditingController).dispose();
    }
  }

  Widget _editField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: muted),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: accent),
        ),
      ),
    );
  }

  Future<void> _showUserInfo(String uid, Map<String, dynamic> data) async {
    List<Map<String, dynamic>> family = [];
    try {
      final snap = await firestore
          .collection('users')
          .doc(uid)
          .collection('familyMembers')
          .get();
      family = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {}

    if (!mounted) return;

    final location = _getUserLocation(data);
    final floodRisk = _mapOf(data['floodRisk']);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text(
          _text(data['name'], 'User Details'),
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('PROFILE'),
                _detail('UID', uid),
                _detail('Name', data['name']),
                _detail('Email', data['email']),
                _detail('Phone', data['phoneNumber']),
                _detail('Login Type', data['loginType']),
                _detail('Status', data['status']),
                _detail('Created At', data['createdAt']),
                _detail('Last Login', data['lastLogin']),
                const Divider(color: Colors.white12, height: 28),
                _sectionLabel('LOCATION'),
                _detail('Latitude', location?.latitude),
                _detail('Longitude', location?.longitude),
                _detail('Location Updated', _getLastLocationUpdate(data)),
                const Divider(color: Colors.white12, height: 28),
                _sectionLabel('FLOOD AI'),
                _detail('Risk', floodRisk['risk'] ?? data['risk']),
                _detail('Probability',
                    floodRisk['probability'] ?? data['probability']),
                _detail('Risk Index',
                    floodRisk['risk_index'] ?? floodRisk['riskIndex']),
                _detail('Elevation',
                    data['groundElevation'] ?? data['ground_elevation_m']),
                _detail('River Distance',
                    data['riverDistance'] ?? data['river_distance_km']),
                const Divider(color: Colors.white12, height: 28),
                _sectionLabel('EMERGENCY FAMILY MEMBERS'),
                if (family.isEmpty)
                  const Text('No family members found.',
                      style: TextStyle(color: muted)),
                ...family.map(
                      (m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.family_restroom, color: accent),
                    title: Text(_text(m['name'], '-'),
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(_text(m['phone'], '-'),
                        style: const TextStyle(color: muted)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showEditUserDialog(uid, data);
            },
            icon: const Icon(Icons.edit),
            label: const Text('EDIT USER'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: accent,
        fontWeight: FontWeight.w800,
        letterSpacing: .7,
      ),
    ),
  );

  Widget _detail(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$title:',
                style: const TextStyle(color: muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              _displayValue(value),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMapPage() {
    return _pageShell(
      'Live User Map',
      Padding(
        padding: const EdgeInsets.all(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: _usersMap(compact: false),
        ),
      ),
    );
  }

  Widget _usersMap({required bool compact}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message('Map error: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: accent));
        }

        final markers = <Marker>[];

        for (final doc in snapshot.data!.docs) {
          final data = doc.data();
          final location = _getUserLocation(data);
          if (location == null) continue;

          final risk = _riskOf(data);
          final name = _text(data['name'], 'User');

          markers.add(
            Marker(
              point: LatLng(location.latitude, location.longitude),
              width: compact ? 38 : 78,
              height: compact ? 42 : 76,
              child: GestureDetector(
                onTap: () => _showUserInfo(doc.id, data),
                child: compact
                    ? Icon(Icons.location_on, color: _riskColor(risk), size: 34)
                    : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_pin_circle,
                        color: _riskColor(risk), size: 40),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(15.3173, 75.7139),
            initialZoom: 7,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.floodguard.app',
            ),
            MarkerLayer(markers: markers),
            if (markers.isEmpty)
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('No user coordinates saved yet')],
              ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // FLOOD RISK GRID
  // ------------------------------------------------------------

  Widget _buildFloodRiskPage() {
    return _pageShell(
      'Karnataka Flood Risk Grid',
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _loadingGrid
                        ? 'Checking flood risk: $_gridCompleted / $_gridTotal cells'
                        : '${_gridCells.length} grid cells',
                    style: const TextStyle(color: muted),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loadingGrid ? null : _loadFloodGrid,
                  icon: const Icon(Icons.refresh),
                  label: const Text('REFRESH RISK'),
                ),
              ],
            ),
          ),
          if (_loadingGrid)
            const LinearProgressIndicator(color: accent),
          if (_gridError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _gridError!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          Expanded(
            child: _gridCells.isEmpty
                ? Center(
              child: _loadingGrid
                  ? const CircularProgressIndicator(color: accent)
                  : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.grid_on,
                      size: 60, color: accent),
                  const SizedBox(height: 12),
                  const Text(
                    'Karnataka Flood Risk Grid',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadFloodGrid,
                    icon: const Icon(Icons.download),
                    label: const Text('LOAD FLOOD GRID'),
                  ),
                ],
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(15.3173, 75.7139),
                    initialZoom: 6.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.floodguard.app',
                    ),
                    PolygonLayer(
                      polygons: _gridCells.map((cell) {
                        final result = _gridRisk[_cellKey(cell)];
                        final risk = _riskFromCell(cell, result);
                        final color = _riskColor(risk);
                        final bounds = _cellBounds(cell);

                        return Polygon(
                          points: [
                            LatLng(bounds.$1, bounds.$2),
                            LatLng(bounds.$1, bounds.$3),
                            LatLng(bounds.$4, bounds.$3),
                            LatLng(bounds.$4, bounds.$2),
                          ],
                          color: color.withOpacity(.35),
                          borderColor: color.withOpacity(.8),
                          borderStrokeWidth: .5,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Wrap(
              spacing: 18,
              children: [
                _legend(Colors.red, 'HIGH'),
                _legend(Colors.orange, 'MODERATE'),
                _legend(Colors.green, 'LOW'),
                _legend(Colors.grey, 'NOT LOADED'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFloodGrid() async {
    if (_loadingGrid) return;

    setState(() {
      _loadingGrid = true;
      _gridError = null;
      _gridCompleted = 0;
      _gridRisk = {};
    });

    try {
      final allCells = await FloodMapService.loadRiskGrid();
      final cells = FloodMapService.getKarnatakaCells(allCells);

      if (!mounted) return;
      setState(() {
        _gridCells = cells;
        _gridTotal = cells.length;
      });

      if (cells.isEmpty) {
        throw Exception('No Karnataka cells found in the grid JSON asset.');
      }

      // /map-risk accepts a list of coordinates. Send small batches rather
      // than trying to send all cells in one request.
      const batchSize = 100;
      final riskResults = <String, Map<String, dynamic>>{};

      for (int start = 0; start < cells.length; start += batchSize) {
        if (!mounted) return;

        final end = math.min(start + batchSize, cells.length);
        final batch = cells.sublist(start, end);

        final locations = batch.map((cell) {
          return <String, dynamic>{
            'latitude': cell.latitude,
            'longitude': cell.longitude,
          };
        }).toList();

        try {
          final results = await floodApi
              .getMapRisk(locations)
              .timeout(const Duration(seconds: 45));

          for (int i = 0; i < batch.length; i++) {
            final cell = batch[i];

            // Best-effort association: response items may carry coordinates.
            // If the backend preserves request order, use that as fallback.
            Map<String, dynamic>? match;

            for (final item in results) {
              final lat = _number(
                  item['latitude'] ?? item['lat'] ?? item['center_lat']);
              final lon = _number(
                  item['longitude'] ?? item['lon'] ?? item['lng'] ??
                      item['center_lon']);

              if (lat != null &&
                  lon != null &&
                  (lat - cell.latitude).abs() < 0.0001 &&
                  (lon - cell.longitude).abs() < 0.0001) {
                match = item;
                break;
              }
            }

            if (match == null && i < results.length) {
              match = results[i];
            }

            if (match != null) {
              riskResults[_cellKey(cell)] = match;
            }
          }
        } catch (e) {
          debugPrint('Flood grid batch $start failed: $e');
        }

        if (mounted) {
          setState(() => _gridCompleted = end);
        }
      }

      if (!mounted) return;

      setState(() {
        _gridRisk = riskResults;
        if (riskResults.isEmpty) {
          _gridError =
          'The grid loaded from the JSON asset, but the backend returned no usable risk results. Check that the API is running and that its /map-risk response contains risk data.';
        } else if (riskResults.length < cells.length) {
          _gridError =
          'Loaded risk for ${riskResults.length} of ${cells.length} cells. Some cells may show their bundled risk values.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _gridError = 'Could not load flood grid: $e');
    } finally {
      if (mounted) setState(() => _loadingGrid = false);
    }
  }

  (double, double, double, double) _cellBounds(FloodRiskCell cell) {
    // Use the opposite corner when present. For missing/zero coordinates,
    // draw a small visible cell around the center/start point.
    final lat2 = cell.latitude2 != 0
        ? cell.latitude2
        : cell.latitude + 0.04;
    final lon2 = cell.longitude2 != 0
        ? cell.longitude2
        : cell.longitude + 0.04;

    return (
    math.min(cell.latitude, lat2),
    math.min(cell.longitude, lon2),
    math.max(cell.longitude, lon2),
    math.max(cell.latitude, lat2),
    );
  }

  String _cellKey(FloodRiskCell cell) =>
      '${cell.latitude.toStringAsFixed(5)},${cell.longitude.toStringAsFixed(5)}';

  String _riskFromCell(
      FloodRiskCell cell, Map<String, dynamic>? result) {
    if (result == null) return cell.risk;

    final risk = result['final_risk'] ??
        result['risk_level'] ??
        result['risk'] ??
        result['riskLevel'];

    if (risk != null && risk.toString().trim().isNotEmpty) {
      return _normalizeRisk(risk.toString());
    }

    final probability = _number(
      result['probability'] ??
          result['risk_index'] ??
          result['riskIndex'] ??
          result['score'],
    );

    if (probability != null) {
      final value = probability <= 1 ? probability * 100 : probability;
      if (value >= 70) return 'HIGH';
      if (value >= 40) return 'MODERATE';
      return 'LOW';
    }

    return cell.risk;
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    );
  }

  // ------------------------------------------------------------
  // SOS ALERTS
  // ------------------------------------------------------------

  Widget _buildSosPage() {
    return _pageShell(
      'Emergency SOS Alerts',
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('sosAlerts')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _message('SOS data error: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: accent));
          }

          final alerts = snapshot.data!.docs;
          if (alerts.isEmpty) return _message('No SOS alerts.');

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final doc = alerts[index];
              final data = doc.data();
              final status = _text(data['status'], 'UNKNOWN').toUpperCase();
              final active = status == 'ACTIVE';

              final sender = _text(
                data['userName'] ?? data['senderName'] ?? data['userId'],
                'Unknown User',
              );

              final recipients = _recipientText(data);
              final latitude = data['latitude'] ?? data['locationLatitude'];
              final longitude = data['longitude'] ?? data['locationLongitude'];
              final created = _displayValue(data['createdAt']);

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? accent.withOpacity(.45) : Colors.white10,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sos, size: 30,
                            color: active ? accent : muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'SOS from $sender',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        _riskBadge(status),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 26),
                    _detail('Sender UID', data['userId'] ?? data['senderId']),
                    _detail('Sent To', recipients),
                    _detail('Latitude', latitude),
                    _detail('Longitude', longitude),
                    _detail('Created At', created),
                    _detail('Resolved At', data['resolvedAt']),
                    if (data['message'] != null)
                      _detail('Message', data['message']),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: active
                          ? ElevatedButton.icon(
                        onPressed: () => _resolveSos(doc.id),
                        icon: const Icon(Icons.check),
                        label: const Text('RESOLVE'),
                      )
                          : const Text(
                        'RESOLVED',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _recipientText(Map<String, dynamic> data) {
    for (final key in [
      'recipients',
      'recipientNames',
      'sentTo',
      'familyMembers',
      'recipientName',
      'recipientPhone',
      'recipientId',
      'phoneNumbers',
      'emergencyContacts',
    ]) {
      final value = data[key];
      if (value == null) continue;

      if (value is List) {
        final entries = value
            .map((item) {
          if (item is Map) {
            final name = item['name'] ?? item['recipientName'];
            final phone = item['phone'] ?? item['phoneNumber'];
            if (name != null && phone != null) return '$name ($phone)';
            return name?.toString() ?? phone?.toString() ?? '';
          }
          return item.toString();
        })
            .where((s) => s.isNotEmpty)
            .toList();
        if (entries.isNotEmpty) return entries.join(', ');
      } else if (value is Map) {
        final entries = value.entries
            .map((e) => '${e.key}: ${e.value}')
            .toList();
        if (entries.isNotEmpty) return entries.join(', ');
      } else if (value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }

    return 'Recipient details not stored in this SOS document';
  }

  Future<void> _resolveSos(String id) async {
    try {
      await firestore.collection('sosAlerts').doc(id).update({
        'status': 'RESOLVED',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resolve SOS: $e')),
        );
      }
    }
  }

  // ------------------------------------------------------------
  // HELPERS
  // ------------------------------------------------------------

  Widget _riskBadge(String risk) {
    final color = _riskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        risk.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _riskOf(Map<String, dynamic> data) {
    final nested = _mapOf(data['floodRisk']);
    return _normalizeRisk(
      _text(nested['risk'] ?? nested['risk_level'] ?? data['risk'], 'UNKNOWN'),
    );
  }

  String _normalizeRisk(String risk) {
    final value = risk.toUpperCase();
    if (value.contains('HIGH')) return 'HIGH';
    if (value.contains('MODERATE') || value.contains('MEDIUM')) return 'MODERATE';
    if (value.contains('LOW')) return 'LOW';
    return 'UNKNOWN';
  }

  Color _riskColor(String risk) {
    switch (_normalizeRisk(risk)) {
      case 'HIGH':
        return Colors.red;
      case 'MODERATE':
        return Colors.orange;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  GeoPoint? _getUserLocation(Map<String, dynamic> data) {
    final location = data['location'];

    if (location is GeoPoint) return location;

    if (location is Map) {
      final lat = _number(location['latitude'] ?? location['lat']);
      final lon = _number(location['longitude'] ?? location['lng'] ?? location['lon']);
      if (lat != null && lon != null) return GeoPoint(lat, lon);
    }

    final lat = _number(data['latitude']);
    final lon = _number(data['longitude']);
    if (lat != null && lon != null) return GeoPoint(lat, lon);

    return null;
  }

  DateTime? _getLastLocationUpdate(Map<String, dynamic> data) {
    final location = data['location'];
    final values = [
      if (location is Map) location['updatedAt'],
      data['lastLocationUpdate'],
      data['locationUpdatedAt'],
    ];

    for (final value in values) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
    }
    return null;
  }

  String _text(dynamic value, [String fallback = '-']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '-';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is DateTime) return value.toLocal().toString();
    return value.toString();
  }

  Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Widget _message(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // LOGOUT
  // ------------------------------------------------------------

  Future<void> _logout() async {
    try {
      await auth.signOut();
      if (!mounted) return;

      // Clear the admin screen and all routes above the login/root route.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }
}