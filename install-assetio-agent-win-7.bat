@echo off
setlocal enabledelayedexpansion

REM Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo =======================================
    echo    Assetio Agent Installation
    echo =======================================
    echo.
    echo ERROR: This installer requires administrator privileges.
    echo Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo =======================================
echo    Assetio Agent Installation
echo =======================================
echo.
echo Installing Assetio Agent...
echo Please wait, this may take a few minutes...
echo.

REM Set your server URL here
set "SERVER_URL=http://192.168.2.6/front/inventory.php"
set "DOWNLOAD_URL=https://github.com/glpi-project/glpi-agent/releases/download/1.10/GLPI-Agent-1.10-x64.msi"
set "INSTALLER_FILE=%TEMP%\assetio-agent-installer.msi"

REM Detect architecture
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    set "ARCH=x64"
    set "DOWNLOAD_URL=https://github.com/glpi-project/glpi-agent/releases/download/1.10/GLPI-Agent-1.10-x64.msi"
) else if "%PROCESSOR_ARCHITECTURE%"=="x86" (
    set "ARCH=x86"
    set "DOWNLOAD_URL=https://github.com/glpi-project/glpi-agent/releases/download/1.10/GLPI-Agent-1.10-x86.msi"
) else (
    echo ERROR: Unsupported architecture
    pause
    exit /b 1
)

echo Detected: Windows %ARCH%
echo.

REM Download the installer using PowerShell (available in Win7 SP1)
echo Downloading Assetio Agent...
echo.

powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; try { Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%INSTALLER_FILE%' -UseBasicParsing; exit 0 } catch { exit 1 }}" 2>nul

if %errorlevel% neq 0 (
    echo [ERROR] Download failed
    echo Please check your internet connection
    echo.
    pause
    exit /b 1
)

REM Check if file was downloaded
if not exist "%INSTALLER_FILE%" (
    echo [ERROR] Installer file not found
    echo.
    pause
    exit /b 1
)

echo [OK] Download completed
echo.

REM Install the agent
echo Installing Assetio Agent...
echo.

msiexec /i "%INSTALLER_FILE%" /quiet SERVER="%SERVER_URL%" TAG="assetio" RUNNOW=1 EXECMODE=service ADD_FIREWALL_EXCEPTION=1

if %errorlevel% equ 0 (
    echo [OK] Installation completed
    echo.
    
    REM Wait for service to be created
    timeout /t 5 /nobreak >nul
    
    REM Rebrand the service
    sc config "GLPI Agent" DisplayName= "Assetio Agent" >nul 2>&1
    sc description "GLPI Agent" "Assetio asset management and inventory service" >nul 2>&1
    
    echo [OK] Service configured as "Assetio Agent"
    echo.
    
    REM Check server connectivity using PowerShell
    echo Verifying connection to Assetio server...
    echo.
    
    powershell -Command "& {try { $response = Invoke-WebRequest -Uri '%SERVER_URL%' -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop; Write-Host '[OK] Successfully connected to Assetio server'; exit 0 } catch { if ($_.Exception.Response.StatusCode.value__ -eq 400 -or $_.Exception.Response.StatusCode.value__ -eq 405) { Write-Host '[OK] Successfully connected to Assetio server'; exit 0 } else { Write-Host '[WARNING] Unable to reach Assetio server'; Write-Host ''; Write-Host 'Possible reasons:'; Write-Host '  - Server is offline or unreachable'; Write-Host '  - Not connected to the correct network'; Write-Host '  - Firewall blocking connection'; Write-Host ''; Write-Host 'The agent is installed and will connect automatically'; Write-Host 'when the server becomes reachable.'; exit 1 } }}" 2>nul
    
    echo.
    echo Assetio Agent is now monitoring this computer.
    echo.
) else (
    echo [ERROR] Installation failed
    echo Error code: %errorlevel%
    echo Please contact support for assistance.
    echo.
    
    REM Cleanup
    if exist "%INSTALLER_FILE%" del /f /q "%INSTALLER_FILE%" >nul 2>&1
    
    pause
    exit /b 1
)

REM Cleanup
if exist "%INSTALLER_FILE%" del /f /q "%INSTALLER_FILE%" >nul 2>&1

echo.
echo ========================================
echo Installation Summary
echo ========================================
echo Status:             Installed
echo Architecture:       %ARCH%
echo.
echo The Assetio Agent will automatically:
echo   * Connect to your asset management server
echo   * Send inventory updates hourly
echo   * Run in the background as a service
echo.
echo ========================================
echo.
echo Installation complete. You can close this window.
timeout /t 10
exit /b 0
