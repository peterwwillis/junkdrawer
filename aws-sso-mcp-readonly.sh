#!/usr/bin/env sh
# Usage: ./aws-mcp-readonly.sh <your-sso-profile-name> <region>
set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

ACCOUNT="$1"
PROFILE="$2"
REGION="${3:-us-east-1}"

# 1. Trigger SSO Login (No-op if session is already active)
aws sso login --profile "$PROFILE"

# 2. Extract Temporary Credentials as Environment Variables
# This ensures the process only sees the Read-Only session keys
eval $(aws configure export-credentials --profile "$PROFILE" --format env)

# 3. Export the Region (Proxy needs this for SigV4 signing)
export AWS_REGION="$REGION"

# 4. Run the Managed MCP Proxy
# This bridges your local IAM creds to the remote Managed AWS MCP Server
exec uvx mcp-proxy-for-aws@latest \
  "https://aws-mcp.$REGION.api.aws/mcp" \
  --metadata "AWS_REGION=$REGION"
