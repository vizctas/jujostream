"""Re-render Focus blue painting from the ORIGINAL 1920x1080 MP4 frame.
Run on jujopc: python tools/focus_motion/remolinos.py
All intermediate/review output lives outside the repository. No image overlays.
"""
import glob
import math
import os
import subprocess
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(r'C:\Users\Jozh\focus-motion-review\azul-original-backup.mp4')
REVIEW = SRC.parent
TEMP = REVIEW / 'azul-ocho-remolinos-1080p.mp4'
PREVIEW = REVIEW / 'azul-ocho-remolinos-preview.mp4'
SHEET = REVIEW / 'azul-ocho-remolinos-sheet.jpg'
FFMPEG = glob.glob(r'C:\Users\Jozh\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg*\bin\ffmpeg.exe')[0]
N, FPS = 120, 24


def run():
    capture = cv2.VideoCapture(str(SRC))
    ok, frame = capture.read()
    capture.release()
    if not ok or frame.shape != (1080, 1920, 3):
        raise RuntimeError('Expected original full-resolution 1920x1080 first frame')
    h, w = frame.shape[:2]
    # Approved map: two original curls and six outer rings, never the spire-side halo.
    def feather(t):
        t = np.clip(t, 0, 1)
        return t*t*(3-2*t)

    curls = []
    for cx, cy, rx, ry, core, strength, offset, direction in (
        (.45, .21, .09, .09, 0, .13, 0., 1), (.61, .29, .08, .07, 0, .095, .55, 1),
        (.77, .09, .09, .115, .59, .135, .8, 1),   # 1 moon
        (.39, .45, .055, .09, .47, .082, 2.0, 1), # 2 valley star
        (.11, .07, .045, .07, .49, .145, 2.6, -1), # 3 left star
        (.27, .05, .05, .075, .53, .093, .3, 1),   # 4 upper star
        (.63, .10, .028, .045, .47, .105, 1.6, -1),# 5 small star
        (.90, .07, .05, .08, .33, .14, 3.3, -1),   # 6 right curl
    ):
        x, y = round(cx*w), round(cy*h)
        a, b = round(rx*w), round(ry*h)
        top, left = max(0,y-b), max(0,x-a)
        roi = np.s_[top:min(h,y+b+1), left:min(w,x+a+1)]
        iy, ix = np.mgrid[roi].astype(np.float32)
        u, v = (ix-x)/a, (iy-y)/b
        radius = np.hypot(u, v)
        weight = feather((1-radius)/(.16 if core else .48))
        if core:
            weight *= feather((radius-core)/.17)*feather(iy/(.018*h))
        if cy == .45:  # taper before the hill under the valley star
            weight *= feather((.51*h-iy)/(.025*h))
        phase = direction*np.arctan2(v, u) + 1.3*radius + offset
        curls.append((roi, u, v, a, b, x-left, y-top, strength*weight, phase))
    cmd = [FFMPEG,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','bgr24',
           '-s',f'{w}x{h}','-r',str(FPS),'-i','pipe:0','-an','-c:v','libx264',
           '-preset','medium','-crf','14','-bf','0','-pix_fmt','yuv420p','-movflags','+faststart',str(TEMP)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        for n in range(N):
            rendered = frame.copy()
            for roi, u, v, a, b, ox, oy, weight, phase in curls:
                # In image coordinates positive angle is clockwise; a positive
                # temporal phase sends the ripple counterclockwise. It closes at 2π.
                angle = weight * np.sin(phase + 2*math.pi*n/N)
                c, s = np.cos(angle), np.sin(angle)
                mx, my = ox+a*(u*c-v*s), oy+b*(u*s+v*c)
                warped = cv2.remap(frame[roi], mx, my, cv2.INTER_LINEAR,
                                   borderMode=cv2.BORDER_REPLICATE)
                np.copyto(rendered[roi], warped, where=(weight>0)[...,None])
            proc.stdin.write(rendered.tobytes())
            if (n+1)%24 == 0: print(f'frame {n+1}/{N}', flush=True)
        proc.stdin.close()
    except BrokenPipeError as exc:
        raise RuntimeError('ffmpeg encoder failed') from exc
    if proc.wait() != 0: raise RuntimeError('ffmpeg encoder returned error')
    subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-i',str(TEMP),
                    '-vf','scale=640:360:flags=lanczos','-an','-c:v','libx264',
                    '-preset','medium','-crf','11','-bf','0','-pix_fmt','yuv420p',
                    '-movflags','+faststart',str(PREVIEW)],check=True)
    video = cv2.VideoCapture(str(TEMP))
    tiles = []
    for index in (0, 30, 60, 90):
        video.set(cv2.CAP_PROP_POS_FRAMES,index)
        ok, image = video.read()
        if not ok: raise RuntimeError(f'Cannot decode contact frame {index}')
        image = cv2.resize(image,(640,360),interpolation=cv2.INTER_AREA)
        cv2.putText(image,f'{index/FPS:.2f}s',(16,34),cv2.FONT_HERSHEY_SIMPLEX,.8,(245,245,245),2,cv2.LINE_AA)
        tiles.append(image)
    video.release()
    sheet = np.vstack((np.hstack(tiles[:2]),np.hstack(tiles[2:])))
    if not cv2.imwrite(str(SHEET),sheet,[cv2.IMWRITE_JPEG_QUALITY,90]):
        raise RuntimeError('Cannot write sheet')
    print('render=',TEMP,'bytes=',TEMP.stat().st_size,flush=True)
    print('preview=',PREVIEW,'bytes=',PREVIEW.stat().st_size,flush=True)
    print('sheet=',SHEET,'bytes=',SHEET.stat().st_size,flush=True)


if __name__ == '__main__':
    run()
