#!/bin/bash
# Generate SSL certificates for Platform, Gateway4, and Gateway5 integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLATFORM_SSL_DIR="$PROJECT_ROOT/volumes/platform/ssl"
GATEWAY4_SSL_DIR="$PROJECT_ROOT/volumes/gateway4/ssl"
GATEWAY5_CERTS_DIR="$PROJECT_ROOT/volumes/gateway5/certificates"

# defaults
FORCE=false
QUIET=false

# parse args (see --help for usage)
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --force   Force regenerate all certificates"
            echo "  -q, --quiet   Minimal output (for CI/CD)"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# logging
log() {
    if [ "$QUIET" = false ]; then
        echo "$1"
    fi
}

log_success() {
    if [ "$QUIET" = false ]; then
        echo "✓ $1"
    fi
}

log_info() {
    if [ "$QUIET" = false ]; then
        echo "→ $1"
    fi
}

log_warn() {
    if [ "$QUIET" = false ]; then
        echo "⚠ $1"
    fi
}

# header
if [ "$QUIET" = false ]; then
    echo "--- certificate generation ---"
    echo ""
fi

# create directories
mkdir -p "$PLATFORM_SSL_DIR"
mkdir -p "$GATEWAY4_SSL_DIR"
mkdir -p "$GATEWAY5_CERTS_DIR"

# check if cert file exists and is valid
check_cert_exists() {
    local file=$1
    if [ -f "$file" ]; then
        if [ -s "$file" ] && grep -q "BEGIN" "$file"; then
            return 0
        fi
    fi
    return 1
}

# should we generate?
should_generate() {
    local cert_file=$1
    local key_file=$2

    if [ "$FORCE" = true ]; then
        return 0
    fi

    if check_cert_exists "$cert_file" && check_cert_exists "$key_file"; then
        return 1
    fi

    return 0
}

# --- platform ssl ---
log "[1/3] checking platform ssl certificates..."

if should_generate "$PLATFORM_SSL_DIR/cert.pem" "$PLATFORM_SSL_DIR/key.pem"; then
    log_info "generating platform ssl certificates..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$PLATFORM_SSL_DIR/key.pem" \
        -out "$PLATFORM_SSL_DIR/cert.pem" \
        -days 1825 -nodes \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,DNS:platform,IP:127.0.0.1" \
        -addext "basicConstraints=CA:FALSE" \
        -addext "keyUsage=digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "platform ssl certificates generated"
        log "  location: $PLATFORM_SSL_DIR"
    else
        echo "✗ failed to generate platform ssl certificates"
        exit 1
    fi
else
    log_success "platform ssl certificates already exist (use --force to regenerate)"
fi

# --- gateway4 ssl ---
log ""
log "[2/3] checking gateway4 ssl certificates..."

if should_generate "$GATEWAY4_SSL_DIR/cert.pem" "$GATEWAY4_SSL_DIR/key.pem"; then
    log_info "generating gateway4 ssl certificates..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$GATEWAY4_SSL_DIR/key.pem" \
        -out "$GATEWAY4_SSL_DIR/cert.pem" \
        -days 1825 -nodes \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,DNS:gateway4,IP:127.0.0.1" \
        -addext "basicConstraints=CA:FALSE" \
        -addext "keyUsage=digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "gateway4 ssl certificates generated"
        log "  location: $GATEWAY4_SSL_DIR"
    else
        echo "✗ failed to generate gateway4 ssl certificates"
        exit 1
    fi
else
    log_success "gateway4 ssl certificates already exist (use --force to regenerate)"
fi

# --- gateway5 certs ---
log ""
log "[3/3] checking gateway5 certificates..."

if should_generate "$GATEWAY5_CERTS_DIR/gw-manager.pem" "$GATEWAY5_CERTS_DIR/gw-manager-key.pem"; then
    log_info "generating gateway5 client certificates..."
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$GATEWAY5_CERTS_DIR/gw-manager-key.pem" \
        -out "$GATEWAY5_CERTS_DIR/gw-manager.pem" \
        -days 1825 -nodes \
        -subj "/CN=gateway5" \
        -addext "subjectAltName=DNS:gateway5,DNS:localhost,IP:127.0.0.1" \
        -addext "basicConstraints=CA:FALSE" \
        -addext "keyUsage=digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=clientAuth,serverAuth" 2>/dev/null

    if [ $? -eq 0 ]; then
        log_success "gateway5 certificates generated"
        log "  location: $GATEWAY5_CERTS_DIR"
    else
        echo "✗ failed to generate gateway5 certificates"
        exit 1
    fi
else
    log_success "gateway5 certificates already exist (use --force to regenerate)"
fi

# --- permissions ---
log ""
log "setting file permissions..."

# platform runs as uid 1001
if command -v chown &> /dev/null && [ "$(id -u)" = "0" ]; then
    chown -R 1001:1001 "$PLATFORM_SSL_DIR"
    log_success "platform ssl directory ownership set to uid 1001"
else
    log_warn "skipping ownership change (requires root)"
fi

# gateway4 runs as uid specified in .env (default: current user)
# ownership is handled by docker user directive, so world-readable is sufficient
log_success "gateway4 ssl directory readable by container user"

# gateway5 runs as uid 100
if command -v chown &> /dev/null && [ "$(id -u)" = "0" ]; then
    chown -R 100:101 "$GATEWAY5_CERTS_DIR"
    log_success "gateway5 certificates directory ownership set to uid 100"
else
    log_warn "skipping ownership change (requires root)"
fi

# make files readable
chmod 644 "$PLATFORM_SSL_DIR"/*.pem 2>/dev/null || true
chmod 644 "$GATEWAY4_SSL_DIR"/*.pem 2>/dev/null || true
chmod 644 "$GATEWAY5_CERTS_DIR"/*.pem 2>/dev/null || true
log_success "file permissions set to 644"

if [ "$QUIET" = false ]; then
    echo ""
    echo "--- certificate generation complete ---"
    echo ""
    echo "next steps:"
    echo "  make up       # start all services"
    echo "  make status   # check service status"
    echo ""
fi
