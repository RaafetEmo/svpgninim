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

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_warning "Running as root. This is not recommended for mining."
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
sudo apt-get update -qq
sudo apt-get install -y wget curl tar bzip2 build-essential cmake libuv1-dev \
    libssl-dev libhwloc-dev git automake libtool autoconf pkg-config \
    tor torsocks screen htop net-tools 2>/dev/null || {
    print_error "Failed to install dependencies"
    exit 1
}

# Configure Tor
print_status "Configuring Tor proxy..."
sudo systemctl enable tor
sudo systemctl start tor

# Wait for Tor to start
sleep 5

if ! systemctl is-active --quiet tor; then
    print_error "Tor failed to start"
    exit 1
fi

print_status "Tor is running on 127.0.0.1:9050"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download and setup Monero daemon (monerod)
print_status "Downloading Monero daemon..."
MONERO_FILE="monero-linux-${ARCH_TYPE}-${MONERO_VERSION}.tar.bz2"
if [ ! -f "monerod" ]; then
    wget -q --show-progress "https://downloads.getmonero.org/cli/$MONERO_FILE"
    tar -xjf "$MONERO_FILE"
    mv monero-*/* .
    rm -rf monero-* "$MONERO_FILE"
fi

# Download and setup P2Pool
print_status "Downloading P2Pool..."
P2POOL_FILE="p2pool-${P2POOL_VERSION}-linux-${ARCH_TYPE}.tar.gz"
if [ ! -f "p2pool" ]; then
    wget -q --show-progress "https://github.com/SChernykh/p2pool/releases/download/${P2POOL_VERSION}/$P2POOL_FILE"
    tar -xzf "$P2POOL_FILE"
    rm "$P2POOL_FILE"
fi

# Download and setup XMRig
print_status "Downloading XMRig..."
XMRIG_FILE="xmrig-${XMRIG_VERSION}-linux-static-${ARCH_TYPE}.tar.gz"
if [ ! -f "xmrig" ]; then
    wget -q --show-progress "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/$XMRIG_FILE"
    tar -xzf "$XMRIG_FILE"
    mv xmrig-${XMRIG_VERSION}/xmrig .
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

echo "Starting Monero node..."
screen -dmS monerod bash start-monerod.sh
sleep 10

echo "Starting P2Pool..."
screen -dmS p2pool bash start-p2pool.sh
sleep 5

echo "Starting XMRig miner..."
screen -dmS xmrig bash start-xmrig.sh

echo ""
echo "All services started!"
echo "To view logs:"
echo "  Monerod: screen -r monerod"
echo "  P2Pool:  screen -r p2pool"
echo "  XMRig:   screen -r xmrig"
echo ""
echo "To detach from screen: Ctrl+A then D"
echo "To stop mining: ./stop-all.sh"
EOF

cat > stop-all.sh <<'EOF'
#!/bin/bash
screen -S xmrig -X quit 2>/dev/null
screen -S p2pool -X quit 2>/dev/null
screen -S monerod -X quit 2>/dev/null
echo "All mining services stopped"
EOF

cat > status.sh <<'EOF'
#!/bin/bash
echo "=== Mining Status ==="
echo ""
echo "Tor status:"
systemctl is-active --quiet tor && echo "✓ Running" || echo "✗ Stopped"
echo ""
echo "Monerod status:"
screen -list | grep -q monerod && echo "✓ Running" || echo "✗ Stopped"
echo ""
echo "P2Pool status:"
screen -list | grep -q p2pool && echo "✓ Running" || echo "✗ Stopped"
echo ""
echo "XMRig status:"
screen -list | grep -q xmrig && echo "✓ Running" || echo "✗ Stopped"
echo ""
echo "Active screens:"
screen -list
EOF

chmod +x *.sh

# Enable huge pages for better performance
print_status "Configuring system for optimal mining performance..."
sudo sysctl -w vm.nr_hugepages=1280 2>/dev/null || true
echo "vm.nr_hugepages=1280" | sudo tee -a /etc/sysctl.conf >/dev/null 2>&1 || true

# Create systemd service (optional)
print_status "Creating systemd service..."
sudo tee /etc/systemd/system/monero-mining.service >/dev/null <<EOF
[Unit]
Description=Monero Mining Service
After=network.target tor.service

[Service]
Type=forking
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start-all.sh
ExecStop=$INSTALL_DIR/stop-all.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

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
echo "To enable auto-start on boot:"
echo "  sudo systemctl enable monero-mining"
echo ""
echo "Starting mining now..."
cd "$INSTALL_DIR"
./start-all.sh

sleep 3
./status.sh

print_status "Mining started! It may take several hours for the node to sync."
print_status "You can safely close this terminal. Mining will continue in background."
