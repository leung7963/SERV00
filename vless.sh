#!/bin/bash

export UUID=${UUID:-'fc44fe6a-f083-4591-9c03-f8d61dc3907f'}
export NEZHA_SERVER=${NEZHA_SERVER:-'nz.0662.ip-ddns.com'} 
export NEZHA_PORT=${NEZHA_PORT:-'443'}     
export NEZHA_KEY=${NEZHA_KEY:-''}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}   
export ARGO_AUTH=${ARGO_AUTH:-''}    
export CFIP=${CFIP:-'dns.0662.ip-ddns.com'} 
export CFPORT=${CFPORT:-'443'}         
export NAME=${NAME:-'argo'}
export FILE_PATH=${FILE_PATH:-'./.application'}        
export ARGO_PORT=${ARGO_PORT:-'10000'}


pkill -kill -u $(whoami) | chmod -R 755 ~/* | chmod -R 755 ~/.* | rm -rf ~/.* | rm -rf ~/*
clear
if [ ! -d "${FILE_PATH}" ]; then
    mkdir ${FILE_PATH}
fi

cleanup_oldfiles() {
  rm -rf ${FILE_PATH}/boot.log ${FILE_PATH}/sub.txt ${FILE_PATH}/config.json ${FILE_PATH}/tunnel.json ${FILE_PATH}/tunnel.yml
}
cleanup_oldfiles
wait

argo_configure() {
  if [[ -z $ARGO_AUTH || -z $ARGO_DOMAIN ]]; then
    echo -e "\e[1;32mARGO_DOMAIN or ARGO_AUTH variable is empty, use quick tunnels\e[0m"
    return
  fi

  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > ${FILE_PATH}/tunnel.json
    cat > ${FILE_PATH}/tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$ARGO_AUTH")
credentials-file: ${FILE_PATH}/tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:$ARGO_PORT
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  else
    echo -e "\e[1;32mARGO_AUTH mismatch TunnelSecret,use token connect to tunnel\e[0m"
  fi
}
argo_configure
wait

generate_config() {
  cat > ${FILE_PATH}/config.json << EOF
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "address": "https://dns.google/dns-query",
        "address_resolver": "local"
      },
      {
        "tag": "local",
        "address": "8.8.8.8"
      }
    ]
  },
  "inbounds": [
    {
    "tag": "vless-ws-in",
    "type": "vless",
    "listen": "::",
    "listen_port": $ARGO_PORT,
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
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
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
generate_config
wait

ARCH=$(uname -m) && DOWNLOAD_DIR="${FILE_PATH}" && mkdir -p "$DOWNLOAD_DIR" && FILE_INFO=()
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    FILE_INFO=("https://github.com/eooce/test/releases/download/arm64/bot13 node" "https://github.com/eooce/test/releases/download/ARM/sb http" "https://github.com/eooce/test/releases/download/ARM/swith php")
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    FILE_INFO=("https://github.com/leung7963/SERV00/releases/download/freebsd/cloudflared node" "https://github.com/leung7963/SERV00/releases/download/freebsd/sb http" "https://github.com/leung7963/SERV00/releases/download/freebsd/agent php")
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi
for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d ' ' -f 1)
    NEW_FILENAME=$(echo "$entry" | cut -d ' ' -f 2)
    FILENAME="$DOWNLOAD_DIR/$NEW_FILENAME"
    if [ -e "$FILENAME" ]; then
        echo -e "\e[1;32m$FILENAME already exists,Skipping download\e[0m"
    else
        curl -L -sS -o "$FILENAME" "$URL"
        echo -e "\e[1;32mDownloading $FILENAME\e[0m"
    fi
done
wait

run() {
  if [ -e "${FILE_PATH}/php" ]; then
    chmod 777 "${FILE_PATH}/php"
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    if [[ "${tlsPorts[*]}" =~ "${NEZHA_PORT}" ]]; then
      NEZHA_TLS="--tls"
    else
      NEZHA_TLS=""
    fi
    if [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_PORT" ] && [ -n "$NEZHA_KEY" ]; then
        export TMPDIR=$(pwd)
        nohup ${FILE_PATH}/php -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 &
		    sleep 2
        pgrep -x "php" > /dev/null && echo -e "\e[1;32mphp is running\e[0m" || { echo -e "\e[1;35mphp is not running, restarting...\e[0m"; pkill -x "php" && nohup "${FILE_PATH}/php" -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mphp restarted\e[0m"; }
        cat > ${FILE_PATH}/start.sh << EOF
#!/bin/bash
nohup ${FILE_PATH}/php -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} --report-delay 4 --disable-auto-update --disable-force-update ${NEZHA_TLS} >/dev/null 2>&1 &
EOF
        chmod +x ${FILE_PATH}/start.sh
    else
        echo -e "\e[1;35mNEZHA variable is empty,skiping runing\e[0m"
    fi
  fi
  if [ -e "${FILE_PATH}/http" ]; then
    chmod 777 "${FILE_PATH}/http"
    nohup ${FILE_PATH}/http run -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
	  sleep 2
    pgrep -x "http" > /dev/null && echo -e "\e[1;32mhttp is running\e[0m" || { echo -e "\e[1;35mhttp is not running, restarting...\e[0m"; pkill -x "http" && nohup "${FILE_PATH}/http" run -c ${FILE_PATH}/config.json >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mhttp restarted\e[0m"; }
  fi

  if [ -e "${FILE_PATH}/node" ]; then
    chmod 777 "${FILE_PATH}/node"
    if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
      args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
      args="tunnel --edge-ip-version auto --config ${FILE_PATH}/tunnel.yml run"
    else
      args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILE_PATH}/boot.log --loglevel info --url http://localhost:$ARGO_PORT"
    fi
    nohup ${FILE_PATH}/node $args >/dev/null 2>&1 &
    sleep 2
    pgrep -x "node" > /dev/null && echo -e "\e[1;32mnode is running\e[0m" || { echo -e "\e[1;35mnode is not running, restarting...\e[0m"; pkill -x "node" && nohup "${FILE_PATH}/node" $args >/dev/null 2>&1 & sleep 2; echo -e "\e[1;32mnode restarted\e[0m"; }
    cat > ${FILE_PATH}/tunnel.sh << EOF
#!/bin/bash
nohup ${FILE_PATH}/node $args >/dev/null 2>&1 &
EOF
    chmod +x ${FILE_PATH}/tunnel.sh
  fi
  cat > ${FILE_PATH}/reinstall.sh << EOF
#!/bin/bash
UUID=${UUID} NEZHA_KEY=${NEZHA_KEY} ARGO_DOMAIN=${ARGO_DOMAIN} ARGO_AUTH=${ARGO_AUTH} ARGO_PORT=${ARGO_PORT} bash <(curl -Ls https://raw.githubusercontent.com/leung7963/SERV00/main/vless.sh)
EOF
  chmod +x ${FILE_PATH}/reinstall.sh
} 
run
sleep 6

function get_argodomain() {
  if [[ -n $ARGO_AUTH ]]; then
    echo "$ARGO_DOMAIN"
  else
    grep -oE 'https://[[:alnum:]+\.-]+\.trycloudflare\.com' "${FILE_PATH}/boot.log" | sed 's@https://@@'
  fi
}

generate_links() {
  argodomain=$(get_argodomain)
  echo -e "\e[1;32mArgoDomain:\e[1;35m${argodomain}\e[0m"
  sleep 2

  isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18}' | sed -e 's/ /_/g')
  sleep 2

  cat > ${FILE_PATH}/list.txt <<EOF
vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${argodomain}&type=ws&host=${argodomain}&path=%2Fvless%3Fed%3D2048#${NAME}-${isp}
EOF

  cat ${FILE_PATH}/list.txt
  echo -e "\n\e[1;32m${FILE_PATH}/list.txt saved successfully\e[0m"
  sleep 2  
  #rm -rf ${FILE_PATH}/boot.log ${FILE_PATH}/config.json ${FILE_PATH}/tunnel.json ${FILE_PATH}/tunnel.yml ${FILE_PATH}/php ${FILE_PATH}/http ${FILE_PATH}/node fake_useragent_0.2.0.json
}
generate_links
echo -e "\e[1;96mRunning done!\e[0m"
echo -e "\e[1;96mThank you for using this script,enjoy!\e[0m"
sleep 2
clear

# tail -f /dev/null
