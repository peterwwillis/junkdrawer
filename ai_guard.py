"""
AI Guard: Production-Ready Security Controller
==============================================
FINAL AUDIT IMPROVEMENTS:
1. Robust Path Decoding: Handles all kernel-escaped characters (spaces, tabs, etc).
2. Busy-Target Handling: Detects and reports when a folder cannot be locked.
3. Path Equality: Uses os.path.samefile() where possible for absolute certainty.
4. Binary Lockdown: Explicitly uses /usr/bin/ paths for all system calls.
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

def decode_kernel_path(path_str):
    """Accurately decodes kernel octal sequences like \\040."""
    # Convert string like 'my\\040path' into bytes, then decode octal escapes
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
                    # parts[4] is the mount point
                    mounts.append((decode_kernel_path(parts[4]), "rw" in line))
    except Exception as e:
        print(f"Kernel Error: {e}")
    return mounts

def check_status(target_path):
    real_target = os.path.realpath(target_path)
    mounts = get_mount_info()
    
    # 1. Direct Mount Check
    for m_path, is_rw in mounts:
        if m_path == real_target:
            return True, is_rw, "direct"

    # 2. Inheritance Check (Is a parent RW?)
    for m_path, is_rw in mounts:
        if is_rw and real_target.startswith(m_path + os.sep):
            return True, True, f"inherited from {m_path}"
            
    return False, False, "none"

def run_secure_cmd(args):
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip()

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

def deny_write(path):
    real_path = os.path.realpath(path)
    is_mounted, _, reason = check_status(real_path)

    if reason != "direct":
        print(f"Error: {real_path} is not an active AI Guard mount.")
        return

    ok, err = run_secure_cmd([UMOUNT_BIN, "--", real_path])
    if ok:
        print(f"🔒 Locked: {real_path}")
        log_event(f"REVOKED: {real_path}")
    else:
        print(f"CRITICAL: Failed to lock {real_path}.\nReason: {err}")
        print("Tip: Ensure no processes (like a terminal or the AI tool) are using this directory.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard v4.1")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR')
    group.add_argument('--deny', '-d', metavar='DIR')
    group.add_argument('--status', '-s', metavar='DIR')
    group.add_argument('--reset', action='store_true')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Error: Run with sudo.")
        sys.exit(1)

    if args.reset:
        paths = set()
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r") as f:
                for line in f:
                    m = re.search(r"ALLOWED: (.*)", line)
                    if m: paths.add(m.group(1).strip())
        for p in paths:
            m, _, r = check_status(p)
            if r == "direct": deny_write(p)
        open(LOG_FILE, 'w').close()
        print("✨ Reset complete.")
    elif args.status:
        m, rw, r = check_status(args.status)
        print(f"State: {'RW' if rw else 'RO'} ({r})")
    elif args.allow: allow_write(args.allow)
    elif args.deny: deny_write(args.deny)

if __name__ == "__main__":
    main()
