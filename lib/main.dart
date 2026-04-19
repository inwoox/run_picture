import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const RunningPhotoApp());
}

class RunningPhotoApp extends StatelessWidget {
  const RunningPhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: fontSizeNotifier,
      builder: (_, isLarge, __) {
        return MaterialApp(
          title: 'RUN PIC',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(isLarge ? 1.3 : 1.1),
              ),
              child: child!,
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
