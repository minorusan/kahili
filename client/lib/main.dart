import 'dart:ui';
import 'package:flutter/material.dart';
import 'api/client_logger.dart';
import 'screens/home_screen.dart';
import 'theme/kahili_theme.dart';

void main() {
  // Catch Flutter framework errors (widget build, layout, paint)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ClientLogger.error(
      'FlutterError: ${details.exceptionAsString()}',
      details.stack?.toString(),
    );
  };

  // Catch uncaught async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    ClientLogger.error(
      'Uncaught: $error',
      stack.toString(),
    );
    return true;
  };

  runApp(const KahiliApp());
}

class KahiliApp extends StatelessWidget {
  const KahiliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kahili',
      debugShowCheckedModeBanner: false,
      theme: KahiliTheme.dark,
      home: const HomeScreen(),
    );
  }
}
