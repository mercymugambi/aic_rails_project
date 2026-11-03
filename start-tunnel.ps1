# start-tunnel.ps1
# Starts a Cloudflare quick tunnel, extracts the public URL,
# and updates CALLBACK_URL in .env automatically.
# Run this BEFORE starting Rails whenever you want to test M-Pesa.

$cloudflared = "C:\Users\lenovo\bin\cloudflared.exe"
$envFile     = Join-Path $PSScriptRoot ".env"

Write-Host ""
Write-Host "AIC Kabuku - Cloudflare Tunnel Launcher" -ForegroundColor Cyan
Write-Host ""

$job = Start-Job -ScriptBlock {
    param($cf)
    & $cf tunnel --url http://localhost:3000 2>&1
} -ArgumentList $cloudflared

Write-Host "Starting tunnel, waiting for URL..." -ForegroundColor Yellow

$tunnelUrl = $null
$timeout   = 30
$elapsed   = 0

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 1
    $elapsed++

    $output = Receive-Job -Job $job -Keep
    $line   = $output | Select-String "trycloudflare.com" | Select-Object -Last 1

    if ($line) {
        $tunnelUrl = ($line.Line -replace '.*\|\s*(https://[^\s|]+).*', '$1').Trim()
        if ($tunnelUrl -match "^https://") { break }
    }
}

if (-not $tunnelUrl) {
    Write-Host "ERROR: Could not get tunnel URL. Is cloudflared installed?" -ForegroundColor Red
    Stop-Job -Job $job
    Remove-Job -Job $job
    exit 1
}

$callbackUrl = "$tunnelUrl/api/v1/callback"

Write-Host ""
Write-Host "Tunnel is LIVE!" -ForegroundColor Green
Write-Host "  Public URL  : $tunnelUrl"   -ForegroundColor White
Write-Host "  Callback URL: $callbackUrl" -ForegroundColor White
Write-Host ""

# Update CALLBACK_URL in .env
$envContent = Get-Content $envFile -Raw
$newContent = $envContent -replace 'CALLBACK_URL=.*', "CALLBACK_URL=$callbackUrl"
Set-Content -Path $envFile -Value $newContent -NoNewline

Write-Host ".env updated with new CALLBACK_URL!" -ForegroundColor Green
Write-Host ""
Write-Host "ACTION: Restart your Rails server now to pick up the new URL." -ForegroundColor Yellow
Write-Host "Press Ctrl+C here when you are done developing." -ForegroundColor DarkGray
Write-Host ""

Receive-Job -Job $job -Wait
Stop-Job  -Job $job
Remove-Job -Job $job
