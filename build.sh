#!/bin/sh
# Builds the P1102 driver from Ubuntu's foo2zjs source package into ./stage,
# laid out exactly as it will be installed under /Library/Printers.
set -eu

VERSION=20200505dfsg0
DEBIAN_REV=3ubuntu1
POOL=https://archive.ubuntu.com/ubuntu/pool/main/f/foo2zjs
ORIG=foo2zjs_${VERSION}.orig.tar.xz
DEBIAN=foo2zjs_${VERSION}-${DEBIAN_REV}.debian.tar.xz
# From Ubuntu's foo2zjs_${VERSION}-${DEBIAN_REV}.dsc
ORIG_SHA256=87465e6a31f8501b90508d50e97901d2cce8b5b3de5418cc156e66d5c500421b
DEBIAN_SHA256=b07011b291b158c13eb185764af4eb8b981980e09745172b3f97b4dfc150de72

# Under CUPS on macOS the filter could not reach Homebrew's gs in /opt/homebrew (sandbox).
# The driver carries its own Ghostscript, built with only the bundled libraries.
GS_TARBALL=ghostpdl-10.08.0.tar.xz
GS_URL=https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/$GS_TARBALL
GS_SHA256=94943e3c4adb7115d132b3c28b913672f2e62e6a9d802f7e754e716b1634174a

HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=$HERE/build
STAGE=$HERE/stage
PREFIX=/Library/Printers/foo2zjs

fetch() {
    file=$1 sha=$2 url=$3
    [ -f "$BUILD/$file" ] || curl -fsSL -o "$BUILD/$file" "$url"
    echo "$sha  $BUILD/$file" | shasum -a 256 -c - >/dev/null \
        || { echo "Checksum mismatch for $file" >&2; rm -f "$BUILD/$file"; exit 1; }
}

mkdir -p "$BUILD"
fetch "$ORIG" "$ORIG_SHA256" "$POOL/$ORIG"
fetch "$DEBIAN" "$DEBIAN_SHA256" "$POOL/$DEBIAN"
fetch "$GS_TARBALL" "$GS_SHA256" "$GS_URL"

GS_SRC=$BUILD/ghostpdl
if [ ! -x "$GS_SRC/bin/gs" ]; then
    rm -rf "$GS_SRC" && mkdir -p "$GS_SRC"
    tar -xf "$BUILD/$GS_TARBALL" -C "$GS_SRC" --strip-components=1
    # A clean PATH keeps configure from picking up Homebrew's libraries instead of the bundled ones.
    # The default device set is kept: trimming it to PBM drops modules the PDF reader needs (arcfour).
    echo "Building Ghostscript (a few minutes; log in $BUILD/ghostpdl-build.log)"
    if ! (cd "$GS_SRC" &&
        PATH=/usr/bin:/bin:/usr/sbin:/sbin ./configure \
            --disable-cups --disable-gtk --without-x \
            --disable-fontconfig --disable-dbus --without-libidn --without-libpaper \
            --without-tesseract --without-pcl --without-xps --without-gpdl \
            --without-urf --without-ijs &&
        PATH=/usr/bin:/bin:/usr/sbin:/sbin make -j"$(sysctl -n hw.ncpu)" gs) > "$BUILD/ghostpdl-build.log" 2>&1
    then
        tail -20 "$BUILD/ghostpdl-build.log" >&2
        echo "Ghostscript build failed; full log: $BUILD/ghostpdl-build.log" >&2
        exit 1
    fi
fi
if otool -L "$GS_SRC/bin/gs" | tail -n +2 | grep -vqE '^[[:space:]]+/(usr/lib|System)/'; then
    echo "Bundled gs links to libraries outside macOS:" >&2
    otool -L "$GS_SRC/bin/gs" >&2
    exit 1
fi

SRC=$BUILD/src
rm -rf "$SRC" && mkdir -p "$SRC"
tar -xf "$BUILD/$ORIG" -C "$SRC" --strip-components=1
tar -xf "$BUILD/$DEBIAN" -C "$SRC"
grep -v '^#' "$SRC/debian/patches/series" | while read -r p; do
    [ -n "$p" ] && patch -d "$SRC" -p1 -s < "$SRC/debian/patches/$p"
done

# foo2zjs-pstops wants GNU sed (gsed) on macOS, which is not reachable under CUPS.
# For this mono printer the wrapper only runs "foo2zjs-pstops -n", and macOS sed gives
# byte-identical output on that path; the GNU-only paths (-r, -w, -a) serve colour models.
sed -i '' 's/^Darwin)[[:space:]]*sed=gsed;;/Darwin)\t\tsed=sed;;/' "$SRC/foo2zjs-pstops.sh"
grep -q '^Darwin).*sed=sed;;' "$SRC/foo2zjs-pstops.sh" \
    || { echo "Could not patch foo2zjs-pstops.sh to use macOS sed" >&2; exit 1; }

# Ubuntu links the system libjbig; macOS has none, so use the copy bundled in the source.
(cd "$SRC" &&
    cc -O2 -Wall -o foo2zjs foo2zjs.c jbig.c jbig_ar.c &&
    cc -O2 -o zjsdecode zjsdecode.c jbig.c jbig_ar.c &&
    make -s foo2zjs-wrapper foo2zjs-pstops)

rm -rf "$STAGE"
mkdir -p "$STAGE$PREFIX/bin" "$STAGE$PREFIX/filter" "$STAGE/Library/Printers/PPDs/Contents/Resources"
install -m 755 "$SRC/foo2zjs" "$SRC/foo2zjs-wrapper" "$SRC/foo2zjs-pstops" "$GS_SRC/bin/gs" "$STAGE$PREFIX/bin/"
install -m 755 "$HERE/foo2zjs-cups" "$STAGE$PREFIX/filter/"

# The upstream PPD, changed only where macOS differs from Linux:
#  - the filter is foo2zjs-cups instead of foomatic-rip;
#  - Copies and N-up are removed, because the macOS print dialog does them;
#  - the default paper is A4.
PPD_OUT=$STAGE/Library/Printers/PPDs/Contents/Resources/HP-LaserJet_Pro_P1102-foo2zjs-macos.ppd
awk -v filter="$PREFIX/filter/foo2zjs-cups" '
/^\*cupsFilter:/ {
    if (!done) printf "*cupsFilter:\t\"application/vnd.cups-postscript 0 %s\"\n", filter
    done = 1; next
}
/^\*OpenUI \*(Copies|NupOrient|NupPages)\// { skip = 1 }
skip { if (/^\*CloseUI:/) skip = 0; next }
/^\*NickName:/ { print "*NickName:      \"HP LaserJet Pro P1102 foo2zjs-z2 (macOS)\""; next }
/^\*Default(PageSize|PageRegion|ImageableArea|PaperDimension): Letter/ { sub(/Letter/, "A4") }
{ print }
' "$SRC/PPD/HP-LaserJet_Pro_P1102.ppd" > "$PPD_OUT"

"$STAGE$PREFIX/bin/gs" -q -dBATCH -dNOPAUSE -dSAFER -sDEVICE=pbmraw -r100 -sOutputFile=/dev/null \
    -c "/Helvetica findfont 12 scalefont setfont 72 72 moveto (ok) show showpage" \
    || { echo "Bundled gs failed its smoke test" >&2; exit 1; }
# End-to-end: the real filter on the staged files, with an empty environment so nothing
# outside the driver folder and the system (e.g. Homebrew) can leak in, as under CUPS.
SELFTEST=$BUILD/selftest
rm -rf "$SELFTEST" && mkdir -p "$SELFTEST"
sed "s|/Library/Printers/foo2zjs/bin|$STAGE$PREFIX/bin|g" "$HERE/foo2zjs-cups" > "$SELFTEST/filter"
printf '%%!PS\n/Helvetica findfont 36 scalefont setfont 72 700 moveto (self-test) show showpage\n' > "$SELFTEST/page.ps"
env -i PPD="$PPD_OUT" /bin/sh "$SELFTEST/filter" 1 user title 1 "" "$SELFTEST/page.ps" \
    > "$SELFTEST/page.zjs" 2> "$SELFTEST/filter.log" || true
"$SRC/zjsdecode" < "$SELFTEST/page.zjs" > "$SELFTEST/decoded.txt" 2>&1 || true
if ! grep -q 'ZJT_START_PAGE' "$SELFTEST/decoded.txt" || ! grep -q 'ZJT_END_DOC' "$SELFTEST/decoded.txt"; then
    cat "$SELFTEST/filter.log" >&2
    echo "Self-test failed: the filter did not produce a page" >&2
    exit 1
fi

echo "Built into $STAGE (gs $("$STAGE$PREFIX/bin/gs" --version), $(file -b "$STAGE$PREFIX/bin/foo2zjs"))"
