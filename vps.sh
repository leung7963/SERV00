



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
