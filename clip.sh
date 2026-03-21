#!/usr/bin/env sh

if [ -n "$WAYLAND_DISPLAY" ]; then
    wl-copy
else
    xsel --clipboard --input
fi

