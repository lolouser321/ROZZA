(() => {
  const host = String(window.location.hostname || '').toLowerCase();
  if (!/(^|\.)youtube(-nocookie)?\.com$/.test(host)) return;
  if (window.__rozzaBackgroundBridgeInstalled) return;
  window.__rozzaBackgroundBridgeInstalled = true;

  let enabled = false;
  let shouldPlay = false;
  let currentVideo = null;
  let intendedVideoId = null;
  let observer = null;
  let recoveryTimes = [];
  const recoveryTimers = new Set();
  const RECOVERY_WINDOW_MS = 12000;
  const MAX_RECOVERIES = 8;

  function emit(event, extra) {
    try {
      window.webkit?.messageHandlers?.callbackHandler?.postMessage({
        event,
        videoId: intendedVideoId || getVideoId(),
        ...(extra || {})
      });
    } catch (_) {}
  }

  function getVideoId() {
    try {
      const embed = window.location.pathname.match(/^\/embed\/([A-Za-z0-9_-]{11})/);
      if (embed) return embed[1];
      if (window.location.pathname.startsWith('/shorts/')) return window.location.pathname.split('/')[2] || null;
      return new URL(window.location.href).searchParams.get('v');
    } catch (_) {
      return null;
    }
  }

  function findDescriptor(obj, name) {
    let p = obj;
    while (p) {
      const d = Object.getOwnPropertyDescriptor(p, name);
      if (d) return d;
      p = Object.getPrototypeOf(p);
    }
    return null;
  }

  const hiddenDescriptor = findDescriptor(document, 'hidden');
  const visibilityDescriptor = findDescriptor(document, 'visibilityState');
  const webkitHiddenDescriptor = findDescriptor(document, 'webkitHidden');

  function nativeValue(descriptor, fallback) {
    try {
      if (descriptor?.get) return descriptor.get.call(document);
      if (Object.prototype.hasOwnProperty.call(descriptor || {}, 'value')) return descriptor.value;
    } catch (_) {}
    return fallback;
  }

  function installConditionalDocumentProperty(name, descriptor, backgroundValue, fallback) {
    try {
      Object.defineProperty(document, name, {
        configurable: true,
        enumerable: descriptor?.enumerable ?? true,
        get() {
          return enabled ? backgroundValue : nativeValue(descriptor, fallback);
        }
      });
      return true;
    } catch (error) {
      emit('BackgroundBridgeError', { stage: 'define-' + name, message: String(error) });
      return false;
    }
  }

  // Install conditional getters once at document start. They are transparent
  // while the bridge is disabled and only report a visible document during an
  // explicitly armed ROZZA background session.
  installConditionalDocumentProperty('hidden', hiddenDescriptor, false, false);
  installConditionalDocumentProperty('visibilityState', visibilityDescriptor, 'visible', 'visible');
  if (webkitHiddenDescriptor) installConditionalDocumentProperty('webkitHidden', webkitHiddenDescriptor, false, false);

  function armFromFirstLifecycleEvent(event) {
    // Intent is synchronized while ROZZA is still foregrounded. Because this
    // script is injected at document start, its capture listener sees the
    // first iOS blur/visibility event before normal YouTube page handlers.
    // Arm *at that boundary* so the page never gets a chance to interpret the
    // transition as an instruction to pause. No foreground video polling or
    // second playback state machine is introduced.
    if (enabled || !shouldPlay) return;
    enabled = true;
    startObserver();
    const video = scanVideo();
    emit('BackgroundBridgeAutoArmed', {
      reason: event?.type || 'lifecycle',
      paused: video ? !!video.paused : null,
      currentTime: video?.currentTime || 0
    });
    if (video && video.paused) {
      scheduleRecovery(video, 'first-lifecycle-event', 0);
    }
  }

  function suppressLifecycleEvent(event) {
    if (!enabled && shouldPlay) armFromFirstLifecycleEvent(event);
    if (!enabled) return;
    try {
      event.stopImmediatePropagation();
      event.stopPropagation();
    } catch (_) {}
  }

  // Capture-phase listeners are always present but completely inert during
  // ordinary foreground playback. `shouldPlay` is only intent metadata. The
  // bridge arms itself at the first actual lifecycle boundary, eliminating
  // the cross-frame/native-callback race that previously left one PAUSE for
  // the user to clear manually from Control Center.
  document.addEventListener('visibilitychange', suppressLifecycleEvent, true);
  document.addEventListener('webkitvisibilitychange', suppressLifecycleEvent, true);
  window.addEventListener('blur', suppressLifecycleEvent, true);

  function pruneRecoveries() {
    const cutoff = Date.now() - RECOVERY_WINDOW_MS;
    recoveryTimes = recoveryTimes.filter(t => t > cutoff);
  }

  function recover(video, reason) {
    if (!enabled || !shouldPlay || !video || video.ended || !video.paused) return;
    pruneRecoveries();
    if (recoveryTimes.length >= MAX_RECOVERIES) {
      emit('BackgroundRecoveryBudgetSpent', { reason, count: recoveryTimes.length, currentTime: video.currentTime || 0 });
      return;
    }
    recoveryTimes.push(Date.now());
    emit('BackgroundRecovery', { reason, attempt: recoveryTimes.length, currentTime: video.currentTime || 0 });
    try {
      const p = video.play();
      if (p && typeof p.catch === 'function') {
        p.catch(error => emit('BackgroundBridgeError', { stage: 'video-play', message: String(error) }));
      }
    } catch (error) {
      emit('BackgroundBridgeError', { stage: 'video-play-sync', message: String(error) });
    }
  }

  function cancelRecoveryTimers(reason) {
    recoveryTimers.forEach(timer => clearTimeout(timer));
    recoveryTimers.clear();
    emit('BackgroundRecoveryCancelled', { reason: reason || 'cancelled' });
  }

  function scheduleRecovery(video, reason, delay) {
    const timer = setTimeout(() => {
      recoveryTimers.delete(timer);
      recover(video, reason);
    }, delay);
    recoveryTimers.add(timer);
  }

  function onVideoPause() {
    const video = currentVideo;
    emit('BackgroundVideoPause', {
      enabled,
      shouldPlay,
      currentTime: video?.currentTime || 0,
      ended: !!video?.ended
    });
    if (enabled && shouldPlay && video && !video.ended) {
      // A Home/lock transition can produce more than one native pause pulse.
      // These are bounded transition retries, not a permanent background loop.
      [70, 260, 700].forEach(delay => scheduleRecovery(video, 'pause-event-' + delay, delay));
    }
  }

  function onVideoPlaying() {
    const video = currentVideo;
    cancelRecoveryTimers('playing-confirmed');
    emit('BackgroundVideoPlaying', { currentTime: video?.currentTime || 0 });
  }

  function attachVideo(video) {
    if (!video || video === currentVideo) return;
    if (currentVideo) {
      try {
        currentVideo.removeEventListener('pause', onVideoPause, true);
        currentVideo.removeEventListener('playing', onVideoPlaying, true);
      } catch (_) {}
    }
    currentVideo = video;
    currentVideo.addEventListener('pause', onVideoPause, true);
    currentVideo.addEventListener('playing', onVideoPlaying, true);
    emit('BackgroundVideoAttached', { paused: !!video.paused, currentTime: video.currentTime || 0 });
  }

  function scanVideo() {
    const video = document.querySelector('video');
    if (video) attachVideo(video);
    return video || currentVideo;
  }

  function startObserver() {
    if (observer) return;
    observer = new MutationObserver(() => scanVideo());
    try { observer.observe(document.documentElement, { childList: true, subtree: true }); } catch (_) {}
  }

  function stopObserver() {
    if (!observer) return;
    observer.disconnect();
    observer = null;
  }

  function setMode(nextEnabled, nextShouldPlay, reason) {
    const wasEnabled = enabled;
    enabled = !!nextEnabled;
    shouldPlay = !!nextShouldPlay;
    if (enabled && !wasEnabled) recoveryTimes = [];
    if (!enabled) {
      cancelRecoveryTimers(reason || 'foreground');
      stopObserver();
      recoveryTimes = [];
      emit('BackgroundBridgeState', { enabled: false, shouldPlay: false, reason: reason || 'foreground' });
      return;
    }

    startObserver();
    const video = scanVideo();
    emit('BackgroundBridgeState', {
      enabled: true,
      shouldPlay,
      reason: reason || 'background',
      paused: video ? !!video.paused : null,
      currentTime: video?.currentTime || 0
    });

    // Do not run a permanent timer. One immediate check plus the real pause
    // event above is enough to recover a lifecycle-induced pause without
    // recreating Pure Tube's 100 ms foreground polling loop.
    if (video && shouldPlay) {
      scheduleRecovery(video, 'background-arm', 80);
    }
  }

  window.addEventListener('message', event => {
    let data = event.data;
    try { if (typeof data === 'string') data = JSON.parse(data); } catch (_) { return; }
    if (!data) return;
    if (data.videoId) intendedVideoId = String(data.videoId);
    if (data.event === 'ROZZA_BACKGROUND_INTENT') {
      shouldPlay = !!data.shouldPlay;
      if (!shouldPlay) cancelRecoveryTimers('explicit-pause-intent');
      emit('BackgroundIntent', { shouldPlay, reason: data.reason || 'intent-sync' });
      return;
    }
    if (data.event === 'ROZZA_BACKGROUND_PULSE') {
      shouldPlay = !!data.shouldPlay;
      if (!enabled || !shouldPlay) return;
      startObserver();
      const video = scanVideo();
      emit('BackgroundPulse', {
        reason: data.reason || 'native-pulse',
        paused: video ? !!video.paused : null,
        currentTime: video?.currentTime || 0
      });
      if (video && video.paused && !video.ended) recover(video, 'native-pulse');
      return;
    }
    if (data.event !== 'ROZZA_BACKGROUND_MODE') return;
    setMode(data.enabled, data.shouldPlay, data.reason);
  }, true);

  emit('BackgroundBridgeInstalled', { href: window.location.href });
})();
