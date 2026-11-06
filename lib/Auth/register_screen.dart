import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/add_family_members_screen.dart';
import 'login_screen.dart';

class registerScreen extends StatefulWidget {
  const registerScreen({super.key});

  @override
  State<registerScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<registerScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String language = 'English';
  String gender = 'Prefer not to say';
  String stateName = 'Karnataka';

  bool termsAccepted = false;
  bool registering = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  static const Color background = Color(0xFF0B0708);
  static const Color card = Color(0xFF211515);
  static const Color input = Color(0xFF130B0B);
  static const Color border = Color(0xFF40302F);
  static const Color red = Color(0xFFE5091A);
  static const Color muted = Color(0xFFC5B5B5);

  final List<String> states = const [
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

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void showMessage(String message, {bool error = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          error ? Colors.red.shade900 : Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'This email is already registered. Please log in.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/Password authentication is not enabled in Firebase.';
      default:
        return e.message ?? 'Registration failed. Please try again.';
    }
  }

  Future<void> register() async {
    if (registering) return;

    if (!_formKey.currentState!.validate()) return;

    if (!termsAccepted) {
      showMessage('Please accept the Terms and Conditions.');
      return;
    }

    setState(() => registering = true);

    User? createdUser;
    bool profileSaved = false;

    try {
      final email = emailController.text.trim();

      // Create the Firebase Authentication account.
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );

      final user = credential.user;

      if (user == null) {
        showMessage('Unable to create your account.');
        return;
      }

      createdUser = user;

      await user.updateDisplayName(nameController.text.trim());

      // Create the profile under the authenticated user's UID.
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      await userRef.set({
        'uid': user.uid,
        'name': nameController.text.trim(),
        'email': email,
        'phoneNumber': '+91${phoneController.text.trim()}',
        'language': language,
        'gender': gender,
        'state': stateName,
        'loginType': 'email',
        'role': 'user',
        'emailVerified': false,
        'familyMembersAdded': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      profileSaved = true;

      // Send the verification email after creating the profile.
      await user.sendEmailVerification();

      if (!mounted) return;

      // Do not proceed to emergency contacts until email is verified.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: card,
            title: const Text(
              'Verify your email',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'We sent a verification link to $email.\n\n'
                  'Open your email and click the verification link. '
                  'Then return to FloodGuard and log in.',
              style: const TextStyle(
                color: muted,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'OK',
                  style: TextStyle(color: red),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const login_screen(),
        ),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Registration authentication error: ${e.code} - ${e.message}',
      );

      // If Firestore failed after Auth account creation, preserve the
      // account so the user can recover instead of creating duplicates.
      showMessage(authErrorMessage(e));
    } on FirebaseException catch (e) {
      debugPrint(
        'Registration Firestore error: ${e.code} - ${e.message}',
      );

      if (createdUser != null && !profileSaved) {
        showMessage(
          'Your account was created, but your profile could not be saved. '
              'Please check Firestore permissions before trying again.',
        );
      } else {
        showMessage(
          'Your profile was saved, but the verification email could not '
              'be completed. Please try logging in and requesting verification.',
        );
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      showMessage('Unable to complete registration. Please try again.');
    } finally {
      if (mounted) {
        setState(() => registering = false);
      }
    }
  }

  InputDecoration decoration(
      String hint, {
        IconData? icon,
        Widget? suffix,
      }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: muted),
      prefixIcon: icon == null ? null : Icon(icon, color: muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: input,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: red, width: 1.5),
      ),
    );
  }

  Widget dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: card,
      style: const TextStyle(color: Colors.white),
      decoration: decoration(label),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
          value: item,
          child: Text(item.toString()),
        ),
      )
          .toList(),
      onChanged: registering ? null : onChanged,
    );
  }

  Widget primaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: registering ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF75252B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: registering
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        )
            : Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        title: const Text('Create account'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Join FloodGuard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create your account to receive flood alerts '
                            'and use emergency SOS.',
                        style: TextStyle(
                          color: muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),

                      const Text(
                        'Full name',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: nameController,
                        enabled: !registering,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white),
                        decoration: decoration(
                          'Enter your full name',
                          icon: Icons.person_outline,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 17),

                      const Text(
                        'Email address',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: emailController,
                        enabled: !registering,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: decoration(
                          'Enter your email address',
                          icon: Icons.email_outlined,
                        ),
                        validator: (value) {
                          final email = (value ?? '').trim();

                          if (email.isEmpty) {
                            return 'Please enter your email address.';
                          }

                          if (!RegExp(
                            r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                          ).hasMatch(email)) {
                            return 'Enter a valid email address.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 17),

                      const Text(
                        'Mobile number',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 7),

                      TextFormField(
                        controller: phoneController,
                        enabled: !registering,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white),
                        decoration: decoration(
                          'Enter 10-digit mobile number',
                          icon: Icons.phone_android,
                        ).copyWith(
                          prefixText: '+91 ',
                          counterText: '',
                        ),
                        validator: (value) {
                          final phone = (value ?? '').trim();

                          if (phone.isEmpty) {
                            return 'Please enter your mobile number.';
                          }

                          if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)) {
                            return 'Enter 10 digits starting with 6, 7, 8, or 9.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 17),

                      dropdown<String>(
                        label: 'Preferred language',
                        value: language,
                        items: const ['English', 'ಕನ್ನಡ'],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => language = value);
                          }
                        },
                      ),

                      const SizedBox(height: 17),

                      dropdown<String>(
                        label: 'Gender',
                        value: gender,
                        items: const [
                          'Prefer not to say',
                          'Male',
                          'Female',
                          'Other',
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => gender = value);
                          }
                        },
                      ),

                      const SizedBox(height: 17),

                      dropdown<String>(
                        label: 'State',
                        value: stateName,
                        items: states,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => stateName = value);
                          }
                        },
                      ),

                      const SizedBox(height: 17),

                      const Text(
                        'Password',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: passwordController,
                        enabled: !registering,
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white),
                        decoration: decoration(
                          'Create a password (at least 6 characters)',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            onPressed: registering
                                ? null
                                : () {
                              setState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: muted,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Password must be at least 6 characters.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 17),

                      const Text(
                        'Confirm password',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: confirmPasswordController,
                        enabled: !registering,
                        obscureText: obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(color: Colors.white),
                        decoration: decoration(
                          'Re-enter your password',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            onPressed: registering
                                ? null
                                : () {
                              setState(() {
                                obscureConfirmPassword =
                                !obscureConfirmPassword;
                              });
                            },
                            icon: Icon(
                              obscureConfirmPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: muted,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password.';
                          }

                          if (value != passwordController.text) {
                            return 'Passwords do not match.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 15),

                      CheckboxListTile(
                        value: termsAccepted,
                        contentPadding: EdgeInsets.zero,
                        activeColor: red,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I accept the Terms and Conditions and Privacy Policy.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                          ),
                        ),
                        onChanged: registering
                            ? null
                            : (value) {
                          setState(() {
                            termsAccepted = value ?? false;
                          });
                        },
                      ),

                      const SizedBox(height: 17),

                      primaryButton('CREATE ACCOUNT', register),

                      const SizedBox(height: 18),

                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            const Text(
                              'Already have an account? ',
                              style: TextStyle(color: muted),
                            ),
                            GestureDetector(
                              onTap: registering
                                  ? null
                                  : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                    const login_screen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  color: red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}