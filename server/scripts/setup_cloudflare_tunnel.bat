@echo off
setlocal

echo ============================================
echo  SUT Smart Bus Cloudflare Tunnel Setup
echo ============================================
echo.

set "ROOT_DIR=%~dp0..\.."
pushd "%ROOT_DIR%"

if not exist "server\.env.cloudflare" (
    if exist "server\.env.cloudflare.example" (
        copy /Y "server\.env.cloudflare.example" "server\.env.cloudflare" >nul
        echo Created server\.env.cloudflare from example.
        echo Edit that file and paste your Cloudflare tunnel token.
        echo.
    ) else (
        echo ERROR: server\.env.cloudflare.example was not found.
        popd
        exit /b 1
    )
)

findstr /C:"replace-with-your-cloudflare-tunnel-token" "server\.env.cloudflare" >nul
if %errorlevel% equ 0 (
    echo Token placeholder is still present in server\.env.cloudflare
    echo.
    echo Get a Docker tunnel token from:
    echo   Cloudflare Zero Trust ^> Networks ^> Tunnels ^> Create a tunnel ^> Docker
    echo.
    echo After pasting the token, start production mode with:
    echo   docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d --build
    echo.
    popd
    pause
    exit /b 0
)

echo Starting stack with Cloudflare Tunnel...
docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d --build

if %errorlevel% neq 0 (
    echo.
    echo ERROR: Failed to start the stack.
    popd
    pause
    exit /b 1
)

echo.
echo Stack started.
echo.
echo Useful commands:
echo   docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml logs -f cloudflared
echo   docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml ps
echo   docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml down
echo.
echo Note:
echo   - FastAPI on port 8000 is now bound to localhost only.
echo   - MQTT WebSocket on port 9001 is now bound to localhost only.
echo   - Raw MQTT on port 1883 is still exposed directly for device traffic.
echo.

popd
pause
