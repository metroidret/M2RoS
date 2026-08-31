@echo off

if not exist out mkdir out

echo. Running scripts
python .\scripts\enemy_csv2asm.py -i .\SRC\data\enemies.csv -o .\SRC\data
if errorlevel 1 goto errorSCRIPT
python.exe .\scripts\samus_csv2asm.py -i .\SRC\samus\samus.csv -o .\SRC\samus
if errorlevel 1 goto errorSCRIPT
python.exe .\scripts\general_csv2asm.py -i .\SRC\data\sprites_credits.csv -o .\SRC\data -n sprites_credits
if errorlevel 1 goto errorSCRIPT
python.exe .\scripts\general_csv2asm.py -i .\SRC\data\sprites_samus.csv -o .\SRC\data -n sprites_samus
if errorlevel 1 goto errorSCRIPT
echo.  Success
echo.

:checkRGBDS
where rgbasm
if ERRORLEVEL 1 (
    echo.
    echo RGBDS not detected. Downloading...
    echo.
    curl -LJO "https://github.com/gbdev/rgbds/releases/download/v1.0.1/rgbds-win32.zip"
    echo.
    tar -xvf rgbds-win32.zip
    echo.
    goto checkRGBDS
)

echo. RGBDS detected
echo. Assembling .asm files
rgbasm -o out/game.o -i SRC/ SRC/game.asm
if errorlevel 1 goto errorASM
echo.  Success
echo.

echo. Linking .o files
rgblink -n out/M2RoS.sym -m out/M2RoS.map -o out/M2RoS.gb out/game.o
if errorlevel 1 goto errorLINK
echo.  Success
echo. 

echo. Writing header
rgbfix -v -t METROID2 -l 0x01 -m MBC1+RAM+BATTERY -r 0x02 -p 0x00 -j out/M2RoS.gb
if errorlevel 1 goto errorFIX
echo.  Done
echo.

certutil -hashfile out/M2RoS.gb MD5
echo.
fc /b Metroid2.gb out\M2RoS.gb
goto assembledDone

:errorSCRIPT
echo.
echo. Script Error.
echo.
goto errorDone
:errorASM
echo.
echo. Assembler Error.
echo.
goto errorDone
:errorLINK
echo.
echo. Linker Error.
echo.
goto errorDone
:errorFIX
echo.
echo. RGBFIX Error.
echo.
goto errorDone

:assembledDone
if not [%1] == [yes] pause
exit 0

:errorDone
pause
exit 1
