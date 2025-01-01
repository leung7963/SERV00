import subprocess
import requests
import time
from datetime import datetime
import re
import json

# 此版本无哪吒，只保活节点，将此文件放到vps，填写以下服务器配置后运行即可
SCRIPT_PATH = "/root/keep.sh"  # 脚本路径
CFIP = 'www.visa.com.tw'  # 优选域名或优选ip，这里设置默认值，后续可修改
CFPORT = '443'  # 优选域名或优选ip对应端口

# 从servers.json文件获取服务器配置信息
servers = {}
try:
    with open('servers.json', 'r') as file:
        servers = json.load(file)
except FileNotFoundError:
    print("servers.json文件不存在，请确保该文件存在且格式正确！")
    raise SystemExit(1)
except json.JSONDecodeError:
    print("servers.json文件内容格式有误，请检查文件内容！")
    raise SystemExit(1)


# 定义输出颜色相关函数（这里简单模拟，实际在终端中显示彩色可能需要更多处理）
def red(text):
    return f"\033[1;91m{text}\033[0m"


def green(text):
    return f"\033[1;32m{text}\033[0m"


def yellow(text):
    return f"\033[1;33m{text}\033[0m"


def purple(text):
    return f"\033[1;35m{text}\033[0m"


def install_packages():
    """
    根据不同系统安装相关软件包
    """
    if subprocess.run(["test", "-f", "/etc/debian_version"], check=True).returncode == 0:
        package_manager = "apt-get install -y"
    elif subprocess.run(["test", "-f", "/etc/redhat-release"], check=True).returncode == 0:
        package_manager = "yum install -y"
    elif subprocess.run(["test", "-f", "/etc/fedora-release"], check=True).returncode == 0:
        package_manager = "dnf install -y"
    elif subprocess.run(["test", "-f", "/etc/alpine-release"], check=True).returncode == 0:
        package_manager = "apk add"
    else:
        print(red("不支持的系统架构！"))
        raise SystemExit(1)
    subprocess.Popen(f"{package_manager} sshpass curl netcat-openbsd jq cron", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def add_cron_job():
    """
    添加定时任务
    """
    if subprocess.run(["test", "-f", "/etc/alpine-release"], check=True).returncode == 0:
        if subprocess.run(["command", "-v", "crond"], check=True).returncode!= 0:
            subprocess.Popen("apk add --no-cache cronie bash", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # 这里假设rc-update和rc-service命令可用，实际可能需要更多判断等操作
            subprocess.run("rc-update add crond", shell=True, check=True)
            subprocess.run("rc-service crond start", shell=True, check=True)
    # 检查定时任务是否已经存在
    crontab_content = subprocess.run("crontab -l", shell=True, capture_output=True, text=True).stdout
    if not re.search(SCRIPT_PATH, crontab_content):
        with open('temp_crontab', 'w') as f:
            f.write(crontab_content + f"*/2 * * * * /bin/bash {SCRIPT_PATH} >> /root/keep_00.log 2>&1")
        subprocess.run("crontab temp_crontab", shell=True, check=True)
        print(green("已添加计划任务，每两分钟执行一次"))
    else:
        print(purple("计划任务已存在，跳过添加计划任务"))


def check_tcp_port(host, port):
    """
    检查TCP端口是否通畅
    """
    result = subprocess.run(["nc", "-z", "-w", "3", host, port], capture_output=True)
    return result.returncode == 0


def check_argo_tunnel(domain):
    """
    检查Argo隧道是否在线
    """
    if not domain:
        return False
    try:
        response = requests.get(f"https://{domain}", timeout=5)
        return response.status_code == 404
    except requests.RequestException:
        return False


def run_remote_command(host, ssh_user, ssh_pass, tcp_port, udp1_port, udp2_port, argo_domain, argo_auth):
    """
    执行远程命令
    """
    remote_command = f'VMESS_PORT={tcp_port} HY2_PORT={udp1_port} TUIC_PORT={udp2_port} ARGO_DOMAIN={argo_domain} ARGO_AUTH=\'{argo_auth}\' CFIP={CFIP} CFPORT={CFPORT} bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sb_00.sh)'
    ssh_command = f'sshpass -p "{ssh_pass}" ssh -o StrictHostKeyChecking=no "{ssh_user}@{host}" "{remote_command}"'
    result = subprocess.run(ssh_command, shell=True, capture_output=True, text=True)
    return result.stdout


if __name__ == "__main__":
    install_packages()
    add_cron_job()
    for host, server_info in servers.items():
        ssh_user, ssh_pass, tcp_port, udp1_port, udp2_port, argo_domain, argo_auth = server_info.split(':')
        tcp_attempt = 0
        argo_attempt = 0
        max_attempts = 3
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M")

        # 检查TCP端口
        while tcp_attempt < max_attempts:
            if check_tcp_port(host, tcp_port):
                print(green(f"{current_time}  TCP端口{tcp_port}通畅 服务器: {host}  账户: {ssh_user}"))
                tcp_attempt = 0
                break
            else:
                print(red(f"{current_time}  TCP端口{tcp_port}不通 服务器: {host}  账户: {ssh_user}"))
                time.sleep(10)
                tcp_attempt += 1

        # 检查Argo隧道
        while argo_attempt < max_attempts:
            if check_argo_tunnel(argo_domain):
                print(green(f"{current_time}  Argo 隧道在线 Argo域名: {argo_domain}   账户: {ssh_user}\n"))
                argo_attempt = 0
                break
            else:
                print(red(f"{current_time}  Argo 隧道离线 Argo域名: {argo_domain}   账户: {ssh_user}"))
                time.sleep(10)
                argo_attempt += 1

        # 如果3次检测失败，则执行SSH连接并执行远程命令
        if tcp_attempt >= 3 or argo_attempt >= 3:
            print(yellow(f"{current_time} 多次检测失败，尝试通过SSH连接并远程执行命令  服务器: {host}  账户: {ssh_user}"))
            if subprocess.run(f'sshpass -p "{ssh_pass}" ssh -o StrictHostKeyChecking=no "{ssh_user}@{host}" -q exit', shell=True).returncode == 0:
                print(green(f"{current_time}  SSH远程连接成功 服务器: {host}  账户 : {ssh_user}"))
                output = run_remote_command(host, ssh_user, ssh_pass, tcp_port, udp1_port, udp2_port, argo_domain, argo_auth)
                print(yellow("远程命令执行结果：\n"))
                print(output)
            else:
                print(red(f"{current_time}  连接失败，请检查你的账户密码 服务器: {host}  账户: {ssh_user}"))