"""Render a subtle, looping rain overlay on a Focus still-image MP4.

Run on JUJOPC with Python (cv2, numpy) and WinGet FFmpeg available:
  python tools/focus_motion/lluvia.py --source <original.mp4> --output-dir <review-dir>
The scene frame is kept unchanged; rain is restricted to sky/edge/foreground zones.
"""
import argparse
import glob
import math
import subprocess
from pathlib import Path

import cv2
import numpy as np


def ffmpeg_path():
    matches = glob.glob(r"C:\Users\Jozh\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg*\bin\ffmpeg.exe")
    if not matches:
        raise FileNotFoundError("WinGet FFmpeg executable not found")
    return matches[0]


def run(source: Path, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    temp, preview, sheet = out_dir / "cabana-render.mp4", out_dir / "cabana-preview.mp4", out_dir / "cabana-sheet.jpg"
    cap = cv2.VideoCapture(str(source))
    ok, original = cap.read()
    cap.release()
    if not ok:
        raise RuntimeError(f"Cannot decode source: {source}")
    h, w = original.shape[:2]
    fps, frames = 24, 120
    yy, xx = np.mgrid[0:h, 0:w]
    # Sky and bottom foreground only. This intentionally avoids the cabin, its roof/eaves,
    # walls, windows and surrounding central landscape entirely without guessing its bounds.
    allowed = (yy < int(.25*h)) | (yy > int(.87*h))
    # Edge exclusions leave the cabin's central structure, roof and immediate eaves untouched.
    rng = np.random.default_rng(20261125)
    streams = []
    for count, length, velocity, thickness, alpha, color in (
        # Integer full-frame traversals over five seconds make each stream periodic.
        (115, .030*h, .20*h, 1, .22, (178, 190, 194)),
        (62, .050*h, .40*h, 2, .13, (205, 211, 213)),
    ):
        xs = rng.uniform(0, w, count).astype(np.float32)
        # Uniform phase over a 5-second torus guarantees continuous wraparound.
        ys = rng.uniform(0, h, count).astype(np.float32)
        lean = rng.uniform(-.065, -.025, count).astype(np.float32)  # rain slants left as it falls
        streams.append((xs, ys, lean, length, velocity, thickness, alpha, color))
    cmd = [ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24",
           "-s", f"{w}x{h}", "-r", str(fps), "-i", "pipe:0", "-an", "-c:v", "libx264", "-preset", "medium",
           "-crf", "19", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(temp)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for n in range(frames):
        t = n / frames
        layer = np.zeros_like(original)
        mask = np.zeros((h, w), dtype=np.uint8)
        for xs, ys, lean, length, velocity, thickness, alpha, color in streams:
            x = xs.astype(np.int32)
            y = np.mod(ys + velocity * t * 5, h).astype(np.int32)
            for xi, yi, slant in zip(x, y, lean):
                x2, y2 = int(xi + slant * length), int(yi + length)
                cv2.line(layer, (int(xi), int(yi)), (x2, y2), color, thickness, cv2.LINE_AA)
                cv2.line(mask, (int(xi), int(yi)), (x2, y2), 255, thickness, cv2.LINE_AA)
                if y2 >= h:
                    cv2.line(layer, (int(xi), int(yi)-h), (x2, y2-h), color, thickness, cv2.LINE_AA)
                    cv2.line(mask, (int(xi), int(yi)-h), (x2, y2-h), 255, thickness, cv2.LINE_AA)
        mask[~allowed] = 0
        a = (mask.astype(np.float32) / 255 * .28)[..., None]
        rendered = np.clip(original.astype(np.float32) * (1-a) + layer.astype(np.float32) * a, 0, 255).astype(np.uint8)
        proc.stdin.write(rendered.tobytes())
        if (n+1) % 24 == 0:
            print(f"encoded {n+1}/{frames}", flush=True)
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError("FFmpeg encoding failed")
    subprocess.run([ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y", "-i", str(temp), "-vf",
                    "scale=640:360:flags=lanczos", "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(preview)], check=True)
    # Actual decoded frames; sheet includes coordinates to support visual QA.
    check = cv2.VideoCapture(str(temp))
    decoded = []
    while True:
        ok, img = check.read()
        if not ok:
            break
        decoded.append(img)
    check.release()
    if len(decoded) != frames:
        raise RuntimeError(f"Expected {frames} decoded frames, got {len(decoded)}")
    # Verify real decoded temporal movement in permitted zones and a quiet protected center.
    diffs = [cv2.absdiff(decoded[i], decoded[(i+1) % frames]).astype(np.float32).mean() for i in range(frames)]
    motion_zone = allowed
    protected = np.zeros((h, w), dtype=bool)
    protected[int(.27*h):int(.78*h), int(.20*w):int(.80*w)] = True
    moving_roi = float(cv2.absdiff(decoded[0], decoded[60])[motion_zone].mean())
    still_center = float(cv2.absdiff(decoded[0], decoded[60])[protected].mean())
    seam = float(diffs[-1])
    ordinary = float(np.median(diffs[:-1]))
    print(f"decoded_frames={len(decoded)} adjacent_mean={ordinary:.4f} loop_seam_mean={seam:.4f} seam_ratio={seam/max(ordinary,1e-6):.3f}")
    print(f"decoded_0_vs_60_allowed_crop_mean={moving_roi:.4f} protected_center_mean={still_center:.4f}")
    if moving_roi < .10 or seam > max(ordinary * 2.5, ordinary + .20):
        raise RuntimeError("Rain motion or loop seam failed decoded-frame checks")
    tiles = []
    for idx in (0, 30, 60, 90):
        img = decoded[idx]
        img = cv2.resize(img, (640, 360), interpolation=cv2.INTER_AREA)
        for x in range(0, 640, 64):
            cv2.line(img, (x, 0), (x, 359), (30, 230, 30), 1)
            cv2.putText(img, str(round(x*w/640)), (x+2, 16), cv2.FONT_HERSHEY_SIMPLEX, .35, (20, 240, 20), 1)
        for y in range(0, 360, 36):
            cv2.line(img, (0, y), (639, y), (30, 230, 30), 1)
            cv2.putText(img, str(round(y*h/360)), (2, y+12), cv2.FONT_HERSHEY_SIMPLEX, .35, (20, 240, 20), 1)
        cv2.putText(img, f"{idx/fps:.2f}s", (530, 24), cv2.FONT_HERSHEY_SIMPLEX, .6, (255,255,255), 2)
        tiles.append(img)
    check.release()
    if not cv2.imwrite(str(sheet), np.vstack((np.hstack(tiles[:2]), np.hstack(tiles[2:]))), [cv2.IMWRITE_JPEG_QUALITY, 91]):
        raise RuntimeError("Cannot write review sheet")
    print(f"render={temp} bytes={temp.stat().st_size}")
    print(f"preview={preview} bytes={preview.stat().st_size}")
    print(f"sheet={sheet} bytes={sheet.stat().st_size}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    run(args.source, args.output_dir)
