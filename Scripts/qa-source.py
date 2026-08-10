#!/usr/bin/env python3
from pathlib import Path
from html.parser import HTMLParser
import re, sys
root=Path(__file__).resolve().parents[1]
html=(root/'rozza2.html').read_text(encoding='utf-8')
errors=[]
class P(HTMLParser):
    def __init__(self): super().__init__(); self.ids=[]
    def handle_starttag(self,tag,attrs):
        for k,v in attrs:
            if k=='id' and v:self.ids.append(v)
p=P();p.feed(html)
seen=set();dups=[]
for x in p.ids:
    if x in seen and x not in dups:dups.append(x)
    seen.add(x)
if dups: errors.append('duplicate HTML ids: '+', '.join(dups))
for rid in ['app','tabbar','searchInput','results','minibar','npSheet','queueSheet','eventSheet','driveSheet','drivePrev','drivePlay','driveNext','flowEnergy','likedTracks','vehicleControlStatus','copyVehicleDiagnosticsBtn']:
    if rid not in seen: errors.append('missing required HTML id: '+rid)
if 'const DEBUG = false;' not in html: errors.append('production HTML DEBUG must be false')
if 'ROZZA 4.1.0 · DRIVE REMOTE' not in html: errors.append('wrong visible version label')
if 'state.active=false;' not in html: errors.append('Flow failure rollback missing')
if "const existing=Q.items.findIndex(x=>trackKey(x)===trackKey(it))" not in html: errors.append('event backup de-duplication missing')

if "window.ROZZANativeControls.remote" not in html: errors.append('unified remote command dispatcher missing')
if "queueIndex: Math.max(0,Q.idx)" not in html or "queueCount: Q.items.length" not in html: errors.append('native playback queue metadata missing')
if "continuousPlayback:true" not in html: errors.append('continuous playback default missing')
if 'data-set="continuousPlayback"' not in html: errors.append('continuous playback setting UI missing')
if "remoteReason='remote-'" not in html: errors.append('background remote-track pulse missing')
if "DRIVE MODE" not in html or "renderDriveMode" not in html: errors.append('Drive Mode UI missing')
if 'previousTrack(){' not in html or "Coordinator.previousTrack()" not in html: errors.append('vehicle previous-track semantics missing')
if 'window.ROZZARemoteDiagnostics=RemoteDiagnostics' not in html: errors.append('vehicle command diagnostics missing')
if "postMessage({ clear:true" not in html: errors.append('native Now Playing clear handoff missing')
if "if(IS_NATIVE_SHELL || !('mediaSession' in navigator) || !current) return;" not in html: errors.append('native shell still risks duplicate Web MediaSession handlers')

if 'window.ROZZANativeNetwork=ROZZANativeNetwork' not in html: errors.append('native network fallback missing')
if 'const MIRROR_POOL_VERSION = 4;' not in html: errors.append('mirror pool migration missing')
if 'pipedapi.orangenet.cc' not in html: errors.append('current uptime seed set missing')
if 'setTimeout(()=>SmartQueue.ensure(false),700)' in html: errors.append('Smart Queue still races initial player load')
if "cmd(autoplay ? 'loadVideoById' : 'cueVideoById', [id])" not in html: errors.append('persistent YouTube player switch missing')
if "event:'ROZZA_BACKGROUND_PULSE'" not in html: errors.append('background pulse handoff missing')
if "window.ROZZANativeNetwork=ROZZANativeNetwork" not in html: errors.append('native network fallback missing')
background=(root/'Resources/yt_background_bridge.js').read_text()
if 'ROZZA_BACKGROUND_PULSE' not in background: errors.append('iframe background pulse receiver missing')
if 'MAX_RECOVERIES = 8' not in background: errors.append('transition recovery budget not updated')
web=(root/'Sources/Web/ROZZAWebAppView.swift').read_text()
if 'name: "networkProxy"' not in web or 'proxyJSONRequest' not in web: errors.append('native URLSession network proxy missing')

dj=(root/'Sources/Playback/DJPlaybackController.swift').read_text()
if 'let delays: [Double] = [0.05, 0.18, 0.45, 0.90, 1.50, 2.40, 3.60]' not in dj: errors.append('native background transition schedule missing')
if 'guard let self, self.isPresented else { return }' not in dj: errors.append('debug polling still runs all the time')
if 'dispatchRemoteCommand' not in dj or 'ROZZA.RemoteCommand' not in dj: errors.append('native remote execution window missing')
if 'nextTrackCommand.isEnabled = true' not in dj or 'previousTrackCommand.isEnabled = true' not in dj: errors.append('native next/previous commands missing')
if 'MPNowPlayingInfoPropertyPlaybackQueueIndex' not in dj or 'MPNowPlayingInfoPropertyPlaybackQueueCount' not in dj: errors.append('native queue metadata publishing missing')
if 'updateNowPlayingArtwork' not in dj: errors.append('native artwork publishing missing')
if 'lastNowPlayingTrackID' not in dj or 'nowPlayingInfo = nil' not in dj: errors.append('stale Now Playing cleanup missing')
proj=(root/'project.yml').read_text()
for token in ['MARKETING_VERSION: 4.1.0','CURRENT_PROJECT_VERSION: 26','Resources/yt_background_bridge.js','path: rozza2.html']:
    if token not in proj: errors.append('project.yml missing: '+token)
workflow=(root/'.github/workflows/ios-ipa.yml').read_text()
if 'working-directory: ios' in workflow or 'path: ios/ROZZA-unsigned.ipa' in workflow: errors.append('GitHub workflow still builds obsolete ios subproject')
if './Scripts/build-unsigned-ipa.sh' not in workflow: errors.append('GitHub workflow does not use canonical root build')
if (root/'ios').exists(): errors.append('obsolete duplicate ios project still present')
app=(root/'Sources/ROZZAApp.swift').read_text()
if '#if DEBUG' not in app or 'DJLauncherButton(controller: dj)' not in app: errors.append('DJ test launcher is not DEBUG-gated')
if errors:
    print('ROZZA PERFORMANCE-AUTOPLAY source QA FAILED:')
    for e in errors: print(' -',e)
    sys.exit(1)
print(f'ROZZA DRIVE-REMOTE source QA PASS — {len(p.ids)} ids, no duplicates, remote transport + Drive Mode guards present.')
