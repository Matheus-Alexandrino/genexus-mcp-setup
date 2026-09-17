@echo off
REM setup-genexus-mcp.bat
REM Lancador de 1 clique para o menu de setup dos MCPs do GeneXus
REM (GxObjGen + genexus-mcp). A logica fica em setup-genexus-mcp.ps1,
REM que precisa estar na mesma pasta que este .bat.

setlocal
set "SCRIPT_DIR=%~dp0"

where powershell >nul 2>nul
if errorlevel 1 (
    echo PowerShell nao foi encontrado no PATH. Instale o Windows PowerShell e tente de novo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup-genexus-mcp.ps1"

echo.
pause
