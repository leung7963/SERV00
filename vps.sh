#!/bin/bash

# 定义颜色
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
skybule="\e[1;36m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
skyblue() { echo -e "\e[1;36m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 定义常量
server_name="sing-box"
work_dir="/etc/sing-box"
config_dir="${work_dir}/config.json"
client_dir="${work_dir}/url.txt"
export CFIP=${CFIP:-'www.visa.com.tw'} 
export CFPORT=${CFPORT:-'443'} 
export UUID=${uuid:-''}
export ARGO_DOMAIN=${argo_domain:-''}
export ARGO_AUTH=${argo_auth:-''}



# 检查是否为root下运行
[[ $EUID -ne 0 ]] && red "请在root用户下运行脚本" && exit 1


# 检查 sing-box 是否已安装
check_singbox() {
if [ -f "${work_dir}/${server_name}" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service sing-box status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active sing-box)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}


# 检查 argo 是否已安装
check_argo() {
if [ -f "${work_dir}/argo" ]; then
    if [ -f /etc/alpine-release ]; then
        rc-service argo status | grep -q "started" && green "running" && return 0 || yellow "not running" && return 1
    else 
        [ "$(systemctl is-active argo)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}


# 检查 nginx 是否已安装
check_nginx() {
if command -v nginx &>/dev/null; then
    if [ -f /etc/alpine-release ]; then
        rc-service nginx status | grep -q "stoped" && yellow "not running" && return 1 || green "running" && return 0
    else 
        [ "$(systemctl is-active nginx)" = "active" ] && green "running" && return 0 || yellow "not running" && return 1
    fi
else
    red "not installed"
    return 2
fi
}


manage_packages() {
    if [ $# -lt 2 ]; then
        red "Unspecified package name or action" 
        return 1
    fi

    action=$1
    shift

    for package in "$@"; do
        if [ "$action" == "install" ]; then
            if command -v "$package" &>/dev/null; then
                green "${package} already installed"
                continue
            fi
            yellow "正在安装 ${package}..."
            if command -v apt &>/dev/null; then
                apt install -y "$package"
            elif command -v dnf &>/dev/null; then
                dnf install -y "$package"
            elif command -v yum &>/dev/null; then
                yum install -y "$package"
            elif command -v apk &>/dev/null; then
                apk update
                apk add "$package"
            else
                red "Unknown system!"
                return 1
            fi
        elif [ "$action" == "uninstall" ]; then
            if ! command -v "$package" &>/dev/null; then
                yellow "${package} is not installed"
                continue
            fi
            yellow "正在卸载 ${package}..."
            if command -v apt &>/dev/null; then
                apt remove -y "$package" && apt autoremove -y
            elif command -v dnf &>/dev/null; then
                dnf remove -y "$package" && dnf autoremove -y
            elif command -v yum &>/dev/null; then
                yum remove -y "$package" && yum autoremove -y
            elif command -v apk &>/dev/null; then
                apk del "$package"
            else
                red "Unknown system!"
                return 1
            fi
        else
            red "Unknown action: $action"
            return 1
        fi
    done

    return 0


# 下载并安装 sing-box,cloudflared
install_singbox() {
    clear
    purple "正在安装sing-box中，请稍后..."
# 判断系统架构
    ARCH_RAW=$(uname -m)
    case "${ARCH_RAW}" in
        'x86_64') ARCH='amd64' ;;
        'x86' | 'i686' | 'i386') ARCH='386' ;;
        'aarch64' | 'arm64') ARCH='arm64' ;;
        'armv7l') ARCH='armv7' ;;
        's390x') ARCH='s390x' ;;
        *) red "不支持的架构: ${ARCH_RAW}"; exit 1 ;;
    esac

# 下载sing-box,cloudflared
    [ ! -d "${work_dir}" ] && mkdir -p "${work_dir}" && chmod 777 "${work_dir}"
    curl -sLo "${work_dir}/${server_name}" "https://github.com/leung7963/SERV00/releases/download/vps/sing-box-liunx-amd64"
    curl -sLo "${work_dir}/argo" "https://github.com/eooce/test/releases/download/$ARCH/bot13"
    chown root:root ${work_dir} && chmod +x ${work_dir}/${server_name} ${work_dir}/argo


    iptables -F > /dev/null 2>&1 && iptables -P INPUT ACCEPT > /dev/null 2>&1 && iptables -P FORWARD ACCEPT > /dev/null 2>&1 && iptables -P OUTPUT ACCEPT > /dev/null 2>&1
    command -v ip6tables &> /dev/null && ip6tables -F > /dev/null 2>&1 && ip6tables -P INPUT ACCEPT > /dev/null 2>&1 && ip6tables -P FORWARD ACCEPT > /dev/null 2>&1 && ip6tables -P OUTPUT ACCEPT > /dev/null 2>&1
    
    manage_packages uninstall ufw firewalld > /dev/null 2>&1

cat > "${config_dir}" << EOF
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
      "uuid": "$uuid"
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



# debian/ubuntu/centos 守护进程
main_systemd_services() {
    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/sing-box/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/argo.service << EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --url http://localhost:8001 --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/sing-box/argo.log 2>&1"
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    if [ -f /etc/centos-release ]; then
        yum install -y chrony
        systemctl start chronyd
        systemctl enable chronyd
        chronyc -a makestep
        yum update -y ca-certificates
        bash -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    fi
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    systemctl enable argo
    systemctl start argo
}




# 适配alpine 守护进程
alpine_openrc_services() {
    cat > /etc/init.d/sing-box << 'EOF'
#!/sbin/openrc-run

description="sing-box service"
command="/etc/sing-box/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background=true
pidfile="/var/run/sing-box.pid"
EOF

    cat > /etc/init.d/argo << 'EOF'
#!/sbin/openrc-run

description="Cloudflare Tunnel"
command="/bin/sh"
command_args="-c '/etc/sing-box/argo tunnel --url http://localhost:8001 --no-autoupdate --edge-ip-version auto --protocol http2 > /etc/sing-box/argo.log 2>&1'"
command_background=true
pidfile="/var/run/argo.pid"
EOF

    chmod +x /etc/init.d/sing-box
    chmod +x /etc/init.d/argo

    rc-update add sing-box default
    rc-update add argo default

}



# 适配alpine运行argo报错用户组和dns的问题
change_hosts() {
    sh -c 'echo "0 0" > /proc/sys/net/ipv4/ping_group_range'
    sed -i '1s/.*/127.0.0.1   localhost/' /etc/hosts
    sed -i '2s/.*/::1         localhost/' /etc/hosts
}

# 修复nginx因host无法安装的问题
fix_nginx() {
    HOSTNAME=$(hostname)
    NGINX_CONFIG_FILE="/etc/nginx/nginx.conf"
    grep -q "127.0.1.1 $HOSTNAME" /etc/hosts || echo "127.0.1.1 $HOSTNAME" | tee -a /etc/hosts >/dev/null
    id -u nginx >/dev/null 2>&1 || useradd -r -d /var/www -s /sbin/nologin nginx >/dev/null 2>&1
    grep -q "^user nginx;" $NGINX_CONFIG_FILE || sed -i "s/^user .*/user nginx;/" $NGINX_CONFIG_FILE >/dev/null 2>&1
}




# nginx订阅配置
add_nginx_conf() {
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    cat > /etc/nginx/nginx.conf << EOF
# nginx_conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    server {
      listen $nginx_port;
      listen [::]:$nginx_port;

  }
}
EOF

nginx -t > /dev/null

if [ $? -eq 0 ]; then
    if [ -f /etc/alpine-release ]; then
     	pkill -f '[n]ginx'
        touch /run/nginx.pid
        nginx -s reload
        rc-service nginx restart
    else
        rm /run/nginx.pid
        systemctl daemon-reload
        systemctl restart nginx
    fi
fi
}





manage_argo() {
if [[ $argo_auth =~ TunnelSecret ]]; then
                echo $argo_auth > ${work_dir}/tunnel.json
                cat > ${work_dir}/tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< "$argo_auth")
credentials-file: ${work_dir}/tunnel.json
protocol: http2
                                           
ingress:
  - hostname: $ArgoDomain
    service: http://localhost:8001
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

                if [ -f /etc/alpine-release ]; then
                    sed -i '/^command_args=/c\command_args="-c '\''/etc/sing-box/argo tunnel --edge-ip-version auto --config /etc/sing-box/tunnel.yml run 2>&1'\''"' /etc/init.d/argo
                else
                    sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --edge-ip-version auto --config /etc/sing-box/tunnel.yml run 2>&1"' /etc/systemd/system/argo.service
                fi
                sleep 1

            elif [[ $argo_auth =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
                if [ -f /etc/alpine-release ]; then
                    sed -i "/^command_args=/c\command_args=\"-c '/etc/sing-box/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token $argo_auth 2>&1'\"" /etc/init.d/argo
                else

                    sed -i '/^ExecStart=/c ExecStart=/bin/sh -c "/etc/sing-box/argo tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token '$argo_auth' 2>&1"' /etc/systemd/system/argo.service
                fi
                restart_argo
                sleep 1 
                change_argo_domain
            else
                yellow "你输入的argo域名或token不匹配，请重新输入"
                exit            
            fi
}




# 启动 sing-box
start_singbox() {
if [ ${check_singbox} -eq 1 ]; then
    yellow "正在启动 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service sing-box start
    else
        systemctl daemon-reload
        systemctl start "${server_name}"
    fi
   if [ $? -eq 0 ]; then
       green "${server_name} 服务已成功启动\n"
   else
       red "${server_name} 服务启动失败\n"
   fi
elif [ ${check_singbox} -eq 0 ]; then
    yellow "sing-box 正在运行\n"
    sleep 1
else
    yellow "sing-box 尚未安装!\n"
    sleep 1
fi
}

restart_singbox() {
if [ ${check_singbox} -eq 0 ]; then
   yellow "正在重启 ${server_name} 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service ${server_name} restart
    else
        systemctl daemon-reload
        systemctl restart "${server_name}"
    fi
    if [ $? -eq 0 ]; then
        green "${server_name} 服务已成功重启\n"
    else
        red "${server_name} 服务重启失败\n"
    fi
elif [ ${check_singbox} -eq 1 ]; then
    yellow "sing-box 未运行\n"
    sleep 1
    menu
else
    yellow "sing-box 尚未安装！\n"
    sleep 1
fi
}





start_nginx() {
if command -v nginx &>/dev/null; then
    yellow "正在启动 nginx 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service nginx start
    else
        systemctl daemon-reload
        systemctl start nginx
    fi
    if [ $? -eq 0 ]; then
        green "Nginx 服务已成功启动\n"
    else
        red "Nginx 启动失败\n"
    fi
else
    yellow "Nginx 尚未安装！\n"
    sleep 1
fi
}


# 重启 nginx
restart_nginx() {
if command -v nginx &>/dev/null; then
    yellow "正在重启 nginx 服务\n"
    if [ -f /etc/alpine-release ]; then
     	pkill -f '[n]ginx'
        touch /run/nginx.pid
        nginx -s reload
        rc-service nginx restart
    else
        systemctl restart nginx
    fi
    if [ $? -eq 0 ]; then
        green "Nginx 服务已成功重启\n"
    else
        red "Nginx 重启失败\n"
    fi
else
    yellow "Nginx 尚未安装！\n"
    sleep 1
fi
}


start_argo() {
if [ ${check_argo} -eq 1 ]; then
    yellow "正在启动 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service argo start
    else
        systemctl daemon-reload
        systemctl start argo
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 0 ]; then
    green "Argo 服务正在运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
fi
}



restart_argo() {
if [ ${check_argo} -eq 0 ]; then
    yellow "正在重启 Argo 服务\n"
    if [ -f /etc/alpine-release ]; then
        rc-service argo restart
    else
        systemctl daemon-reload
        systemctl restart argo
    fi
    if [ $? -eq 0 ]; then
        green "Argo 服务已成功重启\n"
    else
        red "Argo 服务重启失败\n"
    fi
elif [ ${check_argo} -eq 1 ]; then
    yellow "Argo 服务未运行\n"
    sleep 1
    menu
else
    yellow "Argo 尚未安装！\n"
    sleep 1
    menu
fi
}




run(){
if [ ${check_singbox} -eq 0 ]; then
                yellow "sing-box 已经安装！"
            else
                fix_nginx
                manage_packages install nginx jq tar openssl iptables coreutils
                
                [ -n "$(curl -s --max-time 2 ipv6.ip.sb)" ] && manage_packages install ip6tables
                manage_argo
                install_singbox

                if [ -x "$(command -v systemctl)" ]; then
                    main_systemd_services
                elif [ -x "$(command -v rc-update)" ]; then
                    alpine_openrc_services
                    change_hosts
                    rc-service sing-box restart
                    rc-service argo restart
                else
                    echo "Unsupported init system"
                    exit 1 
                fi

                sleep 5
                add_nginx_conf
                exit
            fi


}
done
