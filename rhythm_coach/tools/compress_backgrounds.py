#!/usr/bin/env python3
"""Pré-requis : Pillow avec le support WebP animé.
Lancer : python3 tools/compress_backgrounds.py [--width 540] [--quality 60] [--jobs 2]
"""

import argparse
import os
import shutil
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets" / "backgrounds"
ORIGINALS = ROOT / "assets-originaux" / "backgrounds"


def timing_of(path):
    try:
        im = Image.open(path)
        durations = []
        for i in range(im.n_frames):
            im.seek(i)
            im.load()
            durations.append(im.info["duration"])
        return durations, im.info.get("loop", 0), im.size
    except Exception:
        return None


def target_size(src, width):
    w, h = Image.open(src).size
    return width, round(h * width / w)


def compress(name, width, quality):
    src = ORIGINALS / name
    dst = ASSETS / name
    durations, loop, _ = timing_of(src)
    size = target_size(src, width)
    if dst.read_bytes() != src.read_bytes() and \
            timing_of(dst) == (durations, loop, size):
        return name, src.stat().st_size, dst.stat().st_size, len(durations), "déjà"

    im = Image.open(src)
    images = []
    opaque = True
    for i in range(im.n_frames):
        im.seek(i)
        frame = im.convert("RGBA").resize(size, Image.LANCZOS)
        opaque = opaque and frame.getextrema()[3][0] == 255
        images.append(frame)
    if opaque:
        images = [img.convert("RGB") for img in images]
    # Écrit à côté puis renomme : une interruption ne laisse jamais un fond tronqué.
    tmp = dst.with_name(f".{name}.tmp")
    images[0].save(
        tmp,
        format="WEBP",
        save_all=True,
        append_images=images[1:],
        duration=durations,
        loop=loop,
        quality=quality,
        method=6,
        lossless=False,
    )
    if timing_of(tmp) != (durations, loop, size):
        tmp.unlink()
        raise RuntimeError(f"{name} : boucle, taille ou délais modifiés")
    os.replace(tmp, dst)
    return name, src.stat().st_size, dst.stat().st_size, len(durations), "compressé"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=540)
    parser.add_argument("--quality", type=int, default=60)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()

    ORIGINALS.mkdir(parents=True, exist_ok=True)
    for path in sorted(ASSETS.glob("*.webp")):
        if not (ORIGINALS / path.name).exists():
            shutil.copy2(path, ORIGINALS / path.name)

    names = sorted(p.name for p in ORIGINALS.glob("*.webp"))
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(compress, names, [args.width] * len(names),
                                [args.quality] * len(names)))

    before = sum(r[1] for r in results)
    after = sum(r[2] for r in results)
    for name, b, a, n, state in results:
        print(f"{name}\t{n}\t{b}\t{a}\t{state}")
    print(f"total\t{len(results)} fichiers\t{before}\t{after}", file=sys.stderr)


if __name__ == "__main__":
    main()
