#!/bin/bash

set -e

# 解析命令行参数
TARGET="$1"  # 可选的目标参数

# 如果提供了目标参数则进行验证
if [[ -n "$TARGET" ]] && [[ ! "$TARGET" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?)$ ]]; then
    echo "❌ 用法: $0 [stable|latest|版本号]" >&2
    exit 1
fi

DOWNLOAD_BASE_URL="https://downloads.claude.ai/claude-code-releases"
DOWNLOAD_DIR="$HOME/.claude/downloads"

echo ""
echo "🚀 开始安装 Claude Code..."
echo ""

# 检查必需的依赖
echo "🛠  检查依赖项..."
DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
    echo "   ✅ 找到下载工具: curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
    echo "   ✅ 找到下载工具: wget"
else
    echo "   ❌ 需要安装 curl 或 wget，但两者均未安装" >&2
    exit 1
fi

# 检查 jq 是否可用（可选）
HAS_JQ=false
if command -v jq >/dev/null 2>&1; then
    HAS_JQ=true
    echo "   ✅ 找到 JSON 解析工具: jq"
else
    echo "   ⚠️  未找到 jq，将使用 bash 正则解析（建议安装 jq）"
fi

# 下载函数，兼容 curl 和 wget
# $1: url
# $2: output (可选)
# $3: show_progress (可选, 传入 "true" 显示清爽进度条)
download_file() {
    local url="$1"
    local output="$2"
    local show_progress="${3:-false}"
    
    if [ "$DOWNLOADER" = "curl" ]; then
        local opts="-fsSL"
        if [ "$show_progress" = "true" ]; then
            opts="-fL -#" # -# 显示简单的 # 号进度条
        fi
        if [ -n "$output" ]; then
            curl $opts -o "$output" "$url"
        else
            curl $opts "$url"
        fi
    elif [ "$DOWNLOADER" = "wget" ]; then
        local opts="-q"
        if [ "$show_progress" = "true" ]; then
            opts="-q --show-progress" # 只显示进度条，不显示冗余头部
        fi
        if [ -n "$output" ]; then
            wget $opts -O "$output" "$url"
        else
            wget $opts -O - "$url"
        fi
    else
        return 1
    fi
}

# 简单的 JSON 解析器，用于在 jq 不可用时提取校验和
get_checksum_from_manifest() {
    local json="$1"
    local platform="$2"
    
    # 将 JSON 规范化为单行并提取校验和
    json=$(echo "$json" | tr -d '\n\r\t' | sed 's/ \+/ /g')
    
    # 使用 bash 正则表达式提取平台的校验和
    if [[ $json =~ \"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    return 1
}

# 检测平台
echo ""
echo "🔍 检测系统环境..."
case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "   ❌ 此脚本不支持 Windows。请参阅 https://code.claude.com/docs 了解安装选项。" >&2; exit 1 ;;
    *) echo "   ❌ 不支持的操作系统：$(uname -s)。请参阅 https://code.claude.com/docs 了解支持的平台。" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "   ❌ 不支持的架构：$(uname -m)" >&2; exit 1 ;;
esac

echo "   - 操作系统: $os"
echo "   - 系统架构: $arch"

# 检测 macOS 上的 Rosetta 2
if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
    if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
        arch="arm64"
        echo "   🔄 检测到 Rosetta 2 环境，已切换为原生 arm64 架构"
    fi
fi

# Termux 检测与 glibc 环境准备
if [ -n "$TERMUX_VERSION" ]; then
    echo "   📱 检测到 Termux (Android) 环境"
    if [ -f "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]; then
        echo "   ✅ 检测到 glibc 运行环境已就绪"
    else
        echo ""
        echo "   ⚠️  在 Termux 上运行 Claude Code 需要安装 glibc 运行环境和 patchelf。"
        echo "   💡 运行时将通过清空 LD_PRELOAD 和 patchelf 修改解释器来确保兼容性。"
        read -p "   🤔 是否继续安装 glibc-repo, glibc 和 patchelf？(y/n): " answer
        
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            echo "   📦 正在安装 glibc 相关组件..."
            pkg update -y
            pkg install glibc-repo -y
            pkg install glibc -y
            pkg install patchelf -y
            echo "   ✅ glibc 和 patchelf 已安装完成"
        else
            echo "   ❌ 已取消安装 glibc 环境，无法继续安装 Claude Code。" >&2
            exit 1
        fi
    fi
fi

# 检查 Linux 上的 musl 并相应调整平台
if [ "$os" = "linux" ]; then
    if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
        platform="linux-${arch}-musl"
    else
        platform="linux-${arch}"
    fi
else
    platform="${os}-${arch}"
fi

echo "   - 平台标识: $platform"

mkdir -p "$DOWNLOAD_DIR"

# 获取版本号 (静默下载小文件)
echo ""
echo "🌐 获取版本信息..."
version=$(download_file "$DOWNLOAD_BASE_URL/latest")
echo "   ✅ 最新版本: $version"

# 下载清单并提取校验和 (静默下载小文件)
echo "   📄 正在下载清单文件..."
manifest_json=$(download_file "$DOWNLOAD_BASE_URL/$version/manifest.json")

# 如果 jq 可用，则使用 jq；否则退回到纯 bash 解析
if [ "$HAS_JQ" = true ]; then
    checksum=$(echo "$manifest_json" | jq -r ".platforms[\"$platform\"].checksum // empty")
else
    checksum=$(get_checksum_from_manifest "$manifest_json" "$platform")
fi

# 验证校验和格式（SHA256 = 64个十六进制字符）
if [ -z "$checksum" ] || [[ ! "$checksum" =~ ^[a-f0-9]{64}$ ]]; then
    echo "   ❌ 清单中未找到平台 $platform 的校验和" >&2
    exit 1
fi

# 下载主二进制文件 (开启进度条)
binary_path="$DOWNLOAD_DIR/claude-$version-$platform"
echo ""
echo "📦 正在下载 Claude Code 二进制文件..."
if ! download_file "$DOWNLOAD_BASE_URL/$version/$platform/claude" "$binary_path" "true"; then
    echo ""
    echo "   ❌ 下载失败" >&2
    rm -f "$binary_path"
    exit 1
fi
echo "   ✅ 下载完成"

# 选择合适的校验和工具
echo "🔐 正在验证文件校验和 (SHA256)..."
if [ "$os" = "darwin" ]; then
    actual=$(shasum -a 256 "$binary_path" | cut -d' ' -f1)
else
    actual=$(sha256sum "$binary_path" | cut -d' ' -f1)
fi

if [ "$actual" != "$checksum" ]; then
    echo "   ❌ 校验和验证失败！" >&2
    echo "   期望值: $checksum" >&2
    echo "   实际值: $actual" >&2
    rm -f "$binary_path"
    exit 1
fi
echo "   ✅ 校验和验证通过"

chmod +x "$binary_path"

echo ""
echo "⚙️  正在设置 Claude Code..."

# Termux 专属执行逻辑：必须先 patch 临时文件才能运行 install，且需要清空 LD_PRELOAD
if [ -n "$TERMUX_VERSION" ]; then
    echo "   🩹 应用 Termux 专属补丁..."
    echo "      🔧 修改临时二进制文件解释器..."
    patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$binary_path"
    echo "      ✅ 临时文件修改完成"
    
    echo "      🚀 执行 install 命令..."
    LD_PRELOAD="" "$binary_path" install ${TARGET:+"$TARGET"}
    
    echo "      🔧 修改 ~/.local/bin/claude 的解释器..."
    patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$HOME/.local/bin/claude"
    echo "      ✅ 最终文件修改完成"
else
    # 非 Termux 环境的正常执行逻辑
    "$binary_path" install ${TARGET:+"$TARGET"}
fi

# 清理下载的临时文件
rm -f "$binary_path"

# Termux 专属后处理：配置自修复函数
if [ -n "$TERMUX_VERSION" ]; then
    echo "   🛡️ 正在配置 ~/.bashrc 启动自修复函数..."
    # 精确匹配该函数是否存在，不存在则追加
    if ! grep -q '^claude()' ~/.bashrc; then
        # 追加一个空行，和前面的配置隔开
        echo >> ~/.bashrc
        
        # 使用 Here Document 追加多行文本，'EOF' 加单引号防止变量被提前展开
        cat >> ~/.bashrc << 'EOF'
claude() {
    local binary_path="$HOME/.local/bin/claude"
    
    # 确保二进制文件存在
    if [ -f "$binary_path" ]; then
        # 获取当前解释器路径
        local current_interp
        current_interp=$(patchelf --print-interpreter "$binary_path" 2>/dev/null)
        
        # 如果解释器路径中不包含 com.termux 或 usr/glibc，说明需要修补
        # 注意：模式匹配中不要加双引号，否则会匹配字面的双引号导致失败
        if [[ "$current_interp" != *com.termux* ]] && [[ "$current_interp" != *usr/glibc* ]]; then
            echo "🩹 检测到 Claude 更新或解释器重置，正在重新应用 glibc 补丁..."
            if patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$binary_path"; then
                echo "   ✅ 补丁应用成功！"
            else
                echo "   ❌ 补丁应用失败，请检查 patchelf 和 glibc 环境。" >&2
            fi
        fi
    fi
    
    # 清空 LD_PRELOAD 并执行原生命令
    LD_PRELOAD="" command claude "$@"
}
EOF
        echo "   ✅ 自修复函数配置完成"
    else
        echo "   ⏭️  检测到自修复函数已存在，跳过配置"
    fi
    
    echo ""
    echo "✨ 安装完成！"
    echo ""
    echo "⚠️  重要提示：请执行 source ~/.bashrc 或重启终端以使 claude 命令生效。"
    echo ""
    exit 0
fi

# 非 Termux 环境的正常结束提示
echo ""
echo "✨ 安装完成！"
echo ""
