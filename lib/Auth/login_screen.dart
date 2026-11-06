import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../admin/admin_dashboard_screen.dart';
import '../screens/add_family_members_screen.dart';
import '../screens/floodguard_home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// Backwards compatibility with the old class name.
class login_screen extends LoginScreen {
  const login_screen({super.key});
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  static const Color background = Color(0xFF0B0708);
  static const Color card = Color(0xFF211515);
  static const Color input = Color(0xFF130B0B);
  static const Color border = Color(0xFF40302F);
  static const Color red = Color(0xFFE5091A);
  static const Color muted = Color(0xFFC5B5B5);

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
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

  InputDecoration decoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: input,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: red, width: 1.5),
      ),
    );
  }

  String authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Network error. Check your internet connection.';

      case 'invalid-verification-code':
        return 'Email verification is required. Please verify your email.';

      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  Future<void> login() async {
    if (loading) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      final credential =
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final user = credential.user;

      if (user == null) {
        showMessage('Unable to sign in. Please try again.');
        return;
      }

      // Reload the Firebase user to get the latest verification status.
      await user.reload();

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        showMessage('Unable to load your account. Please sign in again.');
        return;
      }

      if (!currentUser.emailVerified) {
        await currentUser.sendEmailVerification();

        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        showMessage(
          'Please verify your email. A verification email has been sent.',
        );

        return;
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);

      final profile = await userRef.get();

      if (!profile.exists) {
        await FirebaseAuth.instance.signOut();

        showMessage(
          'Your profile was not found. Please contact support.',
        );

        return;
      }

      final data = profile.data() ?? {};

      await userRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      final role = (data['role'] ?? 'user').toString().toLowerCase();

      if (role == 'admin') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminDashboardScreen(),
          ),
              (_) => false,
        );
        return;
      }

      final family =
      await userRef.collection('familyMembers').get();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => family.docs.length < 2
              ? const AddFamilyMembersScreen()
              : const FloodGuardHomeScreen(),
        ),
            (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Login error: ${e.code} - ${e.message}');
      showMessage(authErrorMessage(e));
    } on FirebaseException catch (e) {
      debugPrint('Firestore login error: ${e.code} - ${e.message}');
      showMessage('Unable to load your profile. Please try again.');
    } catch (e) {
      debugPrint('Login completion error: $e');
      showMessage('Login could not be completed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> forgotPassword() async {
    if (loading) return;

    final email = emailController.text.trim();

    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showMessage('Enter your email address first.');
      return;
    }

    setState(() => loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      showMessage(
        'If an account exists for this email, a password-reset email '
            'will be sent.',
        error: false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Password reset error: ${e.code} - ${e.message}');

      if (e.code == 'invalid-email') {
        showMessage('Please enter a valid email address.');
      } else if (e.code == 'network-request-failed') {
        showMessage('Network error. Check your internet connection.');
      } else {
        // Avoid exposing whether an email is registered.
        showMessage(
          'If an account exists for this email, a password-reset email '
              'will be sent.',
          error: false,
        );
      }
    } catch (e) {
      debugPrint('Password reset error: $e');
      showMessage('Unable to send the reset email. Please try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Widget primaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF75252B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: loading
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logowhite.png',
                        width: 42,
                        height: 42,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Flood',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                        ),
                      ),
                      const Text(
                        'Guard',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                        ),
                      ),


                    ],
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(24),
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
                            'Welcome back',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to your FloodGuard account.',
                            style: TextStyle(
                              color: muted,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 25),

                          const Text(
                            'Email address',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enabled: !loading,
                            style: const TextStyle(color: Colors.white),
                            decoration: decoration(
                              'Enter your email address',
                              suffix: const Icon(
                                Icons.email_outlined,
                                color: muted,
                              ),
                            ),
                            validator: (value) {
                              final email = (value ?? '').trim();

                              if (email.isEmpty) {
                                return 'Enter your email address.';
                              }

                              if (!RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(email)) {
                                return 'Enter a valid email address.';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          const Text(
                            'Password',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            textInputAction: TextInputAction.done,
                            enabled: !loading,
                            style: const TextStyle(color: Colors.white),
                            decoration: decoration(
                              'Enter your password',
                              suffix: IconButton(
                                onPressed: loading
                                    ? null
                                    : () {
                                  setState(() {
                                    obscurePassword =
                                    !obscurePassword;
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
                              if (value == null || value.isEmpty) {
                                return 'Enter your password.';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => login(),
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: loading ? null : forgotPassword,
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          primaryButton('LOGIN', login),

                          const SizedBox(height: 22),

                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(color: muted),
                                ),
                                GestureDetector(
                                  onTap: loading
                                      ? null
                                      : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const registerScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Register',
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
                  const SizedBox(height: 20),
                  const Text(
                    'Know the Risk. Find Safety.',
                    style: TextStyle(
                      color: muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}