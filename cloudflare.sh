#!/bin/bash

# ==============================================================================
# SING-BOX 证书一键申请 (Cloudflare DNS )
# 其他用途 请修改代码92行服务重启命令
# ==============================================================================

# 设置：出错即退、函数继承信号、变量未定义报错、管道错误报错
set -eEuo pipefail

# --- 1. 颜色与核心变量 ---
RED='\033[31m' ; GREEN='\033[32m' ; YELLOW='\033[33m' ; CYAN='\033[36m' ; RESET='\033[0m'

ACME_BIN="$HOME/.acme.sh/acme.sh"
CERT_DIR="/etc/sing-box/certs"
CONF_FILE="/root/.cf_creds"

# 错误捕获：精准行号定位与颜色解析
_err_handler() {
  local line=$1
  echo -e "\n${RED}[失败] 脚本在第 ${line} 行中断。请检查 API 权限或网络状态。${RESET}" >&2
  exit 1
}
trap '_err_handler $LINENO' ERR

# --- 2. 基础环境准备 ---
[[ "$EUID" -ne 0 ]] && echo -e "${RED}错误：必须使用 root 权限运行。${RESET}" && exit 1

echo -n -e "${CYAN}:: 正在同步系统依赖环境... ${RESET}"
apt-get update -qq && apt-get install -y curl socat cron ca-certificates -qq >/dev/null 2>&1
systemctl enable --now cron >/dev/null 2>&1 || true
echo -e "${GREEN}[完成]${RESET}"

# --- 3. 配置认证信息 ---
CF_TOKEN=""
CF_ACCOUNT_ID=""

if [[ -f "$CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
  echo -e "\n${YELLOW}检测到已存的 Cloudflare 认证信息 (上次用于: ${LAST_DOMAIN:-未知})${RESET}"
  read -r -p "   是否沿用现有 Token 和 Account ID? [Y/n]: " USE_OLD
  USE_OLD=${USE_OLD:-y}

  if [[ "$USE_OLD" =~ ^[Yy]$ ]]; then
    CF_TOKEN="$SAVED_TOKEN"
    CF_ACCOUNT_ID="$SAVED_ACCOUNT_ID"
  fi
fi

if [[ -z "$CF_TOKEN" ]]; then
  echo -e "\n${CYAN}:: 请输入新的 Cloudflare 认证信息：${RESET}"
  read -r -p "   API Token   : " CF_TOKEN
  read -r -p "   Account ID  : " CF_ACCOUNT_ID
fi

echo -e "\n${CYAN}:: 请输入待申请的域名信息：${RESET}"
read -r -p "   申请域名    : " USER_DOMAIN

[[ -z "$CF_TOKEN" || -z "$CF_ACCOUNT_ID" || -z "$USER_DOMAIN" ]] && echo -e "${RED}错误：参数不完整${RESET}" && exit 1

# 域名逻辑判定
if [[ "$USER_DOMAIN" == *"*"* ]]; then
  CERT_MAIN=${USER_DOMAIN#\*\.}
  DOMAIN_ARGS=(-d "$CERT_MAIN" -d "$USER_DOMAIN")
else
  CERT_MAIN="$USER_DOMAIN"
  DOMAIN_ARGS=(-d "$USER_DOMAIN")
fi

# --- 为每个域名创建独立子文件夹，防止多域名申请时覆盖冲突 ---
CERT_DIR="$CERT_DIR/$CERT_MAIN"

# --- 4. 初始化 acme.sh ---
if [[ ! -f "$ACME_BIN" ]]; then
  echo -n -e "${CYAN}:: 正在安装 acme.sh 核心组件... ${RESET}"
  curl -s https://get.acme.sh | sh -s email="admin@$CERT_MAIN" >/dev/null 2>&1
  echo -e "${GREEN}[完成]${RESET}"
fi

# 导出变量 (acme.sh 会自动加密持久化)
export CF_Token="$CF_TOKEN"
export CF_Account_ID="$CF_ACCOUNT_ID"

# --- 5. 证书申请与部署 (静默模式) ---
echo -n -e "${CYAN}:: 正在申请证书 (Let's Encrypt) 请耐心等待... ${RESET}"
"$ACME_BIN" --issue --dns dns_cf "${DOMAIN_ARGS[@]}" --server letsencrypt --keylength ec-256 >/dev/null 2>&1 || [ $? -eq 2 ]
echo -e "${GREEN}[完成]${RESET}"

echo -n -e "${CYAN}:: 正在部署证书并配置自动续签... ${RESET}"
mkdir -p "$CERT_DIR"
"$ACME_BIN" --install-cert -d "$CERT_MAIN" --ecc \
  --key-file       "$CERT_DIR/private.key" \
  --fullchain-file "$CERT_DIR/fullchain.crt" \
  --reloadcmd      "chmod 644 $CERT_DIR/private.key $CERT_DIR/fullchain.crt && systemctl restart sing-box || true" >/dev/null 2>&1
echo -e "${GREEN}[完成]${RESET}"

# --- 6. 持久化本地配置并输出报告 ---
cat > "$CONF_FILE" <<EOF
SAVED_TOKEN="$CF_TOKEN"
SAVED_ACCOUNT_ID="$CF_ACCOUNT_ID"
LAST_DOMAIN="$USER_DOMAIN"
EOF

echo -e "\n${GREEN}======================================================${RESET}"
echo -e "           ✅ 证书申请与自动化部署成功！"
echo -e "${GREEN}======================================================${RESET}"
echo -e "${CYAN}1. 证书路径:${RESET}"
echo -e "   公钥: ${YELLOW}$CERT_DIR/fullchain.crt${RESET}"
echo -e "   私钥: ${YELLOW}$CERT_DIR/private.key${RESET}"
echo -e ""
echo -e "${CYAN}2. 自动化说明:${RESET}"
echo -e "   - 认证留存: 信息已保存在 $CONF_FILE"
echo -e "   - 续签周期: 每 60 天自动检测并更新"
echo -e "   - 自动重载: 证书更新后自动修正权限并重启服务"
echo -e "   - 涵盖范围: ${DOMAIN_ARGS[*]}"
echo -e "${GREEN}======================================================${RESET}"