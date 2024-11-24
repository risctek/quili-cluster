#!/bin/bash
# start-cluster.sh
# 脚本名称：start-cluster.sh
# 功能：用于启动一个节点集群，包括主节点和数据工作节点，并在主节点意外停止时自动重启。

# 初始化变量
START_CORE_INDEX=1                 # 默认从第1个核心开始分配
DATA_WORKER_COUNT=$(nproc)         # 默认数据工作节点数量为系统可用的CPU核心数
PARENT_PID=$$                      # 当前脚本进程的PID（父进程ID）

# 定义一些路径和二进制文件的变量
QUIL_NODE_PATH=$HOME/ceremonyclient/node    # 节点程序所在的路径
NODE_BINARY=node-1.4.21.1-linux-amd64       # 节点程序的二进制文件名称

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --core-index-start)  # 指定核心起始编号的参数
            START_CORE_INDEX="$2"
            shift 2          # 跳过当前参数及其值
            ;;
        --data-worker-count) # 指定数据工作节点数量的参数
            DATA_WORKER_COUNT="$2"
            shift 2          # 跳过当前参数及其值
            ;;
        *)                   # 处理未知参数
            echo "Unknown option: $1"  # 输出错误信息
            exit 1           # 退出脚本
            ;;
    esac
done

# 验证 START_CORE_INDEX 是否为非负整数
if ! [[ "$START_CORE_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Error: --core-index-start must be a non-negative integer"
    exit 1
fi

# 验证 DATA_WORKER_COUNT 是否为正整数
if ! [[ "$DATA_WORKER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --data-worker-count must be a positive integer"
    exit 1
fi

# 获取系统可用的最大CPU核心数
MAX_CORES=$(nproc)

# 如果 START_CORE_INDEX 为1，则减少可用核心数，因为主节点会占用核心0
if [ "$START_CORE_INDEX" -eq 1 ]; then
    echo "Adjusting max cores available to $((MAX_CORES - 1)) (from $MAX_CORES) due to starting the master node on core 0"
    MAX_CORES=$((MAX_CORES - 1))
fi

# 如果指定的数据工作节点数量超过了可用核心数，则调整为最大可用核心数
if [ "$DATA_WORKER_COUNT" -gt "$MAX_CORES" ]; then
    DATA_WORKER_COUNT=$MAX_CORES
    echo "DATA_WORKER_COUNT adjusted down to maximum: $DATA_WORKER_COUNT"
fi

MASTER_PID=0  # 初始化主节点进程ID

# 杀死之前可能运行的旧节点进程
pkill node-*

# 定义启动主节点的函数
start_master() {
    $QUIL_NODE_PATH/$NODE_BINARY &  # 后台启动主节点程序
    MASTER_PID=$!                   # 获取主节点的进程ID
}

# 如果 START_CORE_INDEX 为1，则启动主节点
if [ $START_CORE_INDEX -eq 1 ]; then
    start_master
fi

# 定义启动工作节点的函数
start_workers() {
    # 启动每个数据工作节点
    for ((i=0; i<DATA_WORKER_COUNT; i++)); do
        CORE=$((START_CORE_INDEX + i))  # 计算核心编号
        echo "Starting core $CORE"
        $QUIL_NODE_PATH/$NODE_BINARY --core $CORE --parent-process $PARENT_PID &  # 后台启动工作节点进程
    done
}

# 定义检查主节点进程是否运行的函数
is_master_process_running() {
    ps -p $MASTER_PID > /dev/null 2>&1  # 检查主节点进程是否存在
    return $?                          # 返回检查结果
}

# 启动数据工作节点
start_workers

# 主循环：定期检查主节点的状态并在必要时重启
while true
do
  # 如果 START_CORE_INDEX 为1（即主节点所在机器），并且主节点进程已停止，则重启主节点
  if [ $START_CORE_INDEX -eq 1 ] && ! is_master_process_running; then
    echo "Process crashed or stopped. restarting..."  # 输出提示信息
    start_master  # 重启主节点
  fi
  sleep 440  # 每440秒检查一次
done
