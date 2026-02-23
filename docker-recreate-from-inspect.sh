#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  docker-recreate-from-inspect.sh <container> [--apply] [--pull] [--dry-run]

Examples:
  # Just print a reconstructed docker run command:
  ./docker-recreate-from-inspect.sh my-container

  # Stop/remove + pull latest image (same tag) + recreate:
  ./docker-recreate-from-inspect.sh my-container --apply --pull

Flags:
  --apply    Actually stop + remove + recreate the container.
  --pull     Pull the image before recreating (uses the same image reference).
  --dry-run  Print what would be done (implies no changes); still prints run cmd.
EOF
}

if [[ $# -lt 1 ]]; then usage; exit 1; fi

container="$1"; shift || true
apply="false"
pull="false"
dry_run="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) apply="true" ;;
    --pull) pull="true" ;;
    --dry-run) dry_run="true" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ "$dry_run" == "true" ]]; then
  apply="false"
fi

if ! docker inspect "$container" >/dev/null 2>&1; then
  echo "Container '$container' not found." >&2
  exit 1
fi

# Helper: JSON query
jqv() { jq -r "$1" ; }

inspect_json="$(docker inspect "$container" | jq '.[0]')"

name="$(printf '%s' "$inspect_json" | jqv '.Name' | sed 's#^/##')"
image="$(printf '%s' "$inspect_json" | jqv '.Config.Image')"
entrypoint="$(printf '%s' "$inspect_json" | jq -c '.Config.Entrypoint')"
cmd="$(printf '%s' "$inspect_json" | jq -c '.Config.Cmd')"
workdir="$(printf '%s' "$inspect_json" | jqv '.Config.WorkingDir')"
user="$(printf '%s' "$inspect_json" | jqv '.Config.User')"
hostname="$(printf '%s' "$inspect_json" | jqv '.Config.Hostname')"
domainname="$(printf '%s' "$inspect_json" | jqv '.Config.Domainname')"

restart_name="$(printf '%s' "$inspect_json" | jqv '.HostConfig.RestartPolicy.Name')"
restart_max="$(printf '%s' "$inspect_json" | jqv '.HostConfig.RestartPolicy.MaximumRetryCount')"

network_mode="$(printf '%s' "$inspect_json" | jqv '.HostConfig.NetworkMode')"
pid_mode="$(printf '%s' "$inspect_json" | jqv '.HostConfig.PidMode')"
ipc_mode="$(printf '%s' "$inspect_json" | jqv '.HostConfig.IpcMode')"
uts_mode="$(printf '%s' "$inspect_json" | jqv '.HostConfig.UTSMode')"

privileged="$(printf '%s' "$inspect_json" | jqv '.HostConfig.Privileged')"
readonly_rootfs="$(printf '%s' "$inspect_json" | jqv '.HostConfig.ReadonlyRootfs')"
init_flag="$(printf '%s' "$inspect_json" | jqv '.HostConfig.Init')"

shm_size="$(printf '%s' "$inspect_json" | jqv '.HostConfig.ShmSize')"
memory="$(printf '%s' "$inspect_json" | jqv '.HostConfig.Memory')"
memory_swap="$(printf '%s' "$inspect_json" | jqv '.HostConfig.MemorySwap')"
cpus="$(printf '%s' "$inspect_json" | jqv '.HostConfig.NanoCpus')"

log_type="$(printf '%s' "$inspect_json" | jqv '.HostConfig.LogConfig.Type')"

# Arrays/maps
env_list="$(printf '%s' "$inspect_json" | jq -r '.Config.Env[]?')"
labels="$(printf '%s' "$inspect_json" | jq -r '.Config.Labels // {} | to_entries[]? | "\(.key)=\(.value)"')"

# Ports:
# HostConfig.PortBindings: {"80/tcp":[{"HostIp":"","HostPort":"8080"}], ...}
port_bindings="$(printf '%s' "$inspect_json" | jq -c '.HostConfig.PortBindings // {}')"
exposed_ports="$(printf '%s' "$inspect_json" | jq -c '.Config.ExposedPorts // {}')"

# Mounts:
# Use .Mounts for runtime mounts (binds/volumes/tmpfs) and re-express as -v/--mount best effort.
mounts="$(printf '%s' "$inspect_json" | jq -c '.Mounts // []')"
tmpfs="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Tmpfs // {} | to_entries[]? | "\(.key)=\(.value)"')"

extra_hosts="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.ExtraHosts[]?')"
dns_servers="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Dns[]?')"
dns_search="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.DnsSearch[]?')"
dns_options="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.DnsOptions[]?')"

cap_add="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.CapAdd[]?')"
cap_drop="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.CapDrop[]?')"
devices="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Devices[]? | "\(.PathOnHost):\(.PathInContainer):\(.CgroupPermissions)"')"

security_opt="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.SecurityOpt[]?')"

# Command assembly
run=(docker run -d --name "$name")

# Restart policy
if [[ -n "$restart_name" && "$restart_name" != "null" && "$restart_name" != "no" ]]; then
  if [[ "$restart_name" == "on-failure" && "$restart_max" != "0" && "$restart_max" != "null" ]]; then
    run+=(--restart "on-failure:$restart_max")
  else
    run+=(--restart "$restart_name")
  fi
fi

# Basic identity options
[[ -n "$hostname" && "$hostname" != "null" ]] && run+=(--hostname "$hostname")
[[ -n "$domainname" && "$domainname" != "null" ]] && run+=(--domainname "$domainname")
[[ -n "$workdir" && "$workdir" != "null" && "$workdir" != "" ]] && run+=(-w "$workdir")
[[ -n "$user" && "$user" != "null" && "$user" != "" ]] && run+=(-u "$user")

# Namespaces / modes
[[ -n "$network_mode" && "$network_mode" != "null" && "$network_mode" != "default" ]] && run+=(--network "$network_mode")
[[ -n "$pid_mode" && "$pid_mode" != "null" && "$pid_mode" != "" ]] && run+=(--pid "$pid_mode")
[[ -n "$ipc_mode" && "$ipc_mode" != "null" && "$ipc_mode" != "" ]] && run+=(--ipc "$ipc_mode")
[[ -n "$uts_mode" && "$uts_mode" != "null" && "$uts_mode" != "" ]] && run+=(--uts "$uts_mode")

# Flags
[[ "$privileged" == "true" ]] && run+=(--privileged)
[[ "$readonly_rootfs" == "true" ]] && run+=(--read-only)
[[ "$init_flag" == "true" ]] && run+=(--init)

# Resources (best effort)
if [[ "$shm_size" != "0" && "$shm_size" != "null" ]]; then
  run+=(--shm-size "$shm_size")
fi
if [[ "$memory" != "0" && "$memory" != "null" ]]; then
  run+=(--memory "$memory")
fi
if [[ "$memory_swap" != "0" && "$memory_swap" != "null" ]]; then
  run+=(--memory-swap "$memory_swap")
fi
if [[ "$cpus" != "0" && "$cpus" != "null" ]]; then
  # NanoCpus is 1e9 units per CPU
  run+=(--cpus "$(awk -v n="$cpus" 'BEGIN{printf "%.3f", n/1000000000}')")
fi

# Logging driver (options not fully reconstructed here)
[[ -n "$log_type" && "$log_type" != "null" && "$log_type" != "json-file" ]] && run+=(--log-driver "$log_type")

# Env
while IFS= read -r e; do
  [[ -n "$e" ]] && run+=(-e "$e")
done <<< "$env_list"

# Labels
while IFS= read -r l; do
  [[ -n "$l" ]] && run+=(--label "$l")
done <<< "$labels"

# DNS / hosts
while IFS= read -r h; do
  [[ -n "$h" ]] && run+=(--add-host "$h")
done <<< "$extra_hosts"

while IFS= read -r d; do
  [[ -n "$d" ]] && run+=(--dns "$d")
done <<< "$dns_servers"

while IFS= read -r s; do
  [[ -n "$s" ]] && run+=(--dns-search "$s")
done <<< "$dns_search"

while IFS= read -r o; do
  [[ -n "$o" ]] && run+=(--dns-option "$o")
done <<< "$dns_options"

# Capabilities, security, devices
while IFS= read -r c; do
  [[ -n "$c" ]] && run+=(--cap-add "$c")
done <<< "$cap_add"

while IFS= read -r c; do
  [[ -n "$c" ]] && run+=(--cap-drop "$c")
done <<< "$cap_drop"

while IFS= read -r so; do
  [[ -n "$so" ]] && run+=(--security-opt "$so")
done <<< "$security_opt"

while IFS= read -r dev; do
  [[ -n "$dev" ]] && run+=(--device "$dev")
done <<< "$devices"

# Ports: use PortBindings if present, else fall back to ExposedPorts
if [[ "$port_bindings" != "{}" ]]; then
  # Iterate bindings
  while IFS= read -r line; do
    # line: containerPortProto|HostIp|HostPort
    cport="${line%%|*}"
    rest="${line#*|}"
    hip="${rest%%|*}"
    hport="${rest#*|}"

    # docker run syntax: -p [ip:]hostPort:containerPort
    if [[ -n "$hip" && "$hip" != "0.0.0.0" ]]; then
      run+=(-p "${hip}:${hport}:${cport}")
    else
      run+=(-p "${hport}:${cport}")
    fi
  done < <(printf '%s' "$port_bindings" | jq -r '
    to_entries[]
    | .key as $cport
    | (.value // [])[]
    | "\($cport)|\(.HostIp // "")|\(.HostPort // "")"
  ')
elif [[ "$exposed_ports" != "{}" ]]; then
  # Just expose container ports (no host mapping)
  while IFS= read -r p; do
    [[ -n "$p" ]] && run+=(--expose "$p")
  done < <(printf '%s' "$exposed_ports" | jq -r 'keys[]')
fi

# Mounts -> -v (best effort)
# For named volumes, Source is volume name; for bind mounts, Source is host path.
# We re-create as: -v Source:Destination[:ro]
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  src="$(printf '%s' "$m" | jq -r '.Source // empty')"
  dst="$(printf '%s' "$m" | jq -r '.Destination // empty')"
  mode_ro="$(printf '%s' "$m" | jq -r '.RW')"
  typ="$(printf '%s' "$m" | jq -r '.Type // empty')"

  [[ -z "$src" || -z "$dst" ]] && continue

  # Skip some internal mounts if any (rare)
  if [[ "$typ" == "volume" || "$typ" == "bind" ]]; then
    if [[ "$mode_ro" == "false" ]]; then
      run+=(-v "${src}:${dst}:ro")
    else
      run+=(-v "${src}:${dst}")
    fi
  fi
done < <(printf '%s' "$mounts" | jq -c '.[]')

# Tmpfs
while IFS= read -r t; do
  [[ -n "$t" ]] && run+=(--tmpfs "$t")
done <<< "$tmpfs"

# Entrypoint and cmd
# If entrypoint is non-null and non-empty, set it.
if [[ "$entrypoint" != "null" && "$entrypoint" != "[]" ]]; then
  # Join JSON array into a shell-escaped string list
  # Prefer --entrypoint for the first element only; if entrypoint has multiple, it's tricky.
  ep_len="$(printf '%s' "$entrypoint" | jq 'length')"
  if [[ "$ep_len" -ge 1 ]]; then
    ep0="$(printf '%s' "$entrypoint" | jq -r '.[0]')"
    run+=(--entrypoint "$ep0")
    # If there are extra entrypoint args, append them before image as part of "cmd" later.
    ep_extra="$(printf '%s' "$entrypoint" | jq -r '.[1:][]?' || true)"
  else
    ep_extra=""
  fi
else
  ep_extra=""
fi

run+=("$image")

# Append entrypoint extra args (if any), then Cmd array items
if [[ -n "${ep_extra:-}" ]]; then
  while IFS= read -r a; do
    [[ -n "$a" ]] && run+=("$a")
  done <<< "$ep_extra"
fi

if [[ "$cmd" != "null" && "$cmd" != "[]" ]]; then
  while IFS= read -r a; do
    [[ -n "$a" ]] && run+=("$a")
  done < <(printf '%s' "$cmd" | jq -r '.[]')
fi

echo "Reconstructed run command (best effort):"
printf '  %q' "${run[@]}"
echo
echo

echo "Image reference: $image"
echo "Container name : $name"
echo "Network mode   : $network_mode"
echo

if [[ "$apply" == "true" ]]; then
  if [[ "$dry_run" == "true" ]]; then
    echo "[dry-run] Would stop/remove and recreate."
    exit 0
  fi

  echo "Stopping container (if running)..."
  docker stop "$container" >/dev/null 2>&1 || true

  echo "Removing container..."
  docker rm "$container"

  if [[ "$pull" == "true" ]]; then
    echo "Pulling image..."
    docker pull "$image"
  fi

  echo "Recreating container..."
  "${run[@]}"

  echo "Done."
else
  echo "No changes applied. Re-run with --apply (and optionally --pull) to recreate."
fi
