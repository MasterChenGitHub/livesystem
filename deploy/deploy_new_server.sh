#!/usr/bin/env bash
# =============================================================================
# 一键新服务器部署脚本
# 
# 功能：整合原 3 个脚本能力（单脚本完成）
# - 第一步：初始化目标服务器环境（Docker、防火墙等）
# - 第二步：一键部署完整应用栈（MySQL、Redis、API、WebRTC）
#
# 用法：
#   bash deploy/deploy_new_server.sh [NEW_SERVER_IP]
#
# 示例：
#   bash deploy/deploy_new_server.sh                # 使用脚本内默认 IP
#   bash deploy/deploy_new_server.sh 192.168.1.100
#
# 可选环境变量：
#   SSH_KEY - 私钥路径（默认：项目根目录 joke.pem）
#   SSH_USER - SSH 用户（默认：root）
#   REMOTE_BASE_DIR - 远端部署目录（默认：/opt/livesystem）
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------
# 配置 & 验证
# --------------------------------------------------------------------------
# 默认服务器 IP（后续变更只需改这里，或启动时传参覆盖）
DEFAULT_SERVER_IP="42.121.222.6"

# 优先使用命令行参数；未传参则使用脚本默认 IP
NEW_IP="${1:-${DEFAULT_SERVER_IP}}"
SSH_USER="${SSH_USER:-root}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-/opt/livesystem}"
SKIP_SERVER_SETUP="${SKIP_SERVER_SETUP:-0}"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}========== $* ==========${NC}"; }

# 获取脚本所在目录（deploy/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 默认使用项目根目录中的私钥，可通过 SSH_KEY 覆盖
SSH_KEY="${SSH_KEY:-${PROJECT_ROOT}/joke.pem}"

# 参数检查
[[ -f "$SSH_KEY" ]] || error "私钥文件不存在：$SSH_KEY"

SSH_TARGET="${SSH_USER}@${NEW_IP}"

info "目标服务器：$SSH_TARGET"
info "私钥：$SSH_KEY"
info "部署目录：$REMOTE_BASE_DIR"

# 依赖检查
section "环境检查"
command -v ssh >/dev/null 2>&1 || error "ssh 命令未找到"
command -v rsync >/dev/null 2>&1 || error "rsync 命令未找到"
info "依赖检查通过"

# --------------------------------------------------------------------------
# SSH 连接测试
# --------------------------------------------------------------------------
section "测试 SSH 连接"
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  "$SSH_TARGET" "echo OK" &>/dev/null; then
  info "SSH 连接成功"
else
  error "SSH 连接失败，请检查 IP、密钥或网络"
fi

# --------------------------------------------------------------------------
# Step 1: 服务器初始化
# --------------------------------------------------------------------------
section "第一步：服务器环境初始化"
if [[ "$SKIP_SERVER_SETUP" == "1" ]]; then
  info "已跳过服务器环境初始化（SKIP_SERVER_SETUP=1）"
else
info "正在远端执行环境初始化（内置 setup 逻辑）..."

if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
  "$SSH_TARGET" "DEPLOY_DIR='${REMOTE_BASE_DIR}' bash -s" <<'REMOTE_SETUP_EOF'
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "[ERROR] 请使用 root 账号执行" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "[setup] 更新系统并安装基础工具..."
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  rsync \
  git \
  vim \
  htop

echo "[setup] 安装 Docker（若未安装）..."
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
fi

systemctl enable --now docker

echo "[setup] 配置 Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  }
}
EOF

systemctl daemon-reload
systemctl restart docker

echo "[setup] 创建部署目录..."
mkdir -p "${DEPLOY_DIR}"/{deploy,myapi,webrtc-server}

echo "[setup] 环境初始化完成"
docker --version
docker compose version
REMOTE_SETUP_EOF
then
  info "✓ 服务器环境初始化完成"
else
  error "✗ 服务器环境初始化失败"
fi
fi

# --------------------------------------------------------------------------
# Step 2: 应用部署
# --------------------------------------------------------------------------
section "第二步：应用栈部署"
info "正在推送项目文件并构建镜像..."

SSH_OPTS=("-i" "$SSH_KEY" "-o" "StrictHostKeyChecking=accept-new")

# 创建远端目录
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_BASE_DIR}'"

# 探测目标机内网 IP（用于 coturn external-ip 公网/内网映射）
SERVER_PRIVATE_IP="$(ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "hostname -I | awk '{print \$1}'")"
if [[ -z "${SERVER_PRIVATE_IP}" ]]; then
  error "无法获取目标服务器内网 IP"
fi
info "目标服务器内网 IP：${SERVER_PRIVATE_IP}"

# 同步项目文件
rsync -az --delete \
  -e "ssh ${SSH_OPTS[*]}" \
  --exclude='.git/' \
  --exclude='**/build/' \
  --exclude='**/.gradle/' \
  --exclude='**/.idea/' \
  --exclude='**/.dart_tool/' \
  --exclude='**/Pods/' \
  --exclude='**/DerivedData/' \
  --exclude='**/node_modules/' \
  "${PROJECT_ROOT}/" "${SSH_TARGET}:${REMOTE_BASE_DIR}/"

info "项目文件同步完成"

# 启动容器
info "正在启动 Docker 容器..."
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "
  set -e
  cd '${REMOTE_BASE_DIR}/deploy'
  cat > .env <<EOF
SERVER_IP=${NEW_IP}
SERVER_PRIVATE_IP=${SERVER_PRIVATE_IP}
EOF
  echo '已写入 deploy/.env (SERVER_IP=${NEW_IP}, SERVER_PRIVATE_IP=${SERVER_PRIVATE_IP})'
  docker compose down || true
  echo '构建镜像中（这可能需要 5-10 分钟）...'
  docker compose up -d --build
  echo '✓ 容器启动完成'
  docker compose ps
"

# --------------------------------------------------------------------------
# 验证部署
# --------------------------------------------------------------------------
section "验证部署结果"

sleep 5  # 等待服务完全启动

info "检查 API 服务..."
if curl -sS -m 5 "http://${NEW_IP}/api/jokes" > /dev/null 2>&1; then
  info "✓ API 服务运行正常"
else
  warn "⚠ API 服务暂未响应（可能仍在启动中）"
fi

info "检查 WebRTC 配置..."
if curl -sS -m 5 "http://${NEW_IP}/api/webrtc/config" > /dev/null 2>&1; then
  info "✓ WebRTC 服务运行正常"
else
  warn "⚠ WebRTC 服务暂未响应（可能仍在启动中）"
fi

# --------------------------------------------------------------------------
# 总结
# --------------------------------------------------------------------------
section "部署完成"
echo ""
echo -e "${GREEN}✓ 新服务器部署成功！${NC}"
echo ""
echo "服务器地址：$NEW_IP"
echo "部署目录：$REMOTE_BASE_DIR"
echo ""
echo "可用的服务接口："
echo "  REST API:      http://${NEW_IP}/api/jokes"
echo "  WebRTC Config: http://${NEW_IP}/api/webrtc/config"
echo "  SSH 连接:      ssh -i $SSH_KEY $SSH_TARGET"
echo ""
echo "常用命令："
echo "  查看容器状态: docker compose -f ${REMOTE_BASE_DIR}/deploy/docker-compose.yml ps"
echo "  查看日志:     docker compose -f ${REMOTE_BASE_DIR}/deploy/docker-compose.yml logs -f"
echo "  重启服务:     docker compose -f ${REMOTE_BASE_DIR}/deploy/docker-compose.yml restart"
echo ""
