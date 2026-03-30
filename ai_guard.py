"""
AI Guard: Dynamic Write Access Controller for Linux Containers
=============================================================
PURPOSE:
Toggles subdirectories between RO and RW for AI tools in containers.
Uses bind-mount propagation to change permissions live.

USAGE:
  Unlock:  sudo python3 ai_guard.py --allow ./src
  Lock:    sudo python3 ai_guard.py --deny ./src
  Reset:   sudo python3 ai_guard.py --reset    (Unmounts all previously allowed paths)
  Status:  sudo python3 ai_guard.py --status ./src

REQUIREMENTS:
1. Linux Host.
2. Container started with `:ro,rshared` volume flags.
3. Sudoers entry for passwordless execution.
"""

import subprocess
import argparse
import os
import sys
import re
from datetime import datetime

# Path to the log file (User must have write access, or keep in /var/log/ and use sudo)
LOG_FILE = "/var/log/ai_guard.log"

def log_event(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
    except PermissionError:
        print(f"Warning: Cannot write to {LOG_FILE}. Run with sudo.")

def get_mount_state(target_path):
    target_path = os.path.abspath(target_path)
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                # Field 5 is the mount point in /proc/self/mountinfo
                if len(parts) > 4 and parts[4] == target_path:
                    # Look for 'rw' or 'ro' in the options (usually after the '-' separator)
                    return True, "rw" in line
    except Exception as e:
        print(f"Error reading mountinfo: {e}")
    return False, False

def run_cmd(cmd):
    try:
        subprocess.check_call(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        return False
    return True

def allow_write(path):
    abs_path = os.path.abspath(path)
    if not os.path.isdir(abs_path):
        print(f"Error: '{abs_path}' is not a directory.")
        return

    mounted, is_rw = get_mount_state(abs_path)
    if mounted and is_rw:
        print(f"Already writable: {abs_path}")
        return

    if run_cmd(f"mount --bind '{abs_path}' '{abs_path}'") and \
       run_cmd(f"mount -o remount,rw '{abs_path}'"):
        print(f"🔓 Unlocked: {abs_path}")
        log_event(f"ALLOWED: {abs_path}")
    else:
        print(f"Failed to unlock {abs_path}")

def deny_write(path):
    abs_path = os.path.abspath(path)
    mounted, _ = get_mount_state(abs_path)
    if not mounted:
        print(f"Already locked: {abs_path}")
        return

    if run_cmd(f"umount '{abs_path}'"):
        print(f"🔒 Locked: {abs_path}")
        log_event(f"REVOKED: {abs_path}")
    else:
        print(f"Failed to lock {abs_path}")

def reset_all():
    """Reads the log to find all 'ALLOWED' paths and unmounts them if they are still mounted."""
    if not os.path.exists(LOG_FILE):
        print("No log file found. Nothing to reset.")
        return

    # Extract unique paths that were allowed
    paths_to_check = set()
    with open(LOG_FILE, "r") as f:
        for line in f:
            match = re.search(r"ALLOWED: (.*)", line)
            if match:
                paths_to_check.add(match.group(1).strip())

    if not paths_to_check:
        print("No previous allow operations found in log.")
        return

    print("Checking for active AI Guard mounts to reset...")
    for path in paths_to_check:
        mounted, _ = get_mount_state(path)
        if mounted:
            deny_write(path)
    
    # Clear the log after a successful total reset
    open(LOG_FILE, 'w').close()
    print("✨ Reset complete. Log cleared.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard")
    parser.add_argument('--allow', '-a', metavar='DIR')
    parser.add_argument('--deny', '-d', metavar='DIR')
    parser.add_argument('--status', '-s', metavar='DIR')
    parser.add_argument('--reset', action='store_true', help='Reset all mounts based on logs')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Permission Denied. Please run: sudo python3 ai_guard.py [args]")
        sys.exit(1)

    if args.reset:
        reset_all()
    elif args.status:
        mounted, rw = get_mount_state(args.status)
        print(f"Path: {os.path.abspath(args.status)}\nState: {'READ-WRITE' if (mounted and rw) else 'READ-ONLY'}")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
