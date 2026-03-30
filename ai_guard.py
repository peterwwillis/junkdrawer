"""
AI Guard: Secure Dynamic Write Access Controller
================================================
PURPOSE:
Toggles subdirectories between RO and RW for AI tools in containers.
Uses direct subprocess execution (no shell) for security.

USAGE:
  sudo python3 ai_guard.py --allow ./src
  sudo python3 ai_guard.py --deny ./src
  sudo python3 ai_guard.py --reset
"""

import subprocess
import argparse
import os
import sys
import re
from datetime import datetime

LOG_FILE = "/var/log/ai_guard.log"

def log_event(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        # Ensure log file exists with restricted permissions if creating new
        if not os.path.exists(LOG_FILE):
            with open(os.open(LOG_FILE, os.O_CREAT | os.O_WRONLY, 0o600), "w") as f:
                pass
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception as e:
        print(f"Logging Error: {e}")

def get_mount_state(target_path):
    target_path = os.path.abspath(target_path)
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                # Field 5 is the mount point
                if len(parts) > 4 and parts[4] == target_path:
                    return True, "rw" in line
    except Exception as e:
        print(f"Error reading mountinfo: {e}")
    return False, False

def run_secure_cmd(args):
    """Executes a command directly without a shell, returning (success, error_msg)."""
    try:
        # capture_output=True handles stdout/stderr separately
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip() or e.stdout.strip()

def allow_write(path):
    abs_path = os.path.abspath(path)
    if not os.path.isdir(abs_path):
        print(f"Error: '{abs_path}' is not a directory.")
        return

    mounted, is_rw = get_mount_state(abs_path)
    if mounted and is_rw:
        print(f"Already writable: {abs_path}")
        return

    # Step 1: Bind mount
    ok, err = run_secure_cmd(["/usr/bin/mount", "--bind", abs_path, abs_path])
    if not ok:
        print(f"Mount Failure: {err}")
        return

    # Step 2: Remount RW
    ok, err = run_secure_cmd(["/usr/bin/mount", "-o", "remount,rw", abs_path])
    if ok:
        print(f"🔓 Unlocked: {abs_path}")
        log_event(f"ALLOWED: {abs_path}")
    else:
        print(f"Remount Failure: {err}")
        # Cleanup the failed bind mount
        run_secure_cmd(["/usr/bin/umount", abs_path])

def deny_write(path):
    abs_path = os.path.abspath(path)
    mounted, _ = get_mount_state(abs_path)
    if not mounted:
        print(f"Already locked: {abs_path}")
        return

    ok, err = run_secure_cmd(["/usr/bin/umount", abs_path])
    if ok:
        print(f"🔒 Locked: {abs_path}")
        log_event(f"REVOKED: {abs_path}")
    else:
        print(f"Unmount Failure: {err}")

def reset_all():
    if not os.path.exists(LOG_FILE):
        print("No log file found.")
        return

    paths_to_check = set()
    with open(LOG_FILE, "r") as f:
        for line in f:
            match = re.search(r"ALLOWED: (.*)", line)
            if match:
                paths_to_check.add(match.group(1).strip())

    for path in paths_to_check:
        mounted, _ = get_mount_state(path)
        if mounted:
            deny_write(path)
    
    open(LOG_FILE, 'w').close()
    print("✨ Reset complete.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard")
    parser.add_argument('--allow', '-a', metavar='DIR')
    parser.add_argument('--deny', '-d', metavar='DIR')
    parser.add_argument('--status', '-s', metavar='DIR')
    parser.add_argument('--reset', action='store_true')
    
    args = parser.parse_args()
    
    if os.geteuid() != 0:
        print("Security Error: This script must be run via sudo.")
        sys.exit(1)

    if args.reset:
        reset_all()
    elif args.status:
        mounted, rw = get_mount_state(args.status)
        print(f"Path: {os.path.abspath(args.status)}\nState: {'RW' if (mounted and rw) else 'RO'}")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)

if __name__ == "__main__":
    main()
