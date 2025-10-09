@echo off
echo Compiling MQL5 file: %1
"C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:%1 /log
echo Compilation finished with exit code: %ERRORLEVEL%
pause