import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Auth/login_screen.dart';
import '../services/app_language.dart';
import 'add_family_members_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color background = Color(0xFF0B0708);
  static const Color card = Color(0xFF171011);
  static const Color card2 = Color(0xFF211618);
  static const Color red = Color(0xFFE5091A);
  static const Color green = Color(0xFF68D46A);
  static const Color orange = Color(0xFFFF9D3D);
  static const Color muted = Color(0xFFB9AEB0);
  static const Color border = Color(0xFF34292B);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool loading = true;

  String name = '';
  String phone = '';
  String language = 'English';
  String gender = '';
  String stateName = '';

  List<Map<String, String>> familyMembers = [];

  bool floodAlerts = true;

  bool weatherAlerts = true;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  // ============================================================
  // LOAD REGISTERED USER DETAILS
  // ============================================================
  Future<void> editProfileDetails() async {
    final user = _auth.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final nameController = TextEditingController(text: name);
    final phoneController = TextEditingController(
      text: phone.replaceAll(RegExp(r'\D'), '').replaceFirst(
        RegExp(r'^91'),
        '',
      ),
    );
    String selectedLanguage = language;
    String selectedGender = gender.isEmpty ? 'Prefer not to say' : gender;
    String selectedState = stateName.isEmpty ? 'Karnataka' : stateName;

    const languages = ['English', 'ಕನ್ನಡ'];
    const genders = [
      'Prefer not to say',
      'Male',
      'Female',
      'Other',
    ];

    const states = [
      'Andhra Pradesh',
      'Arunachal Pradesh',
      'Assam',
      'Bihar',
      'Chhattisgarh',
      'Goa',
      'Gujarat',
      'Haryana',
      'Himachal Pradesh',
      'Jharkhand',
      'Karnataka',
      'Kerala',
      'Madhya Pradesh',
      'Maharashtra',
      'Manipur',
      'Meghalaya',
      'Mizoram',
      'Nagaland',
      'Odisha',
      'Punjab',
      'Rajasthan',
      'Sikkim',
      'Tamil Nadu',
      'Telangana',
      'Tripura',
      'Uttar Pradesh',
      'Uttarakhand',
      'West Bengal',
    ];

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: card2,
              title: const Text(
                'Edit profile',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            labelStyle: TextStyle(color: muted),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter your name.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Mobile number',
                            prefixText: '+91 ',
                            labelStyle: TextStyle(color: muted),
                            counterText: '',
                          ),
                          validator: (value) {
                            final digits =
                            (value ?? '').replaceAll(RegExp(r'\D'), '');

                            if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
                              return 'Enter a 10-digit number starting with 6–9.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: languages.contains(selectedLanguage)
                              ? selectedLanguage
                              : 'English',
                          dropdownColor: card2,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Preferred language',
                            labelStyle: TextStyle(color: muted),
                          ),
                          items: languages.map((item) {
                            return DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedLanguage = value;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: genders.contains(selectedGender)
                              ? selectedGender
                              : 'Prefer not to say',
                          dropdownColor: card2,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            labelStyle: TextStyle(color: muted),
                          ),
                          items: genders.map((item) {
                            return DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedGender = value;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: states.contains(selectedState)
                              ? selectedState
                              : 'Karnataka',
                          dropdownColor: card2,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'State',
                            labelStyle: TextStyle(color: muted),
                          ),
                          items: states.map((item) {
                            return DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedState = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: muted),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    Navigator.pop(dialogContext, {
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'language': selectedLanguage,
                      'gender': selectedGender,
                      'state': selectedState,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
      phoneController.dispose();
    });

    if (!mounted || result == null) return;

    final newName = result['name']!;
    final digits = result['phone']!.replaceAll(RegExp(r'\D'), '');
    final newPhone = '+91${digits.replaceFirst(RegExp(r'^91'), '')}';

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'name': newName,
        'phoneNumber': newPhone,
        'language': result['language'],
        'gender': result['gender'],
        'state': result['state'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update the display name in Firebase Authentication too.
      if (user.displayName != newName) {
        await user.updateDisplayName(newName);
      }

      await AppLanguage.setLanguage(result['language']!);

      if (!mounted) return;

      setState(() {
        name = newName;
        phone = newPhone;
        language = result['language']!;
        gender = result['gender']!;
        stateName = result['state']!;
      });

      showMessage('Profile updated successfully.');
    } on FirebaseException catch (e) {
      debugPrint('PROFILE UPDATE ERROR: ${e.code} - ${e.message}');
      if (mounted) showMessage('Unable to save profile changes.');
    } catch (e) {
      debugPrint('PROFILE UPDATE ERROR: $e');
      if (mounted) showMessage('Unable to update profile.');
    }
  }

  Future<void> loadProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      return;
    }

    try {
      final userRef = _firestore.collection('users').doc(user.uid);

      final results = await Future.wait([
        userRef.get(),
        userRef.collection('familyMembers').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final familySnapshot =
      results[1] as QuerySnapshot<Map<String, dynamic>>;

      final data = userDoc.data() ?? {};

      final members = familySnapshot.docs.map((doc) {
        final memberData = doc.data();

        return <String, String>{
          'id': doc.id,
          'name': (memberData['name'] ?? '').toString(),
          'phone': (memberData['phone'] ??
              memberData['phoneNumber'] ??
              '')
              .toString(),
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        name = (data['name'] ?? user.displayName ?? 'User').toString();

        // Phone-auth users normally have a verified phone number here.
        // Prefer the latest mobile number saved in the user's Firestore profile.
        phone = (data['phoneNumber'] ??
            data['phone'] ??
            user.phoneNumber ??
            '')
            .toString();

        language = (data['language'] ?? 'English').toString();
        AppLanguage.setLanguage(language);

        gender = (data['gender'] ?? '').toString();
        stateName = (data['state'] ?? '').toString();

        familyMembers = members;

        // Load saved preferences when available.
        floodAlerts = data['floodAlerts'] as bool? ?? true;

        weatherAlerts = data['weatherAlerts'] as bool? ?? true;

        loading = false;
      });
    } catch (e) {
      debugPrint('PROFILE LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showMessage('Unable to load profile. Pull down to retry.');
    }
  }

  // ============================================================
  // EDIT NAME
  // ============================================================

  Future<void> updateName() async {
    final controller = TextEditingController(text: name);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: card2,
          title: const Text(
            'Change name',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter your full name',
              hintStyle: TextStyle(color: muted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: muted),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: red, width: 2),
              ),
            ),
            onSubmitted: (value) {
              Navigator.pop(dialogContext, value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (!mounted || result == null || result.trim().isEmpty) return;

    final cleanedName = result.trim();

    if (cleanedName == name) return;

    final user = _auth.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'name': cleanedName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await user.updateDisplayName(cleanedName);

      if (!mounted) return;

      setState(() {
        name = cleanedName;
      });

      showMessage('Name updated successfully.');
    } catch (e) {
      debugPrint('NAME UPDATE ERROR: $e');

      if (!mounted) return;

      showMessage('Unable to update name.');
    }
  }

  // ============================================================
  // SAVE ALERT PREFERENCES
  // ============================================================

  Future<void> updateAlertPreference({
    required String field,
    required bool value,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        field: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ALERT PREFERENCE ERROR: $e');

      if (!mounted) return;

      // Restore the saved value if the write fails.
      await loadProfile();

      if (!mounted) return;

      showMessage('Unable to save this preference.');
    }
  }

  // ============================================================
  // MANAGE FAMILY MEMBERS
  // ============================================================

  Future<void> openFamilyMembers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddFamilyMembersScreen(),
      ),
    );

    if (!mounted) return;

    setState(() {
      loading = true;
    });

    await loadProfile();
  }

  Future<void> deleteFamilyMember(String id) async {
    final user = _auth.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: card2,
          title: const Text(
            'Remove family member?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This contact will no longer be available for Emergency SOS.',
            style: TextStyle(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirm != true) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('familyMembers')
          .doc(id)
          .delete();

      if (!mounted) return;

      await loadProfile();

      if (!mounted) return;

      showMessage('Family member removed.');
    } catch (e) {
      debugPrint('DELETE FAMILY MEMBER ERROR: $e');

      if (!mounted) return;

      showMessage('Unable to remove family member.');
    }
  }

  // ============================================================
  // HELP
  // ============================================================

  void showHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: card2,
          title: const Text(
            'FloodGuard Help',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const SingleChildScrollView(
            child: Text(
              'FloodGuard helps you monitor flood risk and find safety information.\n\n'
                  'FLOOD RISK\n'
                  'Green = Low risk\n'
                  'Orange = Moderate risk\n'
                  'Red = High risk\n\n'
                  'EMERGENCY SOS\n'
                  'Keep your family contacts updated so they can be contacted during an emergency.\n\n'
                  'PROFILE\n'
                  'Your name, mobile number, language, gender and state are based on your registration details.',
              style: TextStyle(color: muted, height: 1.5),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // ABOUT
  // ============================================================

  void showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'FloodGuard',
      applicationVersion: '1.0.0',
      applicationLegalese: 'AI-powered flood safety application',
    );
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  Future<void> signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171011),
        title: const Text(
          'Sign Out',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Color(0xFFB9AEB0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5091A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have been signed out successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginScreen(),
        ),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign out failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget profileTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 21,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle.isEmpty ? 'Not provided' : subtitle,
            style: const TextStyle(
              color: muted,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: muted,
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget infoTile({
    required IconData icon,
    required String title,
    required String value,
    Color iconColor = Colors.white,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? 'Not provided' : value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: card2,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: CircularProgressIndicator(color: red),
        ),
      );
    }

    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'You are not logged in.',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                          (route) => false,
                    );
                  },
                  child: const Text('Go to login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        title: Text(
          AppLanguage.tr('my_profile'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: loadProfile,
          color: red,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
            children: [
              // PROFILE HEADER
          // PROFILE HEADER
          Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: red.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: red,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Name with edit icon beside it
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: Flexible(
                      child: Text(
                        name.isEmpty ? 'User' : name,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // IconButton(
                  //   tooltip: 'Edit profile',
                  //   onPressed: editProfileDetails,
                  //   icon: const Icon(
                  //     Icons.edit_outlined,
                  //     color: red,
                  //     size: 20,
                  //   ),
                  // ),
                ],
              ),

              // Email below the name
              Text(
                _auth.currentUser?.email ?? 'Email not available',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

              const SizedBox(height: 24),


              // REGISTRATION DETAILS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        AppLanguage.tr('registration_details'),
                        style: const TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: editProfileDetails,
                    tooltip: 'Edit registration details',
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: red,
                      size: 21,
                    ),
                  ),
                ],
              ),

              infoTile(
                icon: Icons.phone_android,
                title: AppLanguage.tr('mobile_number'),
                value: phone,
                iconColor: green,
              ),

              infoTile(
                icon: Icons.translate,
                title: AppLanguage.tr('preferred_language'),
                value: language,
                iconColor: orange,
              ),

              infoTile(
                icon: Icons.person_outline,
                title: AppLanguage.tr('gender'),
                value: gender,
                iconColor: green,
              ),

              infoTile(
                icon: Icons.location_on_outlined,
                title: AppLanguage.tr('state'),
                value: stateName,
                iconColor: orange,
              ),

              const SizedBox(height: 20),

              // FAMILY MEMBERS
              sectionTitle(AppLanguage.tr('emergency_family')),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    if (familyMembers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          AppLanguage.tr('no_family_added'),
                          style: const TextStyle(color: muted),
                        ),
                      )
                    else
                      ...familyMembers.map((member) {
                        final memberName = member['name'] ?? '';
                        final memberPhone = member['phone'] ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: card2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFF2A080B),
                                child: Icon(Icons.person, color: red),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      memberName.isEmpty
                                          ? 'Family member'
                                          : memberName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      memberPhone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () =>
                                    deleteFamilyMember(member['id'] ?? ''),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: red,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: openFamilyMembers,
                        icon: const Icon(Icons.group_add),
                        label: Text(
                          familyMembers.isEmpty
                              ? AppLanguage.tr('add_family')
                              : AppLanguage.tr('manage_family'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ALERT SETTINGS
              sectionTitle(AppLanguage.tr('alert_settings')),

              Container(
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: floodAlerts,
                      activeColor: red,
                      title: Text(
                        AppLanguage.tr('flood_alerts'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        AppLanguage.tr('flood_alerts_sub'),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      onChanged: (value) async {
                        setState(() => floodAlerts = value);

                        await updateAlertPreference(
                          field: 'floodAlerts',
                          value: value,
                        );
                      },
                    ),

                    const Divider(color: border, height: 1),
                    SwitchListTile(
                      value: weatherAlerts,
                      activeColor: red,
                      title: Text(
                        AppLanguage.tr('weather_alerts'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        AppLanguage.tr('weather_alerts_sub'),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      onChanged: (value) async {
                        setState(() => weatherAlerts = value);

                        await updateAlertPreference(
                          field: 'weatherAlerts',
                          value: value,
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // HELP & SUPPORT
              sectionTitle(AppLanguage.tr('help_support')),

              profileTile(
                icon: Icons.help_outline,
                title: AppLanguage.tr('help'),
                subtitle: AppLanguage.tr('how_to_use'),
                iconColor: green,
                onTap: showHelp,
              ),

              profileTile(
                icon: Icons.info_outline,
                title: AppLanguage.tr('about_app'),
                subtitle: AppLanguage.tr('app_info'),
                iconColor: orange,
                onTap: showAbout,
              ),

              const SizedBox(height: 20),

              // ACCOUNT
              sectionTitle(AppLanguage.tr('account')),

              profileTile(
                icon: Icons.logout,
                title: AppLanguage.tr('sign_out'),
                subtitle: AppLanguage.tr('sign_out_sub'),
                iconColor: red,
                onTap: signOut,
              ),

              const SizedBox(height: 16),

              const Center(
                child: Text(
                  'FloodGuard • AI Flood Safety',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}