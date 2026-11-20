@ECHO off
:: =============================================================================
:: RETIRED - this batch script is no longer maintained (last version 0.6.0-beta).
:: Please use the PowerShell script Simple-WIM2ESD---ESD2WIM-Converter.ps1
:: (version 1.0.0 and later) instead. This file is kept for reference only.
:: =============================================================================
setlocal EnableDelayedExpansion
TITLE Simple WIM2ESD / ESD2WIM Converter - RETIRED batch version

:: -----------------------------------------------------------------------------
:: DISM selection :
:: The DISM shipped with the OS is used by default, so the newest available
:: DISM version is always used. The bundled DISM folder next to this script
:: is only used as a fallback on systems where no DISM is installed.
:: -----------------------------------------------------------------------------
CD /d "%~dp0"
SET "DISM_EXE=%SYSTEMROOT%\System32\dism.exe"
IF NOT EXIST "%DISM_EXE%" SET "DISM_EXE=%~dp0DISM\dism.exe"
IF NOT EXIST "%DISM_EXE%" GOTO NoDism

GOTO AdminRightsRoutine


:NoDism
CLS
COLOR 17
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                   DISM not found
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  No usable DISM executable was found.
ECHO.
ECHO.  This script uses the DISM installed with Windows :
ECHO.  %SYSTEMROOT%\System32\dism.exe
ECHO.
ECHO.  As a fallback, it looks for a bundled copy in :
ECHO.  %~dp0DISM\dism.exe
ECHO.
ECHO.  Neither was found. Please make sure DISM is available and try again.
ECHO.
PAUSE
EXIT


:AdminRightsRoutine
>NUL 2>&1 NET SESSION
IF %ERRORLEVEL% NEQ 0 GOTO GetAdminRights
GOTO Home


:GetAdminRights
CLS
COLOR 17
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                           Administrator Rights Required
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  You did not execute the script as Administrator.
ECHO.  Administrator rights are required.
ECHO.  You will now be prompted for Administrator rights.
ECHO.  If you do not grant Administrator rights, this script will not run.
ECHO.
PAUSE
ECHO Set UAC = CreateObject^("Shell.Application"^) > "%temp%\GetAdminRights.vbs"
ECHO UAC.ShellExecute "cmd.exe", "/c """"%~f0""""", "", "runas", 1 >> "%temp%\GetAdminRights.vbs"
"%temp%\GetAdminRights.vbs"
DEL "%temp%\GetAdminRights.vbs"
EXIT /B


:Home
CLS
COLOR 17
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                      Welcome
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Welcome to the Simple WIM2ESD / ESD2WIM Converter (version 0.6.0-beta)
ECHO.
ECHO.  NOTE : This batch script is RETIRED and no longer maintained.
ECHO.         Please use Simple-WIM2ESD---ESD2WIM-Converter.ps1 (version 1.0.0) instead.
ECHO.
ECHO.  This tool allows to quickly convert a WIM Image to an ESD Image, and vice-versa.
ECHO.
ECHO.  Using DISM : %DISM_EXE%
ECHO.
ECHO.  Please read the full documentation on :
ECHO.  https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter/
ECHO.
ECHO.
PAUSE
GOTO ConversionType


:ConversionType
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 Program Parameters
ECHO.                                                  Conversion Type
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  What type of conversion do you want ?
ECHO.
ECHO.  [1] WIM --^> ESD
ECHO.  [2] ESD --^> WIM
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c 12qs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 GOTO WimEsdPreset
IF %ERRORLEVEL%==2 GOTO EsdWimPreset
IF %ERRORLEVEL%==3 EXIT
GOTO Home


:WimEsdPreset
SET "SRCtype=WIM"
SET "DSTtype=ESD"
SET "SRC_PATH=install.wim"
SET "DST_PATH=install.esd"
SET "COMPRESS_TYPE=Recovery"
GOTO SrcPath


:EsdWimPreset
SET "SRCtype=ESD"
SET "DSTtype=WIM"
SET "SRC_PATH=install.esd"
SET "DST_PATH=install.wim"
SET "COMPRESS_TYPE=Maximum"
GOTO SrcPath


:SrcPath
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                               Path to Source Image
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Current Path to the source Image is : %SRC_PATH%
ECHO.  Do you wish to change it ?
ECHO.
ECHO.  [Y] Yes
ECHO.  [N] No
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c ynqs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 GOTO SrcPathSet
IF %ERRORLEVEL%==2 GOTO SrcPathCheck
IF %ERRORLEVEL%==3 EXIT
GOTO Home


:SrcPathSet
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                               Path to Source Image
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Please enter the path to the source image.
ECHO.  Paths containing spaces are supported, quotes are removed automatically.
ECHO.
SET "c="
SET /P "c=  Path : "
IF DEFINED c SET "c=%c:"=%"
IF DEFINED c SET "SRC_PATH=%c%"
GOTO SrcPathCheck


:SrcPathCheck
IF NOT EXIST "%SRC_PATH%" (
ECHO.
ECHO.  The source image "%SRC_PATH%" does not exist. Please enter a valid path.
ECHO.
PAUSE
GOTO SrcPathSet
)
GOTO DstPath


:DstPath
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                             Path to Destination Image
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Current Path to the destination Image is : %DST_PATH%
ECHO.  Do you wish to change it ?
ECHO.
ECHO.  [Y] Yes
ECHO.  [N] No
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c ynqs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 GOTO DstPathSet
IF %ERRORLEVEL%==2 GOTO CompressType
IF %ERRORLEVEL%==3 EXIT
GOTO Home


:DstPathSet
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                             Path to Destination Image
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Please enter the path to the destination image.
ECHO.  Paths containing spaces are supported, quotes are removed automatically.
ECHO.
SET "c="
SET /P "c=  Path : "
IF DEFINED c SET "c=%c:"=%"
IF DEFINED c SET "DST_PATH=%c%"
GOTO CompressType


:CompressType
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                                   Compress Type
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Current Compression Type is : %COMPRESS_TYPE%
ECHO.  Do you wish to change it ?
ECHO.
ECHO.  [Y] Yes
ECHO.  [N] No
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c ynqs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 GOTO CompressTypeSet
IF %ERRORLEVEL%==2 GOTO IndexAnalyzer
IF %ERRORLEVEL%==3 EXIT
GOTO Home


:CompressTypeSet
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                                   Compress Type
ECHO.                           ================================================================
ECHO.
ECHO.
ECHO.  Please enter the compression type.
ECHO.
ECHO.  Available Compression Types :
ECHO.
ECHO.  [1] None :  No Compression (Fastest) [Destination Image bigger than Source Image]
ECHO.
ECHO.  [2] Fast :  Low Compression (Fast) [Destination Image 'may' be bigger than Source Image]
ECHO.
ECHO.  [3] Maximum :  Very High Compression (Slow) [Recommended maximum for WIM Images]
ECHO.
ECHO.  [4] Recovery :  Insane Compression (Slowest) [ESD format - only use for ESD Images]
ECHO.
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c 1234qs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 SET "COMPRESS_TYPE=None"
IF %ERRORLEVEL%==2 SET "COMPRESS_TYPE=Fast"
IF %ERRORLEVEL%==3 SET "COMPRESS_TYPE=Maximum"
IF %ERRORLEVEL%==4 SET "COMPRESS_TYPE=Recovery"
IF %ERRORLEVEL%==5 EXIT
IF %ERRORLEVEL%==6 GOTO Home
GOTO IndexAnalyzer


:IndexAnalyzer
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                               Analyzing %SRCtype% . . .
ECHO.                           ================================================================
ECHO.
SET "images="
"%DISM_EXE%" /English /Get-WimInfo /WimFile:"%SRC_PATH%" > "%temp%\SimpleWimEsd_WimInfo.txt" 2>&1
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
FOR /F "tokens=2 delims=: " %%A IN ('findstr /B /C:"Index" "%temp%\SimpleWimEsd_WimInfo.txt"') DO SET "images=%%A"
DEL "%temp%\SimpleWimEsd_WimInfo.txt" >NUL 2>&1
IF NOT DEFINED images GOTO ERROR
FOR /L %%i IN (1, 1, %images%) DO CALL :GetIndexName %%i
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                           ================================================================
ECHO.
ECHO.         The %SRCtype% Image contains the following %images% indexes :
ECHO.
FOR /L %%i IN (1, 1, %images%) DO ECHO.  [%%i] !name%%i!
ECHO.
ECHO.                           ================================================================
ECHO.
ECHO.         What do you want to do ?
ECHO.
ECHO.  [1] Export a single Index
ECHO.  [2] Export all Indexes
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c 12qs /n /m "  Your choice :  "
IF %ERRORLEVEL%==1 GOTO ExportSingleIndex
IF %ERRORLEVEL%==2 GOTO ExportAllIndex
IF %ERRORLEVEL%==3 EXIT
GOTO Home


:GetIndexName
SET "name%1="
"%DISM_EXE%" /English /Get-WimInfo /WimFile:"%SRC_PATH%" /Index:%1 > "%temp%\SimpleWimEsd_IndexInfo.txt" 2>&1
FOR /F "tokens=1* delims=: " %%A IN ('findstr /B /C:"Name" "%temp%\SimpleWimEsd_IndexInfo.txt"') DO SET "name%1=%%B"
DEL "%temp%\SimpleWimEsd_IndexInfo.txt" >NUL 2>&1
GOTO :eof


:DelDstPath
IF EXIST "%DST_PATH%" DEL /F "%DST_PATH%"
GOTO :eof


:ExportSingleIndex
CLS
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                                Export Single Index
ECHO.                           ================================================================
ECHO.
ECHO.     Please enter the Index number you want to export.
ECHO.
ECHO.     Here are the Indexes :
ECHO.
FOR /L %%i IN (1, 1, %images%) DO ECHO.  [%%i] !name%%i!
ECHO.
ECHO.
SET "INDEXCHOICE="
SET /P "INDEXCHOICE=     Your choice :  "
ECHO(!INDEXCHOICE!|findstr /R "^[1-9][0-9]*$" >NUL || GOTO ExportSingleIndex
IF !INDEXCHOICE! GTR %images% GOTO ExportSingleIndex
CLS
TITLE Simple WIM2ESD / ESD2WIM Converter - %SRCtype%2%DSTtype% - Exporting Index %INDEXCHOICE% . . .
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                                Export Single Index
ECHO.                                             Exporting Index %INDEXCHOICE% . . .
ECHO.                           ================================================================
ECHO.
ECHO.     PLEASE NOTE :
ECHO.     This operation may take a few minutes to complete depending on your PC Hardware.
ECHO.     This operation will use a lot of CPU and Memory resources.
ECHO.     Your system may be hotter or may seem unresponsive while processing your request.
ECHO.     Please do not interfere with the process before it has ended.
ECHO.
ECHO.
CALL :DelDstPath
"%DISM_EXE%" /Export-Image /SourceImageFile:"%SRC_PATH%" /SourceIndex:%INDEXCHOICE% /DestinationImageFile:"%DST_PATH%" /Compress:%COMPRESS_TYPE% /CheckIntegrity
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
GOTO SUCCESS


:ExportAllIndex
CALL :DelDstPath
FOR /L %%i IN (1, 1, %images%) DO (
CALL :ExportOneIndex %%i
IF !ERRORLEVEL! NEQ 0 GOTO ERROR
)
GOTO SUCCESS


:ExportOneIndex
CLS
TITLE Simple WIM2ESD / ESD2WIM Converter - %SRCtype%2%DSTtype% - Exporting Index %1 / %images% . . .
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                 %SRCtype% --^> %DSTtype%
ECHO.                                                Exporting All Indexes
ECHO.                                            Exporting Index %1 of %images% . . .
ECHO.                           ================================================================
ECHO.
ECHO.     PLEASE NOTE :
ECHO.     This operation may take a few minutes to complete depending on your PC Hardware.
ECHO.     This operation will use a lot of CPU and Memory resources.
ECHO.     Your system may be hotter or may seem unresponsive while processing your request.
ECHO.     Please do not interfere with the process before it has ended.
ECHO.
ECHO.
"%DISM_EXE%" /Export-Image /SourceImageFile:"%SRC_PATH%" /SourceIndex:%1 /DestinationImageFile:"%DST_PATH%" /Compress:%COMPRESS_TYPE% /CheckIntegrity
GOTO :eof


:SUCCESS
CLS
COLOR 17
TITLE Simple WIM2ESD / ESD2WIM Converter - By Joel Didier (Studisys)
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                      Success
ECHO.                           ================================================================
ECHO.
ECHO.  Successfully performed requested tasks.
ECHO.
ECHO.  Thanks for using my script.
ECHO.  GitHub Page : https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter/
ECHO.  Version : 0.6.0-beta
ECHO.  Original Author : Joel Didier (Studisys)
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c qs /n /m ""
IF %ERRORLEVEL%==1 EXIT
GOTO Home


:ERROR
COLOR 17
TITLE Simple WIM2ESD / ESD2WIM Converter - By Joel Didier (Studisys)
ECHO.
ECHO.                           ================================================================
ECHO.                                          Simple WIM2ESD / ESD2WIM Converter
ECHO.                                                       Error
ECHO.                           ================================================================
ECHO.
ECHO.  Something wrong occured . . .
ECHO.
ECHO.  Please check the error given by DISM above and the log located in :
ECHO.  %SYSTEMROOT%\Logs\DISM\dism.log
ECHO.
ECHO.  If the problem persists, please open an issue on :
ECHO.  https://github.com/dmatrix68-boop/Simple-WIM2ESD---ESD2WIM-Converter/issues
ECHO.
ECHO.                           ================================================================
ECHO.                                        Press 'Q' to exit, 'S' to start over
ECHO.                           ================================================================
ECHO.
CHOICE /c qs /n /m ""
IF %ERRORLEVEL%==1 EXIT
GOTO Home
