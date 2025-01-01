#!/bin/bash 

# 此版本无哪吒，只保活节点,将此文件放到vps，填写以下服务器配置后bash keep.sh运行即可

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

    remote_command="bash <(curl -s https://raw.githubusercontent.com/leung7963/SERV00/main/restart.sh)"
    
    sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" "$remote_command"
}

# 从servers.txt读取服务器列表
lines=()
while IFS= read -r line; do
    lines+=("$line")
done < servers.txt

for line in "${lines[@]}"; do
    host=$(echo "$line" | cut -d':' -f1)
    ssh_user=$(echo "$line" | cut -d':' -f2)
    ssh_pass=$(echo "$line" | cut -d':' -f3)
    tcp_port=$(echo "$line" | cut -d':' -f4)
    argo_domain=$(echo "$line" | cut -d':' -f5)
    remarks=$(echo "$line" | cut -d':' -f6)

    tcp_attempt=0
    argo_attempt=0
    max_attempts=3
    time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")

    # 检查 TCP 端口
    for (( ; tcp_attempt < max_attempts; tcp_attempt++ )); do
        if check_tcp_port "$host" "$tcp_port"; then
            green "$time  TCP端口通畅 服务器: $host  账户: $remarks"
            tcp_attempt=0
            break
        else
            red "$time  TCP端口不通 服务器: $host  账户: $remarks"
            sleep 10
        fi
    done

    # 检查 Argo 隧道
    for (( ; argo_attempt < max_attempts; argo_attempt++ )); do
        if check_argo_tunnel "$argo_domain"; then
            green "$time  Argo 隧道在线 Argo 账户: $remarks\n"
            argo_attempt=0
            break
        else
            red "$time  Argo 隧道离线 账户: $remarks"
            sleep 10
        fi
    done
   
    # 如果3次检测失败，则执行 SSH 连接并执行远程命令
    if [ $tcp_attempt -ge 3 ] || [ $argo_attempt -ge 3 ]; then
        yellow "$time 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: $host  账户: $remarks"
        if sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no "$ssh_user@$host" -q exit; then
            green "$time  SSH远程连接成功 服务器: $host  账户 : $remarks"
            output=$(run_remote_command "$host" "$ssh_user" "$ssh_pass" "$tcp_port" "$argo_domain" "$remarks")
            yellow "远程命令执行结果：\n"
            echo "$output"
        else
            red "$time  连接失败，请检查你的账户密码 服务器: $host  账户: $remarks"
        fi
    fi
done
