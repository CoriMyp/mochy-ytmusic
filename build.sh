#!/bin/sh
# draws the art, checks the manifest against mochy's rules, then packs build/yt-music.mochyymodule.zip
set -e
cd "$(dirname "$0")"
perl tools/art.pl
perl tools/check.pl
rm -rf build
mkdir -p build
perl tools/pack.pl build/yt-music.mochyymodule.zip
