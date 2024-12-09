#!/bin/bash

FILE_PATH="./site"

echo "检查并 重启 任务"

# 检查进程是否在运行

echo "检查php"
pgrep -x "php" > /dev/null


#如果没有运行，则启动 nezha
if [ $? -ne 0 ]; then
    nohup ./vless/start.sh >/dev/null 2>&1 &
    echo "运行成功php"
fi

echo "检查http"
pgrep -x "http" > /dev/null


if [ $? -ne 0 ]; then
    nohup ./vless/http -c ./vless/config.json >/dev/null 2>&1 &
    echo "http运行成功"
fi



# 检查进程是否在运行
echo "检查node"
pgrep -x "node" > /dev/null


if [ $? -ne 0 ]; then
    nohup ./vless/tunnel.sh >/dev/null 2>&1 &
    echo "node运行成功"
fi