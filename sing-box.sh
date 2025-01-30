#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
skyblue="\e[1;36m"

# 定义常量（通过环境变量设置）
export UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
export ARGO_DOMAIN=${ARGO_DOMAIN:-'your-fixed-domain.argo'}
export ARGO_AUTH=${ARGO_AUTH:-'your-argo-token-or-json'}
export NON_INTERACTIVE=${NON_INTERACTIVE:-1} # 1=非交互模式

# 路径配置
server_name="sing-box"
work_dir="/etc/sing-box"
config_dir="${work_dir}/config.json"
client_dir="${work_dir}/url.txt"

# 非交互处理函数
auto_continue() {
  [[ $NON_INTERACTIVE -eq 1 ]] && return 0 || return 1
}

# 安装依赖
install_dependencies() {
  apt-get update >/dev/null 2>&1
  apt-get install -y jq curl wget openssl net-tools coreutils >/dev/null 2>&1
  apt-get install -y nginx >/dev/null 2>&1 || {
    apt-get install -y apache2-utils >/dev/null 2>&1
  }
}

# 安装sing-box核心
install_singbox_core() {
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       echo "Unsupported architecture"; exit 1 ;;
  esac

  LATEST_VERSION=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
  DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/sing-box-${LATEST_VERSION#v}-linux-$ARCH.tar.gz"

  mkdir -p $work_dir
  wget -qO- $DOWNLOAD_URL | tar xz -C $work_dir --strip-components=1
}

# 生成配置文件
generate_config() {
  cat > $config_dir <<EOF
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "address": "1.1.1.1",
        "address_resolver": "local"
      },
      {
        "tag": "local",
        "address": "local"
      }
    ]
  },
  "inbounds": [
    {
    "tag": "vless-ws-in",
    "type": "vless",
    "listen": "::",
    "listen_port": 8001,
    "users": [
    {
      "uuid": "$UUID"
    }
  ],
    "transport": {
      "type": "ws",
      "path": "/vless",
      "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }

 ],
  "outbounds": [
    {
            "type": "wireguard",
            "tag": "warp",
            "server": "162.159.192.1", 
            "server_port": 2408,
            "local_address": [
                "172.16.0.2/32",
"2606:4700:110:8d67:252e:1624:cfae:59ef/128"
            ],
            "private_key": "cCnffl8J5FKGLjH7BksSwOOkSiXkls21EypaXpoGOkI=",
            "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "reserved":[0, 0, 0],
            "mtu": 1280
        },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
    {
     "domain": [
     "oh.my.god"
      ],
     "outbound": "warp"
    }
    ],
    "final": "warp"
    }
}
EOF
}

# 配置Argo隧道
setup_argo() {
  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    # JSON格式处理
    echo "$ARGO_AUTH" > ${work_dir}/tunnel.json
    cat > ${work_dir}/tunnel.yml <<EOF
tunnel: $(jq -r .TunnelID ${work_dir}/tunnel.json)
credentials-file: ${work_dir}/tunnel.json
protocol: http2
ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:8001
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
    ARGO_CMD="--config ${work_dir}/tunnel.yml"
  else
    # Token处理
    ARGO_CMD="--token $ARGO_AUTH"
  fi

  # 下载Argo
  wget -qO ${work_dir}/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x ${work_dir}/cloudflared

  # Systemd服务配置
  cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=${work_dir}/cloudflared tunnel --edge-ip-version auto $ARGO_CMD run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

# 配置系统服务
setup_services() {
  # Sing-box服务
  cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=${work_dir}/sing-box run -c ${config_dir}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now sing-box argo >/dev/null 2>&1
}

# 生成节点信息
generate_client_info() {
  IP=$(curl -s4m8 ip.sb) || IP=$(curl -s6m8 ip.sb)
  [[ -z $IP ]] && IP=$(getent hosts www.cloudflare.com | awk '{ print $1 }')

  cat > $client_dir <<EOF
vless://${UUID}@${IP}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&fp=random&type=ws&path=%2Fvless#Argo-VLESS
EOF

  echo -e "${green}安装完成！节点信息已保存至：${client_dir}"
  echo -e "${purple}VLESS链接：$(cat $client_dir)${re}"
}

# 主安装流程
main() {
  [[ $EUID -ne 0 ]] && echo -e "${red}请使用root用户运行！" && exit 1
  
  install_dependencies
  install_singbox_core
  generate_config
  setup_argo
  setup_services
  generate_client_info
}

# 执行安装
if [[ $NON_INTERACTIVE -eq 1 ]]; then
  main
else
  echo -e "${red}此脚本需在非交互模式下运行，请设置NON_INTERACTIVE=1"
  exit 1
fi