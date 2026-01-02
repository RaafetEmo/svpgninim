#!/bin/bash

# Monero P2Pool + XMRig Mining Setup Script with Tor
# Usage: curl https://your-domain.com/m.sh | sh -s <wallet_address>

set -e

WALLET_ADDRESS="$1"
INSTALL_DIR="$HOME/monero-mining"
MONERO_VERSION="v0.18.3.4"
XMRIG_VERSION="6.21.3"
P2POOL_VERSION="v4.1"

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
elif [ "$ARCH" = "aarch64" ]; then
    ARCH_TYPE="aarch64"
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
DataDirectory /var/lib/tor
Log notice stdout
EOF

# Start Tor in background if not running
if ! pgrep -x "tor" > /dev/null; then
    print_status "Starting Tor daemon..."
    mkdir -p /var/lib/tor
    chmod 700 /var/lib/tor 2>/dev/null || true
    
    if [ "$IS_DOCKER" = "1" ] || [ "$EUID" -eq 0 ]; then
        tor -f /etc/tor/torrc > /dev/null 2>&1 &
    else
        if command -v systemctl &> /dev/null; then
            sudo systemctl enable tor 2>/dev/null || true
            sudo systemctl start tor 2>/dev/null || true
        else
            tor -f /etc/tor/torrc > /dev/null 2>&1 &
        fi
    fi
    
    sleep 5
else
    print_status "Tor is already running"
fi

# Verify Tor is working
if curl --socks5 127.0.0.1:9050 --connect-timeout 5 -s https://check.torproject.org/api/ip 2>/dev/null | grep -q "true"; then
    print_status "Tor is working correctly"
else
    print_warning "Tor connection check failed, but continuing..."
fi

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download and setup Monero daemon (monerod)
print_status "Downloading Monero daemon..."
MONERO_FILE="monero-linux-${ARCH_TYPE}-${MONERO_VERSION}.tar.bz2"
if [ ! -f "monerod" ]; then
    wget --progress=bar:force:noscroll "https://downloads.getmonero.org/cli/$MONERO_FILE" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Failed to download Monero daemon"
        exit 1
    fi
    print_status "Extracting Monero daemon..."
    tar -xjf "$MONERO_FILE"
    mv monero-*/* . 2>/dev/null || true
    rm -rf monero-* "$MONERO_FILE"
fi

# Download and setup P2Pool
print_status "Downloading P2Pool..."
P2POOL_FILE="p2pool-${P2POOL_VERSION}-linux-${ARCH_TYPE}.tar.gz"
if [ ! -f "p2pool" ]; then
    wget --progress=bar:force:noscroll "https://github.com/SChernykh/p2pool/releases/download/${P2POOL_VERSION}/$P2POOL_FILE" 2>&1
    if [ $? -ne 0 ]; then
        print_error "Failed to download P2Pool"
        exit 1
    fi
    print_status "Extracting P2Pool..."
    tar -xzf "$P2POOL_FILE"
    rm "$P2POOL_FILE"
fi

# Download and setup XMRig
print_status "Downloading XMRig..."
XMRIG_FILE="xmrig-${XMRIG_VERSION}-linux-static-${ARCH_TYPE}.tar.gz"
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
    tor -f /etc/tor/torrc >/dev/null 2>&1 &
    sleep 5
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
pgrep -x tor > /dev/null && echo "✓ Running (PID: $(pgrep -x tor))" || echo "✗ Stopped"
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
