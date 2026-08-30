import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/data/demo_catalog.dart';
import 'src/playback/platform_playback_bridge.dart';
import 'src/playback/playback_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final playback = PlaybackController(
    bridge: PlatformPlaybackBridge(),
    initialQueue: DemoCatalog.tracks,
  );
  await playback.initialize();
  runApp(RozzaApp(playback: playback));
}
