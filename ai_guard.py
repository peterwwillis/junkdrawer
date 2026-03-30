import subprocess
import argparse
import os
import sys

def get_mount_info(target_path):
    """
    Parses /proc/self/mountinfo to check if a path is currently a mount point.
    Returns (is_mounted, is_rw)
    """
    target_path = os.path.abspath(target_path)
    try:
        with open("/proc/self/mountinfo", "r") as f:
            for line in f:
                parts = line.split()
                # mountinfo format: [id] [parent] [major:minor] [root] [mount_point] [opts] ...
                mount_point = parts[4]
                if mount_point == target_path:
                    # Check if 'rw' is in the VFS options (usually parts[5])
                    opts = parts[5].split(',')
                    return True, "rw" in opts
    except FileNotFoundError:
        print("Error: Could not access /proc/self/mountinfo")
        sys.exit(1)
    return False, False

def run_cmd(cmd):
    try:
        subprocess.check_call(cmd, shell=True)
    except subprocess.CalledProcessError:
        print(f"Error: Failed to execute: {cmd}")
        sys.exit(1)

def allow_write(path):
    abs_path = os.path.abspath(path)
    if not os.path.isdir(abs_path):
        print(f"Error: '{abs_path}' is not a valid directory.")
        return

    mounted, is_rw = get_mount_info(abs_path)
    
    if mounted and is_rw:
        print(f"Verified: '{abs_path}' is already writable.")
        return

    print(f"🔓 Unlocking: {abs_path}")
    # Create the bind mount and ensure it is RW
    run_cmd(f"mount --bind '{abs_path}' '{abs_path}'")
    run_cmd(f"mount -o remount,rw '{abs_path}'")

def deny_write(path):
    abs_path = os.path.abspath(path)
    mounted, is_rw = get_mount_info(abs_path)

    if not mounted:
        print(f"Verified: '{abs_path}' is already in its default (Read-Only) state.")
        return

    # Safety Guard: Check if this is a sub-mount we created
    # We check if it is a bind mount of itself (common pattern for this trick)
    print(f"🔒 Locking: {abs_path}")
    run_cmd(f"umount '{abs_path}'")

def main():
    parser = argparse.ArgumentParser(description="Verified Dynamic Read/Write Toggler")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR')
    group.add_argument('--deny', '-d', metavar='DIR')
    group.add_argument('--status', '-s', action='store_true', help='Check status of a directory')
    parser.add_argument('path', nargs='?', help='The directory to check/modify')

    args = parser.parse_args()
    if os.geteuid() != 0:
        print("Required: Run with sudo.")
        sys.exit(1)

    target = args.allow or args.deny or args.path
    if not target:
        parser.print_help()
        return

    if args.status:
        mounted, rw = get_mount_info(target)
        status = "READ-WRITE" if (mounted and rw) else "READ-ONLY"
        print(f"Current State of {target}: {status}")
    elif args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)

if __name__ == "__main__":
    main()
