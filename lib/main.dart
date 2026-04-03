import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const RunningPhotoApp());
}

class RunningPhotoApp extends StatelessWidget {
  const RunningPhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RUN PICTURE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}
