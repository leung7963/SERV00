#!/bin/bash 

# 此版本无哪吒，只保活节点,将此文件放到vps，填写以下服务器配置后bash keep.sh运行即可

SCRIPT_PATH="/root/keep.sh"                    # 脚本路径
export CFIP=${CFIP:-'www.visa.com.tw'}         # 优选域名或优选ip
export CFPORT=${CFIPPORT:-'443'}               # 优选域名或优选ip对应端口

# 从servers.txt文件读取服务器配置信息并解析为关联数组
servers=()
if [ -f "servers.txt" ]; then
    while IFS= read -r line; do
        key=$(echo "$line" | cut -d':' -f1)
        value=$(echo "$line" | cut -d':' -f2-)
        servers["$key"]="$value"
    done < servers.txt
else
    red "未找到servers.txt文件，请确保该文件存在且配置正确！"
    exit 1
fi

# 定义颜色
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }




# 检查 TCP 端口是否通畅
check_tcp_port() {
    local host=$1
    local port=$2
    nc -z -w 3 "$host" "$port" &> /dev/null
    return $?
}

# 检查 Argo 隧道是否在线
check_argo_tunnel() {
    local domain=$1
    if [ -z "$domain" ]; then
        return 1
    else
        http_code=$(curl -o /dev/null -s -w "%{http_code}\n" "https://$domain")
        if [ "$http_code" -eq 404 ]; then
            return 0
        else
            return 1
        fi
    fi
}

# 执行远程命令
run_remote_command() {
    local host=$1
    local ssh_user=$2
    local ssh_pass=$3
    local tcp_port=$4
    local udp1_port=$5
    local udp2_port=$6
    local argo_domain=${7}
    local argo_auth=${8}

    remote_command="VMESS_PORT=$tcp_port HY2_PORT=$udp1_port TUIC_PORT=$udp2_port ARGO_DOMAIN=$argo_domain ARGO_AUTH='$argo_auth' CFIP=$CFIP CFPORT=$CFPORT bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_00.sh)"
    
    sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" "$remote_command"
}

# 循环遍历服务器列表检测（使用从servers.txt解析出的servers）
for host in "${!servers[@]}"; do
    IFS=':' read -r ssh_user ssh_pass tcp_port udp1_port udp2_port argo_domain argo_auth <<< "${servers[$host]}"

    tcp_attempt=0
    argo_attempt=0
    max_attempts=3
    time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")

    # 检查 TCP 端口
    while [ $tcp_attempt -lt $max_attempts ]; do
        if check_tcp_port "$host" "$tcp_port"; then
            green "$time  TCP端口${tcp_port}通畅 服务器: $host  账户: $ssh_user"
            tcp_attempt=0
            break
        else
            red "$time  TCP端口${tcp_port}不通 服务器: $host  账户: $ssh_user"
            sleep 10
            tcp_attempt=$((tcp_attempt+1))
        fi
    done

    # 检查 Argo 隧道
    while [ $argo_attempt -lt $max_attempts ]; do
        if check_argo_tunnel "$argo_domain"); then
            green "$time  Argo 隧道在线 Argo域名: $argo_domain   账户: $ssh_user\n"
            argo_attempt=0
            break
        else
            red "$time  Argo 隧道离线 Argo域名: $argo_domain   账户: $ssh_user"
            sleep 10
            argo_attempt=$((argo_attempt+1))
        fi
    done
   
    # 如果3次检测失败，则执行 SSH 连接并执行远程命令
    if [ $tcp_attempt -ge 3 ] || [ $argo_attempt -ge 3 ]; then
        yellow "$time 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: $host  账户: $ssh_user"
        if sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" -q exit; then
            green "$time  SSH远程连接成功 服务器: $host  账户 : $ssh_user"
            output=$(run_remote_command "$host" "$ssh_user" "$ssh_pass" "$tcp_port" "$udp1_port" "$udp2_port" "$argo_domain" "$argo_auth")
            yellow "远程命令执行结果：\n"
            echo "$output"
        else
            red "$time  连接失败，请检查你的账户密码 服务器: $host  账户: $ssh_user"
        fi
    fi
done