# MySQL MCP（团队集成版）

## 上游来源
- 官方上游仓库：`designcomputer/mysql_mcp_server`
- 仓库地址：<https://github.com/designcomputer/mysql_mcp_server>
- 本目录不重复造轮子，核心能力直接来自上游；这里做的是项目内集成和团队分发标准化。

## 本项目层的作用
- 固定版本：统一使用 `mysql-mcp-server==0.2.2`，避免不同成员安装到不同版本导致行为差异。
- 一键落地：脚本自动写入 `.vscode/mcp.json`，并生成 `.vscode/mysql.mcp.env` 模板。
- 配置分离：数据库凭据放在 `.vscode/mysql.mcp.env`，不硬编码到 `mcp.json`。
- 兼容处理：安装脚本兼容不同 PowerShell 版本的 JSON 解析差异，异常时会备份旧配置。
- 文档标准：同时提供 VSCode 与 Codex 的接入说明，降低团队接入成本。

## Windows 一键安装（VSCode 工作区）
在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mcp\mysql\setup-vscode-mysql-mcp.ps1
```

执行完成后：
1. 编辑 `.vscode/mysql.mcp.env`，填入真实数据库连接信息。
2. 重启 MCP 客户端。

## 全局配置注意事项
- 同时使用工作区 `.vscode/mcp.json` 与全局 `C:\Users\ranyun\.codex\config.toml` 时，建议避免同名服务。
- 推荐将全局旧项 `[mcp_servers.mysql]` 删除、注释或改名为 `mysql_legacy`。
- Codex 全局示例：`tools/mcp/mysql/codex.mysql.example.toml`。

## 如何更新上游版本
当上游发布新版本时，按以下流程更新：

1. 修改版本号
- `tools/mcp/mysql/setup-vscode-mysql-mcp.ps1` 中的 `mysql-mcp-server==0.2.2`
- `tools/mcp/mysql/codex.mysql.example.toml` 中的同版本号

2. 本地验证
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mcp\mysql\setup-vscode-mysql-mcp.ps1
Get-Content .\.vscode\mcp.json -Raw | ConvertFrom-Json | Out-Null
```

3. 回归检查
- 能正常发现并调用 MySQL MCP 工具
- `.vscode/mysql.mcp.env` 可被正确读取
- 文档命令仍可直接复用

## 目录说明
- `setup-vscode-mysql-mcp.ps1`：VSCode 本地安装脚本
- `mysql.mcp.env.example`：数据库连接模板
- `codex.mysql.example.toml`：Codex 全局配置示例
