#!/usr/bin/env sh
exec xattr -d com.apple.quarantine "$@"
