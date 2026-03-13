#!/usr/bin/env bash
set -euo pipefail

COMMAND="install"
UPSTREAM="all"
SERVER_NAME="mysql_1"
WORKSPACE_ROOT="$(pwd)"
OUTPUT_DIR=""
KEEP_LEGACY_MYSQL="0"
KEEP_OTHER_UPSTREAMS="0"

DESIGNCOMPUTER_PACKAGE="mysql-mcp-server==0.2.2"
BENBORLA_PACKAGE="@benborla29/mcp-server-mysql@2.0.5"

print_usage() {
  cat <<'EOF'
用法:
  bash ./tools/mysql/setup-vscode-mysql-mcp.sh [install|apply] [参数]

命令:
  install                       生成可复制的预设配置（默认命令）
  apply                         将指定上游写入目标项目 .vscode/mcp.json

参数:
  --upstream <name>             上游: all(默认)、designcomputer、benborla
  --server-name <name>          mcp.json 中服务名，默认 mysql_1
  --workspace-root <path>       apply 目标项目根目录，默认当前目录
  --output-dir <path>           install 输出目录，默认 ~/.mysql-mcp-presets
  --keep-legacy-mysql           保留旧服务名 mysql
  --keep-other-upstreams        apply 时保留其他受管上游配置（默认清理）
  -h, --help                    显示帮助
EOF
}

if (($# > 0)); then
  case "$1" in
    install|apply)
      COMMAND="$1"
      shift
      ;;
  esac
fi

while (($# > 0)); do
  case "$1" in
    --upstream)
      if (($# < 2)); then
        echo "错误: --upstream 需要一个值" >&2
        exit 1
      fi
      UPSTREAM="$2"
      shift 2
      ;;
    --server-name)
      if (($# < 2)); then
        echo "错误: --server-name 需要一个值" >&2
        exit 1
      fi
      SERVER_NAME="$2"
      shift 2
      ;;
    --workspace-root)
      if (($# < 2)); then
        echo "错误: --workspace-root 需要一个值" >&2
        exit 1
      fi
      WORKSPACE_ROOT="$2"
      shift 2
      ;;
    --output-dir)
      if (($# < 2)); then
        echo "错误: --output-dir 需要一个值" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --keep-legacy-mysql)
      KEEP_LEGACY_MYSQL="1"
      shift
      ;;
    --keep-other-upstreams)
      KEEP_OTHER_UPSTREAMS="1"
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

case "${UPSTREAM}" in
  all|designcomputer|benborla)
    ;;
  *)
    echo "错误: --upstream 仅支持 all/designcomputer/benborla" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE_PATH="${SCRIPT_DIR}/mysql.mcp.env.example"

if [[ ! -f "${ENV_TEMPLATE_PATH}" ]]; then
  echo "缺少模板文件: ${ENV_TEMPLATE_PATH}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误: 未检测到 python3，无法自动写入 JSON 配置" >&2
  exit 1
fi

check_dependencies() {
  local target_upstreams=("$@")

  for item in "${target_upstreams[@]}"; do
    if [[ "${item}" == "designcomputer" ]] && ! command -v uvx >/dev/null 2>&1; then
      echo "warning: 未检测到 uvx。designcomputer 上游依赖 uvx: https://docs.astral.sh/uv/getting-started/installation/" >&2
    fi
    if [[ "${item}" == "benborla" ]] && ! command -v npx >/dev/null 2>&1; then
      echo "warning: 未检测到 npx。benborla 上游依赖 Node.js/npm。" >&2
    fi
  done
}

build_upstream_list() {
  if [[ "${UPSTREAM}" == "all" ]]; then
    printf '%s\n' "designcomputer" "benborla"
    return
  fi
  printf '%s\n' "${UPSTREAM}"
}

run_install() {
  local output_dir
  if [[ -n "${OUTPUT_DIR}" ]]; then
    output_dir="${OUTPUT_DIR}"
  else
    output_dir="${HOME}/.mysql-mcp-presets"
  fi

  mkdir -p "${output_dir}"
  cp "${ENV_TEMPLATE_PATH}" "${output_dir}/mysql.mcp.env.example"

  local generated=()
  while IFS= read -r upstream_item; do
    local preset_path="${output_dir}/mcp.${upstream_item}.json"
    python3 - "${upstream_item}" "${SERVER_NAME}" "${preset_path}" "${DESIGNCOMPUTER_PACKAGE}" "${BENBORLA_PACKAGE}" <<'PY'
import json
import sys

upstream_name = sys.argv[1]
server_name = sys.argv[2]
preset_path = sys.argv[3]
designcomputer_package = sys.argv[4]
benborla_package = sys.argv[5]

if upstream_name == "designcomputer":
    server_config = {
        "type": "stdio",
        "command": "uvx",
        "args": [
            "--from",
            designcomputer_package,
            "python",
            "-m",
            "mysql_mcp_server.server",
        ],
        "envFile": ".vscode/mysql.mcp.env",
    }
else:
    server_config = {
        "type": "stdio",
        "command": "npx",
        "args": [
            "-y",
            benborla_package,
        ],
        "envFile": ".vscode/mysql.mcp.env",
    }

config = {"servers": {server_name: server_config}}
with open(preset_path, "w", encoding="utf-8", newline="\n") as file:
    json.dump(config, file, ensure_ascii=False, indent=2)
    file.write("\n")
PY
    generated+=("${upstream_item}")
    echo "Generated preset: ${preset_path}"
  done < <(build_upstream_list)

  check_dependencies "${generated[@]}"
  echo "Preset output dir: ${output_dir}"
  echo "将 mcp.<upstream>.json 复制到目标项目 .vscode/mcp.json，再将 mysql.mcp.env.example 复制为 .vscode/mysql.mcp.env 并填写数据库连接信息。"
}

run_apply() {
  if [[ "${UPSTREAM}" == "all" ]]; then
    echo "错误: apply 命令必须指定单个上游：--upstream designcomputer 或 --upstream benborla" >&2
    exit 1
  fi

  if [[ ! -d "${WORKSPACE_ROOT}" ]]; then
    echo "错误: 目标项目目录不存在: ${WORKSPACE_ROOT}" >&2
    exit 1
  fi

  local workspace_root
  workspace_root="$(cd "${WORKSPACE_ROOT}" && pwd)"
  local vscode_dir="${workspace_root}/.vscode"
  local mcp_path="${vscode_dir}/mcp.json"
  local env_example_path="${vscode_dir}/mysql.mcp.env.example"
  local env_path="${vscode_dir}/mysql.mcp.env"

  mkdir -p "${vscode_dir}"
  cp "${ENV_TEMPLATE_PATH}" "${env_example_path}"
  if [[ ! -f "${env_path}" ]]; then
    cp "${ENV_TEMPLATE_PATH}" "${env_path}"
  fi

  python3 - "${mcp_path}" "${SERVER_NAME}" "${UPSTREAM}" "${KEEP_LEGACY_MYSQL}" "${KEEP_OTHER_UPSTREAMS}" "${DESIGNCOMPUTER_PACKAGE}" "${BENBORLA_PACKAGE}" "${env_path}" <<'PY'
import datetime
import json
import os
import shutil
import sys

mcp_path = sys.argv[1]
server_name = sys.argv[2]
upstream = sys.argv[3]
keep_legacy_mysql = sys.argv[4] == "1"
keep_other_upstreams = sys.argv[5] == "1"
designcomputer_package = sys.argv[6]
benborla_package = sys.argv[7]
env_path = sys.argv[8]

def build_server_config(upstream_name: str) -> dict:
    if upstream_name == "designcomputer":
        return {
            "type": "stdio",
            "command": "uvx",
            "args": [
                "--from",
                designcomputer_package,
                "python",
                "-m",
                "mysql_mcp_server.server",
            ],
            "envFile": ".vscode/mysql.mcp.env",
        }

    return {
        "type": "stdio",
        "command": "npx",
        "args": [
            "-y",
            benborla_package,
        ],
        "envFile": ".vscode/mysql.mcp.env",
    }

def detect_managed_upstream(server_config) -> str:
    if not isinstance(server_config, dict):
        return ""

    command = str(server_config.get("command", ""))
    args = server_config.get("args")
    if not isinstance(args, list):
        return ""

    arg_text = " ".join(str(item) for item in args)
    if command == "uvx" and ("mysql-mcp-server==" in arg_text or "mysql_mcp_server.server" in arg_text):
        return "designcomputer"
    if command == "npx" and "@benborla29/mcp-server-mysql" in arg_text:
        return "benborla"
    return ""

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

if (not keep_legacy_mysql) and (server_name != "mysql") and ("mysql" in servers):
    servers.pop("mysql", None)
    print("Removed local legacy server name 'mysql' to reduce naming conflicts.")

if not keep_other_upstreams:
    for existing_name in list(servers.keys()):
        if existing_name == server_name:
            continue
        detected = detect_managed_upstream(servers.get(existing_name))
        if detected:
            servers.pop(existing_name, None)
            print(f"Removed old managed mysql server '{existing_name}' ({detected}).")

servers[server_name] = build_server_config(upstream)
config["servers"] = servers

with open(mcp_path, "w", encoding="utf-8", newline="\n") as file:
    json.dump(config, file, ensure_ascii=False, indent=2)
    file.write("\n")

required_keys = {
    "designcomputer": ["MYSQL_HOST", "MYSQL_PORT", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_DATABASE"],
    "benborla": ["MYSQL_HOST", "MYSQL_PORT", "MYSQL_USER", "MYSQL_PASS", "MYSQL_DB"],
}

env_map = {}
if os.path.exists(env_path):
    with open(env_path, "r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            env_map[key.strip()] = value.strip()

missing_keys = [key for key in required_keys[upstream] if not env_map.get(key)]
if missing_keys:
    print(
        "warning: Env file missing keys for upstream "
        f"'{upstream}': {', '.join(missing_keys)}"
    )
PY

  check_dependencies "${UPSTREAM}"
  echo "MySQL MCP 配置已写入: ${mcp_path}"
  echo "服务名: ${SERVER_NAME}"
  echo "上游: ${UPSTREAM}"
  echo "请在 ${env_path} 中填写数据库连接信息后，重启 MCP 客户端。"
}

if [[ "${COMMAND}" == "install" ]]; then
  run_install
  exit 0
fi

run_apply
