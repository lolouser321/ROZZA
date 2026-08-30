import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/rozza_theme.dart';
import 'features/shell/rozza_shell.dart';
import 'playback/playback_controller.dart';

class RozzaApp extends StatelessWidget {
  const RozzaApp({super.key, required this.playback, this.locale});

  final PlaybackController playback;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ROZZA',
      debugShowCheckedModeBanner: false,
      theme: RozzaTheme.dark,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: RozzaShell(playback: playback),
    );
  }
}
