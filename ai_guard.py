"""
AI Guard: Dynamic Write Access Controller for Linux Containers
=============================================================

PURPOSE:
This script allows you to toggle specific subdirectories between Read-Only (RO) 
and Read-Write (RW) modes for an AI coding tool running in a container. 
It uses Linux bind-mount propagation to change permissions on-the-fly 
without restarting the container or modifying the AI tool.

REQUIREMENTS:
1. Linux Host with `mount` and `umount` capabilities.
2. The container MUST be started with `rshared` propagation.
   Example: docker run -v /home/user/project:/workspace:ro,rshared ...

USAGE:
  Unlock a directory:  sudo python3 ai_guard.py --allow ./src/utils
  Lock a directory:    sudo python3 ai_guard.py --deny ./src/utils
  Check status:        sudo python3 ai_guard.py --status ./src/utils

SAFETY FEATURES:
- Kernel Verification: Checks /proc/self/mountinfo to prevent redundant mounts.
- Idempotency: Running --allow on an already unlocked folder does nothing.
- Audit Log: Every change is logged to /var/log/ai_guard.log for security reviews.
"""

import subprocess
import argparse
import os
import sys
from datetime import datetime

LOG_FILE = "/var/log/ai_guard.log"

def log_event(message):
    """Appends a timestamped message to the audit log."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] {message}\n"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(entry)
    except PermissionError:
        print(f"Warning: Could not write to log file {LOG_FILE} (Permission Denied)")

def get_mount_state(target_path):
    """Parses /proc/self/mountinfo to check path state."""
    target_path = os.path.abspath(target_path)
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4 and parts[4] == target_path:
                    opts = parts[5].split(',')
                    return True, "rw" in opts
    except FileNotFoundError:
        print("Error: Could not access /proc/self/mountinfo")
        sys.exit(1)
    return False, False

def run_cmd(cmd):
    try:
        subprocess.check_call(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError:
        print(f"Error: Failed to execute: {cmd}")
        sys.exit(1)

def allow_write(path):
    abs_path = os.path.abspath(path)
    if not os.path.isdir(abs_path):
        print(f"Error: '{abs_path}' is not a directory.")
        return

    mounted, is_rw = get_mount_state(abs_path)
    if mounted and is_rw:
        print(f"Verified: '{abs_path}' is already writable.")
        return

    print(f"🔓 Unlocking: {abs_path}")
    run_cmd(f"mount --bind '{abs_path}' '{abs_path}'")
    run_cmd(f"mount -o remount,rw '{abs_path}'")
    log_event(f"ALLOWED WRITE: {abs_path}")

def deny_write(path):
    abs_path = os.path.abspath(path)
    mounted, is_rw = get_mount_state(abs_path)
    if not mounted:
        print(f"Verified: '{abs_path}' is already Locked (Read-Only).")
        return

    print(f"🔒 Locking: {abs_path}")
    run_cmd(f"umount '{abs_path}'")
    log_event(f"REVOKED WRITE: {abs_path}")

def main():
    parser = argparse.ArgumentParser(description="AI Guard: Dynamic RW Toggler")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR')
    group.add_argument('--deny', '-d', metavar='DIR')
    group.add_argument('--status', '-s', metavar='DIR')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Required: Run with sudo.")
        sys.exit(1)

    if args.status:
        mounted, rw = get_mount_state(args.status)
        state = "READ-WRITE (Unlocked)" if (mounted and rw) else "READ-ONLY (Locked)"
        print(f"Path: {os.path.abspath(args.status)}\nState: {state}")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)

if __name__ == "__main__":
    main()
