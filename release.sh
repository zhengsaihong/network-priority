#!/bin/zsh
set -eu
cd "${0:A:h}"

# Pin the author's personal certificate. Never select another identity automatically.
identity='E580924ECBEA16BC84274EABE23FF0BE0597E6AA'
authority='Apple Development: 2358049458@qq.com (A36TCY95NB)'
security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity"

stage="$PWD/.build/release-1.0.0"
mkdir -p "$stage" dist
OUTPUT_DIR="$stage" SIGNING_IDENTITY="$identity" zsh build.sh
app_path="$stage/网络优先级.app"
codesign -dvv "$app_path" 2> .build/signature.txt
/usr/bin/grep -Fxq "Authority=$authority" .build/signature.txt
ln -sfn /Applications "$stage/Applications"
cp README.md "$stage/README.md"

hdiutil create -volname '网络优先级 1.0.0' -srcfolder "$stage" -ov -format UDZO dist/NetworkPriority-1.0.0-universal.dmg
ditto -c -k --sequesterRsrc --keepParent "$app_path" dist/NetworkPriority-1.0.0-universal.zip
cd dist
shasum -a 256 NetworkPriority-1.0.0-universal.dmg NetworkPriority-1.0.0-universal.zip > SHA256SUMS.txt
cat SHA256SUMS.txt
