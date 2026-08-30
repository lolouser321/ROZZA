import 'package:flutter_test/flutter_test.dart';
import 'package:rozza/src/data/demo_catalog.dart';
import 'package:rozza/src/playback/playback_controller.dart';

import 'support/fake_playback_bridge.dart';

void main() {
  test('pause creates a hard human-pause intent until explicit play', () async {
    final bridge = FakePlaybackBridge();
    final controller = PlaybackController(
      bridge: bridge,
      initialQueue: DemoCatalog.tracks,
    );
    await controller.play();
    expect(controller.state.humanPauseActive, isFalse);
    await controller.pause();
    expect(controller.state.humanPauseActive, isTrue);
    expect(controller.state.isPlaying, isFalse);
    await controller.play();
    expect(controller.state.humanPauseActive, isFalse);
    expect(bridge.calls, containsAllInOrder(['play', 'pause', 'play']));
  });

  test('next and previous mutate the queue index exactly once', () async {
    final bridge = FakePlaybackBridge();
    final controller = PlaybackController(
      bridge: bridge,
      initialQueue: DemoCatalog.tracks,
    );
    expect(controller.state.queueIndex, 0);
    await controller.next();
    expect(controller.state.queueIndex, 1);
    await controller.previous();
    expect(controller.state.queueIndex, 0);
    expect(bridge.calls, containsAllInOrder(['next', 'previous']));
  });
}
