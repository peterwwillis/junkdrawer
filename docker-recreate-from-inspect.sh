#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  docker-recreate-from-inspect.sh <container> [OPTIONS]

Options:
  --apply      Actually stop + remove + recreate the container.
  --pull       Pull the image before recreating (uses the same image reference).
  --dry-run    Print what would be done without making changes.
  --simple     Omit uncommon/verbose args from output:
                 hostname, domainname, user, shm-size, network, ipc, uts,
                 pid, environment variables, and labels.
  -h|--help    Show this help.

Examples:
  # Print reconstructed docker run command (all options):
  ./docker-recreate-from-inspect.sh my-container

  # Print reconstructed command, omitting env/labels/network/etc.:
  ./docker-recreate-from-inspect.sh my-container --simple

  # Stop/remove + pull latest image tag + recreate:
  ./docker-recreate-from-inspect.sh my-container --apply --pull
EOF
}

if [[ $# -lt 1 ]]; then usage; exit 1; fi

container="$1"; shift || true
apply="false"
pull="false"
dry_run="false"
simple="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)    apply="true" ;;
    --pull)     pull="true" ;;
    --dry-run)  dry_run="true" ;;
    --simple)   simple="true" ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ "$dry_run" == "true" ]] && apply="false"

if ! docker inspect "$container" >/dev/null 2>&1; then
  echo "Container '$container' not found." >&2
  exit 1
fi

# ── helpers ────────────────────────────────────────────────────────────────────
jqv() { jq -r "$1"; }

inspect_json="$(docker inspect "$container" | jq '.[0]')"
q() { printf '%s' "$inspect_json" | jqv "$1"; }
qc() { printf '%s' "$inspect_json" | jq -c "$1"; }

# ── extract fields ─────────────────────────────────────────────────────────────
name="$(q '.Name' | sed 's#^/##')"
image="$(q '.Config.Image')"
entrypoint="$(qc '.Config.Entrypoint')"
cmd="$(qc '.Config.Cmd')"
workdir="$(q '.Config.WorkingDir')"
user="$(q '.Config.User')"
hostname="$(q '.Config.Hostname')"
domainname="$(q '.Config.Domainname')"

restart_name="$(q '.HostConfig.RestartPolicy.Name')"
restart_max="$(q '.HostConfig.RestartPolicy.MaximumRetryCount')"

network_mode="$(q '.HostConfig.NetworkMode')"
pid_mode="$(q '.HostConfig.PidMode')"
ipc_mode="$(q '.HostConfig.IpcMode')"
uts_mode="$(q '.HostConfig.UTSMode')"

privileged="$(q '.HostConfig.Privileged')"
readonly_rootfs="$(q '.HostConfig.ReadonlyRootfs')"
init_flag="$(q '.HostConfig.Init')"

shm_size="$(q '.HostConfig.ShmSize')"
memory="$(q '.HostConfig.Memory')"
memory_swap="$(q '.HostConfig.MemorySwap')"
cpus="$(q '.HostConfig.NanoCpus')"

log_type="$(q '.HostConfig.LogConfig.Type')"

env_list="$(printf '%s' "$inspect_json" | jq -r '.Config.Env[]?')"
labels="$(printf '%s' "$inspect_json" | jq -r '.Config.Labels // {} | to_entries[]? | "\(.key)=\(.value)"')"

port_bindings="$(qc '.HostConfig.PortBindings // {}')"
exposed_ports="$(qc '.Config.ExposedPorts // {}')"

mounts="$(qc '.Mounts // []')"
tmpfs="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Tmpfs // {} | to_entries[]? | "\(.key)=\(.value)"')"

extra_hosts="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.ExtraHosts[]?')"
dns_servers="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Dns[]?')"
dns_search="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.DnsSearch[]?')"
dns_options="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.DnsOptions[]?')"

cap_add="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.CapAdd[]?')"
cap_drop="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.CapDrop[]?')"
devices="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.Devices[]? | "\(.PathOnHost):\(.PathInContainer):\(.CgroupPermissions)"')"
security_opt="$(printf '%s' "$inspect_json" | jq -r '.HostConfig.SecurityOpt[]?')"

# ── build args array ───────────────────────────────────────────────────────────
# Each entry in `args` is one logical argument (flag + value as a single string,
# or a bare flag). The image and command args go into `image_args` so they can
# always be printed last.
args=()
image_args=()

add() { args+=("$@"); }           # add one or more args
addi() { image_args+=("$@"); }    # add to post-image section

# ── restart policy ─────────────────────────────────────────────────────────────
if [[ -n "$restart_name" && "$restart_name" != "null" && "$restart_name" != "no" ]]; then
  if [[ "$restart_name" == "on-failure" && "$restart_max" != "0" && "$restart_max" != "null" ]]; then
    add "--restart on-failure:$restart_max"
  else
    add "--restart $restart_name"
  fi
fi

# ── identity / namespace (omitted by --simple) ─────────────────────────────────
if [[ "$simple" == "false" ]]; then
  [[ -n "$hostname"   && "$hostname"   != "null" ]] && add "--hostname $hostname"
  [[ -n "$domainname" && "$domainname" != "null" ]] && add "--domainname $domainname"
  [[ -n "$user"       && "$user"       != "null" && "$user"       != "" ]] && add "--user $user"

  [[ -n "$network_mode" && "$network_mode" != "null" && "$network_mode" != "default" ]] && add "--network $network_mode"
  [[ -n "$pid_mode"     && "$pid_mode"     != "null" && "$pid_mode"     != "" ]]        && add "--pid $pid_mode"
  [[ -n "$ipc_mode"     && "$ipc_mode"     != "null" && "$ipc_mode"     != "" ]]        && add "--ipc $ipc_mode"
  [[ -n "$uts_mode"     && "$uts_mode"     != "null" && "$uts_mode"     != "" ]]        && add "--uts $uts_mode"
fi

# ── workdir (kept in both modes) ───────────────────────────────────────────────
[[ -n "$workdir" && "$workdir" != "null" && "$workdir" != "" ]] && add "--workdir $workdir"

# ── boolean flags ──────────────────────────────────────────────────────────────
[[ "$privileged"      == "true" ]] && add "--privileged"
[[ "$readonly_rootfs" == "true" ]] && add "--read-only"
[[ "$init_flag"       == "true" ]] && add "--init"

# ── resources ──────────────────────────────────────────────────────────────────
if [[ "$simple" == "false" ]]; then
  [[ "$shm_size"    != "0" && "$shm_size"    != "null" ]] && add "--shm-size $shm_size"
fi
[[ "$memory"      != "0" && "$memory"      != "null" ]] && add "--memory $memory"
[[ "$memory_swap" != "0" && "$memory_swap" != "null" ]] && add "--memory-swap $memory_swap"
if [[ "$cpus" != "0" && "$cpus" != "null" ]]; then
  add "--cpus $(awk -v n="$cpus" 'BEGIN{printf "%.3f", n/1000000000}')"
fi

# ── logging driver ─────────────────────────────────────────────────────────────
[[ -n "$log_type" && "$log_type" != "null" && "$log_type" != "json-file" ]] \
  && add "--log-driver $log_type"

# ── env vars (omitted by --simple) ────────────────────────────────────────────
if [[ "$simple" == "false" ]]; then
  while IFS= read -r e; do
    [[ -n "$e" ]] && add "--env $(printf '%q' "$e")"
  done <<< "$env_list"
fi

# ── labels (omitted by --simple) ──────────────────────────────────────────────
if [[ "$simple" == "false" ]]; then
  while IFS= read -r l; do
    [[ -n "$l" ]] && add "--label $(printf '%q' "$l")"
  done <<< "$labels"
fi

# ── DNS / extra hosts ──────────────────────────────────────────────────────────
while IFS= read -r h; do [[ -n "$h" ]] && add "--add-host $h";     done <<< "$extra_hosts"
while IFS= read -r d; do [[ -n "$d" ]] && add "--dns $d";          done <<< "$dns_servers"
while IFS= read -r s; do [[ -n "$s" ]] && add "--dns-search $s";   done <<< "$dns_search"
while IFS= read -r o; do [[ -n "$o" ]] && add "--dns-option $o";   done <<< "$dns_options"

# ── capabilities / security / devices ─────────────────────────────────────────
while IFS= read -r c;  do [[ -n "$c"  ]] && add "--cap-add $c";       done <<< "$cap_add"
while IFS= read -r c;  do [[ -n "$c"  ]] && add "--cap-drop $c";      done <<< "$cap_drop"
while IFS= read -r so; do [[ -n "$so" ]] && add "--security-opt $so"; done <<< "$security_opt"
while IFS= read -r dv; do [[ -n "$dv" ]] && add "--device $dv";       done <<< "$devices"

# ── ports ─────────────────────────────────────────────────────────────────────
if [[ "$port_bindings" != "{}" ]]; then
  while IFS= read -r line; do
    cport="${line%%|*}"; rest="${line#*|}"; hip="${rest%%|*}"; hport="${rest#*|}"
    if [[ -n "$hip" && "$hip" != "0.0.0.0" ]]; then
      add "--publish ${hip}:${hport}:${cport}"
    else
      add "--publish ${hport}:${cport}"
    fi
  done < <(printf '%s' "$port_bindings" | jq -r '
    to_entries[]
    | .key as $cport
    | (.value // [])[]
    | "\($cport)|\(.HostIp // "")|\(.HostPort // "")"
  ')
elif [[ "$exposed_ports" != "{}" ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && add "--expose $p"
  done < <(printf '%s' "$exposed_ports" | jq -r 'keys[]')
fi

# ── mounts ────────────────────────────────────────────────────────────────────
while IFS= read -r m; do
  [[ -z "$m" ]] && continue
  src="$(printf '%s' "$m" | jq -r '.Source // empty')"
  dst="$(printf '%s' "$m" | jq -r '.Destination // empty')"
  rw="$(printf '%s' "$m" | jq -r '.RW')"
  typ="$(printf '%s' "$m" | jq -r '.Type // empty')"
  [[ -z "$src" || -z "$dst" ]] && continue
  if [[ "$typ" == "volume" || "$typ" == "bind" ]]; then
    if [[ "$rw" == "false" ]]; then
      add "--volume ${src}:${dst}:ro"
    else
      add "--volume ${src}:${dst}"
    fi
  fi
done < <(printf '%s' "$mounts" | jq -c '.[]')

while IFS= read -r t; do
  [[ -n "$t" ]] && add "--tmpfs $t"
done <<< "$tmpfs"

# ── entrypoint ──────────────────────────────────────────────���─────────────────
ep_extra=""
if [[ "$entrypoint" != "null" && "$entrypoint" != "[]" ]]; then
  ep_len="$(printf '%s' "$entrypoint" | jq 'length')"
  if [[ "$ep_len" -ge 1 ]]; then
    ep0="$(printf '%s' "$entrypoint" | jq -r '.[0]')"
    add "--entrypoint $(printf '%q' "$ep0")"
    ep_extra="$(printf '%s' "$entrypoint" | jq -r '.[1:][]?' || true)"
  fi
fi

# ── image (always last before cmd args) ───────────────────────────────────────
addi "$image"

# extra entrypoint args + Cmd go after image
if [[ -n "${ep_extra:-}" ]]; then
  while IFS= read -r a; do [[ -n "$a" ]] && addi "$(printf '%q' "$a")"; done <<< "$ep_extra"
fi

if [[ "$cmd" != "null" && "$cmd" != "[]" ]]; then
  while IFS= read -r a; do [[ -n "$a" ]] && addi "$(printf '%q' "$a")"; done \
    < <(printf '%s' "$cmd" | jq -r '.[]')
fi

# ── pretty-print the command ───────────────────────────────────────────────────
print_command() {
  local indent="    "
  echo "docker run \\"
  for arg in "${args[@]}"; do
    echo "${indent}${arg} \\"
  done
  # image + cmd args — last line has no trailing backslash
  local total=${#image_args[@]}
  local i=0
  for arg in "${image_args[@]}"; do
    i=$(( i + 1 ))
    if [[ $i -lt $total ]]; then
      echo "${indent}${arg} \\"
    else
      echo "${indent}${arg}"
    fi
  done
}

# ── build the actual exec array (for --apply) ─────────────────────────────────
# We need a real array with properly-split tokens for execution.
build_exec_array() {
  exec_args=(docker run -d --name "$name")
  for arg in "${args[@]}"; do
    # Split the stored string back into tokens (flag + value, or bare flag)
    read -ra tokens <<< "$arg"
    exec_args+=("${tokens[@]}")
  done
  for arg in "${image_args[@]}"; do
    exec_args+=("$arg")
  done
}

# ── output ────────────────────────────────────────────────────────────────────
echo "# Reconstructed docker run command (best effort)"
[[ "$simple" == "true" ]] && echo "# (--simple: hostname, domainname, user, shm-size, network, ipc, uts, pid, env, labels omitted)"
echo
print_command
echo
echo "# Image : $image"
echo "# Name  : $name"
echo "# Net   : $network_mode"
echo

# ── apply ─────────────────────────────────────────────────────────────────────
if [[ "$apply" == "true" ]]; then
  if [[ "$dry_run" == "true" ]]; then
    echo "[dry-run] Would stop, remove, and recreate '$name'. No changes made."
    exit 0
  fi

  build_exec_array

  echo "Stopping container '$container'..."
  docker stop "$container" >/dev/null 2>&1 || true

  echo "Removing container '$container'..."
  docker rm "$container"

  if [[ "$pull" == "true" ]]; then
    echo "Pulling image '$image'..."
    docker pull "$image"
  fi

  echo "Recreating container..."
  "${exec_args[@]}"

  echo "Done."
else
  echo "# No changes applied. Re-run with --apply [--pull] to recreate."
fi
