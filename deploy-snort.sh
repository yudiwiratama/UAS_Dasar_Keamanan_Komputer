#!/bin/bash

# Reset SECONDS
SECONDS=0

# Meminta input nama interface jaringan, segmen IP, dan jumlah thread untuk kompilasi
read -p "Masukkan nama interface jaringan (misalnya eth0): " INTERFACE
read -p "Masukkan segmen IP untuk HOME_NET (misalnya 10.10.10.11/32): " HOME_NET
read -p "Masukkan jumlah thread untuk kompilasi (misalnya 4): " THREADS

# Update and install dependencies
echo "Installing dependencies..."
sudo apt update
sudo apt install build-essential libpcap-dev libpcre3-dev libnet1-dev zlib1g-dev luajit hwloc libdnet-dev libdumbnet-dev bison flex liblzma-dev openssl libssl-dev pkg-config libhwloc-dev cmake cpputest libsqlite3-dev uuid-dev libcmocka-dev libnetfilter-queue-dev libmnl-dev autotools-dev libluajit-5.1-dev libunwind-dev libfl-dev -y

# Install Snort DAQ
echo "Installing Snort DAQ..."
git clone https://github.com/snort3/libdaq.git
cd libdaq
./bootstrap
./configure
make -j$THREADS
sudo make install
cd ..

# Install Gperftools
echo "Installing Gperftools..."
wget https://github.com/gperftools/gperftools/releases/download/gperftools-2.16/gperftools-2.16.tar.gz
tar xzf gperftools-2.16.tar.gz
cd gperftools-2.16/
./configure
make -j$THREADS
sudo make install
cd ..

# Install Snort
echo "Installing Snort..."
wget https://github.com/snort3/snort3/archive/refs/tags/3.6.0.0.tar.gz
tar -xvzf 3.6.0.0.tar.gz
cd snort3-3.6.0.0
./configure_cmake.sh --prefix=/usr/local --enable-tcmalloc
cd build
make -j$THREADS
sudo make install
sudo ldconfig
cd ..

# Check Snort version
echo "Checking Snort version..."
snort -V

# Configure network interface
echo "Configuring network interface $INTERFACE..."
sudo ip link set dev $INTERFACE promisc on
sudo ethtool -K $INTERFACE gro off lro off

# Create systemd service for Snort NIC configuration
echo "Creating systemd service for Snort NIC configuration..."
cat <<EOL | sudo tee /etc/systemd/system/snort3-nic.service
[Unit]
Description=Set Snort 3 NIC in promiscuous mode and Disable GRO, LRO on boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link set dev $INTERFACE promisc on
ExecStart=/usr/sbin/ethtool -K $INTERFACE gro off lro off
TimeoutStartSec=0
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOL

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl start snort3-nic.service
sudo systemctl enable snort3-nic.service

# Setup Snort rules
echo "Setting up Snort rules..."
sudo mkdir -p /usr/local/etc/rules
wget -qO- https://www.snort.org/downloads/community/snort3-community-rules.tar.gz | sudo tar xz -C /usr/local/etc/rules/

# Edit Snort configuration using sed
echo "Editing Snort configuration..."
sed -i '/variables = default_variables/s/$/,/' /usr/local/etc/snort/snort.lua	

sed -i '/variables = default_variables/a \
    rules = [[\
    include /usr/local/etc/rules/snort3-community-rules/snort3-community.rules\
    include /usr/local/etc/rules/local.rules\
    ]]\
' /usr/local/etc/snort/snort.lua

# Install Snort OpenAppID
echo "Installing Snort OpenAppID..."
wget https://www.snort.org/downloads/openappid/33380 -O OpenAppId-33380.tgz
tar -xzvf OpenAppId-33380.tgz
sudo cp -R odp /usr/local/lib/

# Configure Snort for OpenAppID using sed
echo "Configuring Snort for OpenAppID..."
sed -i "/app_detector_dir = /a \
    app_detector_dir = '/usr/local/lib',\
    log_stats = true,\
" /usr/local/etc/snort/snort.lua


# Create log directory for Snort
echo "Creating log directory for Snort..."
sudo mkdir -p /var/log/snort

# Verify Snort configuration
echo "Verifying Snort configuration..."
snort -c /usr/local/etc/snort/snort.lua

# Create custom Snort rules
echo "Creating custom Snort rules..."
sudo bash -c "echo -e 'alert icmp any any -> \$HOME_NET any (msg:\"ICMP connection test\"; sid:1000001; rev:1;)' > /usr/local/etc/rules/local.rules"
sudo bash -c "echo -e 'alert tcp any any -> \$HOME_NET 22 (msg:\"SSH Brute Force Detection\"; detection_filter:track by_src, count 3, seconds 5; sid:1000002; rev:1;)' > /usr/local/etc/rules/local.rules"
# Verify custom rules
echo "Verifying custom rules..."
snort -c /usr/local/etc/snort/snort.lua -R /usr/local/etc/rules/local.rules

# Create systemd service for Snort
echo "Creating systemd service for Snort..."
cat <<EOL | sudo tee /etc/systemd/system/snort3.service
[Unit]
Description=Snort Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snort -c /usr/local/etc/snort/snort.lua -A alert_fast -s 65535 -k none -D -i $INTERFACE -m 0x1b -u root -g root
StandardOutput=append:/var/log/snort/fast.log
StandardError=append:/var/log/snort/error.log
ExecStop=/bin/kill -9 \$MAINPID

[Install]
WantedBy=multi-user.target
EOL

# Reload, enable, start and check status of Snort service
sudo systemctl daemon-reload
sudo systemctl enable --now snort3
sudo systemctl status snort3

echo "Snort installation and configuration completed successfully!"
echo "Waktu yang dibutuhkan: $SECONDS detik"
