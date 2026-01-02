#!/bin/bash

# Monero P2Pool + XMRig Mining Setup Script with Tor
# Usage: curl https://your-domain.com/m.sh | sh -s <wallet_address>

set -e

WALLET_ADDRESS="$1"
INSTALL_DIR="$HOME/monero-mining"
MONERO_VERSION="v0.18.4.4"
XMRIG_VERSION="6.21.3"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
}

# Check if wallet address is provided
if [ -z "$WALLET_ADDRESS" ]; then
    print_error "Wallet address not provided!"
    echo "Usage: curl https://your-domain.com/m.sh | sh -s <wallet_address>"
    exit 1
fi

print_status "Starting Monero mining setup..."
print_status "Wallet address: $WALLET_ADDRESS"

# Detect environment
IS_DOCKER=0
if [ -f /.dockerenv ]; then
    print_warning "Running in Docker container"
    IS_DOCKER=1
fi

# Detect CPU architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH_TYPE="x86_64"
    MONERO_ARCH="x64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_TYPE="aarch64"
    MONERO_ARCH="armv8"
else
    print_error "Unsupported architecture: $ARCH"
    exit 1
fi

print_status "Detected architecture: $ARCH_TYPE"

# Update system and install dependencies
print_status "Installing dependencies..."
if command -v apt-get &> /dev/null; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y wget curl tar bzip2 build-essential cmake libuv1-dev \
        libssl-dev libhwloc-dev git automake libtool autoconf pkg-config \
        tor torsocks screen htop net-tools procps 2>/dev/null || {
        print_error "Failed to install dependencies"
        exit 1
    }
elif command -v yum &> /dev/null; then
    yum install -y wget curl tar bzip2 gcc gcc-c++ make cmake libuv-devel \
        openssl-devel hwloc-devel git automake libtool autoconf pkgconfig \
        tor screen htop net-tools 2>/dev/null || {
        print_error "Failed to install dependencies"
        exit 1
    }
fi

# Configure and start Tor
print_status "Configuring Tor proxy..."

# Create Tor config
mkdir -p /etc/tor
cat > /etc/tor/torrc <<EOF
SocksPort 9050
ControlPort 9051
Log notice stdout
EOF

# Start Tor in background if not running
if ! pgrep -x "tor" > /dev/null; then
    print_status "Starting Tor daemon and monitoring bootstrap..."
    
    # Start Tor and read stdout directly
    (tor -f /etc/tor/torrc 2>&1 | while IFS= read -r line; do
        echo "$line"
        if echo "$line" | grep -q "Bootstrapped 100%"; then
            print_status "Tor bootstrapped successfully!"
            break
        fi
    done) &
    
    # Wait for Tor process to actually start
    sleep 2
    
    print_status "Tor is now running"
else
    print_status "Tor is already running"
fi

# Verify Tor is working
print_status "Verifying Tor connection..."
if curl --socks5 127.0.0.1:9050 --connect-timeout 10 -s https://check.torproject.org/api/ip 2>/dev/null | grep -q '"IsTor":true'; then
    print_status "Tor connection verified successfully"
else
    print_warning "Tor connection verification failed, but continuing..."
fi

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download and setup Monero daemon (monerod)
print_status "Downloading Monero daemon ${MONERO_VERSION}..."
if [ ! -f "monerod" ]; then
    wget --progress=bar:force:noscroll "https://downloads.getmonero.org/cli/monero-linux-${MONERO_ARCH}-${MONERO_VERSION}.tar.bz2" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Failed to download Monero daemon"
        exit 1
    fi
    print_status "Extracting Monero daemon..."
    tar -xjf "monero-linux-${MONERO_ARCH}-${MONERO_VERSION}.tar.bz2"
    mv monero-*/* . 2>/dev/null || true
    rm -rf monero-* "monero-linux-${MONERO_ARCH}-${MONERO_VERSION}.tar.bz2"
    print_status "Monero daemon installed successfully"
fi

# Download and setup P2Pool
print_status "Downloading P2Pool v4.13..."
if [ ! -f "p2pool" ]; then
    wget --progress=bar:force:noscroll "https://github.com/SChernykh/p2pool/releases/download/v4.13/p2pool-v4.13-linux-x64.tar.gz" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Failed to download P2Pool"
        exit 1
    fi
    print_status "Extracting P2Pool..."
    tar -xzf "p2pool-v4.13-linux-x64.tar.gz"
    chmod +x p2pool 2>/dev/null || true
    rm "p2pool-v4.13-linux-x64.tar.gz"
    print_status "P2Pool installed successfully"
fi

# Download and setup XMRig
print_status "Downloading XMRig ${XMRIG_VERSION}..."

# Map architecture for XMRig
case "$ARCH_TYPE" in
    x86_64) XMRIG_ARCH="x64" ;;
    aarch64) XMRIG_ARCH="aarch64" ;;
    *) XMRIG_ARCH="$ARCH_TYPE" ;;
esac

XMRIG_FILE="xmrig-${XMRIG_VERSION}-linux-static-${XMRIG_ARCH}.tar.gz"
if [ ! -f "xmrig" ]; then
    wget --progress=bar:force:noscroll "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/$XMRIG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Failed to download XMRig"
        exit 1
    fi
    print_status "Extracting XMRig..."
    tar -xzf "$XMRIG_FILE"
    mv xmrig-${XMRIG_VERSION}/xmrig . 2>/dev/null || true
    rm -rf xmrig-${XMRIG_VERSION} "$XMRIG_FILE"
    print_status "XMRig installed successfully"
fi

# Create XMRig config with Tor support
print_status "Creating XMRig configuration..."
cat > config.json <<EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "max-threads-hint": 100
    },
    "pools": [
        {
            "url": "127.0.0.1:3333",
            "user": "$WALLET_ADDRESS",
            "pass": "x",
            "keepalive": true,
            "tls": false
        }
    ],
    "socks5": "127.0.0.1:9050"
}
EOF

# Create startup script
print_status "Creating startup scripts..."

cat > start-monerod.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./monerod --zmq-pub tcp://127.0.0.1:18083 \
    --disable-dns-checkpoints \
    --enable-dns-blocklist \
    --prune-blockchain \
    --sync-pruned-blocks \
    --max-concurrency 4 \
    --proxy 127.0.0.1:9050 \
    --tx-proxy tor,127.0.0.1:9050,16 \
    --anonymous-inbound 127.0.0.1:18083,127.0.0.1:9050,16
EOF

cat > start-p2pool.sh <<EOF
#!/bin/bash
cd "$(dirname "\$0")"
./p2pool --host 127.0.0.1 --wallet $WALLET_ADDRESS --mini
EOF

cat > start-xmrig.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./xmrig -c config.json
EOF

cat > start-all.sh <<'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# Check if Tor is running, start if not
if ! pgrep -x "tor" > /dev/null; then
    echo "Starting Tor..."
    
    # Start Tor and monitor bootstrap from stdout
    (tor -f /etc/tor/torrc 2>&1 | while IFS= read -r line; do
        echo "$line"
        if echo "$line" | grep -q "Bootstrapped 100%"; then
            echo "Tor ready!"
            break
        fi
    done) &
    
    # Wait for Tor to be ready
    sleep 2
fi

echo "Starting Monero node..."
if command -v screen &> /dev/null; then
    screen -dmS monerod bash start-monerod.sh
else
    nohup bash start-monerod.sh > monerod.log 2>&1 &
fi
sleep 10

echo "Starting P2Pool..."
if command -v screen &> /dev/null; then
    screen -dmS p2pool bash start-p2pool.sh
else
    nohup bash start-p2pool.sh > p2pool.log 2>&1 &
fi
sleep 5

echo "Starting XMRig miner..."
if command -v screen &> /dev/null; then
    screen -dmS xmrig bash start-xmrig.sh
else
    nohup bash start-xmrig.sh > xmrig.log 2>&1 &
fi

echo ""
echo "All services started!"
if command -v screen &> /dev/null; then
    echo "To view logs:"
    echo "  Monerod: screen -r monerod"
    echo "  P2Pool:  screen -r p2pool"
    echo "  XMRig:   screen -r xmrig"
    echo ""
    echo "To detach from screen: Ctrl+A then D"
else
    echo "To view logs:"
    echo "  Monerod: tail -f monerod.log"
    echo "  P2Pool:  tail -f p2pool.log"
    echo "  XMRig:   tail -f xmrig.log"
fi
echo "To stop mining: ./stop-all.sh"
EOF

cat > stop-all.sh <<'EOF'
#!/bin/bash
if command -v screen &> /dev/null; then
    screen -S xmrig -X quit 2>/dev/null
    screen -S p2pool -X quit 2>/dev/null
    screen -S monerod -X quit 2>/dev/null
else
    pkill -f xmrig
    pkill -f p2pool
    pkill -f monerod
fi
echo "All mining services stopped"
EOF

cat > status.sh <<'EOF'
#!/bin/bash
echo "=== Mining Status ==="
echo ""
echo "Tor status:"
if pgrep -x tor > /dev/null; then
    echo "✓ Running (PID: $(pgrep -x tor))"
    if netstat -tuln 2>/dev/null | grep -q ":9050" || ss -tuln 2>/dev/null | grep -q ":9050"; then
        echo "  Port 9050: Listening"
    fi
else
    echo "✗ Stopped"
fi
echo ""
echo "Monerod status:"
pgrep -f monerod > /dev/null && echo "✓ Running (PID: $(pgrep -f monerod))" || echo "✗ Stopped"
echo ""
echo "P2Pool status:"
pgrep -f p2pool > /dev/null && echo "✓ Running (PID: $(pgrep -f p2pool))" || echo "✗ Stopped"
echo ""
echo "XMRig status:"
pgrep -f xmrig > /dev/null && echo "✓ Running (PID: $(pgrep -f xmrig))" || echo "✗ Stopped"
echo ""
if command -v screen &> /dev/null; then
    echo "Active screens:"
    screen -list 2>/dev/null || echo "No active screens"
fi
echo ""
echo "Network connections:"
netstat -tulpn 2>/dev/null | grep -E '(3333|9050|18083)' || ss -tulpn 2>/dev/null | grep -E '(3333|9050|18083)' || echo "Cannot check network connections"
EOF

cat > logs.sh <<'EOF'
#!/bin/bash
echo "=== Recent XMRig Output ==="
if [ -f xmrig.log ]; then
    tail -n 20 xmrig.log
elif command -v screen &> /dev/null && screen -list | grep -q xmrig; then
    echo "XMRig is running in screen session. Use: screen -r xmrig"
else
    echo "No logs available"
fi
EOF

chmod +x *.sh

# Enable huge pages for better performance
print_status "Configuring system for optimal mining performance..."
sysctl -w vm.nr_hugepages=1280 2>/dev/null || true
echo "vm.nr_hugepages=1280" >> /etc/sysctl.conf 2>/dev/null || true

print_status "Setup completed successfully!"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Directory:${NC} $INSTALL_DIR"
echo -e "${GREEN}Wallet Address:${NC} $WALLET_ADDRESS"
echo -e "${GREEN}Monero Version:${NC} $MONERO_VERSION"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To start mining:"
echo "  cd $INSTALL_DIR && ./start-all.sh"
echo ""
echo "To stop mining:"
echo "  cd $INSTALL_DIR && ./stop-all.sh"
echo ""
echo "To check status:"
echo "  cd $INSTALL_DIR && ./status.sh"
echo ""
echo "To view logs:"
echo "  cd $INSTALL_DIR && ./logs.sh"
echo ""
print_status "Starting mining now..."
cd "$INSTALL_DIR"
./start-all.sh

sleep 3
./status.sh

print_status "Mining started! It may take several hours for the node to sync."
print_status "You can safely close this terminal. Mining will continue in background."
