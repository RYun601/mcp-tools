[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "apply")]
    [string]$Command = "install",

    [ValidateSet("all", "designcomputer", "benborla")]
    [string]$Upstream = "all",

    [string]$ServerName = "mysql_1",
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$OutputDir = "",
    [switch]$KeepLegacyMysql,
    [switch]$KeepOtherUpstreams
)

$ErrorActionPreference = "Stop"

$DesigncomputerPackage = "mysql-mcp-server==0.2.2"
$BenborlaPackage = "@benborla29/mcp-server-mysql@2.0.5"

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

function Format-CompactJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,
        [int]$IndentSize = 2
    )

    $stringBuilder = New-Object System.Text.StringBuilder
    $indentLevel = 0
    $isInString = $false
    $isEscaped = $false
    $newline = "`r`n"

    for ($index = 0; $index -lt $Json.Length; $index++) {
        $char = $Json[$index]

        if ($isInString) {
            [void]$stringBuilder.Append($char)

            if ($isEscaped) {
                $isEscaped = $false
                continue
            }

            if ($char -eq '\') {
                $isEscaped = $true
                continue
            }

            if ($char -eq '"') {
                $isInString = $false
            }
            continue
        }

        if ([char]::IsWhiteSpace($char)) {
            continue
        }

        switch ($char) {
            '{' {
                [void]$stringBuilder.Append($char)
                $indentLevel++
                [void]$stringBuilder.Append($newline)
                [void]$stringBuilder.Append((' ' * ($indentLevel * $IndentSize)))
            }
            '[' {
                [void]$stringBuilder.Append($char)
                $indentLevel++
                [void]$stringBuilder.Append($newline)
                [void]$stringBuilder.Append((' ' * ($indentLevel * $IndentSize)))
            }
            '}' {
                $indentLevel--
                [void]$stringBuilder.Append($newline)
                [void]$stringBuilder.Append((' ' * ($indentLevel * $IndentSize)))
                [void]$stringBuilder.Append($char)
            }
            ']' {
                $indentLevel--
                [void]$stringBuilder.Append($newline)
                [void]$stringBuilder.Append((' ' * ($indentLevel * $IndentSize)))
                [void]$stringBuilder.Append($char)
            }
            ',' {
                [void]$stringBuilder.Append($char)
                [void]$stringBuilder.Append($newline)
                [void]$stringBuilder.Append((' ' * ($indentLevel * $IndentSize)))
            }
            ':' {
                [void]$stringBuilder.Append(': ')
            }
            '"' {
                $isInString = $true
                [void]$stringBuilder.Append($char)
            }
            default {
                [void]$stringBuilder.Append($char)
            }
        }
    }

    return $stringBuilder.ToString()
}

function Get-UpstreamList {
    param([string]$Name)

    if ($Name -eq "all") {
        return @("designcomputer", "benborla")
    }

    return @($Name)
}

function Get-MySqlMcpServerConfig {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("designcomputer", "benborla")]
        [string]$UpstreamName
    )

    if ($UpstreamName -eq "designcomputer") {
        return @{
            type = "stdio"
            command = "uvx"
            args = @(
                "--from",
                $DesigncomputerPackage,
                "python",
                "-m",
                "mysql_mcp_server.server"
            )
            envFile = ".vscode/mysql.mcp.env"
        }
    }

    return @{
        type = "stdio"
        command = "npx"
        args = @(
            "-y",
            $BenborlaPackage
        )
        envFile = ".vscode/mysql.mcp.env"
    }
}

function Get-MySqlMcpUpstreamName {
    param([object]$ServerConfig)

    if ($null -eq $ServerConfig) {
        return $null
    }

    if (-not ($ServerConfig -is [System.Collections.IDictionary])) {
        return $null
    }

    $command = [string]($ServerConfig["command"])
    $args = $ServerConfig["args"]
    if ($null -eq $args -or -not ($args -is [System.Collections.IEnumerable]) -or ($args -is [string])) {
        return $null
    }

    $argText = (($args | ForEach-Object { [string]$_ }) -join " ")

    if ($command -eq "uvx" -and ($argText -match "mysql-mcp-server==|mysql_mcp_server\.server")) {
        return "designcomputer"
    }

    if ($command -eq "npx" -and ($argText -match "@benborla29/mcp-server-mysql")) {
        return "benborla"
    }

    return $null
}

function Get-RequiredEnvKeys {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("designcomputer", "benborla")]
        [string]$UpstreamName
    )

    if ($UpstreamName -eq "designcomputer") {
        return @("MYSQL_HOST", "MYSQL_PORT", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_DATABASE")
    }

    return @("MYSQL_HOST", "MYSQL_PORT", "MYSQL_USER", "MYSQL_PASS", "MYSQL_DB")
}

function Read-EnvKeyMap {
    param([string]$Path)

    $result = @{}
    if (-not (Test-Path $Path)) {
        return $result
    }

    $lines = Get-Content -Path $Path
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimLine = $line.Trim()
        if ($trimLine.StartsWith("#")) {
            continue
        }

        $parts = $trimLine.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $key = $parts[0].Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $result[$key] = $parts[1]
        }
    }

    return $result
}

function Show-MissingEnvKeyWarning {
    param(
        [string]$EnvPath,
        [string]$UpstreamName
    )

    $envMap = Read-EnvKeyMap -Path $EnvPath
    $requiredKeys = Get-RequiredEnvKeys -UpstreamName $UpstreamName
    $missingKeys = @()

    foreach ($requiredKey in $requiredKeys) {
        if (-not $envMap.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace([string]$envMap[$requiredKey])) {
            $missingKeys += $requiredKey
        }
    }

    if ($missingKeys.Count -gt 0) {
        Write-Warning ("Env file missing keys for upstream '{0}': {1}" -f $UpstreamName, ($missingKeys -join ", "))
    }
}

function Read-McpConfig {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return @{}
    }

    try {
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey("AsHashtable")) {
            return Get-Content -Path $Path -Raw | ConvertFrom-Json -AsHashtable
        }

        $parsed = Get-Content -Path $Path -Raw | ConvertFrom-Json
        return ConvertTo-HashtableRecursive -InputObject $parsed
    }
    catch {
        $backupPath = "$Path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $Path -Destination $backupPath -Force
        Write-Warning "Existing mcp.json is invalid JSON. Backed up to: $backupPath"
        return @{}
    }
}

function Save-McpConfig {
    param(
        [string]$Path,
        [hashtable]$Config
    )

    $jsonCompact = $Config | ConvertTo-Json -Depth 20 -Compress
    $jsonFormatted = Format-CompactJson -Json $jsonCompact -IndentSize 2
    Set-Content -Path $Path -Value $jsonFormatted -Encoding UTF8
}

function Show-DependencyWarning {
    param([string[]]$UpstreamNames)

    if (($UpstreamNames -contains "designcomputer") -and (-not (Get-Command uvx -ErrorAction SilentlyContinue))) {
        Write-Warning "uvx was not found. designcomputer upstream requires uvx: https://docs.astral.sh/uv/getting-started/installation/"
    }

    if (($UpstreamNames -contains "benborla") -and (-not (Get-Command npx -ErrorAction SilentlyContinue))) {
        Write-Warning "npx was not found. benborla upstream requires Node.js/npm."
    }
}

$toolDir = (Resolve-Path $PSScriptRoot).Path
$envExampleTemplatePath = Join-Path $toolDir "mysql.mcp.env.example"
if (-not (Test-Path $envExampleTemplatePath)) {
    throw "Template file not found: $envExampleTemplatePath"
}

if ($Command -eq "install") {
    $targetUpstreams = Get-UpstreamList -Name $Upstream

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".mysql-mcp-presets"
    }

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $resolvedOutputDir = (Resolve-Path $OutputDir).Path

    $outputEnvTemplatePath = Join-Path $resolvedOutputDir "mysql.mcp.env.example"
    Copy-Item -Path $envExampleTemplatePath -Destination $outputEnvTemplatePath -Force

    foreach ($targetUpstream in $targetUpstreams) {
        $serverConfig = Get-MySqlMcpServerConfig -UpstreamName $targetUpstream
        $presetConfig = @{
            servers = @{
                $ServerName = $serverConfig
            }
        }

        $presetPath = Join-Path $resolvedOutputDir ("mcp.{0}.json" -f $targetUpstream)
        Save-McpConfig -Path $presetPath -Config $presetConfig
        Write-Host ("Generated preset: {0}" -f $presetPath)
    }

    Show-DependencyWarning -UpstreamNames $targetUpstreams

    Write-Host ("Preset output dir: {0}" -f $resolvedOutputDir)
    Write-Host "Copy mcp.<upstream>.json to target project .vscode/mcp.json, then copy mysql.mcp.env.example to .vscode/mysql.mcp.env and fill credentials."
    exit 0
}

if ($Command -eq "apply" -and -not $PSBoundParameters.ContainsKey("Upstream")) {
    $Upstream = "designcomputer"
}

if ($Upstream -eq "all") {
    throw "apply command requires a single upstream: -Upstream designcomputer or -Upstream benborla"
}

if (-not (Test-Path $WorkspaceRoot)) {
    throw "Workspace path does not exist: $WorkspaceRoot"
}

$resolvedWorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
$vscodeDir = Join-Path $resolvedWorkspaceRoot ".vscode"
$mcpPath = Join-Path $vscodeDir "mcp.json"
$envExamplePath = Join-Path $vscodeDir "mysql.mcp.env.example"
$envPath = Join-Path $vscodeDir "mysql.mcp.env"

New-Item -ItemType Directory -Force -Path $vscodeDir | Out-Null
Copy-Item -Path $envExampleTemplatePath -Destination $envExamplePath -Force
if (-not (Test-Path $envPath)) {
    Copy-Item -Path $envExampleTemplatePath -Destination $envPath -Force
}

$config = Read-McpConfig -Path $mcpPath
if (-not ($config -is [System.Collections.IDictionary])) {
    $config = @{}
}

if (-not $config.ContainsKey("servers") -or $null -eq $config["servers"] -or -not ($config["servers"] -is [System.Collections.IDictionary])) {
    $config["servers"] = @{}
}

$servers = $config["servers"]
if ((-not $KeepLegacyMysql.IsPresent) -and ($ServerName -ne "mysql") -and ($servers.ContainsKey("mysql"))) {
    $servers.Remove("mysql")
    Write-Host "Removed local legacy server name 'mysql' to reduce naming conflicts."
}

if (-not $KeepOtherUpstreams.IsPresent) {
    foreach ($existingServerName in @($servers.Keys)) {
        if ($existingServerName -eq $ServerName) {
            continue
        }

        $detectedUpstream = Get-MySqlMcpUpstreamName -ServerConfig $servers[$existingServerName]
        if ($null -ne $detectedUpstream) {
            $servers.Remove($existingServerName)
            Write-Host ("Removed old managed mysql server '{0}' ({1})." -f $existingServerName, $detectedUpstream)
        }
    }
}

$servers[$ServerName] = Get-MySqlMcpServerConfig -UpstreamName $Upstream
$config["servers"] = $servers
Save-McpConfig -Path $mcpPath -Config $config

Show-MissingEnvKeyWarning -EnvPath $envPath -UpstreamName $Upstream
Show-DependencyWarning -UpstreamNames @($Upstream)

Write-Host "MySQL MCP config updated: $mcpPath"
Write-Host "Server name: $ServerName"
Write-Host "Upstream: $Upstream"
Write-Host "Edit $envPath with DB credentials, then restart your MCP client."
