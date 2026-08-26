import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'src/audio_handler.dart';
import 'src/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final handler = await AudioService.init(
    builder: RozzaAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.rozza.app.playback',
      androidNotificationChannelName: 'ROZZA playback',
      androidNotificationOngoing: true,
    ),
  );
  runApp(RozzaApp(handler: handler));
}

class RozzaApp extends StatelessWidget {
  const RozzaApp({super.key, required this.handler});

  final RozzaAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ROZZA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF9D5CFF),
        scaffoldBackgroundColor: const Color(0xFF09070E),
        useMaterial3: true,
      ),
      home: HomeScreen(handler: handler),
    );
  }
}
