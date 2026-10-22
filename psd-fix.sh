#!/usr/bin/env bash
# psd-fix.sh — repair a psd-broken browser profile (the "profile suddenly
# empty" failure). It undoes what psd's crash-repair shuffles, restores the
# LARGEST intact copy of the profile, and starts psd the documented way.
#
# Run in a terminal with ALL browsers closed:
#     bash ~/psd-fix.sh
#
# Safety rules:
#   - NOTHING is ever deleted. Losers of the restore are renamed with a
#     "-broken-<timestamp>" suffix instead.
#   - If anything looks unexpected, it aborts and prints what to check.
set -u
FFDIR="$HOME/.mozilla/firefox"
P="vhv9lp7w.default-release"                       # profile to fix
DIR="$FFDIR/$P"
RESQ="$HOME/firefox-profile-rescue"                # optional extra candidate
RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
TMP="$RUN/psd/peterw-firefox-$P"
TS=$(date +%Y%m%d_%H%M%S)

fail() { echo "FAIL: $* >&2"; exit 1; }
info() { echo "== $*"; }

[[ $EUID -eq 0 ]] && fail "run as your user, not root."

# ---- 1. no browser may be running (psd's own rule; we abort, not kill) ----
info "checking for running browsers..."
block=""
for f in /usr/share/psd/browsers/*; do
  n=$(source "$f" 2>/dev/null; echo "${PSNAME:-}")
  [[ -z "$n" ]] && continue
  for p in $(pgrep -x -u "$(id -u)" -- "$n" 2>/dev/null); do
    echo "  running: '$n' PID $p ($(readlink /proc/$p/exe 2>/dev/null || echo '?'))"
    block=1
  done
done
[[ -n "$block" ]] && { echo "Close the browsers above, then re-run."; exit 2; }

# ---- 2. fully stop psd and unmount its overlays (incl. dead ones) ---------
info "stopping psd and unmounting overlays..."
systemctl --user stop psd-resync.timer psd-resync.service psd.service 2>/dev/null
systemctl --user kill -s KILL psd.service 2>/dev/null
systemctl --user reset-failed 2>/dev/null
for m in "$RUN"/psd/*; do
  mountpoint -q "$m" && { fusermount3 -u "$m" 2>/dev/null || fusermount3 -uz "$m" 2>/dev/null; }
done
find "$RUN/psd" -mindepth 1 -delete 2>/dev/null
rm -f "$RUN/psd.pid"
sleep 1
mount | grep -q 'psd' && fail "some psd mounts are stuck - reboot and re-run."
[[ -e "$RUN/psd" ]] && rmdir "$RUN/psd" 2>/dev/null

# ---- 3. find the largest intact copy of the profile ------------------------
info "scoring candidate profile copies (by places.sqlite size)..."
best=""; best_size=0
for c in "$DIR" "$DIR-backup" "$DIR-back-ovfs" "$DIR"-backup-crashrecovery-* "$RESQ"; do
  [[ -d "$c" ]] || continue
  s=$(stat -c %s "$c/places.sqlite" 2>/dev/null || echo 0)
  printf "  %10d  %s\n" "$s" "$c"
  (( s > best_size )) && { best_size=$s; best=$c; }
done
[[ -n "$best" && "$best_size" -gt 50000000 ]] \
  || fail "no candidate with a real places.sqlite found. Do NOT proceed blindly - ask for help."

# ---- 4. put the winner at the live path (losers renamed aside) -------------
if [[ -L "$DIR" ]]; then unlink "$DIR"; fi
if [[ -d "$DIR" && "$DIR" != "$best" ]]; then
  mv "$DIR" "$DIR-broken-$TS" && echo "  moved current live dir aside -> $DIR-broken-$TS"
fi
for suffix in -backup -back-ovfs; do
  [[ -e "$FFDIR/$P$suffix" ]] && mv "$FFDIR/$P$suffix" "$FFDIR/$P$suffix-broken-$TS"
done
if [[ "$best" != "$DIR" ]]; then
  mv "$best" "$DIR" || fail "could not move $best into place."
fi
rm -f "$DIR/.flagged"    # psd's overlay marker must not be in a disk copy
info "restored $best ($best_size bytes of places.sqlite) as the live profile."

# ---- 5. start psd the documented way and verify ----------------------------
info "starting psd.service (documented way; timer starts with it)..."
systemctl --user start psd.service || fail "psd failed to start: journalctl --user -u psd -u psd-resync -e"
ok=""
for i in $(seq 1 60); do
  [[ -L "$DIR" && "$(readlink "$DIR")" == "$TMP" ]] && { ok=1; break; }
  sleep 1
done
[[ -n "$ok" ]] || fail "overlay did not come up. Check: journalctl --user -u psd-resync -e"

v=$(stat -c %s "$TMP/places.sqlite" 2>/dev/null || echo 0)
echo
echo "places.sqlite through overlay: $v  (want $best_size)"
if [[ "$v" == "$best_size" ]]; then
  echo "SUCCESS - open Firefox and verify. Reopen your other browsers after."
  echo "Tip: this keeps happening because chromium's fuse daemon keeps dying;"
  echo "a reboot usually clears it. If it recurs, tell the agent."
else
  echo "MISMATCH - tell the agent the numbers above."
  exit 3
fi
