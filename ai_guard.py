"""
AI Guard: Secure Dynamic Write Access Controller (v3)
====================================================
SECURITY FEATURES:
1. Symlink Safety: Resolves all paths via os.path.realpath() before checking kernel state.
2. Octal Decoding: Correctly parses kernel-escaped paths (e.g., spaces as \\040).
3. Argument Guarding: Uses '--' to prevent paths from being interpreted as flags.
4. Secure Execution: No shell usage; restricted log file permissions (0600).

USAGE:
  sudo python3 ai_guard.py --allow "/path/with spaces/src"
  sudo python3 ai_guard.py --deny "/path/with spaces/src"
  sudo python3 ai_guard.py --reset
"""

import subprocess
import argparse
import os
import sys
import re
from datetime import datetime

LOG_FILE = "/var/log/ai_guard.log"

def decode_kernel_path(path):
    """Decodes octal sequences used by the kernel in /proc/self/mountinfo."""
    try:
        # Kernel escapes are octal \ooo. We decode them back to literal bytes then utf-8.
        return path.encode('utf-8').decode('unicode_escape').encode('latin1').decode('utf-8')
    except Exception:
        return path

def log_event(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        if not os.path.exists(LOG_FILE):
            # Create with owner-only read/write permissions (0600)
            fd = os.open(LOG_FILE, os.O_CREAT | os.O_WRONLY, 0o600)
            os.close(fd)
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception as e:
        print(f"Logging Error: {e}")

def get_mount_state(target_path):
    """Checks the kernel mount table with path decoding and normalization."""
    # Resolve symlinks so we match what the kernel actually sees
    real_target = os.path.realpath(target_path)
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4:
                    # parts[4] is the mount point. It must be decoded.
                    kernel_mount = decode_kernel_path(parts[4])
                    if kernel_mount == real_target:
                        # Check for 'rw' in the VFS options (usually parts[5])
                        return True, "rw" in line
    except Exception as e:
        print(f"Error reading mountinfo: {e}")
    return False, False

def run_secure_cmd(args):
    """Executes command directly. Uses '--' to prevent flag injection."""
    try:
        # capture_output=True ensures we see exact system errors
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip() or e.stdout.strip()

def allow_write(path):
    real_path = os.path.realpath(path)
    if not os.path.isdir(real_path):
        print(f"Error: '{real_path}' is not a directory.")
        return

    mounted, is_rw = get_mount_state(real_path)
    if mounted and is_rw:
        print(f"Already writable: {real_path}")
        return

    # Using '--' tells mount that everything following is a positional path
    ok, err = run_secure_cmd(["/usr/bin/mount", "--bind", "--", real_path, real_path])
    if not ok:
        print(f"Mount Failure: {err}")
        return

    ok, err = run_secure_cmd(["/usr/bin/mount", "-o", "remount,rw", "--", real_path])
    if ok:
        print(f"🔓 Unlocked: {real_path}")
        log_event(f"ALLOWED: {real_path}")
    else:
        print(f"Remount Failure: {err}")
        run_secure_cmd(["/usr/bin/umount", "--", real_path])

def deny_write(path):
    real_path = os.path.realpath(path)
    mounted, _ = get_mount_state(real_path)
    if not mounted:
        print(f"Already locked: {real_path}")
        return

    ok, err = run_secure_cmd(["/usr/bin/umount", "--", real_path])
    if ok:
        print(f"🔒 Locked: {real_path}")
        log_event(f"REVOKED: {real_path}")
    else:
        print(f"Unmount Failure: {err}")

def reset_all():
    if not os.path.exists(LOG_FILE):
        print("No log found.")
        return

    paths_to_reset = set()
    with open(LOG_FILE, "r") as f:
        for line in f:
            match = re.search(r"ALLOWED: (.*)", line)
            if match:
                paths_to_reset.add(match.group(1).strip())

    for p in paths_to_reset:
        mounted, _ = get_mount_state(p)
        if mounted:
            deny_write(p)
    
    # Securely clear the log
    open(LOG_FILE, 'w').close()
    print("✨ System reset to default Read-Only state.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard v3")
    parser.add_argument('--allow', '-a', metavar='DIR')
    parser.add_argument('--deny', '-d', metavar='DIR')
    parser.add_argument('--status', '-s', metavar='DIR')
    parser.add_argument('--reset', action='store_true')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Access Denied: Must be run with sudo.")
        sys.exit(1)

    if args.reset:
        reset_all()
    elif args.status:
        m, rw = get_mount_state(args.status)
        print(f"Path: {os.path.realpath(args.status)}\nState: {'READ-WRITE' if (m and rw) else 'READ-ONLY'}")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
