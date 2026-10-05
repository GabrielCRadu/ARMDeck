#!/bin/bash
# deploy-decky-plugin.sh (armdeck): builds the ARMDeck Decky plugin (userspace/decky/armdeck) and
# copies it to ~/homebrew/plugins/ARMDeck on the phone, then restarts Decky so it loads it. Run on the PC (Git Bash or Linux)
# with Node and pnpm installed. The phone address: $OP8_PHONE, else tools/.phone, else the USB
# address, as in deploy.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/userspace/decky/armdeck
PHONE=${OP8_PHONE:-$(head -1 "$ROOT/tools/.phone" 2>/dev/null)}
PHONE=${PHONE:-gabriel@172.16.42.1}
SSH=(ssh -i "$HOME/.ssh/op8_pmos" -o HostKeyAlias=172.16.42.1 -o ConnectTimeout=10 "$PHONE")
DEST=homebrew/plugins/ARMDeck

cd "$SRC"
pnpm install --frozen-lockfile >/dev/null
pnpm run build
T=$(mktemp -d)
mkdir -p "$T/ARMDeck/dist"
cp plugin.json package.json main.py "$T/ARMDeck/"
cp "$ROOT/LICENSE" "$T/ARMDeck/"
cp dist/index.js "$T/ARMDeck/dist/"
"${SSH[@]}" "rm -rf ~/$DEST.new && mkdir -p ~/homebrew/plugins"
scp -q -r -i "$HOME/.ssh/op8_pmos" -o HostKeyAlias=172.16.42.1 "$T/ARMDeck" "$PHONE:$DEST.new"
"${SSH[@]}" "rm -rf ~/$DEST.old; [ -d ~/$DEST ] && mv ~/$DEST ~/$DEST.old; mv ~/$DEST.new ~/$DEST && rm -rf ~/$DEST.old && ls -la ~/$DEST ~/$DEST/dist"
rm -rf "$T"
# Decky's hot reload does not notice a plugin folder that was swapped in whole: restart it.
# op8-decky starts it again and stops the plugins of the old one.
"${SSH[@]}" 'p=$(pgrep -o -f "services/[P]luginLoader"); [ -n "$p" ] || exit 0
	kill -TERM "$p"; i=0
	while [ $i -lt 12 ] && kill -0 "$p" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done
	kill -0 "$p" 2>/dev/null && kill -KILL "$p"; echo "Decky restarted"'
echo "ARMDeck plugin deployed."
