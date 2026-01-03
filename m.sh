#!/bin/bash

#=============================================================================
# NANOMINER MONERO (XMR) MINING - NANOPOOL
# Nanominer automatically connects to Nanopool - NO POOL URL NEEDED!
#=============================================================================

#=============================================================================
# CONFIGURATION - EDIT THESE
#=============================================================================
WALLET="47PFHCgahfpFHUN7NcRRoZYYewoexEnVxeDiEVtbhXpigBjyE7QrRFp3i5FmZy74C2j9sXcYiX3fJNS5gaB6wAL2NEipZxg"
WORKER="VPS-2"
EMAIL="your@email.com"

# Miner Settings
VERSION="3.10.0"
CPU_THREADS="0"  # 0 = use all threads

#=============================================================================
# COLORS
#=============================================================================
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'; B='\033[1m'

#=============================================================================
# PATHS
#=============================================================================
DIR="$HOME/nanominer-xmr"
MINER="$DIR/nanominer"
LOGS="$DIR/logs"

#=============================================================================
# FUNCTIONS
#=============================================================================
msg() { echo -e "${C}[*]${N} ${B}$1${N}"; }
ok() { echo -e "${G}[✓]${N} $1"; }
err() { echo -e "${R}[✗]${N} $1"; exit 1; }
warn() { echo -e "${Y}[!]${N} $1"; }

banner() {
    clear
    echo -e "${C}╔═══════════════════════════════════════════════╗${N}"
    echo -e "${C}║${W}   Nanominer v${VERSION} - Monero (XMR)       ${N}${C}║${N}"
    echo -e "${C}║${W}   Auto-connects to Nanopool               ${N}${C}║${N}"
    echo -e "${C}╚═══════════════════════════════════════════════╝${N}"
    echo ""
}

install_deps() {
    msg "Checking dependencies..."
    for d in wget tar; do
        command -v $d &>/dev/null || {
            warn "Installing $d..."
            sudo apt-get update -qq && sudo apt-get install -y $d || err "Failed to install $d"
        }
        ok "$d ready"
    done
    echo ""
}

download() {
    msg "Downloading Nanominer v${VERSION}..."
    cd "$MINER" || err "Cannot cd to $MINER"
    
    [ -f "nanominer" ] && { ok "Already exists"; return 0; }
    
    local url="https://github.com/nanopool/nanominer/releases/download/v${VERSION}/nanominer-linux-${VERSION}.tar.gz"
    
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

    [ "$CPU_THREADS" != "0" ] && echo "cpuThreads = $CPU_THREADS" >> config.ini
    
    cat >> config.ini <<EOF

memTweak = 1
logPath = $LOGS
EOF
    
    ok "Config created"
    echo ""
    echo -e "${C}Settings:${N}"
    echo -e "  Wallet:  ${Y}${WALLET:0:12}...${WALLET: -8}${N}"
    echo -e "  Worker:  ${W}$WORKER${N}"
    echo -e "  Pool:    ${G}Nanopool (auto)${N}"
    [ "$CPU_THREADS" != "0" ] && echo -e "  Threads: $CPU_THREADS" || echo -e "  Threads: All CPUs"
    echo ""
}

optimize() {
    msg "Optimizing..."
    sudo modprobe msr 2>/dev/null && ok "MSR loaded" || warn "MSR unavailable"
    sudo sysctl -w vm.nr_hugepages=1168 &>/dev/null && ok "Huge pages set" || warn "Huge pages failed"
    echo ""
}

mine() {
    cd "$MINER" || err "Cannot cd to $MINER"
    pkill -9 nanominer 2>/dev/null; sleep 1
    
    banner
    echo -e "${G}╔═══════════════════════════════════════════════╗${N}"
    echo -e "${G}║           🚀 MINING STARTED 🚀                ║${N}"
    echo -e "${G}╠═══════════════════════════════════════════════╣${N}"
    echo -e "${G}║${N} Worker: ${W}$WORKER${N}"
    echo -e "${G}║${N} Coin:   ${C}Monero (XMR)${N}"
    echo -e "${G}║${N} Pool:   ${Y}Nanopool (automatic)${N}"
    echo -e "${G}╠═══════════════════════════════════════════════╣${N}"
    echo -e "${G}║${N} Press ${Y}Ctrl+C${N} to stop"
    echo -e "${G}╚═══════════════════════════════════════════════╝${N}"
    echo ""
    
    ./nanominer
}

stop() {
    echo ""; warn "Stopping..."; pkill -9 nanominer 2>/dev/null
    ok "Stopped"; echo ""; exit 0
}

#=============================================================================
# MAIN
#=============================================================================
main() {
    banner
    
    # Validate
    [[ ! "$WALLET" =~ ^4[0-9A-Za-z]{94}$ ]] && err "Invalid Monero wallet!"
    
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
