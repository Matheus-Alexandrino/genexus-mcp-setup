@echo off
REM setup-genexus-mcp.bat
REM Lancador de 1 clique para o menu de setup da stack de MCPs do dev
REM GeneXus da Datainfo (GxObjGen + genexus-mcp + Azure DevOps + Oracle
REM SQLcl). A logica fica em setup-genexus-mcp.ps1, que precisa estar
REM na mesma pasta que este .bat.

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
