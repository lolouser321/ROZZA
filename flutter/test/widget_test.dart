import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rozza/src/app.dart';
import 'package:rozza/src/data/demo_catalog.dart';
import 'package:rozza/src/playback/playback_controller.dart';
import 'package:rozza/src/widgets/artwork.dart';

import 'support/fake_playback_bridge.dart';

void main() {
  setUpAll(() async {
    RozzaArtwork.networkImagesEnabled = false;
    final loader = FontLoader('RozzaSans')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDownAll(() => RozzaArtwork.networkImagesEnabled = true);

  testWidgets('professional shell exposes the primary product navigation', (
    tester,
  ) async {
    final playback = PlaybackController(
      bridge: FakePlaybackBridge(),
      initialQueue: DemoCatalog.tracks,
    );
    await tester.pumpWidget(RozzaApp(playback: playback));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ROZZA'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('A night drive,\nscored for you.'), findsOneWidget);
  });

  testWidgets('Arabic locale renders the shell RTL without overflow', (
    tester,
  ) async {
    final playback = PlaybackController(
      bridge: FakePlaybackBridge(),
      initialQueue: DemoCatalog.tracks,
    );
    await tester.pumpWidget(
      RozzaApp(playback: playback, locale: const Locale('ar')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
