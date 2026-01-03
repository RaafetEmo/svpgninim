#!/bin/bash

#=============================================================================
# NANOMINER MONERO (XMR) MINING - NANOPOOL
# Auto-connects to Nanopool - NO POOL URL NEEDED!
#=============================================================================

#=============================================================================
# CONFIGURATION - EDIT THESE
#=============================================================================
WALLET="47PFHCgahfpFHUN7NcRRoZYYewoexEnVxeDiEVtbhXpigBjyE7QrRFp3i5FmZy74C2j9sXcYiX3fJNS5gaB6wAL2NEipZxg"
WORKER="VPS-2"
EMAIL="your@email.com"

# Miner Settings
VERSION="3.10.0"
CPU_THREADS="0"

#=============================================================================
# PATHS
#=============================================================================
DIR="$HOME/nanominer-xmr"
MINER="$DIR/nanominer"
LOGS="$DIR/logs"

#=============================================================================
# FUNCTIONS
#=============================================================================
msg() { echo "[*] $1"; }
ok() { echo "[✓] $1"; }
err() { echo "[✗] $1"; exit 1; }
warn() { echo "[!] $1"; }

banner() {
    clear
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   Nanominer v${VERSION} - Monero (XMR)       ║"
    echo "║   Auto-connects to Nanopool               ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

install_deps() {
    msg "Checking dependencies..."
    for d in wget tar; do
        if ! command -v $d >/dev/null 2>&1; then
            warn "Installing $d..."
            apt-get update -qq && apt-get install -y $d || err "Failed to install $d"
        fi
        ok "$d ready"
    done
    echo ""
}

download() {
    msg "Downloading Nanominer v${VERSION}..."
    cd "$MINER" || err "Cannot cd to $MINER"
    
    if [ -f "nanominer" ]; then
        ok "Already exists"
        return 0
    fi
    
    url="https://github.com/nanopool/nanominer/releases/download/v${VERSION}/nanominer-linux-${VERSION}.tar.gz"
    
    wget -q --show-progress "$url" -O nm.tar.gz || err "Download failed"
    tar xzf nm.tar.gz || err "Extract failed"
    rm nm.tar.gz
    chmod +x nanominer
    
    ok "Nanominer ready"
    echo ""
}

make_config() {
    msg "Creating config.ini..."
    cd "$MINER" || err "Cannot cd to $MINER"
    
    cat > config.ini <<EOF
[RandomX]
wallet = $WALLET
rigName = $WORKER
email = $EMAIL
EOF

    if [ "$CPU_THREADS" != "0" ]; then
        echo "cpuThreads = $CPU_THREADS" >> config.ini
    fi
    
    cat >> config.ini <<EOF

memTweak = 1
logPath = $LOGS
EOF
    
    ok "Config created"
    echo ""
    echo "Settings:"
    wallet_start=$(echo $WALLET | cut -c1-12)
    wallet_end=$(echo $WALLET | cut -c87-95)
    echo "  Wallet:  ${wallet_start}...${wallet_end}"
    echo "  Worker:  $WORKER"
    echo "  Pool:    Nanopool (auto)"
    if [ "$CPU_THREADS" != "0" ]; then
        echo "  Threads: $CPU_THREADS"
    else
        echo "  Threads: All CPUs"
    fi
    echo ""
}

optimize() {
    msg "Optimizing..."
    if modprobe msr 2>/dev/null; then
        ok "MSR loaded"
    else
        warn "MSR unavailable"
    fi
    
    if sysctl -w vm.nr_hugepages=1168 >/dev/null 2>&1; then
        ok "Huge pages set"
    else
        warn "Huge pages failed (may need root or writable /proc)"
    fi
    echo ""
}

mine() {
    cd "$MINER" || err "Cannot cd to $MINER"
    pkill -9 nanominer 2>/dev/null
    sleep 1
    
    banner
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           🚀 MINING STARTED 🚀                ║"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║ Worker: $WORKER"
    echo "║ Coin:   Monero (XMR)"
    echo "║ Pool:   Nanopool (automatic)"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║ Press Ctrl+C to stop"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
    
    ./nanominer
}

stop() {
    echo ""
    warn "Stopping..."
    pkill -9 nanominer 2>/dev/null
    ok "Stopped"
    echo ""
    exit 0
}

validate_wallet() {
    # Simple check: starts with 4 and is 95 chars
    wallet_len=$(echo -n "$WALLET" | wc -c)
    wallet_first=$(echo "$WALLET" | cut -c1)
    
    if [ "$wallet_first" != "4" ] || [ "$wallet_len" != "95" ]; then
        err "Invalid Monero wallet!"
    fi
}

#=============================================================================
# MAIN
#=============================================================================
main() {
    banner
    
    # Validate
    validate_wallet
    
    # Setup
    mkdir -p "$DIR" "$MINER" "$LOGS"
    
    install_deps
    optimize
    download
    make_config
    mine
}

trap stop INT TERM
main
