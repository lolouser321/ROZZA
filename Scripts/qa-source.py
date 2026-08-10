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
for rid in ['app','tabbar','searchInput','results','minibar','npSheet','queueSheet','eventSheet','flowEnergy','likedTracks']:
    if rid not in seen: errors.append('missing required HTML id: '+rid)
if 'const DEBUG = false;' not in html: errors.append('production HTML DEBUG must be false')
if 'ROZZA 4.0.3 · SEARCH HOTFIX' not in html: errors.append('wrong visible version label')
if 'state.active=false;' not in html: errors.append('Flow failure rollback missing')
if 'const MIRROR_POOL_VERSION = 3;' not in html: errors.append('search mirror migration missing')
if 'pipedapi.syncpundit.io' not in html: errors.append('current CORS Piped seeds missing')
if "m.k === 'piped' ? '/healthcheck' : '/api/v1/stats'" not in html: errors.append('Piped healthcheck fix missing')
if "const existing=Q.items.findIndex(x=>trackKey(x)===trackKey(it))" not in html: errors.append('event backup de-duplication missing')
proj=(root/'project.yml').read_text()
for token in ['MARKETING_VERSION: 4.0.3','CURRENT_PROJECT_VERSION: 23','Resources/yt_background_bridge.js','path: rozza2.html']:
    if token not in proj: errors.append('project.yml missing: '+token)
app=(root/'Sources/ROZZAApp.swift').read_text()
if '#if DEBUG' not in app or 'DJLauncherButton(controller: dj)' not in app: errors.append('DJ test launcher is not DEBUG-gated')
if errors:
    print('ROZZA GOLD source QA FAILED:')
    for e in errors: print(' -',e)
    sys.exit(1)
print(f'ROZZA SEARCH HOTFIX source QA PASS — {len(p.ids)} ids, no duplicates, production debug UI gated.')
