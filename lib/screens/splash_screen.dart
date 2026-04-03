import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text('RUN PICTURE',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
              letterSpacing: 2.0,
            )),
      ),
    );
  }
}
