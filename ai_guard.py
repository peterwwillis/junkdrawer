#!/usr/bin/env python

"""
AI Guard: Secure Dynamic Write Access Controller (v5 - Final)
============================================================

WHAT IS THIS?
A security-focused utility for Linux to manage directory permissions for AI 
coding tools running in containers. It allows you to toggle specific 
directories between Read-Only (RO) and Read-Write (RW) without 
restarting the container or modifying the AI tool.

HOW IT WORKS:
1. Start your container with the project root mounted as 'ro,rshared'.
2. AI Guard uses 'bind propagation' to create "writeable islands" on top 
   of the read-only foundation. 
3. Because of 'rshared', the container sees the permission change instantly.

PREREQUISITES:
- Linux Host.
- Project mounted in Docker/Podman with: -v /path:/workspace:ro,rshared
- Sudoers entry for passwordless use (optional but recommended).

USAGE:
  Unlock a dir:  sudo python3 ai_guard.py --allow ./src
  Lock a dir:    sudo python3 ai_guard.py --deny ./src
  Force Lock:    sudo python3 ai_guard.py --deny ./src --force
  Reset all:     sudo python3 ai_guard.py --reset

POTENTIAL PROBLEMS & SOLUTIONS:
- Problem: "Target is Busy" error when locking.
  Cause: The AI tool or a terminal is currently "inside" that folder.
  Solution: Use the --force flag to kill processes using that directory.
- Problem: Changes aren't appearing in the container.
  Cause: Container was started without the 'rshared' propagation flag.
  Solution: Restart container with ':ro,rshared' in the volume string.
"""

import subprocess
import argparse
import os
import sys
import re
from datetime import datetime

LOG_FILE = "/var/log/ai_guard.log"
MOUNT_BIN = "/usr/bin/mount"
UMOUNT_BIN = "/usr/bin/umount"
FUSER_BIN = "/usr/bin/fuser"

def decode_kernel_path(path_str):
    """Accurately decodes kernel octal sequences like \\040."""
    try:
        return path_str.encode('utf-8').decode('unicode_escape').encode('latin1').decode('utf-8')
    except:
        return path_str

def log_event(message):
    clean_msg = message.replace('\n', ' ').replace('\r', ' ')
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        if not os.path.exists(LOG_FILE):
            os.close(os.open(LOG_FILE, os.O_CREAT | os.O_WRONLY, 0o600))
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {clean_msg}\n")
    except: pass

def get_mount_info():
    mounts = []
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4:
                    mounts.append((decode_kernel_path(parts[4]), "rw" in line))
    except Exception as e:
        print(f"Kernel Error: {e}")
    return mounts

def check_status(target_path):
    real_target = os.path.realpath(target_path)
    mounts = get_mount_info()
    
    for m_path, is_rw in mounts:
        if m_path == real_target:
            return True, is_rw, "direct"

    for m_path, is_rw in mounts:
        if is_rw and real_target.startswith(m_path + os.sep):
            return True, True, f"inherited from {m_path}"
            
    return False, False, "none"

def run_secure_cmd(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip() or e.stdout.strip()

def allow_write(path):
    real_path = os.path.realpath(path)
    if not os.path.isdir(real_path):
        print(f"Error: {real_path} is not a directory.")
        return

    is_mounted, is_rw, reason = check_status(real_path)
    if is_rw:
        print(f"Verified: Already writable ({reason}).")
        return

    if not (is_mounted and reason == "direct"):
        ok, err = run_secure_cmd([MOUNT_BIN, "--bind", "--", real_path, real_path])
        if not ok:
            print(f"Mount failed: {err}")
            return

    ok, err = run_secure_cmd([MOUNT_BIN, "-o", "remount,rw", "--", real_path])
    if ok:
        print(f"🔓 Unlocked: {real_path}")
        log_event(f"ALLOWED: {real_path}")
    else:
        print(f"Remount Error: {err}")
        if reason != "direct": run_secure_cmd([UMOUNT_BIN, "--", real_path])

def deny_write(path, force=False):
    real_path = os.path.realpath(path)
    is_mounted, _, reason = check_status(real_path)

    if reason != "direct":
        print(f"Error: {real_path} is not an active AI Guard mount.")
        return

    if force:
        print(f"Force-clearing processes using {real_path}...")
        run_secure_cmd([FUSER_BIN, "-k", "-m", real_path])

    ok, err = run_secure_cmd([UMOUNT_BIN, "--", real_path])
    if ok:
        print(f"🔒 Locked: {real_path}")
        log_event(f"REVOKED: {real_path}")
    else:
        print(f"CRITICAL: Failed to lock {real_path}.\nReason: {err}")
        if "target is busy" in err.lower():
            print("Tip: Use --force to kill processes holding this directory open.")

def reset_all():
    paths = set()
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE, "r") as f:
            for line in f:
                m = re.search(r"ALLOWED: (.*)", line)
                if m: paths.add(m.group(1).strip())
    
    for p in paths:
        m, _, r = check_status(p)
        if r == "direct": 
            deny_write(p, force=False)
            
    open(LOG_FILE, 'w').close()
    print("✨ Reset complete. System back to default Read-Only.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard v5")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR')
    group.add_argument('--deny', '-d', metavar='DIR')
    group.add_argument('--status', '-s', metavar='DIR')
    group.add_argument('--reset', action='store_true')
    parser.add_argument('--force', '-f', action='store_true', help='Force unmount by killing active processes')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Fatal: Run with sudo.")
        sys.exit(1)

    if args.reset:
        reset_all()
    elif args.status:
        m, rw, r = check_status(args.status)
        print(f"State: {'RW' if rw else 'RO'} ({r})")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny, force=args.force)

if __name__ == "__main__":
    main()
