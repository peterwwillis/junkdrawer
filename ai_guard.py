import subprocess
import argparse
import os
import sys

def run_cmd(cmd):
    """Executes a shell command and handles errors."""
    try:
        subprocess.check_call(cmd, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"Error: Command failed: {cmd}")
        sys.exit(1)

def is_mounted(path):
    """Checks if a path is already a mount point."""
    return os.path.ismount(path)

def allow_write(path):
    """Makes a directory writable by bind-mounting it onto itself."""
    abs_path = os.path.abspath(path)
    
    if not os.path.exists(abs_path):
        print(f"Error: Path '{abs_path}' does not exist.")
        return

    if is_mounted(abs_path):
        print(f"Info: '{abs_path}' is already a mount point (likely writable).")
        return

    print(f"🔓 Unlocking: {abs_path}")
    # Bind mount the path to itself to create a distinct mount point
    run_cmd(f"mount --bind '{abs_path}' '{abs_path}'")
    # Remount it as read-write (default for bind mounts, but explicit is safe)
    run_cmd(f"mount -o remount,rw '{abs_path}'")

def deny_write(path):
    """Makes a directory read-only again by unmounting the bind mount."""
    abs_path = os.path.abspath(path)

    if not is_mounted(abs_path):
        print(f"Info: '{abs_path}' is not currently a mount point (already read-only?).")
        return

    print(f"🔒 Locking: {abs_path}")
    # Unmounting reveals the underlying Read-Only layer from the container mount
    run_cmd(f"umount '{abs_path}'")

def main():
    parser = argparse.ArgumentParser(description="Dynamic Read/Write Toggler for AI Containers")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--allow', '-a', metavar='DIR', help='Make directory writable')
    group.add_argument('--deny', '-d', metavar='DIR', help='Make directory read-only')
    
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("This script must be run as root (use sudo).")
        sys.exit(1)

    if args.allow:
        allow_write(args.allow)
    elif args.deny:
        deny_write(args.deny)

if __name__ == "__main__":
    main()

