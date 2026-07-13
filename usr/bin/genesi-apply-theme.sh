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
WALL=/usr/share/wallpapers/genesi/wallpaper.png
if command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && [ -f "$WALL" ]; then
    plasma-apply-wallpaperimage "$WALL" 2>/dev/null || true
fi

# Color scheme -- live, no restart.
plasma-apply-colorscheme Genesi 2>/dev/null || true

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
fi

# One-shot: remove the autostart so this only runs on the very first login.
# (Panel layout + Kickoff sizing already come from the static appletsrc; there
# is no layout step to retry, and every apply above is idempotent.)
rm -f ~/.config/autostart/genesi-apply-theme.desktop

exit 0
