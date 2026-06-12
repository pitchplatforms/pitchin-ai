@echo off
:: Run ralph 1 worker at a time, N times total, with 60s between each run.
:: Usage: loop-10.bat [N]   (default: 10)
:: Stop early: Ctrl+C, or create ralph\STOP before the next iteration.
:: Note: must run as Administrator to keep the laptop awake (powercfg).

set max=%~1
if "%max%"=="" set max=10

:: Disable sleep so the laptop stays awake during the run.
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
echo Laptop sleep disabled for this run.

set count=0
:loop
if %count% equ %max% goto end

set /a next=%count%+1
echo.
echo === Ralph run %next% of %max% ===
bash ralph/loop-parallel.sh 1

set /a count=%count%+1
if %count% equ %max% goto end

echo Waiting 60 seconds before next run...
timeout /t 60
goto loop

:end
echo.
echo Done — completed %count% run(s).

:: Restore default sleep timeouts (30 min on AC, 15 min on battery).
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
echo Laptop sleep settings restored.
