#!/usr/bin/env python3
# build-seed.py — turn seed/library.yml into the demo library's files.
#
# Runs on the VPS, called by tasks/seed.yml with the manifest converted to JSON.
# Standard library only; the heavy lifting is the server's own tools: Jellyfin's
# ffmpeg (which has libx264 and libx265) and Debian's exiftool.
#
# For each entry:
#   1. the original is downloaded once into --cache with curl, named by its
#      sha1, and refused unless the sha1 Commons publishes matches;
#   2. a photo is rotated upright by hand (ffmpeg is told not to autorotate, so
#      no EXIF orientation is applied twice), scaled to 3024 px on its long
#      edge, re-encoded, and given the manifest's date and GPS by exiftool;
#      a video is transcoded to H.264 or HEVC in MP4 with its creation_time;
#   3. the result lands in --out at the entry's path, atomically.
#
# --out is owned by this script: files not in the manifest are deleted, and an
# entry is rebuilt only when its manifest line changed (.build-state.json).
# Prints "changed" when it wrote or deleted anything, for Ansible.

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.parse

USER_AGENT = "jellypic-demo-seed/1.0"
LONG_EDGE = 3024
PACE_SECONDS = 2
ROTATIONS = {
    "2": "hflip",
    "3": "hflip,vflip",
    "4": "vflip",
    "5": "transpose=0",
    "6": "transpose=1",
    "7": "transpose=3",
    "8": "transpose=2",
}


def sha1_of(path):
    digest = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(entry, cache):
    ext = os.path.splitext(urllib.parse.urlsplit(entry["url"]).path)[1].lower()
    path = os.path.join(cache, entry["sha1"] + ext)
    if os.path.exists(path):
        return path
    # curl over HTTP/2, not urllib: from this VPS upload.wikimedia.org answers
    # every HTTP/1.1 request with 429 (curl --http1.1 included) and serves HTTP/2
    # ones, and urllib only speaks HTTP/1.1. curl also honours Retry-After.
    time.sleep(PACE_SECONDS)
    fd, tmp = tempfile.mkstemp(dir=cache, suffix=".part")
    os.close(fd)
    try:
        try:
            run("curl", "--fail", "--silent", "--show-error", "--location", "--http2",
                "--retry", "5", "--retry-delay", "30", "--max-time", "600",
                "--user-agent", USER_AGENT, "--output", tmp, entry["url"])
        except subprocess.CalledProcessError as e:
            raise SystemExit(f"download failed for {entry['url']}: {e.stderr.decode(errors='replace').strip()}")
        actual = sha1_of(tmp)
        if actual != entry["sha1"]:
            raise SystemExit(f"sha1 mismatch for {entry['url']}: expected {entry['sha1']}, got {actual}")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return path


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def build_photo(entry, src, tmp, ffmpeg):
    orientation = subprocess.run(
        ["exiftool", "-n", "-s3", "-Orientation", src], check=True, capture_output=True, text=True
    ).stdout.strip()
    filters = [ROTATIONS[orientation]] if orientation in ROTATIONS else []
    filters.append(
        f"scale='if(gte(iw,ih),min(iw,{LONG_EDGE}),-2)':'if(gte(iw,ih),-2,min(ih,{LONG_EDGE}))'"
    )
    run(ffmpeg, "-v", "error", "-y", "-noautorotate", "-i", src, "-vf", ",".join(filters),
        "-map_metadata", "-1", "-pix_fmt", "yuvj420p", "-q:v", "3", "-frames:v", "1", tmp)
    stamp = entry["taken"].replace("-", ":")
    lat, lon = entry["lat"], entry["lon"]
    run("exiftool", "-q", "-overwrite_original",
        f"-DateTimeOriginal={stamp}", f"-CreateDate={stamp}", f"-ModifyDate={stamp}",
        f"-GPSLatitude={abs(lat)}", f"-GPSLatitudeRef={'N' if lat >= 0 else 'S'}",
        f"-GPSLongitude={abs(lon)}", f"-GPSLongitudeRef={'E' if lon >= 0 else 'W'}",
        "-Artist=National Park Service",
        "-Copyright=Public domain (PD-USGov-NPS)",
        f"-ImageDescription={entry['page']}",
        tmp)


def build_video(entry, src, tmp, ffmpeg):
    if entry["codec"] == "hevc":
        video = ["-c:v", "libx265", "-crf", "24", "-preset", "medium", "-tag:v", "hvc1"]
    else:
        video = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-profile:v", "high"]
    run(ffmpeg, "-v", "error", "-y", "-i", src, "-map", "0:v:0", "-map", "0:a:0?",
        "-map_metadata", "-1", *video, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart", "-metadata", f"creation_time={entry['created_utc']}",
        "-f", "mp4", tmp)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()

    manifest = json.load(open(args.manifest))
    entries = [("photo", e) for e in manifest["photos"]] + [("video", e) for e in manifest["videos"]]
    state_path = os.path.join(args.out, ".build-state.json")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {}
    loaded_state = dict(state)
    changed = False

    wanted = {}
    for kind, entry in entries:
        key = hashlib.sha1(json.dumps(entry, sort_keys=True).encode()).hexdigest()
        wanted[entry["path"]] = key
        target = os.path.join(args.out, entry["path"])
        if state.get(entry["path"]) == key and os.path.exists(target):
            continue
        src = fetch(entry, args.cache)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(target), prefix=".", suffix=os.path.splitext(target)[1])
        os.close(fd)
        try:
            (build_photo if kind == "photo" else build_video)(entry, src, tmp, args.ffmpeg)
            os.chmod(tmp, 0o644)
            os.replace(tmp, target)
        except subprocess.CalledProcessError as e:
            sys.exit(f"{entry['path']}: {' '.join(e.cmd[:2])} failed: {e.stderr.decode(errors='replace')[-800:]}")
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        state[entry["path"]] = key
        changed = True
        print(f"built {entry['path']}", file=sys.stderr)

    for root, _, files in os.walk(args.out):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, args.out)
            if rel != ".build-state.json" and rel not in wanted:
                os.unlink(path)
                state.pop(rel, None)
                changed = True
    for root, dirs, _ in os.walk(args.out, topdown=False):
        for d in dirs:
            path = os.path.join(root, d)
            if not os.listdir(path):
                os.rmdir(path)

    # Rewritten only when it differs: a rewrite bumps --out's mtime, which
    # rsync -a carries to the library, so an idle deploy would rescan it.
    new_state = {k: v for k, v in state.items() if k in wanted}
    if new_state != loaded_state or not os.path.exists(state_path):
        with open(state_path + ".tmp", "w") as f:
            json.dump(new_state, f, indent=1, sort_keys=True)
        os.replace(state_path + ".tmp", state_path)
    print("changed" if changed else "unchanged")


if __name__ == "__main__":
    main()
