import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'floodguard_home_screen.dart';

class AddFamilyMembersScreen extends StatefulWidget {
  const AddFamilyMembersScreen({super.key});

  @override
  State<AddFamilyMembersScreen> createState() =>
      _AddFamilyMembersScreenState();
}

class _AddFamilyMembersScreenState
    extends State<AddFamilyMembersScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController name1Controller =
  TextEditingController();

  final TextEditingController phone1Controller =
  TextEditingController();

  final TextEditingController name2Controller =
  TextEditingController();

  final TextEditingController phone2Controller =
  TextEditingController();

  bool saving = false;

  @override
  void dispose() {
    name1Controller.dispose();
    phone1Controller.dispose();
    name2Controller.dispose();
    phone2Controller.dispose();
    super.dispose();
  }

  Future<void> saveFamilyMembers() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login again.'),
        ),
      );
      return;
    }

    setState(() {
      saving = true;
    });

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      await userRef
          .collection('familyMembers')
          .doc('member1')
          .set({
        'name': name1Controller.text.trim(),
        'phone': phone1Controller.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await userRef
          .collection('familyMembers')
          .doc('member2')
          .set({
        'name': name2Controller.text.trim(),
        'phone': phone2Controller.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark that family members have been added.
      await userRef.set({
        'familyMembersAdded': true,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Family members saved successfully.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const FloodGuardHomeScreen(),
        ),
      );
    } catch (e) {
      debugPrint(
        'FAMILY MEMBER SAVE ERROR: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save family members: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  InputDecoration inputDecoration(
      String hint,
      IconData icon,
      ) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(
          color: Colors.green,
          width: 2,
        ),
      ),
    );
  }

  Widget memberTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add Family Members',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),

                const Text(
                  'Emergency Family Contacts',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Add two family members who can be '
                      'contacted during an emergency.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey,
                  ),
                ),

                const SizedBox(height: 30),

                memberTitle('FAMILY MEMBER 1'),

                const SizedBox(height: 12),

                TextFormField(
                  controller: name1Controller,
                  textCapitalization:
                  TextCapitalization.words,
                  decoration: inputDecoration(
                    'Family member name',
                    Icons.person,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter family member name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 15),

                TextFormField(
                  controller: phone1Controller,
                  keyboardType:
                  TextInputType.phone,
                  decoration: inputDecoration(
                    'Phone number',
                    Icons.phone,
                  ),
                  validator: (value) {
                    final phone =
                        value?.trim() ?? '';

                    if (phone.isEmpty) {
                      return 'Enter phone number';
                    }

                    if (phone.length < 10) {
                      return 'Enter a valid phone number';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 30),

                memberTitle('FAMILY MEMBER 2'),

                const SizedBox(height: 12),

                TextFormField(
                  controller: name2Controller,
                  textCapitalization:
                  TextCapitalization.words,
                  decoration: inputDecoration(
                    'Family member name',
                    Icons.person,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter family member name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 15),

                TextFormField(
                  controller: phone2Controller,
                  keyboardType:
                  TextInputType.phone,
                  decoration: inputDecoration(
                    'Phone number',
                    Icons.phone,
                  ),
                  validator: (value) {
                    final phone =
                        value?.trim() ?? '';

                    if (phone.isEmpty) {
                      return 'Enter phone number';
                    }

                    if (phone.length < 10) {
                      return 'Enter a valid phone number';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : saveFamilyMembers,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      Colors.green,
                      foregroundColor:
                      Colors.white,
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(20),
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child:
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                        : const Text(
                      'SAVE & CONTINUE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}