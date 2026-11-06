#!/usr/bin/env python3
"""Deterministic, loopback-only browser fixtures. Never uses personal accounts."""
import http.server
import io
import json
import math
import struct
import wave
import zlib
from urllib.parse import urlparse

STYLE = """<meta name="viewport" content="width=device-width"><style>
:root{color-scheme:light dark}*{box-sizing:border-box}body{margin:0;padding:64px;font:16px/1.6 system-ui;background:light-dark(#f7f5fb,#1d1c24);color:light-dark(#282433,#f0edf8)}main{max-width:780px;margin:auto}h1{font-size:44px;line-height:1.15;letter-spacing:-1.5px}small{color:#9487ba;letter-spacing:2px}a{color:light-dark(#705f9c,#c0afea)}section{padding:24px;border:1px solid #8883;border-radius:16px;margin:20px 0;background:light-dark(#fff,#25232e)}button,input{font:inherit;padding:10px 16px;border-radius:8px;border:1px solid #8885}button{cursor:pointer}nav{display:flex;gap:24px;flex-wrap:wrap}audio{width:100%}.wide{width:100%;overflow:auto}.wide div{width:2200px;height:90px;background:linear-gradient(90deg,#b7a5dc,#91c4b0,#e0b292);padding:24px;color:#222}textarea{font:inherit;width:100%;height:120px;padding:14px}code{font-family:ui-monospace,monospace}</style>"""

def page(title, body, head=''):
    return (f"<!doctype html><html><head><title>{title}</title>{STYLE}{head}</head><body><main>{body}</main></body></html>").encode()

def favicon_png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\x00' + b''.join(bytes((33, 199, 139, 255)) if 2 <= x < 14 and 2 <= y < 14 else bytes((0, 0, 0, 0)) for x in range(16)) for y in range(16))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urlparse(self.path).path
        headers = {}
        content_type = 'text/html; charset=utf-8'
        if path == '/audio.wav':
            stream = io.BytesIO()
            with wave.open(stream, 'wb') as output:
                output.setparams((1, 2, 22050, 0, 'NONE', 'not compressed'))
                output.writeframes(b''.join(struct.pack('<h', int(1400 * math.sin(2 * math.pi * 220 * n / 22050))) for n in range(22050 * 4)))
            body = stream.getvalue(); content_type = 'audio/wav'
        elif path == '/download':
            body = b'VEIL deterministic download fixture.\n'; content_type = 'text/plain'
            headers['Content-Disposition'] = 'attachment; filename="veil-fixture.txt"'
        elif path == '/favicon.ico':
            self.send_error(404);return
        elif path == '/favicon.png':
            body = favicon_png(); content_type = 'image/png'
        elif path == '/icons':
            body = page('Mint favicon fixture', '<small>VEIL QA</small><h1>A little mint.</h1><p>This page supplies a deterministic green site icon.</p><a href="/page/after-icon">Another page</a>', '<link rel="icon" type="image/png" href="/favicon.png">')
        elif path == '/form':
            body = page('Draft fixture', '''<small>VEIL QA</small><h1>Keep your words.</h1><section><label>Unsaved draft<textarea id="draft" placeholder="Write a synthetic draft"></textarea></label><button id="save">Save draft</button><p id="status">No changes</p></section><a href="/">Back home</a><script>let dirty=false;draft.addEventListener('input',()=>{dirty=true;document.getElementById('status').textContent='Unsaved changes'});save.onclick=()=>{dirty=false;document.getElementById('status').textContent='Saved';document.dispatchEvent(new Event('veil-test-saved'))};addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue=''}})</script>''')
        elif path == '/media':
            body = page('A small loop', '''<small>VEIL QA</small><h1>A small loop.</h1><section><audio id="audio" controls loop src="/audio.wav"></audio><p>Play this synthetic tone, then switch tabs or Spaces.</p></section><a href="/">Back home</a><script>navigator.mediaSession.metadata=new MediaMetadata({title:'A small loop',artist:'VEIL fixtures'});navigator.mediaSession.setActionHandler('play',()=>audio.play());navigator.mediaSession.setActionHandler('pause',()=>audio.pause());</script>''')
        elif path == '/fullscreen':
            body=page('Fullscreen fixture','<small>VEIL QA</small><h1>A little more screen.</h1><section><button id="enter">Enter fullscreen</button><p id="mode">Windowed</p></section><script>enter.onclick=()=>document.documentElement.requestFullscreen();document.addEventListener("fullscreenchange",()=>{mode.textContent=document.fullscreenElement?"Fullscreen":"Windowed"})</script>')
        elif path == '/scroll':
            body = page('Horizontal scrolling', '''<small>VEIL QA</small><h1>Scroll stays scroll.</h1><section><div class="wide"><div>Horizontal canvas → → →</div></div><p>A two-finger scroll inside the canvas must not navigate back.</p></section><a href="/">Back home</a>''')
        elif path.startswith('/bench/'):
            name=path.rsplit('/',1)[-1]
            body=page('Benchmark '+name,'<small>VEIL QA · DETERMINISTIC</small><h1>Fixture '+name+'</h1><section><p>8 MiB of initialized page data, a bounded DOM, and no animation or network polling.</p>'+''.join('<p>Row '+str(i)+' · A quiet synthetic browsing fixture.</p>' for i in range(100))+'</section><script>window.fixtureData=new Uint8Array(8*1024*1024);fixtureData.fill(61);</script>')
        elif path.startswith('/page/'):
            name = path.rsplit('/', 1)[-1]
            body = page('Page ' + name, f'<small>VEIL QA</small><h1>Page {name}</h1><section><p>Navigation history and tab organization fixture.</p><a href="/page/next">Next page</a></section><a href="/">Home</a>')
        elif path == '/cookie':
            headers['Set-Cookie'] = 'veil_fixture=isolated; Path=/; SameSite=Lax'
            body = page('Cookie fixture', '<h1>Profile fixture</h1><code id="cookie"></code><script>cookie.textContent=document.cookie</script>')
        else:
            body = page('A little more room', '''<small>VEIL · LOCAL FIXTURE</small><h1>Your internet,<br>with room to breathe.</h1><p>A real Chromium page inside a native macOS shell.</p><section><nav><a href="/page/one">Navigation</a><a href="/form">Unsaved work</a><a href="/media">Media</a><a href="/scroll">Horizontal scroll</a><a href="/download">Download</a><a href="/cookie">Cookies</a><a href="/page/popup" target="_blank">New-tab link</a></nav></section><section><h2>Try the everyday flow.</h2><p>Open ⌘T, pin a tab with ⌘D, make a Space, drag a tab, then close and reopen VEIL.</p></section>''')
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        for key, value in headers.items(): self.send_header(key, value)
        self.end_headers();self.wfile.write(body)

if __name__ == '__main__':
    print('VEIL fixtures at http://127.0.0.1:8765', flush=True)
    http.server.ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
