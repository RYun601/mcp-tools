#!/usr/bin/env bash
set -euo pipefail

SERVER_NAME="mysql_1"
KEEP_LEGACY_MYSQL="0"

print_usage() {
  cat <<'EOF'
用法:
  bash ./tools/mcp/mysql/setup-vscode-mysql-mcp.sh [--server-name <name>] [--keep-legacy-mysql]

参数:
  --server-name <name>   指定写入到 mcp.json 的服务名，默认 mysql_1
  --keep-legacy-mysql    保留本地旧服务名 mysql，不自动移除
  -h, --help             显示帮助
EOF
}

while (($# > 0)); do
  case "$1" in
    --server-name)
      if (($# < 2)); then
        echo "错误: --server-name 需要一个值" >&2
        exit 1
      fi
      SERVER_NAME="$2"
      shift 2
      ;;
    --keep-legacy-mysql)
      KEEP_LEGACY_MYSQL="1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "错误: 未知参数 $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VSCODE_DIR="${WORKSPACE_ROOT}/.vscode"
MCP_PATH="${VSCODE_DIR}/mcp.json"
ENV_TEMPLATE_PATH="${WORKSPACE_ROOT}/tools/mcp/mysql/mysql.mcp.env.example"
ENV_EXAMPLE_PATH="${VSCODE_DIR}/mysql.mcp.env.example"
ENV_PATH="${VSCODE_DIR}/mysql.mcp.env"

mkdir -p "${VSCODE_DIR}"

if [[ ! -f "${ENV_TEMPLATE_PATH}" ]]; then
  echo "缺少模板文件: ${ENV_TEMPLATE_PATH}" >&2
  exit 1
fi

cp "${ENV_TEMPLATE_PATH}" "${ENV_EXAMPLE_PATH}"
if [[ ! -f "${ENV_PATH}" ]]; then
  cp "${ENV_TEMPLATE_PATH}" "${ENV_PATH}"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 未检测到 python3，无法自动写入 mcp.json" >&2
  exit 1
fi

python3 - "${MCP_PATH}" "${SERVER_NAME}" "${KEEP_LEGACY_MYSQL}" <<'PY'
import datetime
import json
import os
import shutil
import sys

mcp_path = sys.argv[1]
server_name = sys.argv[2]
keep_legacy_mysql = sys.argv[3] == "1"

config = {}
if os.path.exists(mcp_path):
    try:
        with open(mcp_path, "r", encoding="utf-8") as file:
            config = json.load(file)
    except Exception:
        backup_path = f"{mcp_path}.bak.{datetime.datetime.now():%Y%m%d%H%M%S}"
        shutil.copy2(mcp_path, backup_path)
        print(f"warning: Existing mcp.json is invalid JSON. Backed up to: {backup_path}")
        config = {}

if not isinstance(config, dict):
    config = {}

servers = config.get("servers")
if not isinstance(servers, dict):
    servers = {}

if (not keep_legacy_mysql) and ("mysql" in servers):
    servers.pop("mysql", None)
    print("Removed local legacy server name 'mysql' to reduce naming conflicts.")

servers[server_name] = {
    "type": "stdio",
    "command": "uvx",
    "args": [
        "--from",
        "mysql-mcp-server==0.2.2",
        "python",
        "-m",
        "mysql_mcp_server.server",
    ],
    "envFile": ".vscode/mysql.mcp.env",
}

config["servers"] = servers

with open(mcp_path, "w", encoding="utf-8", newline="\n") as file:
    json.dump(config, file, ensure_ascii=False, indent=2)
    file.write("\n")
PY

if ! command -v uvx >/dev/null 2>&1; then
  echo "warning: 未检测到 uvx，请先安装 uv: https://docs.astral.sh/uv/getting-started/installation/" >&2
fi

echo "MySQL MCP 配置已写入: ${MCP_PATH}"
echo "服务名: ${SERVER_NAME}"
echo "请在 ${ENV_PATH} 中填写数据库连接信息后，重启 MCP 客户端。"
