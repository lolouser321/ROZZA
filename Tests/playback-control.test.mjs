import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const [controller, legacyManager, player] = await Promise.all([
  readFile(new URL("Sources/Playback/DJPlaybackController.swift", root), "utf8"),
  readFile(new URL("Sources/Playback/PlaybackManager.swift", root), "utf8"),
  readFile(new URL("rozza2.html", root), "utf8"),
]);

test("the bundled player JavaScript parses", () => {
  const inlineScripts = [...player.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
    .map((match) => match[1])
    .filter((source) => source.trim());
  assert.ok(inlineScripts.length > 0);
  for (const source of inlineScripts) assert.doesNotThrow(() => new Function(source));
});

test("DJPlaybackController is the only native remote-command owner", () => {
  assert.match(controller, /MPRemoteCommandCenter\.shared\(\)/);
  assert.doesNotMatch(legacyManager, /\.addTarget\s*\{/);
  for (const command of [
    "playCommand",
    "pauseCommand",
    "togglePlayPauseCommand",
    "nextTrackCommand",
    "previousTrackCommand",
    "changePlaybackPositionCommand",
  ]) {
    assert.match(controller, new RegExp(`center\\.${command}\\.isEnabled = true`));
  }
  assert.match(controller, /center\.skipForwardCommand\.isEnabled = false/);
  assert.match(controller, /center\.skipBackwardCommand\.isEnabled = false/);
});

test("a human pause invalidates every native recovery generation", () => {
  const pauseBranch = controller.slice(
    controller.indexOf("private func registerExplicitPlaybackIntent"),
    controller.indexOf("private func enforcePausedTransportAfterHumanPause"),
  );
  assert.match(pauseBranch, /hardUserPauseActive = true/);
  assert.match(pauseBranch, /resumeYouTubeAfterBackgroundTransition = false/);
  assert.match(pauseBranch, /resumeYouTubeAfterInterruption = false/);
  assert.match(pauseBranch, /backgroundResumeGeneration \+= 1/);
  assert.match(pauseBranch, /remoteCommandGeneration \+= 1/);
  assert.match(player, /wantPlay=false; lastExplicitPauseAt=Date\.now\(\);\s*clearTimeout\(recoveryT\);/);
  assert.match(player, /Coordinator\.cancelAutomaticRecovery\(\)/);
  assert.match(controller, /suspendAllWebMedia\(reason: reason\)/);
  assert.match(controller, /setAllMediaPlaybackSuspended\(true\)/);
});

test("transport and Now Playing observations never rewrite explicit intent", () => {
  const messenger = controller.slice(
    controller.indexOf("func handleYouTubeMessengerEvent"),
    controller.indexOf("func handlePlaybackIntent"),
  );
  const metadata = controller.slice(
    controller.indexOf("func updateNowPlaying(info:"),
    controller.indexOf("private func updateNowPlayingArtwork"),
  );
  assert.doesNotMatch(messenger, /youtubeWantsPlayback\s*=/);
  assert.doesNotMatch(metadata, /youtubeWantsPlayback\s*=/);
  assert.doesNotMatch(metadata, /hardUserPauseActive\s*=/);
});

test("real interruptions suspend without changing play intent and resume only the same session", () => {
  assert.doesNotMatch(controller, /Ignored AVAudioSession interruption for WebKit-owned YouTube/);
  assert.match(controller, /playbackControlPhase = \.systemInterrupted/);
  assert.match(controller, /resumeYouTubeAfterInterruption = youtubeWantsPlayback && !hardUserPauseActive/);
  assert.match(controller, /interruptedPlaybackSessionID == activePlaybackSessionID/);
  assert.match(controller, /shouldResume && resumeYouTubeAfterInterruption && youtubeWantsPlayback && !hardUserPauseActive && sameSession/);
  assert.match(controller, /setAllMediaPlaybackSuspended\(false\)/);
  assert.match(player, /suspend\(reason='system-interruption'\)[\s\S]*?if\(!wantPlay\) return false;[\s\S]*?cmd\('pauseVideo'/);
  assert.match(player, /deferPlay\(reason='play-during-interruption'\)/);
});

test("all automatic recovery paths are fenced during an interruption", () => {
  assert.match(player, /backgroundResumeIfWanted[\s\S]*?ROZZAInterruptionActive/);
  assert.match(player, /track-start-nudge-[\s\S]*?!ROZZAInterruptionActive/);
  assert.match(player, /attemptStartupRecovery\(\)[\s\S]*?!ROZZAInterruptionActive/);
  assert.match(player, /attemptForegroundRecovery\(\)[\s\S]*?!ROZZAInterruptionActive/);
  assert.match(controller, /scheduleBackgroundYouTubeResumeKicks[\s\S]*?!self\.genuineInterruptionActive/);
});

test("remote next and previous switch once and rely on playIndex autoplay", () => {
  assert.match(player, /next\(\)\{[\s\S]*?const before=Q\.idx;[\s\S]*?Coordinator\.next\(false\);[\s\S]*?ok:Q\.idx!==before/);
  assert.match(player, /previous\(\)\{[\s\S]*?const before=Q\.idx;[\s\S]*?Coordinator\.previousTrack\(\);[\s\S]*?ok:p>=0&&Q\.idx!==before/);
  assert.match(player, /if\(ROZZAInterruptionActive\) return \{ok:false,action:'next'/);
  assert.match(player, /if\(ROZZAInterruptionActive\) return \{ok:false,action:'previous'/);
  assert.match(player, /this\.playIndex\(n, true, auto\?'auto-next':'next-button'\)/);
  assert.match(player, /this\.playIndex\(p, true,'remote-previous-track'\)/);
});
