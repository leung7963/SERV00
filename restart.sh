#!/bin/bash


FILE_PATH="./.application"

echo "检查并 重启 任务"

# 检查进程是否在运行

echo "检查php"
pgrep -x "php" > /dev/null
if [ $? -ne 0 ]; then
    nohup  ${FILE_PATH}/start.sh >/dev/null 2>&1 &
    echo "运行成功php"
fi


echo "检查http"
pgrep -x "http" > /dev/null
if [ $? -ne 0 ]; then
    nohup  ${FILE_PATH}/http -c  ${FILE_PATH}/config.json >/dev/null 2>&1 &
    echo "http运行成功"
fi


echo "检查node"
pgrep -x "node" > /dev/null
if [ $? -ne 0 ]; then
    nohup  ${FILE_PATH}/tunnel.sh >/dev/null 2>&1 &
    echo "node运行成功"
fi