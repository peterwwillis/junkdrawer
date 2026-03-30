"""
AI Guard: Production-Hardened Dynamic Write Access Controller
============================================================
SECURITY & RELIABILITY UPDATES:
1. Anti-Injection: Path sanitization prevents newline characters in logs.
2. Parent Awareness: Detects if a parent directory is already RW.
3. Anti-Stacking: Logic ensures we don't layer mounts on top of each other.
4. Robust Decoding: Handles kernel octal escapes for special characters.
5. Absolute Binaries: Forces /usr/bin paths to prevent PATH hijacking.
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

def decode_kernel_path(path):
    """Correctly decodes kernel octal escapes (e.g., \\040 for space)."""
    try:
        # Kernel uses literal octal strings. We convert to bytes then decode.
        return path.encode('utf-8').decode('unicode_escape').encode('latin1').decode('utf-8')
    except Exception:
        return path

def log_event(message):
    """Logs sanitized events to prevent log-injection attacks."""
    # Sanitize: Remove newlines to prevent faking log entries
    clean_msg = message.replace('\n', ' ').replace('\r', ' ')
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        if not os.path.exists(LOG_FILE):
            fd = os.open(LOG_FILE, os.O_CREAT | os.O_WRONLY, 0o600)
            os.close(fd)
        with open(LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {clean_msg}\n")
    except Exception as e:
        print(f"Logging Error: {e}")

def get_mount_info():
    """Returns a list of (mount_point, is_rw) from the kernel."""
    mounts = []
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) > 4:
                    path = decode_kernel_path(parts[4])
                    # 'rw' is usually in the vfs options (parts[5])
                    mounts.append((path, "rw" in line))
    except Exception as e:
        print(f"Error reading mountinfo: {e}")
    return mounts

def check_status(target_path):
    """
    Checks if a path is already writable, either directly 
    or via an inherited parent mount.
    """
    real_target = os.path.realpath(target_path)
    mounts = get_mount_info()
    
    # 1. Check for exact mount
    exact_match = next((m for m in mounts if m[0] == real_target), None)
    if exact_match:
        return True, exact_match[1], "exact"

    # 2. Check for parent inheritance (is a parent already RW?)
    for m_path, is_rw in mounts:
        if is_rw and real_target.startswith(m_path + os.sep):
            return True, True, f"inherited from {m_path}"
            
    return False, False, "none"

def run_secure_cmd(args):
    """Executes command directly with argument protection."""
    try:
        result = subprocess.run(args, capture_output=True, text=True, check=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip() or e.stdout.strip()

def allow_write(path):
    real_path = os.path.realpath(path)
    if not os.path.isdir(real_path):
        print(f"Error: '{real_path}' is not a directory.")
        return

    is_mounted, is_rw, reason = check_status(real_path)
    
    if is_rw:
        print(f"Already writable ({reason}): {real_path}")
        return

    # If it's mounted but RO (exact match), we just need to remount
    if is_mounted and reason == "exact":
        print(f"Remounting existing mount as RW: {real_path}")
    else:
        # Create the bind mount first
        ok, err = run_secure_cmd([MOUNT_BIN, "--bind", "--", real_path, real_path])
        if not ok:
            print(f"Mount Failure: {err}")
            return

    # Set to RW
    ok, err = run_secure_cmd([MOUNT_BIN, "-o", "remount,rw", "--", real_path])
    if ok:
        print(f"🔓 Unlocked: {real_path}")
        log_event(f"ALLOWED: {real_path}")
    else:
        print(f"Remount Failure: {err}")
        # Clean up if we just created the bind mount
        if reason != "exact":
            run_secure_cmd([UMOUNT_BIN, "--", real_path])

def deny_write(path):
    real_path = os.path.realpath(path)
    is_mounted, _, reason = check_status(real_path)

    if not is_mounted or reason != "exact":
        print(f"No specific AI-Guard mount found for: {real_path}")
        return

    ok, err = run_secure_cmd([UMOUNT_BIN, "--", real_path])
    if ok:
        print(f"🔒 Locked: {real_path}")
        log_event(f"REVOKED: {real_path}")
    else:
        print(f"Unmount Failure: {err}")

def reset_all():
    if not os.path.exists(LOG_FILE):
        print("No log found.")
        return

    # Extract all paths that were ever allowed
    paths_to_reset = set()
    with open(LOG_FILE, "r") as f:
        for line in f:
            match = re.search(r"ALLOWED: (.*)", line)
            if match:
                paths_to_reset.add(match.group(1).strip())

    active_mounts = [m[0] for m in get_mount_info()]
    
    for p in paths_to_reset:
        if p in active_mounts:
            deny_write(p)
    
    open(LOG_FILE, 'w').close()
    print("✨ Reset complete. All dynamic mounts removed.")

def main():
    parser = argparse.ArgumentParser(description="AI Guard v4")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR')
    group.add_argument('--deny', '-d', metavar='DIR')
    group.add_argument('--status', '-s', metavar='DIR')
    group.add_argument('--reset', action='store_true')
    
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Fatal: Script must be run with sudo (required for mount operations).")
        sys.exit(1)

    if args.reset:
        reset_all()
    elif args.status:
        m, rw, reason = check_status(args.status)
        state = "READ-WRITE" if rw else "READ-ONLY"
        print(f"Path: {os.path.realpath(args.status)}\nState: {state} ({reason})")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)

if __name__ == "__main__":
    main()
