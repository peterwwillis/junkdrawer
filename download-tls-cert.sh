#!/usr/bin/env sh
# download-tls-cert.sh - Download TLS certificate from a host/port

set -e
_get_cert () {
  openssl s_client -showcerts -connect "$1":"$2" </dev/null 2>/dev/null | openssl x509 -outform PEM 
}
if [ $# -lt 2 ] ; then
  echo "Usage: $0 HOST PORT [OUTFILE]"
  echo ""
  echo "Connects to TCP PORT on HOST and downloads TLS certificates."
  echo "Saves to OUTFILE if it is specified, otherwise outputs to standard out."
  exit 1
fi
HOST="$1"; shift
PORT="$1"; shift
if [ $# -gt 0 ] ; then
  _get_cert "$HOST" "$PORT" > "$1"
else
  _get_cert "$HOST" "$PORT"
fi
