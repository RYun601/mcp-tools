[CmdletBinding()]
param(
    [string]$ServerName = "mysql_hppi",
    [switch]$KeepLegacyMysql
)

$ErrorActionPreference = "Stop"

function ConvertTo-HashtableRecursive {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $result
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $result = @()
        foreach ($item in $InputObject) {
            $result += ,(ConvertTo-HashtableRecursive -InputObject $item)
        }
        return $result
    }

    if ($InputObject -is [pscustomobject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-HashtableRecursive -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

# Resolve repository root from script path so cwd does not matter
$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$vscodeDir = Join-Path $workspaceRoot ".vscode"
$mcpPath = Join-Path $vscodeDir "mcp.json"
$envExampleTemplatePath = Join-Path $workspaceRoot "tools\mcp\mysql\mysql.mcp.env.example"
$envExamplePath = Join-Path $vscodeDir "mysql.mcp.env.example"
$envPath = Join-Path $vscodeDir "mysql.mcp.env"

New-Item -ItemType Directory -Force -Path $vscodeDir | Out-Null

if (-not (Test-Path $envExampleTemplatePath)) {
    throw "Template file not found: $envExampleTemplatePath"
}

Copy-Item -Path $envExampleTemplatePath -Destination $envExamplePath -Force
if (-not (Test-Path $envPath)) {
    Copy-Item -Path $envExampleTemplatePath -Destination $envPath -Force
}

$config = @{}
if (Test-Path $mcpPath) {
    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("AsHashtable")) {
            $config = Get-Content $mcpPath -Raw | ConvertFrom-Json -AsHashtable
        }
        else {
            $parsed = Get-Content $mcpPath -Raw | ConvertFrom-Json
            $config = ConvertTo-HashtableRecursive -InputObject $parsed
        }
    }
    catch {
        $backupPath = "$mcpPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $mcpPath -Destination $backupPath -Force
        Write-Warning "Existing mcp.json is invalid JSON. Backed up to: $backupPath"
        $config = @{}
    }
}

if (-not $config.ContainsKey("servers") -or $null -eq $config["servers"]) {
    $config["servers"] = @{}
}

$servers = $config["servers"]
if ((-not $KeepLegacyMysql.IsPresent) -and ($servers.ContainsKey('mysql'))) {
    $servers.Remove("mysql")
    Write-Host "Removed local legacy server name 'mysql' to reduce naming conflicts."
}

$servers[$ServerName] = @{
    type = "stdio"
    command = "uvx"
    args = @(
        "--from",
        "mysql-mcp-server==0.2.2",
        "python",
        "-m",
        "mysql_mcp_server.server"
    )
    envFile = ".vscode/mysql.mcp.env"
}

$config | ConvertTo-Json -Depth 20 | Set-Content -Path $mcpPath -Encoding UTF8

if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
    Write-Warning "uvx was not found. Install uv first: https://docs.astral.sh/uv/getting-started/installation/"
}

Write-Host "MySQL MCP config updated: $mcpPath"
Write-Host "Server name: $ServerName"
Write-Host "Edit $envPath with DB credentials, then restart your MCP client."
