@echo off
REM Launch Cloudflare Tunnel and Python server
tasklist /FI "IMAGENAME eq cloudflared.exe" /NH | findstr /I "cloudflared.exe" >nul
if %ERRORLEVEL%==0 (
	echo cloudflared appears to already be running. Skipping start.
) else (
	echo cloudflared not detected — starting tunnel...
	pushd "C:\Program Files (x86)\cloudflared"
	start "" "C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel run my-ws-tunnel
	popd
)

cd /d "C:\Users\stayd\OneDrive\Apps\Multi"
python server.py