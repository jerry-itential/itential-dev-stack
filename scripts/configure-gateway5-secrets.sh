#!/bin/bash
# Configure the Gateway5 local secret store - generate its encryption key
# This script = idempotent meaning, it's safe to run multiple times

set -e

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# must match GATEWAY_SECRETS_ENCRYPT_KEY_FILE in docker-compose.yml (gateway5-data volume)
KEY_FILE="/etc/gateway/gateway_secrets_encryption.key"

# wait for gateway5 to be running
MAX_WAIT=60
for ((i=0; i<MAX_WAIT; i+=2)); do
    if [ "$(docker inspect -f '{{.State.Running}}' gateway5 2>/dev/null)" = "true" ]; then
        break
    fi
    if [ $i -ge $((MAX_WAIT - 2)) ]; then
        log_error "Gateway5 container not running after ${MAX_WAIT}s"
        exit 1
    fi
    sleep 2
done

if docker exec gateway5 test -s "$KEY_FILE"; then
    log_info "Gateway5 secret store key already exists"
    exit 0
fi

# generate as the container user so gateway5 can read it; 400 per Itential docs. the
# server reads the key when a secret is used, so no restart is needed
log_info "Generating Gateway5 secret store key..."
docker exec gateway5 sh -c "umask 377 && head -c 256 /dev/urandom | base64 > $KEY_FILE"
log_info "Gateway5 secret store configured ($KEY_FILE)"
