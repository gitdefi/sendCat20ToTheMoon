#!/bin/bash

# 使用如报错请先执行命令 sudo apt-get install jq
# sudo apt-get install curl
# CentOS/RHEL的linux系统，将上方apt-get替换为yum指令
# 信息捕手聚合社区 - 脚本工具 + KOL信息 + 监控工具 全聚合～
# 购买联系客服微信：coecvyy

# 公共函数
function app() {
    # ANSI 转义码定义
    RED='\033[0;31m'    # 红色
    GREEN='\033[0;32m'  # 绿色
    YELLOW='\033[0;33m' # 黄色
    NC='\033[0m'        # 无颜色
    # 变量，自己设置
    #转账最大gas费，链上gas高于此值，取消转账
    sendMaxFee=300
    #mint最大gas费
    mintMaxFee=500
    #当前gas的倍率
    coefficient=1
    # 是否启用最小gas费功能：true，开启；false，关闭
    enableFeeAdjustment=false  # 开关变量
    # 配置最小的转账gas
    sendMinFee=100

    # 自动生成多开的不同路径配置文件
    local filename=$1  # 第一个参数
    folder="./shell/wallets/$filename"
    myconfig="$folder/config.json" #想实现多打，可在/cli目录下创建不同的json文件，并将此处替换
    # 检查文件夹是否存在
    if [ ! -d "$folder" ]; then
        # 不存在该文件夹，创建folder
        echo -e "${GREEN}正在创建文件夹:$folder${NC}"
        mkdir -p "$folder"
        configJsonFile="$folder/config.json"
        echo "${GREEN}正在拷贝配置文件:$configJsonFile"
        jq --arg configFolder "$folder" '.dataDir = $configFolder' config.json > $configJsonFile
    else
        configJsonFile="$folder/config.json"
        if [ ! -d "$configJsonFile" ]; then
            echo "${GREEN}正在拷贝配置文件:$configJsonFile${NC}"
            jq --arg configFolder "$folder" '.dataDir = $configFolder' config.json > $configJsonFile
        fi
    fi

    log_file="$folder/mint_log.txt"
    success_count=0
    # 初始化日志文件
    echo "Minting Script Started at $(date)" | tee -a $log_file
    

    # 检查 curl 是否存在
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}警告: 未找到 curl,请安装 curl 后再运行此脚本。${NC}" >&2
        exit 1  # 终止脚本
    fi

    # 检查 jq 是否安装
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}jq not found. Please install jq to proceed.${NC}" >&2
        exit 1
    fi

    # 定义命令
    createWallet="sudo yarn cli wallet create --config $myconfig"
    showAddress="sudo yarn cli wallet address --config $myconfig"
    showBalances="sudo yarn cli wallet balances --config $myconfig"
    echo -e "${GREEN}1. 创建新钱包;${NC}"
    echo -e "${GREEN}2. 显示钱包地址;${NC}"
    echo -e "${GREEN}3. 显示钱包Cat20 Tokens;${NC}"
    echo -e "${GREEN}4. 将外部钱包(unisat或其他工具创建)注册到本地节点;${NC}"
    echo -e "${GREEN}5. 转账;${NC}"
    echo -e "${GREEN}6. 自动开打${NC}"
    # 读取用户输入
    read -p "请输入选项 [1~6]: " user_input
    if [[ $user_input == "1" ]]; then
        echo "-------------------------------------------"
        echo "--------------create wallet----------------"
        echo "-------------------------------------------"
        echo -e "${GREEN}请保存好助记词!${NC}"
        $createWallet
        echo -e "${GREEN}正在获取钱包地址...${NC}"
        $showAddress
    elif [[ $user_input == "2" ]]; then
        echo "-------------------------------------------"
        echo "-----------show wallet address-------------"
        echo "-------------------------------------------"
        $showAddress
    elif [[ $user_input == "3" ]]; then
        echo "-------------------------------------------"
        echo "-----------show wallet address-------------"
        echo "-------------------------------------------"
        $showBalances
    elif [[ $user_input == "4" ]];then
        echo "-------------------------------------------"
        echo "-----------show wallet address-------------"
        echo "-------------------------------------------"
        if [ -d "../tracker/docker/data/cat-$filename" ]; then
            # echo "路径存在"
            exportWallet="sudo yarn cli wallet export --config $myconfig"
        else
            # echo "路径不存在"
            exportWallet="sudo yarn cli wallet export --create true --config $myconfig"
        fi
        $exportWallet
    elif [[ $user_input == "5" ]];then
        echo "-------------------------------------------"
        echo "---------------send tokens-----------------"
        echo "-------------------------------------------"
        read -p "请输入转账token合约,直接回车,默认为first Cat20 token: " token
        if [[ -z "$token" ]]; then
            token='45ee725c2c5993b3e4d308842d87e973bf1951f5f7a804b21e4dd964ecd12d6b_0'
        fi
        read -p "请输入接收方地址: " receiver
        read -p "请输入转账数量: " amount
        read -p "请输入 'y' 确认转账: " user_input
        if [[ $user_input == "y" ]]; then
            feeRate=$(curl -s 'https://mempool.fractalbitcoin.io/api/v1/fees/recommended' | jq -r '.fastestFee')
            echo "The mempool fee rate is: $feeRate"
            echo -e "正在使用当前 $feeRate 费率进行 ${GREEN}转账${NC}" | tee -a $log_file
            # 检查 feeRate 是否为有效的整数
            if ! [[ "$feeRate" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}获取的费率无效或为空: $feeRate ${NC}" | tee -a $log_file
                feeRate=15 # 或者设置为一个合适的默认值
                exit 1
            fi
            if [[ "$feeRate" == 0 ]]; then
                echo -e "${RED}获取链上当前gas失败: $feeRate,请稍后重试${NC}" | tee -a $log_file
                echo "正在退出本脚本...."
                exit 1
            fi
            if [[ "$feeRate" -lt 5 ]]; then
                echo "链上gas小于5,已设为7"
                feeRate=7
            fi
            if [[ "$enableFeeAdjustment" == true ]]; then
                if [[ "$feeRate" -lt $sendMinFee ]]; then
                    echo "链上gas小于$sendMinFee,已将gas设为$sendMinFee"
                    echo -e "${GREEN}可前往./shell/common.sh文件中修改'sendMinFee'参数进行调整${NC}"
                    feeRate=$sendMinFee
                fi
            else
                echo -e "${YELLOW}feeRate 调整功能已关闭${NC}"
            fi
            feeRate=$(echo "scale=0; $coefficient * $feeRate" | bc) 
            feeRate=${feeRate%.*}
            echo "支付gas费为:$feeRate"
            # 比较 feeRate 是否大于 预设值
            if [ "$feeRate" -gt $sendMaxFee ]; then
                echo -e "${YELLOW}费率超过 $sendMaxFee,跳过当前循环,请稍后重试...${NC}" | tee -a $log_file
                echo "更改脚本中'sendMaxFee'参数,可自定义能接受的最大gas费,默认按照链上当前gas转账"
                echo -e "${GREEN}可前往./shell/common.sh文件中修改'sendMaxFee'参数进行调整${NC}"
                echo "取消转账，退出本脚本..."
                exit 1
            fi
            sendTokens="sudo yarn cli send -i $token $receiver $amount --fee-rate $feeRate --config $myconfig"
            $sendTokens
        else
            echo "取消转账，退出本脚本"
        fi
    else
        read -p "请输入需要mint的token合约: " token
        read -p "请输入需要mint的数量(limit): " amount
        read -p "自动开打，输入 'y' 确认: " user_input
        if [[ $user_input == "y" ]]; then
            echo "开始自动mint..."
            # 循环
            while true; do
                # 检查文件是否存在
                if [ -f /tmp/current_fee_rate.txt ]; then
                    # 从文件中读取 feeRate
                    feeRate=$(cat /tmp/current_fee_rate.txt)
                    echo "The mempool fee rate is: $feeRate"
                    # 检查 feeRate 是否为有效的整数
                    if [[ "$feeRate" == 0 ]]; then
                        echo -e "${YELLOW}获取链上当前gas失败: $feeRate,4s后稍后重试${NC}" | tee -a $log_file
                        feeRate=0 # 或者设置为一个合适的默认值
                        sleep 4
                        continue
                    fi
                else
                    feeRate=$(curl -s 'https://mempool.fractalbitcoin.io/api/v1/fees/recommended' | jq -r '.fastestFee')
                    # tx_cnt=$(curl -s 'https://mempool.fractalbitcoin.io/api/address/' | jq -r '.fastestFee')
                    echo "The mempool fee rate is: $feeRate"
                    # 检查 feeRate 是否为有效的整数
                    if [[ "$feeRate" == 0 ]]; then
                        echo -e "${RED}获取链上当前gas失败: $feeRate,10s后稍后重试${NC}" | tee -a $log_file
                        feeRate=0 # 或者设置为一个合适的默认值
                        sleep 10
                        continue
                    fi
                fi
                echo -e "正在使用当前 $feeRate 费率进行 ${GREEN}Mint${NC}" | tee -a $log_file
                echo -e "Mint的token为:${GREEN}$token${NC}"
                # 检查 feeRate 是否为有效的整数
                if ! [[ "$feeRate" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}获取的费率无效或为空! $feeRate ${NC}" | tee -a $log_file
                    feeRate=0 # 或者设置为一个合适的默认值
                    sleep 4
                    continue
                fi
                feeRate=$(echo "scale=0; $coefficient * $feeRate" | bc) 
                feeRate=${feeRate%.*}
                echo "支付gas费为:$feeRate"
                # 比较 mintFee 是否大于 mintMaxFee
                if [ "$feeRate" -gt $mintMaxFee ]; then
                    echo -e "${YELLOW}费率超过 $mintMaxFee,跳过当前循环,稍后重试...${NC}" | tee -a $log_file
                    echo -e "${GREEN}请前往./shell/common.sh文件中修改'mintMaxFee'参数进行调整${NC}"
                    sleep 4
                    continue
                fi

                command="yarn cli mint -i $token $amount --fee-rate $feeRate --config $myconfig"

                $command
                command_status=$?
                echo "返回状态：$command_status"
                if [ $command_status -ne 0 ]; then
                    echo "命令执行失败，退出循环" | tee -a $log_file
                    exit 1
                else
                    success_count=$((success_count + 1))
                    echo "成功mint了 $success_count 次" | tee -a $log_file
                fi

                sleep 3
            done
        else
            echo "停止执行。"
            exit 1
        fi

    fi

}
