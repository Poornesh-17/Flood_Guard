import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'splash_screen.dart';
import 'Auth/login_screen.dart';
import 'screens/floodguard_home_screen.dart';
import 'services/app_language.dart';

class FloodGuardApp extends StatelessWidget {
  const FloodGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguage.languageNotifier,
      builder: (context, currentLang, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: AppLanguage.tr('app_name'),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0B0708),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFE5091A),
              brightness: Brightness.dark,
            ),
            fontFamily: 'Roboto',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0B0708),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

/// Determines which screen to show after the splash screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFFE5091A),
              ),
            ),
          );
        }

        if (snapshot.data != null) {
          return const FloodGuardHomeScreen();
        }

        return const LoginScreen();
      },
    );
  }
}