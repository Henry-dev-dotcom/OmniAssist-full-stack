<#
.SYNOPSIS
  Starts OmniAssist on this PC: database, API, and the web app, all on one address.

.DESCRIPTION
  Open http://localhost:8000 on this PC. For your phone, see docs/personal-setup.md.
  Close this window to stop it. Safe to run again; it never creates duplicates.

.PARAMETER Build
  Rebuild the web app first (needs Flutter). Do this after updating the code.

.PARAMETER PgData
  PostgreSQL data folder to start if the database is not already running.

.PARAMETER BindAll
  Listen on the whole network, not only this PC. Only for a trusted home network; the
  phone cannot install the app or get notifications without HTTPS (use Tailscale instead).
#>
param(
    [switch]$Build,
    [string]$PgData = "C:\dev\omni-pg",
    [string]$PgBin = "C:\Program Files\PostgreSQL\13\bin",
    [string]$Flutter = "C:\dev\flutter\bin",
    [int]$Port = 8000,
    [switch]$BindAll
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$api = Join-Path $root "apps\api"
$client = Join-Path $root "apps\client"
$envFile = Join-Path $api ".env"

function Say($text) { Write-Host "[OmniAssist] $text" -ForegroundColor Cyan }

if (-not (Test-Path $envFile)) {
    throw "Missing $envFile. Copy infra\env\.env.example there first (see docs\personal-setup.md)."
}
$settings = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*)\s*$') { $settings[$Matches[1]] = $Matches[2] }
}

# 1. Web app
if ($Build) {
    Say "Building the web app (a few minutes)..."
    $env:PATH = "$Flutter;$env:PATH"
    Push-Location $client
    try {
        flutter pub get
        dart run build_runner build --delete-conflicting-outputs
        flutter build web --release --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw "Web build failed." }
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $client "build\web\index.html"))) {
    throw "The web app is not built yet. Run this script with -Build."
}

# 2. Database
$dbUrl = $settings["OMNI_DATABASE_URL"]
if ($dbUrl -notmatch ':(\d+)/') { throw "OMNI_DATABASE_URL in .env has no port." }
$dbPort = [int]$Matches[1]
function DbUp { [bool](Get-NetTCPConnection -State Listen -LocalPort $dbPort -ErrorAction SilentlyContinue) }
if (-not (DbUp)) {
    if (-not (Test-Path $PgData)) { throw "Database not running on port $dbPort and no data folder at $PgData." }
    Say "Starting the database on port $dbPort..."
    Start-Process -WindowStyle Hidden -FilePath (Join-Path $PgBin "pg_ctl.exe") -ArgumentList @(
        "-D", $PgData, "-o", "`"-p $dbPort -c listen_addresses=localhost`"", "-l", "$PgData.log", "start")
    for ($i = 0; $i -lt 30 -and -not (DbUp); $i++) { Start-Sleep -Seconds 1 }
    if (-not (DbUp)) { throw "The database did not start. See $PgData.log" }
}

# 3. API (also serves the web app). Migrations run first and are safe to repeat.
$env:OMNI_WEB_DIR = (Join-Path $client "build\web")
$uv = "python"
Push-Location $api
try {
    Say "Updating the database structure..."
    & $uv -m uv run alembic upgrade head
    if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }

    $hostName = if ($BindAll) { "0.0.0.0" } else { "127.0.0.1" }
    if ($settings["OMNI_VAPID_PRIVATE_KEY"]) {
        Say "Starting the reminder sender (push notifications)..."
        $worker = Start-Process -PassThru -WindowStyle Hidden -FilePath $uv -ArgumentList @(
            "-m", "uv", "run", "python", "-m", "src.workers.reminder_worker")
    }
    Say "Ready: open http://localhost:$Port  (close this window to stop)"
    & $uv -m uv run uvicorn src.main:app --host $hostName --port $Port --proxy-headers
} finally {
    Pop-Location
    if ($worker -and -not $worker.HasExited) { Stop-Process -Id $worker.Id -Force }
}
