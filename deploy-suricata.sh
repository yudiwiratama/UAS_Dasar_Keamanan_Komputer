#!/bin/bash
# Reset SECONDS
SECONDS=0

# Meminta input dari pengguna untuk interface
read -p "Masukkan nama interface (misalnya ens3): " INTERFACE
read -p "Masukkan nilai baru untuk HOME_NET (contoh: 10.10.10.12/32): " NEW_HOME_NET

# Validasi input (opsional, hanya menerima format CIDR)
if [[ ! $NEW_HOME_NET =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo "Format IP yang dimasukkan tidak valid. Harap gunakan format CIDR (contoh: 10.10.10.12/32)."
    exit 1
fi

# Instalasi Suricata
echo "Memulai instalasi Suricata..."
sudo apt update -y 
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:oisf/suricata-stable
apt update -y
sudo apt-get install -y suricata


SURICATA_FILE="/etc/suricata/suricata.yaml"

# Tambahkan pagar (#) pada baris pertama HOME_NET dan tambahkan HOME_NET baru
sudo sed -i '/^\s*HOME_NET: /{s/^/#/;a\
    HOME_NET: "['"$NEW_HOME_NET"']"
}' "$SURICATA_FILE"


# Verifikasi perubahan
echo "HOME_NET telah diperbarui dengan nilai baru: [$NEW_HOME_NET]"
grep -i home_net "$SURICATA_FILE"

# Konfigurasi dasar
echo "Mengonfigurasi Suricata..."

# Cari dan ubah nilai interface di bagian af-packet
sudo sed -i '/^\s*af-packet:/,/^- interface:/s/^\(\s*-\s*interface:\s*\).*/\1'"$INTERFACE"'/' "$SURICATA_FILE"

# Verifikasi perubahan
echo "Interface di bagian af-packet telah diperbarui menjadi: $INTERFACE"
grep -A 5 "af-packet" "$SURICATA_FILE"


# Menambahkan file aturan lokal ke konfigurasi Suricata
echo "Menambahkan file aturan lokal ke konfigurasi Suricata..."
sudo sed -i '/^\s*-\s*suricata\.rules$/a\  - /var/lib/suricata/rules/local.rules' "$SURICATA_FILE"

# Mengubah aturan tanpa merestart layanan
echo "Menambahkan pengaturan untuk memodifikasi aturan tanpa merestart layanan..."
sudo bash -c "echo 'detect-engine:' >> /etc/suricata/suricata.yaml"
sudo bash -c "echo '  - rule-reload: true' >> /etc/suricata/suricata.yaml"

# Restart layanan Suricata
echo "Merestart layanan Suricata..."
sudo systemctl restart suricata
sudo suricata-update

# Membuat aturan lokal
echo "Membuat aturan lokal..."
sudo mkdir -p /var/lib/suricata/rules/
sudo touch /var/lib/suricata/rules/local.rules
sudo bash -c "echo -e 'alert icmp any any -> \$HOME_NET any (msg:\"ICMP connection test\"; sid:1000001; rev:1;)' > /var/lib/suricata/rules/local.rules"
sudo bash -c "echo -e 'alert tcp any any -> \$HOME_NET 22 (msg:\"SSH Brute Force Detected\"; flags:S; detection_filter:track by_src, count 3, seconds 10; classtype:attempted-admin; sid:1000002; rev:1;)' > /var/lib/suricata/rules/local.rules"

# Restart layanan Suricata
echo "Merestart layanan Suricata..."
sudo systemctl restart suricata
sudo suricata-update
sudo systemctl status suricata
echo "Instalasi dan konfigurasi Suricata selesai."
echo "Waktu yang dibutuhkan: $SECONDS detik"
