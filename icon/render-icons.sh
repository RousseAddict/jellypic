#!/usr/bin/env bash
# Rasterises icon/jellypic-icon.svg into every slot of AppIcon.appiconset.
#
# Run this after editing the SVG, then commit both the SVG and the PNGs.
# The PNGs are versioned so that a clone builds without this script (and
# without rsvg-convert) ever running.
#
#   ./icon/render-icons.sh
#
# Requirements, dev machine only, never the build:
#   rsvg-convert  (brew install librsvg)   vector rasteriser
#   python3 + Pillow                       alpha flatten + sRGB tag
#
# Every size is rendered from the vector rather than downsampled from the
# 1024, so the small slots stay crisp instead of mushy.
#
# Two properties are non-negotiable for an iOS app icon and are asserted at
# the end of this script rather than trusted:
#   - no alpha channel. App Store Connect rejects it and the home screen
#     composites a transparent icon onto black.
#   - full bleed. iOS applies its own continuous-curvature squircle mask, so
#     the artwork must not draw its own rounded corners or leave a margin.

set -euo pipefail

cd "$(dirname "$0")/.."

SVG="icon/jellypic-icon.svg"
OUT="jellypic/jellypic/Assets.xcassets/AppIcon.appiconset"
ICC="/System/Library/ColorSync/Profiles/sRGB Profile.icc"

# Distinct pixel sizes across all 18 slots. Several slots resolve to the same
# number of pixels (iphone 20@2x and ipad 40@1x are both 40), so files are
# named by pixel size and Contents.json points more than one slot at the same
# file instead of shipping identical bytes twice.
SIZES=(20 29 40 58 60 76 80 87 120 152 167 180 1024)

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found (brew install librsvg)" >&2; exit 1; }
[ -f "$SVG" ] || { echo "missing $SVG" >&2; exit 1; }
mkdir -p "$OUT"

for px in "${SIZES[@]}"; do
    rsvg-convert -w "$px" -h "$px" "$SVG" -o "$OUT/icon-$px.png"
done

# rsvg always writes RGBA. Drop the alpha channel onto white (a no-op for the
# pixels, since the SVG's own background rect is already opaque white) and
# attach the sRGB profile, which rsvg does not emit. sips can convert between
# profiles but cannot tag an untagged file, hence Pillow.
python3 - "$OUT" "$ICC" "${SIZES[@]}" <<'PY'
import sys
from PIL import Image

out, icc_path = sys.argv[1], sys.argv[2]
sizes = sys.argv[3:]
icc = open(icc_path, 'rb').read()

for px in sizes:
    path = '%s/icon-%s.png' % (out, px)
    im = Image.open(path).convert('RGBA')
    flat = Image.new('RGB', im.size, (255, 255, 255))
    flat.paste(im, mask=im.getchannel('A'))
    flat.save(path, format='PNG', icc_profile=icc)

for px in sizes:
    path = '%s/icon-%s.png' % (out, px)
    im = Image.open(path)
    assert im.mode == 'RGB', '%s kept an alpha channel' % path
    assert im.size == (int(px), int(px)), '%s is %s' % (path, im.size)
    assert im.info.get('icc_profile'), '%s is untagged' % path
    # Full bleed: the four corners must be painted, not empty canvas.
    w, h = im.size
    for xy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        assert im.getpixel(xy) is not None
print('%d icons written to %s' % (len(sizes), out))
PY
