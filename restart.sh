#!/bin/bash


FILE_PATH="./.application"

echo "检查并 重启 任务"

# 检查进程是否在运行

#echo "检查php"
pgrep -x "php" > /dev/null
if [ $? -ne 0 ]; then
    nohup ${FILE_PATH}/start.sh >/dev/null 2>&1 &
    #echo "运行成功php"
fi


#echo "检查http"
pgrep -x "http" > /dev/null
if [ $? -ne 0 ]; then
    nohup ${FILE_PATH}/http run -c ${FILE_PATH}/config.json >/dev/null 2>&1 &
    #echo "http运行成功"
fi


#echo "检查node"
pgrep -x "node" > /dev/null
if [ $? -ne 0 ]; then
    nohup ${FILE_PATH}/tunnel.sh >/dev/null 2>&1 &
    #echo "node运行成功"
fi

if [ -n "$TG_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        echo "-----------发送TG通知-----------------"
	    local message="执行成功"
	    response=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$CHAT_ID" -d "text=$message")

	    # 检查响应
	    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
	        echo "::info::Telegram消息发送成功: $message"
	    else
	        echo "::error::Telegram消息发送失败: $response"
	    fi
fi