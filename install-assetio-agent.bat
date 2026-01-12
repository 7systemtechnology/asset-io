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

REM Check if winget is available
winget --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Windows Package Manager not found.
    echo Please update to Windows 10 1809+ or Windows 11.
    echo.
    pause
    exit /b 1
)

REM Set your server URL here
set "SERVER_URL=http://192.168.2.6/front/inventory.php"

REM Install the agent silently
winget install --id GLPI-Project.GLPI-Agent --silent --accept-package-agreements --accept-source-agreements --override "/quiet SERVER='%SERVER_URL%' RUNNOW=1 TAG='assetio' EXECMODE=service ADD_FIREWALL_EXCEPTION=1" >nul 2>&1

REM Check installation result
if %errorlevel% equ 0 (
    echo [OK] Installation completed
    echo.
    
    REM Wait for service to be created
    timeout /t 5 /nobreak >nul
    
    REM Rebrand the service
    sc config "GLPI Agent" DisplayName= "Assetio Asset Monitor" >nul 2>&1
    sc description "GLPI Agent" "Assetio asset management and inventory service" >nul 2>&1
    
    echo [OK] Service configured successfully
    echo.
    
    REM Check server connectivity
    echo Verifying connection to: %SERVER_URL%
    echo.
    
    REM Try to reach the server using curl or PowerShell
    curl --version >nul 2>&1
    if %errorlevel% equ 0 (
        REM Use curl if available
        curl -s -o nul -w "%%{http_code}" --max-time 10 "%SERVER_URL%" > "%TEMP%\assetio_check.tmp" 2>&1
        set /p HTTP_CODE=<"%TEMP%\assetio_check.tmp"
        del "%TEMP%\assetio_check.tmp" 2>nul
    ) else (
        REM Fallback to PowerShell
        powershell -Command "try { $response = Invoke-WebRequest -Uri '%SERVER_URL%' -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>&1
        if !errorlevel! equ 0 (
            set "HTTP_CODE=200"
        ) else (
            set "HTTP_CODE=000"
        )
    )
    
    REM Check the response
    if "!HTTP_CODE!"=="200" (
        echo [OK] Connected to asset management server successfully
        echo Server URL: %SERVER_URL%
    ) else if "!HTTP_CODE!"=="000" (
        echo [WARNING] Unable to reach asset management server
        echo Server URL: %SERVER_URL%
        echo.
        echo Possible reasons:
        echo - Server is offline or unreachable
        echo - Firewall blocking connection
        echo - Incorrect URL configured
        echo.
        echo The agent is installed but may not send inventory until server is reachable.
    ) else (
        echo [WARNING] Server responded with HTTP code: !HTTP_CODE!
        echo Server URL: %SERVER_URL%
        echo.
        echo The agent is installed but server connectivity should be verified.
    )
    echo.
    echo Assetio Agent is now monitoring this computer.
    echo.
) else (
    echo [ERROR] Installation failed
    echo Error code: %errorlevel%
    echo Please contact IT support.
    echo.
    pause
    exit /b 1
)

echo.
echo Installation complete. You can close this window.
timeout /t 10
exit /b 0
```

## What It Now Does:

1. **After installation**, it tests connectivity to your server URL
2. **Shows the full URL** it's trying to reach
3. **Reports different scenarios:**
   - ✅ **HTTP 200**: Server is reachable and responding correctly
   - ⚠️ **HTTP 000** (timeout/unreachable): Server cannot be reached
   - ⚠️ **Other HTTP codes**: Server responded but may have issues

## Example Outputs:

**Success:**
```
[OK] Installation completed
[OK] Service configured successfully

Verifying connection to: https://your-glpi-server.com/front/inventory.php

[OK] Connected to asset management server successfully
Server URL: https://your-glpi-server.com/front/inventory.php

Assetio Agent is now monitoring this computer.
```

**Server Unreachable:**
```
[OK] Installation completed
[OK] Service configured successfully

Verifying connection to: https://your-glpi-server.com/front/inventory.php

[WARNING] Unable to reach asset management server
Server URL: https://your-glpi-server.com/front/inventory.php

Possible reasons:
- Server is offline or unreachable
- Firewall blocking connection
- Incorrect URL configured

The agent is installed but may not send inventory until server is reachable.

Assetio Agent is now monitoring this computer.



