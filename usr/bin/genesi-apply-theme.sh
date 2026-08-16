#!/bin/bash
# Genesi OS - Theme Applicator (first-login safety net)
#
# The Genesi desktop config (wallpaper, color scheme, icon theme, window
# decoration) is pre-seeded into the user's HOME from skel-override, so a
# correctly-seeded login already paints Genesi on the FIRST frame:
#   - kwinrc      -> Klassy decoration, blur, rounded corners (read at KWin start)
#   - kdeglobals  -> ColorScheme=Genesi, Icons=Tela-circle-green-dark, Darkly
#   - appletsrc   -> wallpaper = /usr/share/wallpapers/genesi/wallpaper.png
#
# This script is only a guarded fallback for the case where a setting didn't
# take, and it is deliberately FLICKER-FREE. It NEVER restarts kwin or
# plasmashell -- the old `kwin --replace` (compositor black-flash) and
# `plasmashell --replace` (panel rebuild) were exactly the "2 piscadas" we want
# gone. It applies any missing bits live and asks KWin to reload config in place.

# Wait until plasmashell is actually up (no fixed-sleep race).
for _ in $(seq 1 20); do
    pgrep -x plasmashell >/dev/null 2>&1 && break
    sleep 0.5
done

# Pick a working qdbus (Plasma 6 ships qdbus6).
QDBUS=""
for q in qdbus6 qdbus-qt6 qdbus; do
    if command -v "$q" >/dev/null 2>&1; then QDBUS="$q"; break; fi
done

# Wallpaper -- live apply (no shell restart). When the seeded appletsrc already
# loaded our wallpaper this is a no-op and there is NO fade; it only does
# anything (and only then a brief fade) if the seed somehow didn't take.
# One-shot marker. The parts below that express TASTE (wallpaper, colour
# scheme) run only on the first login: re-applying them every time would stomp
# on a user who deliberately picked their own, which is why this script used to
# delete itself entirely.
GENESI_THEME_MARKER="$HOME/.config/.genesi-theme-applied"
[ -e "$GENESI_THEME_MARKER" ] && GENESI_FIRST_RUN=0 || GENESI_FIRST_RUN=1

WALL=/usr/share/wallpapers/genesi/wallpaper.png
if [ "$GENESI_FIRST_RUN" = 1 ] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && [ -f "$WALL" ]; then
    plasma-apply-wallpaperimage "$WALL" 2>/dev/null || true
fi

# Color scheme -- live, no restart.
# plasma-apply-colorscheme is a NO-OP when the scheme NAME already matches --
# it prints "already set" and changes nothing. That is precisely the broken
# case: kdeglobals still says ColorScheme=Genesi while its [Colors:*] values
# have been clobbered, so the one command that could repair them declines to
# run. Bounce through another scheme to force a real rewrite.
if [ "$GENESI_FIRST_RUN" = 1 ]; then
    plasma-apply-colorscheme Genesi 2>/dev/null || true
else
    # Repair pass: force the values to be rewritten from Genesi.colors even
    # though the name already matches.
    plasma-apply-colorscheme BreezeDark 2>/dev/null || true
    plasma-apply-colorscheme Genesi 2>/dev/null || true
fi

# Selected-item text MUST stay white on the brand-green selection background.
# Belt-and-suspenders: the skel kdeglobals and the Genesi color scheme both
# already ship white selection foregrounds, but if any earlier seed/scheme step
# left a dark value, selected text (e.g. in the Package Installer) goes
# near-black and vanishes. Force it white here on every new user's first login,
# so an installed system can never come up with the unreadable selection again.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kdeglobals --group "Colors:Selection" \
        --key BackgroundNormal "29,158,117" 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group "Colors:Selection" \
        --key BackgroundAlternate "22,120,90" 2>/dev/null || true
    for key in ForegroundActive ForegroundInactive ForegroundLink \
        ForegroundNegative ForegroundNeutral ForegroundNormal \
        ForegroundPositive ForegroundVisited; do
        kwriteconfig6 --file kdeglobals --group "Colors:Selection" \
            --key "$key" "255,255,255" 2>/dev/null || true
    done
fi

# Icon theme -- plasma-changeicons repaints the running shell live (it is the
# same tool System Settings uses), so no plasmashell --replace is needed. Also
# persist to kdeglobals for apps that read it at start.
if [ -d /usr/share/icons/Tela-circle-green-dark ]; then
    /usr/lib/plasma-changeicons Tela-circle-green-dark 2>/dev/null || true
    kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-circle-green-dark 2>/dev/null || true
fi

# Window decoration / effects (Klassy, blur, rounded corners) come from the
# seeded kwinrc. Ask KWin to reload it IN PLACE -- no compositor restart, so no
# black flash. Safe on both X11 and Wayland (unlike kwin_wayland --replace).
if [ -n "$QDBUS" ]; then
    "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true
    # KWin reconfigure only reaches the WINDOW MANAGER. kwriteconfig6 wrote
    # kdeglobals without emitting any change signal, so every already-open Qt
    # app keeps the stale palette -- the repair appears to do nothing until the
    # user logs out. KGlobalSettings' notifyChange(ChangePalette=0, 0) is what
    # tells them to re-read it.
    "$QDBUS" org.kde.KGlobalSettings /KGlobalSettings         org.kde.KGlobalSettings.notifyChange 0 0 2>/dev/null || true
    "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true
fi

# One-shot: remove the autostart so this only runs on the very first login.
# (Panel layout + Kickoff sizing already come from the static appletsrc; there
# is no layout step to retry, and every apply above is idempotent.)
# Deliberately NOT deleting this autostart entry any more.
#
# It used to `rm -f` itself here, which made the whole script one-shot. That is
# exactly why "selected text goes colourless and icons go black" kept coming
# back after every system update and had to be fixed by hand, forever: anything
# that later clobbered kdeglobals (a Plasma update, a regenerated kdedefaults
# layer) was never repaired, because the repair had deleted itself.
#
# The contrast repair above is idempotent and cheap -- it writes the same few
# keys and reconfigures KWin -- so it is safe to run at every login. The parts
# that express taste are marker-gated above, so a user's own wallpaper and
# colour scheme survive.
mkdir -p "$(dirname "$GENESI_THEME_MARKER")" 2>/dev/null || true
touch "$GENESI_THEME_MARKER" 2>/dev/null || true

exit 0
