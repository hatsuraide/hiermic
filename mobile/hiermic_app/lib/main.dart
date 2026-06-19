import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() => runApp(const HierMicApp());

class HierMicApp extends StatelessWidget {
  const HierMicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HierMic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
