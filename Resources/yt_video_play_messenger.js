function videoTags() {
    return document.getElementsByTagName("video");
}

function playVideo() {
    let videos = videoTags();
    if (videos.length > 0) {
        let video = videos[0];
        video.play();
    }
}
function pauseVideo() {
    var video = document.querySelector('video');
    if (video) {
        video.pause();
        return true;
    }
    // Fallback
    var videos = document.querySelectorAll('video, video[src]');
    if (videos.length > 0) {
        videos[0].pause();
        return true;
    }
    return false;
}

function playVideoWithTime(currentTime) {
    let videos = videoTags();
    
    if (videos.length > 0) {
        let video = videos[0];
        video.currentTime = currentTime;
        video.play();
    }
}

function isVideoPlaying(videoElement) {
    return !videoElement.paused && !videoElement.ended && videoElement.currentTime > 0;
}

/* Close fullscreen */
function closeFullscreen() {
  if (document.exitFullscreen) {
    document.exitFullscreen();
  } else if (document.webkitExitFullscreen) { /* Safari */
    document.webkitExitFullscreen();
  } else if (document.msExitFullscreen) { /* IE11 */
    document.msExitFullscreen();
  }
}

function exitPiP() {
    if (document.pictureInPictureElement) {
        document.exitPictureInPicture();
    }
}

function requestPictureInPicture() {
    var videos = videoTags();
    if (videos.length > 0) {
        let video = videos[0];
        if (isVideoPlaying(video)) {
            video.requestPictureInPicture()
            .then(pipWindow => {
                // Handle the PiP window here if needed
                console.log('Entered Picture-in-Picture mode.');
            })
            .catch(error => {
                // Handle errors here
                console.error('Error trying to enter Picture-in-Picture mode:', error);
            });
        }
    }
}

function pictureIsShow() {
    let videos = videoTags();
    if (videos.length > 0) {
        let isShow = false;
        for (let i = 0; i < videos.length; i++) {
            if (isVideoPlaying(videos[i])) {
                isShow = document.pictureInPictureElement === videos[i];
                break;
            }
        }
        return isShow;
    } else {
        return false;
    }
}

function videoControlsIsShow() {
    let videos = videoTags();
    if (videos.length > 0) {
        let isShow = false;
        for (let i = 0; i < videos.length; i++) {
            if (isVideoPlaying(videos[i])) {
                isShow = videos[i].controls;
                break;
            }
        }
        return isShow;
    } else {
        return false;
    }
}

function mobileTopBar() {
    var foundElement = null;
    var found = false;
    const headers = document.getElementsByTagName("header");
    for (var i = 0; i < headers.length; i++) {
        const item = headers.item(i);
        var classes = item.className != undefined ? item.className.split(" ") : [];
        for (var j = 0, jl = classes.length; j < jl; j++) {
            if (classes[j] == "mobile-topbar-header") {
                found = true;
                foundElement = item;
                break;
            }
        }
        if (found) {
            break;
        }
    }
    return foundElement;
}

function youtubeControlsIsShow() {
    const playerControlContainer = document.getElementById('player-control-overlay');
    const youtubeControls = playerControlContainer.getElementsByClassName('player-controls-content');
    let isShow = false;
    if (youtubeControls.length > 0) {
        let controls = youtubeControls[0];
        const computedStyle = window.getComputedStyle(controls);
        isShow = computedStyle.visibility === "visible";
    }
    return isShow;
}

function removeOpenAppButton() {
    const header = mobileTopBar();
    const buttons = header.getElementsByTagName("button");
    for (let i=0; i<buttons.length; i++) {
        var str = buttons.item(i).className;
        str = str.replace(/^\s+|\s+$/g, '');
        if (str == "open-app-button") {
            buttons.item(i).remove();
        }
    }
}

function setupVideoPlayingHandler() {
    var hasTouch = false;
    window.addEventListener('click', function handleTouch() {
        hasTouch = true;
    });
    try {
        var videos = videoTags();
        let video = videos[0];
        var rect = video.getBoundingClientRect();
        console.log(rect);
        video.videoId
        var ctrlHeight = 40;
        video.setAttribute('playsinline', '');
        video.setAttribute('webkit-playsinline', '');
        video.autoplay = false;
        video.muted = false;
        
        let isPaused = video.paused;
//        let currentTime = video.currentTime;
        var message = "VideoIsPlaying_";
//        let isControlsShow = youtubeControlsIsShow();
        
        let videoId = getVideoId()
                
//        message += isPaused + "_" + currentTime + "_" + hasTouch + "_" + isControlsShow;
        
        if (!videoId) return;

        let payload = {
            event: 'VideoIsPlaying',
            videoId: videoId,
            paused: isPaused,
            hasTouch: hasTouch
        };
        
        
        webkit.messageHandlers.callbackHandler.postMessage(payload);
        removeOpenAppButton();
    } catch (error) {
        console.log(error);
    }
}

function setupVideoPlayingListener() {
    // If we have video tags, setup onplaying handler
    if (videoTags().length > 0) {
        setupVideoPlayingHandler();
    }

    // Otherwise, wait for 100s and check again.
    setTimeout(setupVideoPlayingListener, 100);
}
setupVideoPlayingListener();

//document.cookie="VISITOR_INFO1_LIVE=oKckVSqvaGw; path=/; domain=.youtube.com";

function getVideoId() {
    try {
        if (location.pathname.startsWith('/shorts/')) {
            return location.pathname.split('/')[2];
        }
        return new URL(location.href).searchParams.get('v');
    } catch {
        return null;
    }
}




/* ============================
   🔥 YouTube Fullscreen Listener
   ============================ */

(function () {

    let lastState = "none";
    let lastEmitTime = 0;

    function notify(state) {

        const now = Date.now();

        // ❌ cùng trạng thái → không gửi
        if (state === lastState) return;

        // ❌ spam trong < 300ms → bỏ
        if (now - lastEmitTime < 300) return;

        lastState = state;
        lastEmitTime = now;

        try {
            webkit.messageHandlers.callbackHandler.postMessage({
                event: "YouTubeFullscreen",
                state: state
            });
        } catch (e) {}
    }


    function hookVideoFullscreen(video) {
//        if (video.paused) {
//            video.play();
//        }
        
        
        function ensurePlaying() {
            if (video.paused) {
                video.play().catch(()=>{});
            }
        }
        
        if (typeof video.webkitPresentationMode !== "undefined") {
           
            video.addEventListener("webkitpresentationmodechanged", function () {
                ensurePlaying()
                if (video.webkitPresentationMode === "fullscreen") {
                    notify("enter");
                } else {
                    notify("exit");
                }
            });
        }
        
        video.addEventListener("fullscreenchange", function () {
            ensurePlaying();
            
            if (document.fullscreenElement === video) {
                notify("enter");
            } else {
                notify("exit");
            }
        });
    }

    function scan() {
        document
            .querySelectorAll("video")
            .forEach(v => hookVideoFullscreen(v));
    }

    scan();

    const obs = new MutationObserver(scan);
    obs.observe(document.body, { childList: true, subtree: true });

})();


//function forcePlayAfterSeek() {
//    let v = document.querySelector("video");
//    if (!v) return;
//
//    v.addEventListener("seeking", function() {
//        // YouTube thường pause ở đây
//        setTimeout(function() {
//            if (v.paused) {
//                v.play();
//            }
//        }, 150);
//    });
//
//    v.addEventListener("seeked", function() {
//        setTimeout(function() {
//            if (v.paused) {
//                v.play();
//            }
//        }, 150);
//    });
//}
//
//function waitVideoThenHook() {
//    let v = document.querySelector("video");
//    if (v) {
//        forcePlayAfterSeek();
//        return;
//    }
//    setTimeout(waitVideoThenHook, 300);
//}
//
//waitVideoThenHook();

function focustApp() {
    window.onblur = null;
    window.blurred = false;

    document.hasFocus = function () {return true;};
    window.onFocus = function () {return true;};

    Object.defineProperty(document, "hidden", { value : false});
    Object.defineProperty(document, "mozHidden", { value : false});
    Object.defineProperty(document, "msHidden", { value : false});
    Object.defineProperty(document, "webkitHidden", { value : false});
    Object.defineProperty(document, 'visibilityState', { get: function () { return "visible"; } });

    document.onvisibilitychange = undefined;

    for (event_name of ["visibilitychange",
                        "webkitvisibilitychange",
                        "blur"
//                        "mozvisibilitychange",
//                        "msvisibilitychange"
                       ]) {
      window.addEventListener(event_name, function(event) {
            event.stopImmediatePropagation();
        }, true);
    }
}

focustApp()

//for (event_name of ["visibilitychange", "webkitvisibilitychange", "blur", "focus"]) {
//  window.addEventListener(event_name, function(event) {
//        event.stopImmediatePropagation();
//    }, true);
//}
//"""

function setupPlayPauseListener() {
    // Tìm video element
    var videos = videoTags();
    if (!videos || videos.length === 0) {
        // Chưa có video → thử lại sau 500ms
        setTimeout(setupPlayPauseListener, 500);
        return;
    }

    var video = videos[0];

    // Nếu đã attach rồi thì bỏ qua
    if (video._playPauseListenerAttached) return;
    video._playPauseListenerAttached = true;

    video.addEventListener('play', function() {
        webkit.messageHandlers.callbackHandler.postMessage({
            event: 'VideoPlay',
            videoId: getVideoId(),
            currentTime: video.currentTime,
            paused: false
        });
    });

    video.addEventListener('pause', function() {
        if (video.ended) return;
        webkit.messageHandlers.callbackHandler.postMessage({
            event: 'VideoPause',
            videoId: getVideoId(),
            currentTime: video.currentTime,
            paused: true
        });
    });

    // YouTube đôi khi replace video element khi next video
    // → dùng MutationObserver để re-attach nếu element bị thay
    var observer = new MutationObserver(function() {
        var newVideos = videoTags();
        if (!newVideos || newVideos.length === 0) return;
        var newVideo = newVideos[0];
        if (!newVideo._playPauseListenerAttached) {
            observer.disconnect();
            setupPlayPauseListener(); // re-attach vào element mới
        }
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true
    });
}
