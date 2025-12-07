#!/bin/bash
# tdl-msgwait Linux 一键安装脚本

set -e

echo "🚀 开始安装 tdl-msgwait 扩展..."
echo ""

# 颜色定义
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. 检测 tdl 可执行文件
echo -e "${CYAN}📦 检查 tdl 可执行文件...${NC}"

# 查找 tdl 可执行文件（优先级：当前目录 > 同级目录 > PATH）
TDL_PATH=""
if [ -f "./tdl" ]; then
    TDL_PATH="./tdl"
elif [ -f "../tdl-0.20.0/tdl" ]; then
    TDL_PATH="../tdl-0.20.0/tdl"
elif [ -f "../../tdl-0.20.0/tdl" ]; then
    TDL_PATH="../../tdl-0.20.0/tdl"
elif command -v tdl &> /dev/null; then
    TDL_PATH="tdl"
else
    echo -e "${RED}❌ 未找到 tdl 可执行文件${NC}"
    echo -e "${YELLOW}请确保 tdl 文件存在，或提供 tdl 路径${NC}"
    echo ""
    echo "可以尝试："
    echo "  1. 从 https://github.com/iyear/tdl/releases 下载 tdl"
    echo "  2. 将 tdl 放在当前目录或指定路径"
    exit 1
fi

echo -e "${GREEN}✅ 找到 tdl 文件${NC}"
echo "   路径: $TDL_PATH"
TDL_VERSION=$($TDL_PATH version 2>/dev/null | head -n 1 || echo "未知版本")
echo "   版本: $TDL_VERSION"
echo ""

# 2. 检测 Go 是否安装
echo -e "${CYAN}📦 检查 Go 是否已安装...${NC}"
if ! command -v go &> /dev/null; then
    echo -e "${RED}❌ 未找到 go 命令${NC}"
    echo -e "${YELLOW}请先安装 Go: https://go.dev/dl/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Go 已安装${NC}"
GO_VERSION=$(go version)
echo "   版本: $GO_VERSION"
echo ""

# 3. 检查当前目录
if [ ! -f "main.go" ]; then
    echo -e "${RED}❌ 错误: 请在 ext_msgwait 目录下运行此脚本${NC}"
    exit 1
fi

# 4. 整理依赖
echo -e "${CYAN}📦 整理 Go 依赖...${NC}"
# 设置国内代理加速
export GOPROXY=https://goproxy.cn,direct
go mod tidy
echo -e "${GREEN}✅ 依赖整理完成${NC}"
echo ""

# 4.5. 预下载所有依赖包
echo -e "${CYAN}📥 下载依赖包（可能需要一些时间）...${NC}"
echo -e "${YELLOW}提示: 如果下载很慢，可以按 Ctrl+C 取消并检查网络${NC}"
go mod download
echo -e "${GREEN}✅ 依赖包下载完成${NC}"
echo ""

# 5. 检测系统内存并选择编译模式
echo -e "${CYAN}📊 检测系统资源...${NC}"

# 获取可用内存（MB）
AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $7}')
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
AVAILABLE_DISK=$(df -m . | awk 'NR==2 {print $4}')

echo "   总内存: ${TOTAL_MEM}MB"
echo "   可用内存: ${AVAILABLE_MEM}MB"
echo "   可用磁盘: ${AVAILABLE_DISK}MB"
echo ""

# 检查是否需要创建swap
SWAP_CREATED=false
if [ "$AVAILABLE_MEM" -lt 600 ]; then
    echo -e "${YELLOW}⚠️  检测到可用内存较低 (${AVAILABLE_MEM}MB)${NC}"
    
    # 检查是否已有swap
    SWAP_SIZE=$(free -m | awk '/^Swap:/{print $2}')
    
    if [ "$SWAP_SIZE" -eq 0 ] || [ "$SWAP_SIZE" -lt 500 ]; then
        echo -e "${CYAN}💾 尝试自动创建临时交换空间...${NC}"
        
        # 检查磁盘空间是否充足（至少需要1.5GB）
        if [ "$AVAILABLE_DISK" -gt 1500 ]; then
            SWAPFILE="/tmp/tdl_compile_swap_$$"
            echo "   创建 1GB 临时交换文件: $SWAPFILE"
            
            if sudo fallocate -l 1G "$SWAPFILE" 2>/dev/null && \
               sudo chmod 600 "$SWAPFILE" && \
               sudo mkswap "$SWAPFILE" >/dev/null 2>&1 && \
               sudo swapon "$SWAPFILE" 2>/dev/null; then
                
                SWAP_CREATED=true
                AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $7}')
                echo -e "${GREEN}✅ 临时交换空间创建成功${NC}"
                echo "   新的可用内存: ${AVAILABLE_MEM}MB"
                echo ""
            else
                echo -e "${YELLOW}⚠️  无法创建交换空间（可能需要sudo权限）${NC}"
                echo "   将使用极限内存优化模式继续..."
                echo ""
            fi
        else
            echo -e "${YELLOW}⚠️  磁盘空间不足 (${AVAILABLE_DISK}MB < 1500MB)，无法创建swap${NC}"
            echo "   将使用极限内存优化模式继续..."
            echo ""
        fi
    else
        echo "   已有交换空间: ${SWAP_SIZE}MB"
        echo ""
    fi
fi

# 根据可用内存选择编译模式
if [ "$AVAILABLE_MEM" -lt 600 ]; then
    # 极低内存模式 (< 600MB)
    echo -e "${CYAN}📦 使用极限内存优化模式编译${NC}"
    
    export GOGC=20
    export GOMEMLIMIT=384MiB
    export GODEBUG=gctrace=0
    COMPILE_PARALLEL=1
    COMPILE_MODE="极限模式 (384MB限制)"
    
elif [ "$AVAILABLE_MEM" -lt 1500 ]; then
    # 低内存模式 (600MB - 1.5GB)
    echo -e "${YELLOW}💡 检测到可用内存中等 (${AVAILABLE_MEM}MB)${NC}"
    echo -e "${CYAN}📦 使用低内存优化模式编译${NC}"
    echo ""
    
    export GOGC=50
    export GOMEMLIMIT=512MiB
    COMPILE_PARALLEL=1
    COMPILE_MODE="低内存模式 (512MB限制)"
    
else
    # 标准模式 (> 1.5GB)
    echo -e "${GREEN}✅ 内存充足 (${AVAILABLE_MEM}MB)${NC}"
    echo -e "${CYAN}📦 使用标准模式编译${NC}"
    echo ""
    
    export GOGC=100
    COMPILE_PARALLEL=4
    COMPILE_MODE="标准模式 (并发编译)"
fi

echo "编译配置: $COMPILE_MODE"
echo "预计耗时: 2-5 分钟"
echo ""

# 6. 开始编译
echo -e "${CYAN}🔨 编译扩展...${NC}"

START_TIME=$(date +%s)

# 执行编译
go build \
    -p "$COMPILE_PARALLEL" \
    -ldflags="-s -w" \
    -trimpath \
    -o tdl-msgwait \
    main.go

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [ ! -f "tdl-msgwait" ]; then
    echo -e "${RED}❌ 编译失败${NC}"
    echo ""
    echo "可能的原因："
    echo "  1. Go 版本过低（需要 >= 1.21）"
    echo "  2. 依赖包下载不完整"
    echo "  3. 内存不足（当前可用: ${AVAILABLE_MEM}MB）"
    echo "  4. 磁盘空间不足"
    echo ""
    echo "故障排查："
    echo "  - 查看内存: free -h"
    echo "  - 查看磁盘: df -h"
    echo "  - 创建交换空间或在本地编译后上传"
    exit 1
fi

FILE_SIZE=$(du -h tdl-msgwait | cut -f1)

FILE_SIZE=$(du -h tdl-msgwait | cut -f1)

echo -e "${GREEN}✅ 编译成功${NC}"
echo "   耗时: ${DURATION}秒"
echo "   文件大小: ${FILE_SIZE}"
echo ""

# 7. 创建扩展目录
EXTENSIONS_DIR="$HOME/.tdl/extensions"
echo -e "${CYAN}📁 创建扩展目录: $EXTENSIONS_DIR${NC}"
mkdir -p "$EXTENSIONS_DIR"

# 8. 复制可执行文件
echo -e "${CYAN}📦 安装扩展文件...${NC}"
cp tdl-msgwait "$EXTENSIONS_DIR/"
chmod +x "$EXTENSIONS_DIR/tdl-msgwait"
echo -e "${GREEN}✅ 扩展文件已安装${NC}"
echo ""

# 8.5. 注册扩展到 tdl
echo -e "${CYAN}🔧 注册扩展到 tdl...${NC}"
if $TDL_PATH extension install --force "$EXTENSIONS_DIR/tdl-msgwait"; then
    echo -e "${GREEN}✅ 扩展注册成功${NC}"
else
    echo -e "${YELLOW}⚠️  扩展注册失败，可手动执行:${NC}"
    echo "   $TDL_PATH extension install --force $EXTENSIONS_DIR/tdl-msgwait"
fi
echo ""

# 9. 创建数据目录
DATA_DIR="$HOME/.tdl/extensions_data/msgwait"
echo -e "${CYAN}📁 创建数据目录: $DATA_DIR${NC}"
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/log"

# 10. 复制配置文件
echo -e "${CYAN}⚙️  配置配置文件...${NC}"

CONFIG_NEEDS_EDIT=false

if [ -f "$DATA_DIR/config.yaml" ]; then
    echo -e "${YELLOW}⚠️  配置文件已存在，跳过复制（保留现有配置）${NC}"
    echo "   位置: $DATA_DIR/config.yaml"
else
    if [ -f "config.yaml" ]; then
        cp config.yaml "$DATA_DIR/"
        echo -e "${GREEN}✅ 配置文件已复制${NC}"
        echo "   位置: $DATA_DIR/config.yaml"
        CONFIG_NEEDS_EDIT=true
    else
        echo -e "${YELLOW}⚠️  config.yaml 模板文件不存在，创建默认配置${NC}"
        
        # 创建默认配置文件
        cat > "$DATA_DIR/config.yaml" << 'EOF'
# 注意：Telegram API 配置由 tdl 提供，无需在此配置

# 自动添加到订阅 API 配置
subscription_api:
  host: "113.194.190.201:26908"
  api_key: "123456"

# 获取频道100调历史信息的功能开关
features:
  fetch_history_enabled: true  # 是否在启动时获取历史消息

# 监听配置
monitor:
  # 要监听的频道ID列表
  channels:
    - 2582776039
    - 1338209352
    - 1965523384
    - 1914963500
    - 1695276861
    - 2817717177
    - 1313311705

  # 白名单频道 - 这些频道不经过二次内容过滤
  whitelist_channels:
    - 1313311705

# 过滤配置
filters:
  # 关键词列表 - 消息必须包含这些关键词之一
  keywords:
    - "https://"
    - "http://"

  # 内容过滤 - 二次过滤，消息内容必须包含这些词之一
  content_filter:
    - "投稿"
    - "订阅"

  # 链接黑名单 - 包含这些关键字的链接不显示
  link_blacklist:
    - "register"
    - "t.me"
    - ".jpg"
    - ".jpeg"
    - ".png"
    - ".gif"
    - ".webp"
    - ".bmp"
    - "go1.569521.xyz"
EOF
        
        echo -e "${GREEN}✅ 已创建默认配置文件${NC}"
        echo "   位置: $DATA_DIR/config.yaml"
        CONFIG_NEEDS_EDIT=true
    fi
fi
echo ""

# 11. 验证安装
echo -e "${CYAN}🔍 验证安装...${NC}"
if $TDL_PATH extension list 2>/dev/null | grep -q "msgwait"; then
    echo -e "${GREEN}✅ 扩展已成功注册${NC}"
else
    echo -e "${YELLOW}⚠️  扩展未在列表中显示，但文件已安装${NC}"
fi
echo ""

# 12. 显示安装信息
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 安装完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📋 安装信息:${NC}"
echo "   编译模式: $COMPILE_MODE"
echo "   编译耗时: ${DURATION}秒"
echo "   文件大小: ${FILE_SIZE}"
echo "   扩展文件: $EXTENSIONS_DIR/tdl-msgwait"
echo "   配置文件: $DATA_DIR/config.yaml"
echo "   日志目录: $DATA_DIR/log"
echo ""

# 重要提醒
if [ "$CONFIG_NEEDS_EDIT" = true ]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}⚠️  重要：请立即编辑配置文件！${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}📝 配置文件位置:${NC}"
    echo "   $DATA_DIR/config.yaml"
    echo ""
    echo -e "${YELLOW}🔧 必须修改的配置项:${NC}"
    echo "   1. subscription_api.host    - API服务器地址（当前: 113.194.190.201:26908）"
    echo "   2. subscription_api.api_key - API密钥（当前: 123456）"
    echo "   3. monitor.channels         - 要监听的频道ID列表"
    echo ""
    echo -e "${YELLOW}💡 编辑命令:${NC}"
    echo "   nano $DATA_DIR/config.yaml"
    echo "   或"
    echo "   vi $DATA_DIR/config.yaml"
    echo ""
    echo -e "${YELLOW}📖 获取频道ID方法:${NC}"
    echo "   $TDL_PATH chat ls -n default"
    echo ""
fi

# 清理临时交换空间
if [ "$SWAP_CREATED" = true ]; then
    echo -e "${CYAN}🧹 清理临时交换空间...${NC}"
    if sudo swapoff "$SWAPFILE" 2>/dev/null && sudo rm -f "$SWAPFILE"; then
        echo -e "${GREEN}✅ 临时交换空间已清理${NC}"
    else
        echo -e "${YELLOW}⚠️  请手动清理: sudo swapoff $SWAPFILE && sudo rm $SWAPFILE${NC}"
    fi
    echo ""
fi
echo -e "${YELLOW}🔧 使用方法:${NC}"

if [ "$CONFIG_NEEDS_EDIT" = true ]; then
    echo -e "${RED}   ⚠️  第一次使用前，必须先编辑配置文件！${NC}"
    echo ""
fi

echo "   1. 确保已登录 tdl:"
echo "      ${CYAN}$TDL_PATH login${NC}"
echo ""
echo "   2. 编辑配置文件:"
echo "      ${CYAN}nano $DATA_DIR/config.yaml${NC}"
echo ""
echo "   3. 运行扩展:"
echo "      ${CYAN}$TDL_PATH -n default msgwait${NC}"
echo ""
echo "   4. 查看日志:"
echo "      ${CYAN}tail -f $DATA_DIR/log/latest.log${NC}"
echo ""
echo "   5. 调试模式:"
echo "      ${CYAN}$TDL_PATH -n default --debug msgwait${NC}"
echo ""
echo -e "${YELLOW}💡 提示:${NC}"
echo "   - 查看扩展列表: ${CYAN}$TDL_PATH extension list${NC}"
echo "   - 查看日志: ${CYAN}tail -f $DATA_DIR/log/latest.log${NC}"
echo "   - 停止运行: ${CYAN}Ctrl+C${NC}"
echo ""
