import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const FrndCloneApp());
}

class FrndCloneApp extends StatelessWidget {
  const FrndCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF9C4DFF);

    return MaterialApp(
      title: 'Frnd Clone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF080A1F),
        canvasColor: const Color(0xFF0C0F23),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141A37),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: seedColor),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5AA2),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
