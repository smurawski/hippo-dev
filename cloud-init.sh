#!/usr/bin/env bash
set -ex pipefail

export DEBIAN_FRONTEND=noninteractive

echo "# update packages..."
sudo apt update
sudo apt install -y \
        git \
        build-essential \
        pkg-config \
        ca-certificates \
        apt-transport-https \
        apache2-utils

echo "# nodejs"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install 'v16.13.0'
nvm use 'v16.13.0'

echo "# rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
rustup target add wasm32-wasi

echo "# dotnet6..."
curl -sSfLo- https://dot.net/v1/dotnet-install.sh | bash
echo "export PATH=\"$HOME/.dotnet:$PATH\"" >> $HOME/.bashrc
export PATH="$HOME/.dotnet:$PATH"

echo "# wagi..."
VERSION=v0.4.0
wget https://github.com/deislabs/wagi/releases/download/$VERSION/wagi-$VERSION-linux-amd64.tar.gz
sudo tar -C /usr/local/bin/ -xzf wagi-$VERSION-linux-amd64.tar.gz

echo "# bindle..."
wget https://bindle.blob.core.windows.net/releases/bindle-v0.6.0-linux-amd64.tar.gz
sudo tar -C /usr/local/bin/ -xzf bindle-v0.6.0-linux-amd64.tar.gz
sudo mkdir -p /home/ubuntu/.config/bindle
sudo chown -R ubuntu:ubuntu /home/ubuntu/.config/bindle

echo "# bindle daemon file..."
sudo tee -a /etc/systemd/system/bindle.service <<'EOF'
[Unit]
Description=Bindle server
[Service]
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/bindle-server --unauthenticated
User=ubuntu
Group=ubuntu
[Install]
WantedBy=multi-user.target
EOF
sudo chmod +x /etc/systemd/system/bindle.service

echo "# starting bindle ..."
sudo systemctl enable bindle
sudo systemctl start bindle

echo "# waiting for bindle to start ..."
sleep 5 # wait for bindle to start

echo "# yo-wasm..."
npm install -g yo
npm install -g generator-wasm

echo "# wasmtime"
curl https://wasmtime.dev/install.sh -sSf | bash
export WASMTIME_HOME="$HOME/.wasmtime"
export PATH="$WASMTIME_HOME/bin:$PATH"

echo '# hippo CLI'
wget https://github.com/deislabs/hippo-cli/releases/download/v0.9.0/hippo-v0.9.0-linux-amd64.tar.gz
sudo tar -C /usr/local/bin/ -xzf hippo-v0.9.0-linux-amd64.tar.gz

echo "# hippo..."
git clone https://github.com/deislabs/hippo.git
pushd hippo
dotnet restore
pushd src/Web
npm run cibuild
popd
dotnet publish src/Web/Web.csproj -c Release --self-contained -r linux-x64
mkdir -p ./src/Web/bin/Release/net6.0/linux-x64/publish/certs
cp .github/release-image/localhost.conf ./src/Web/bin/Release/net6.0/linux-x64/publish/certs
popd

echo "# hippo daemon file..."
sudo tee -a /etc/systemd/system/hippo.service <<'EOF'
[Unit]
Description=Hippo server
[Service]
Restart=on-failure
RestartSec=5s
Environment=BINDLE_URL=http://localhost:8080/v1
Environment=ASPNETCORE_ENVIRONMENT=Development
Environment=HOME=/home/ubuntu
WorkingDirectory=/home/ubuntu/hippo/src/Web/bin/Release/net6.0/linux-x64/publish/
ExecStart=/home/ubuntu/.dotnet/dotnet /home/ubuntu/hippo/src/Web/bin/Release/net6.0/linux-x64/publish/Hippo.Web.dll
User=root
Group=root
[Install]
WantedBy=multi-user.target
EOF

sudo chmod +x /etc/systemd/system/hippo.service

echo "# starting hippo ..."
sudo systemctl enable hippo
sudo systemctl start hippo

echo "# waiting for hippo to start ..."
sleep 5 # wait for hippo to start

sudo chown -R ubuntu:ubuntu /home/ubuntu

echo "create .env file for easy reuse."
echo "export USER=admin" > .env
echo "export HIPPO_USERNAME=admin" >> .env
echo "export HIPPO_PASSWORD='Passw0rd!'" >> .env
echo "export HIPPO_URL=https://localhost:5001" >> .env
echo "export BINDLE_URL=http://localhost:8080/v1" >> .env
echo "export GLOBAL_AGENT_FORCE_GLOBAL_AGENT=false" >> .env

echo "# complete!"
echo "You can access hippo at https://localhost:5001"
echo "You can start a new WASM project with:"
echo "  source .env"
echo "  yo wasm"
echo "and follow the prompts"