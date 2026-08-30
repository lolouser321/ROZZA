import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rozza/src/app.dart';
import 'package:rozza/src/data/demo_catalog.dart';
import 'package:rozza/src/playback/playback_controller.dart';
import 'package:rozza/src/widgets/artwork.dart';
import 'package:rozza/src/widgets/mini_player.dart';

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

  testWidgets('capture ROZZA phone shell', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = PlaybackController(
      bridge: FakePlaybackBridge(),
      initialQueue: DemoCatalog.tracks,
    );

    await tester.pumpWidget(RozzaApp(playback: playback));
    await tester.pump(const Duration(milliseconds: 700));

    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('goldens/rozza_home_phone.png'),
    );
  });

  testWidgets('capture ROZZA now playing', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final playback = PlaybackController(
      bridge: FakePlaybackBridge(),
      initialQueue: DemoCatalog.tracks,
    );

    await tester.pumpWidget(RozzaApp(playback: playback));
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile('goldens/rozza_now_playing_phone.png'),
    );
  });
}
