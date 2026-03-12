# MCP 工具目录说明

本目录用于存放项目内可复用的 MCP 集成工具。  
当前已提供：

- `mysql/`：MySQL MCP 的团队集成方案（安装脚本、模板、文档）

后续新增自定义 MCP 时，建议按同级目录扩展，例如：

- `tools/mcp/redis/`
- `tools/mcp/es/`
- `tools/mcp/internal-api/`

每个子目录建议保持以下结构：

- 安装脚本（例如 `setup-*.ps1`）
- 连接模板（例如 `*.env.example`）
- 客户端配置示例（VSCode/Codex）
- `README.md`（说明上游来源、用途、升级方式）
