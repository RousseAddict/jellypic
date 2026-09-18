#!/usr/bin/env bash
# Rasterises icon/jellypic-icon.svg into every slot of AppIcon.appiconset, and
# icon/jellypic-mark.svg into LogoMark.imageset (the wordmark above the grid).
#
# The two SVGs share the same six petals but are NOT the same drawing: the icon
# is full bleed on opaque white, the mark is transparent and trimmed tight. An
# icon has iOS's squircle around it; the mark has the app's own background.
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
MARK_SVG="icon/jellypic-mark.svg"
OUT="jellypic/jellypic/Assets.xcassets/AppIcon.appiconset"
MARK_OUT="jellypic/jellypic/Assets.xcassets/LogoMark.imageset"
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

# The mark is laid out at 22 pt, so the slots are 22/44/66 px. It is rendered
# once at 1024, trimmed to the ink, then resampled: the petals do not touch the
# viewBox edges, and rendering each slot directly would leave a different amount
# of slack at each size, so the mark would sit at a different optical size in
# the 2x and 3x builds.
mkdir -p "$MARK_OUT"
rsvg-convert -w 1024 -h 1024 "$MARK_SVG" -o "$MARK_OUT/logo-mark.png"

python3 - "$MARK_OUT" "$ICC" <<'PY'
import sys
from PIL import Image

out, icc_path = sys.argv[1], sys.argv[2]
icc = open(icc_path, 'rb').read()
source = '%s/logo-mark.png' % out

im = Image.open(source).convert('RGBA')
box = im.getbbox()
assert box, 'the mark rendered empty'
# Square the trimmed box so the mark keeps its aspect ratio in a square slot.
left, top, right, bottom = box
side = max(right - left, bottom - top)
cx, cy = (left + right) // 2, (top + bottom) // 2
im = im.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))

for px, name in ((22, 'logo-mark.png'), (44, 'logo-mark@2x.png'), (66, 'logo-mark@3x.png')):
    im.resize((px, px), Image.LANCZOS).save('%s/%s' % (out, name),
                                            format='PNG', icc_profile=icc)

for px, name in ((22, 'logo-mark.png'), (44, 'logo-mark@2x.png'), (66, 'logo-mark@3x.png')):
    check = Image.open('%s/%s' % (out, name))
    assert check.mode == 'RGBA', '%s lost its transparency' % name
    assert check.size == (px, px), '%s is %s' % (name, check.size)
print('3 mark slots written to %s' % out)
PY
