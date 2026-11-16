#!/usr/bin/env bash
# Re-fetches the vendored libraries in Libs/ at the pinned versions listed in docs/LIBRARIES.md.
# Run from the repo root, review `git diff --stat Libs/`, run the tests, then commit.
# To move a pin: change it here and in docs/LIBRARIES.md, and check that the new LibStub minor is not lower than the
# copies other addons on the target client already ship (LibStub keeps the highest, but we never ship a lower one).
set -euo pipefail

ACE3_COMMIT="ac3d1225037e0dc74e025a72342c0f7824aae147" # WoWUIDev/Ace3 master, 2026-10-28
LIBSERIALIZE_TAG="v1.2.3"                             # rossnichols/LibSerialize
LIBDEFLATE_REF="main"                                 # SafeteeWoW/LibDeflate 1.0.2-release
LIBDBICON_REV="168"                                   # repos.wowace.com/wow/libdbicon-1-0 trunk
LSM_REV="186"                                         # repos.wowace.com/wow/libsharedmedia-3-0 trunk
LDB_REF="master"                                      # tekkub/libdatabroker-1-1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Ace3 @ $ACE3_COMMIT"
curl -fsSL "https://github.com/WoWUIDev/Ace3/archive/$ACE3_COMMIT.tar.gz" | tar xz -C "$work"
ace="$work/Ace3-$ACE3_COMMIT"
for lib in CallbackHandler-1.0 AceAddon-3.0 AceEvent-3.0 AceTimer-3.0 AceConsole-3.0 AceDB-3.0 AceDBOptions-3.0 \
	AceComm-3.0 AceConfig-3.0 AceGUI-3.0; do
	rm -rf "Libs/${lib:?}"
	cp -r "$ace/$lib" "Libs/$lib"
done
cp "$ace/LibStub/LibStub.lua" Libs/LibStub/LibStub.lua
cp "$ace/LICENSE.txt" Libs/Ace3-LICENSE.txt

echo "LibSerialize $LIBSERIALIZE_TAG"
curl -fsSL "https://raw.githubusercontent.com/rossnichols/LibSerialize/$LIBSERIALIZE_TAG/LibSerialize.lua" -o Libs/LibSerialize/LibSerialize.lua
curl -fsSL "https://raw.githubusercontent.com/rossnichols/LibSerialize/$LIBSERIALIZE_TAG/LICENSE" -o Libs/LibSerialize/LICENSE

echo "LibDeflate $LIBDEFLATE_REF"
curl -fsSL "https://raw.githubusercontent.com/SafeteeWoW/LibDeflate/$LIBDEFLATE_REF/LibDeflate.lua" -o Libs/LibDeflate/LibDeflate.lua
curl -fsSL "https://raw.githubusercontent.com/SafeteeWoW/LibDeflate/$LIBDEFLATE_REF/LICENSE.txt" -o Libs/LibDeflate/LICENSE.txt

echo "LibDBIcon r$LIBDBICON_REV, LibSharedMedia r$LSM_REV, LibDataBroker $LDB_REF"
curl -fsSL "https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua?p=$LIBDBICON_REV" -o Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua
curl -fsSL "https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0/LibSharedMedia-3.0.lua?p=$LSM_REV" -o Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua
curl -fsSL "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt" -o Libs/LibSharedMedia-3.0/LICENSE.txt # its header says LGPL v2.1
curl -fsSL "https://raw.githubusercontent.com/tekkub/libdatabroker-1-1/$LDB_REF/LibDataBroker-1.1.lua" -o Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua

# Line endings: LF everywhere (.gitattributes).
find Libs -type f \( -name '*.lua' -o -name '*.xml' \) -exec sed -i 's/\r$//' {} +
echo "Done. Now: lua tests/run.lua && git diff --stat Libs/"
