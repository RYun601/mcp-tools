# MySQL MCP（团队集成版）

## 上游来源
- `designcomputer/mysql_mcp_server`
- <https://github.com/designcomputer/mysql_mcp_server>
- `benborla/mcp-server-mysql`
- <https://github.com/benborla/mcp-server-mysql>

## 本目录职责
- 保持上游版本固定，避免团队成员使用不同版本导致行为差异。
- 通过 `install` 命令生成“可复制到任意项目”的预设配置。
- 通过 `apply` 命令将指定上游写入目标项目 `.vscode/mcp.json`。
- 统一使用 `.vscode/mysql.mcp.env` 保存数据库配置，不在 `mcp.json` 中硬编码凭据。

## 命令模式

### 1) install（默认）
用途：机器级生成预设配置，一次生成后可在多个项目复用（在工具根目录下执行下列命令）。

Windows：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\mysql\setup-vscode-mysql-mcp.ps1 install
```

macOS/Linux：
```bash
bash ./mysql/setup-vscode-mysql-mcp.sh install
```

默认行为：
- 未指定上游时，生成全部上游配置（`designcomputer` + `benborla`）。
- 默认输出目录：
`~/.mysql-mcp-presets`

可选参数：
- `--upstream designcomputer|benborla|all`
- `--server-name mysql_custom`
- `--output-dir /custom/output/dir`

产出文件：
- `mcp.designcomputer.json`
- `mcp.benborla.json`
- `mysql.mcp.env.example`

### 2) apply
用途：将指定上游写入某个项目的 `.vscode/mcp.json`，并可清理旧上游配置避免冲突。

Windows（默认在工具根目录执行，显式指定目标项目）：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\mysql\setup-vscode-mysql-mcp.ps1 apply -WorkspaceRoot D:\path\to\target-project
```

macOS/Linux（默认在工具根目录执行，显式指定目标项目）：
```bash
bash ./mysql/setup-vscode-mysql-mcp.sh apply --workspace-root /path/to/target-project
```

如果当前目录本身就是目标项目根目录，可省略 `-WorkspaceRoot/--workspace-root`。
如果不指定 `-Upstream/--upstream`，`apply` 默认使用 `designcomputer`。

apply 行为：
- 自动创建目标项目 `.vscode/`。
- 写入或更新 `.vscode/mcp.json` 指定服务。
- 同步 `.vscode/mysql.mcp.env.example`。
- 若 `.vscode/mysql.mcp.env` 不存在则自动创建。
- 默认清理已识别的旧 MySQL MCP 上游配置，避免冲突。

可选参数：
- `--upstream designcomputer|benborla`（apply 选填，默认 `designcomputer`，不能为 `all`）
- `--server-name mysql_custom`
- `--workspace-root /path/to/project`
- `--keep-legacy-mysql`（保留旧服务名 `mysql`）
- `--keep-other-upstreams`（保留其他受管上游配置）

## 环境变量说明
`mysql.mcp.env.example` 同时包含两套变量名，支持同一文件兼容两种上游：
- designcomputer: `MYSQL_PASSWORD`、`MYSQL_DATABASE`
- benborla: `MYSQL_PASS`、`MYSQL_DB`

建议两套变量保持一致，避免切换上游时连接信息不一致。

## 上游固定版本
- `designcomputer`: `mysql-mcp-server==0.2.2`
- `benborla`: `@benborla29/mcp-server-mysql@2.0.5`

如需升级版本，请同时修改：
- `tools/mysql/setup-vscode-mysql-mcp.ps1`
- `tools/mysql/setup-vscode-mysql-mcp.sh`
- `tools/mysql/codex.mysql.example.toml`（若对应上游也要升级）

## 目录说明
- `setup-vscode-mysql-mcp.ps1`: Windows 脚本（install/apply）
- `setup-vscode-mysql-mcp.sh`: macOS/Linux 脚本（install/apply）
- `mysql.mcp.env.example`: 数据库连接模板（双上游兼容）
- `codex.mysql.example.toml`: Codex 全局配置示例（designcomputer）
