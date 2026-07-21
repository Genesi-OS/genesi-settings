#!/bin/bash
# Genesi OS - Panel migration (one-shot, per existing user)
#
# New users get the full Genesi panel from the static skel appletsrc, which
# already lists every default widget (AI Mode = applet 32, Containers = applet
# 33, ...). But an EXISTING user keeps the panel layout that plasmashell built
# at their first login; adding a widget to skel never touches it. So when a new
# default widget ships (e.g. org.genesi.containers via the genesi-desktop meta),
# already-installed systems get the plasmoid in /usr/share/plasma/plasmoids but
# it never lands on the running panel.
#
# This script heals that. The genesi-settings post_upgrade scriptlet drops the
# accompanying autostart into each existing user's ~/.config/autostart on
# `pacman -Syu`; on the next login this runs IN the user's session (so the
# plasmashell D-Bus scripting interface and the session bus are available) and
# adds any missing default widget to the live panel via evaluateScript. Going
# through plasmashell means the change is persisted by the shell itself — no
# editing of plasma-org.kde.plasma.desktop-appletsrc under a running session
# (which plasmashell would clobber from its in-memory layout on logout).
#
# It is idempotent: it only adds a widget that is not already on a panel, so it
# can never create a duplicate, and it self-removes its autostart once done.

set -u

# Every default Genesi widget that must reach an EXISTING user's panel. Add new
# ones here; the marker below is keyed to this list so appending a widget
# automatically re-arms the migration for users who already ran an older one.
WIDGETS="org.genesi.containers org.genesi.studio"

MARKER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/genesi"
# The marker used to be a fixed "panel-migrate-containers.done", which meant a
# user who had already been migrated once could never receive a widget added
# later — the script exited before doing anything. Key the marker to the widget
# set instead, so shipping a new widget produces a new marker name and the
# migration runs again (still exactly once per set).
MARKER_KEY="$(printf '%s' "$WIDGETS" | tr ' ' '-')"
MARKER="$MARKER_DIR/panel-migrate-$MARKER_KEY.done"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/genesi-panel-migrate.desktop"

# Already migrated for THIS widget set -> make sure the autostart is gone, stop.
if [ -f "$MARKER" ]; then
    rm -f "$AUTOSTART"
    exit 0
fi

# Wait until plasmashell is actually up (no fixed-sleep race).
for _ in $(seq 1 30); do
    pgrep -x plasmashell >/dev/null 2>&1 && break
    sleep 0.5
done

# Pick a working qdbus (Plasma 6 ships qdbus6).
QDBUS=""
for q in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$q" >/dev/null 2>&1; then QDBUS="$q"; break; fi
done
[ -n "$QDBUS" ] || exit 0   # nothing to do without D-Bus; retry next login

# Add every widget in $WIDGETS that no panel already has.
# print("ok") on success (all present, or just added), "nopanel" if there is no
# panel to add them to. Anything else (empty / error) -> leave the marker unset
# so we retry on the next login.
#
# The widget list is injected as a JS array literal. It is built from the
# WIDGETS constant above (plugin ids only — no user input ever reaches here).
JS_WIDGETS=""
for w in $WIDGETS; do
    JS_WIDGETS="$JS_WIDGETS\"$w\","
done

JS="
var want = [${JS_WIDGETS%,}];
var ps = panels();
if (ps.length == 0) {
    print('nopanel');
} else {
    var have = {};
    for (var i = 0; i < ps.length; i++) {
        var ws = ps[i].widgets();
        for (var j = 0; j < ws.length; j++) { have[ws[j].type] = true; }
    }
    for (var k = 0; k < want.length; k++) {
        if (!have[want[k]]) { ps[0].addWidget(want[k]); }
    }
    print('ok');
}
"

RESULT="$("$QDBUS" org.kde.plasma.shell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$JS" 2>/dev/null)" || RESULT=""

# Mark done + drop the autostart only on a confirmed success, so a transient
# failure (plasmashell not ready, scripting locked) is retried next login
# instead of being silently skipped forever.
if [ "$RESULT" = "ok" ]; then
    mkdir -p "$MARKER_DIR"
    : > "$MARKER"
    rm -f "$AUTOSTART"
fi

exit 0
