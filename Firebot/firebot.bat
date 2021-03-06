@echo off

set FIREBOTRUNDIR=%CD%

set repo=%~f1
set smvrepo=%repo%\smv
set fdsrepo=%repo%\fds
set botrepo=%repo%\bot

set clean=%2
set update=%3
set altemail=%4
set usematlab=%5
set installed=%6
set lite=%7
set emailto=%8

set botbranch=master
set fdsbranch=master
set smvbranch=master

set abort=0
if NOT exist %smvrepo% (
  echo ***Error: the repository %smvrepo% does not exist
  set abort=1
)

if NOT exist %fdsrepo% (
  echo ***Error: the repository %fdsrepo% does not exist
  set abort=1
)

if %abort% == 1 (
   echo firebot aborted
   exit /b
)

call :cd_repo %smvrepo% %botbranch%  || exit /b 1
call :cd_repo %fdsrepo% %fdsbranch%  || exit /b 1
call :cd_repo %botrepo% %smvbranch%  || exit /b 1
cd %FIREBOTRUNDIR%

echo.
echo Settings
echo --------
echo     fds repo: %fdsrepo%
echo     smv repo: %smvrepo%
echo      run dir: %FIREBOTRUNDIR%
if %clean% == 1 (
echo  clean repos: yes
) else (
echo  clean repos: no
)
if %update% == 1 (
echo update repos: yes
) else (
echo update repos: no
)
echo.

:: -------------------------------------------------------------
::                         set environment
:: -------------------------------------------------------------

:: set number of OpenMP threads

set OMP_NUM_THREADS=1

:: -------------------------------------------------------------
::                         setup environment
:: -------------------------------------------------------------

if not exist output mkdir output
if not exist history mkdir history
if not exist timings mkdir timings

set OUTDIR=%FIREBOTRUNDIR%\output
set HISTORYDIR=%FIREBOTRUNDIR%\history
set TIMINGSDIR=%FIREBOTRUNDIR%\timings

erase %OUTDIR%\*.txt %OUTDIR%\*.log 1> Nul 2>&1

set email=%botrepo%\Scripts\email.bat

set emailaltsetup=%userprofile%\bin\setup_gmail.bat
if "%altemail%" == "1" (
  if exist %emailaltsetup% (
     call %emailaltsetup%  
  )
)

set errorlog=%OUTDIR%\firebot_errors.txt
set timefile=%OUTDIR%\time.txt
set datefile=%OUTDIR%\date.txt
set waitfile=%OUTDIR%\wait.txt
set warninglog=%OUTDIR%\firebot_warnings.txt
set errorwarninglog=%OUTDIR%\firebot_errorswarnings.txt
set infofile=%OUTDIR%\firebot_info.txt
set revisionfilestring=%OUTDIR%\revision_string.txt
set stagestatus=%OUTDIR%\firebot_status.log
set counta=%OUTDIR%\firebot_count0a.txt
set countb=%OUTDIR%\firebot_count0b.txt
set scratchfile=%OUTDIR%\firebot_scratch.txt
set have_matlab=0

set fromsummarydir=%smvrepo%\Manuals\SMV_Summary

set haveerrors=0
set havewarnings=0
set have_icc=1

set emailexe=%userprofile%\bin\mailsend.exe
set gettimeexe=%userprofile%\FIRE-LOCAL\repo_exes\get_time.exe

call :get_datetime startdate starttime

call "%fdsrepo%\Utilities\Scripts\setup_intel_compilers.bat" 1> Nul 2>&1
call %botrepo%\Firebot\firebot_email_list.bat

set mailToList=%mailToFDS%
if NOT "%emailto%" == "" (
  set mailToList=%emailto%
)

:: -------------------------------------------------------------
::                           stage 0
:: -------------------------------------------------------------

echo  Status
echo  ------

echo. > %errorlog%
echo. > %warninglog%
echo. > %stagestatus%

call :is_file_installed %gettimeexe%|| exit /b 1
echo    found get_time

call :GET_TIME TIME_beg
call :GET_TIME PRELIM_beg

:: looking for Fortran
ifort 1> %scratchfile% 2>&1
type %scratchfile% | find /i /c "not recognized" > %counta%
set /p nothave_ifort=<%counta%
set have_ifort=1
if %nothave_ifort% == 1 (
  echo    Fortran not found
  echo "           firebot aborted"
  echo "***Fatal error: Fortran compiler not present" > %errorlog%
  call :output_abort_message
  exit /b 1
)
echo    found Fortran

:: if -installed option is used use installed smokeview
::    otherwise look for C to build smokeview and
::    use installed smokeview if C not found
if %installed% == 1 goto else1
icl 1> %scratchfile% 2>&1
type %scratchfile% | find /i /c "not recognized" > %countb%
set /p nothave_icc=<%countb%
if %nothave_icc% == 1 (
  set have_icc=0
  echo    C compiler not found - looking for Smokeview
  call :is_file_installed smokeview|| exit /b 1
  set smokeview=smokeview
  echo    found smokeview
) else (
  echo    found C
)
goto endif1
:else1
  set have_icc=0
  call :is_file_installed smokeview|| exit /b 1
  set smokeview=smokeview
  echo    found smokeview
:endif1

:: looking  for email
if NOT exist %emailexe% (
  echo ***Warning: email client not found.   
  echo    firebot messages will only be sent to the console.
) else (
  echo    found mailsend
)

call :is_file_installed background|| exit /b 1
echo    found background

call :is_file_installed cut|| exit /b 1
echo    found cut

call :is_file_installed git|| exit /b 1
echo    found git

call :is_file_installed grep|| exit /b 1
echo    found grep

call :is_file_installed make|| exit /b 1
echo    found make

where matlab 2>&1 | find /i /c "Could not find" > %OUTDIR%\stage_count0a.txt
set /p nothavematlab=<%OUTDIR%\stage_count0a.txt
if %nothavematlab% == 0 (
  echo    found matlab
  set have_matlab=1
)
if %nothavematlab% == 1 (
  echo    matlab not found - VV and User guides will not be built
)

call :is_file_installed pdflatex|| exit /b 1
echo    found pdflatex

call :is_file_installed sed|| exit /b 1
echo    found sed

call :is_file_installed sh2bat||exit /b 1
echo    found sh2bat

echo. 1>> %OUTDIR%\stage0.txt 2>&1

:: cleaning repos
echo.
echo Settings
echo --------
if %clean% == 0 goto skip_clean1
   echo    Cleaning
   echo       fds
   call :git_clean %fdsrepo% || exit /b 1
   echo       smokeview
   call :git_clean %smvrepo% || exit /b 1
:skip_clean1

:: updating  repos

if %update% == 0 goto skip_update1
  echo    Updating
  echo       fds
  call :cd_repo %fdsrepo% %fdsbranch% || exit /b 1
  git fetch origin master 1>> %OUTDIR%\stage0.txt 2>&1
  git merge origin/master 1>> %OUTDIR%\stage0.txt 2>&1

  echo       smv
  call :cd_repo %smvrepo% %smvbranch% || exit /b 1
  git fetch origin master 1>> %OUTDIR%\stage0.txt 2>&1
  git merge origin/master 1>> %OUTDIR%\stage0.txt 2>&1
:skip_update1

cd %fdsrepo%
git describe --long --dirty > %revisionfilestring%
set /p revisionstring=<%revisionfilestring%

git log --abbrev-commit . | head -1 | gawk "{print $2}" > %revisionfilestring%
set /p revisionnum=<%revisionfilestring%

set errorlogpc=%HISTORYDIR%\errors_%revisionnum%.txt
set warninglogpc=%HISTORYDIR%\warnings_%revisionnum%.txt

set timingslogfile=%TIMINGSDIR%\timings_%revisionnum%.txt

:: -------------------------------------------------------------
::                           stage 1
:: -------------------------------------------------------------

echo  Building FDS

echo    debug

cd %fdsrepo%\Build\mpi_intel_win_64_db
erase *.obj *.mod *.exe *.pdb 1> Nul 2>&1
call make_fds bot 1> %OUTDIR%\makefdsd.log 2>&1
call :does_file_exist fds_mpi_win_64_db.exe %OUTDIR%\makefdsd.log|| exit /b 1
call :find_warnings "warning" %OUTDIR%\makefdsd.log "Stage 1b, FDS parallel debug compilation"

if %lite% == 1 goto skip_lite1

  echo    release

  cd %fdsrepo%\Build\mpi_intel_win_64
  erase *.obj *.mod *.exe *.pdb 1> Nul 2>&1
  call make_fds bot 1> %OUTDIR%\makefdsr.log 2>&1
  call :does_file_exist fds_mpi_win_64.exe %OUTDIR%\makefdsr.log|| exit /b 1
  call :find_warnings "warning" %OUTDIR%\makefdsr.log "Stage 1d, FDS parallel release compilation"
:skip_lite1

:: -------------------------------------------------------------
::                           stage 2
:: -------------------------------------------------------------

if %lite% == 1 goto skip_lite2
  if %installed% == 1 goto skip_build_cstuff
  if %have_icc% == 0 goto skip_build_cstuff
    echo  Building Smokeview

    echo    libs

    cd %smvrepo%\Build\LIBS\intel_win_64
    call makelibs bot 1>> %OUTDIR%\stage2a.txt 2>&1

    echo    debug

    cd %smvrepo%\Build\smokeview\intel_win_64
    erase *.obj *.mod *.exe smokeview_win_64_db.exe 1> Nul 2>&1
    call make_smv_db -r bot 1> %OUTDIR%\makesmvd.log 2>&1
    call :does_file_exist smokeview_win_64_db.exe %OUTDIR%\makesmvd.log|| exit /b 1
    call :find_warnings "warning" %OUTDIR%\makesmvd.log "Stage 2a, Smokeview debug compilation"

    echo    release

    cd %smvrepo%\Build\smokeview\intel_win_64
    erase *.obj *.mod smokeview_win_64.exe 1> Nul 2>&1
    call make_smv -r bot 1> %OUTDIR%\makesmvr.log 2>&1

    call :does_file_exist smokeview_win_64.exe %OUTDIR%\makesmvr.log|| aexit /b 1
    call :find_warnings "warning" %OUTDIR%\makesmvr.log "Stage 2b, Smokeview release compilation"
    set smokeview=%smvrepo%\Build\smokeview\intel_win_64\smokeview_win_64.exe
  :skip_build_cstuff

:: -------------------------------------------------------------
::                           stage 3
:: -------------------------------------------------------------

  echo  Building Utilities

  echo    fds2ascii
  cd %fdsrepo%\Utilities\fds2ascii\intel_win_64
  erase *.obj *.mod *.exe 1> Nul 2>&1
  call make_fds2ascii bot 1> %OUTDIR%\makefds2ascii.log 2>&1
  call :does_file_exist fds2ascii_win_64.exe %OUTDIR%\makefds2ascii.log|| exit /b 1
  call :find_warnings "warning" %OUTDIR%\makefds2ascii.log "Stage 3, Building FDS/Smokeview utilities"

  if %have_icc% == 1 (
    echo    background
    cd %smvrepo%\Build\background\intel_win_64
    erase *.obj *.mod *.exe 1> Nul 2>&1
    call make_background bot 1> %OUTDIR%\makebackground.log 2>&1
    call :does_file_exist background.exe %OUTDIR%\makebackground.log
    call :find_warnings "warning" %OUTDIR%\makebackground.log "Stage 3, Building FDS/Smokeview utilities"
  ) else (
    call :is_file_installed background|| exit /b 1
    echo    background not built, using installed version
  )
:skip_lite2

call :GET_DURATION PRELIM %PRELIM_beg%

:: -------------------------------------------------------------
::                           stage 4
:: -------------------------------------------------------------

call :GET_TIME RUNVV_beg

echo  Running verification cases
echo    debug mode

:: run cases

cd %fdsrepo%\Verification\scripts
call Run_FDS_cases -debug 1> %OUTDIR%\stage4a.txt 2>&1

:: check cases

set haveerrors_now=0
echo. > %OUTDIR%\stage_error.txt
cd %fdsrepo%\Verification\scripts
call Check_FDS_cases 

:: report errors

call :report_errors Stage 4a, "Debug FDS case errors"|| exit /b 1

if %lite% == 1 goto skip_lite3

  echo    release mode

:: run cases

  cd %fdsrepo%\Verification\
  if %clean% == 0 goto skip_clean2
     echo    cleaning Verification directory
     call :git_clean %fdsrepo%\Verification
:skip_clean2

  cd %fdsrepo%\Verification\scripts
  call Run_FDS_cases  1> %OUTDIR%\stage4b.txt 2>&1

:: check cases

  set haveerrors_now=0
  echo. > %OUTDIR%\stage_error.txt
  cd %fdsrepo%\Verification\scripts
  call Check_FDS_cases

:: report errors

  call :report_errors Stage 4b, "Release FDS case errors"|| exit /b 1
:skip_lite3

call :GET_DURATION RUNVV %RUNVV_beg%

if %lite% == 1 goto skip_lite4

:: -------------------------------------------------------------
::                           stage 5
:: -------------------------------------------------------------

  if exist %emailexe% (
    call :get_datetime current_ddate current_ttime

    echo "making pictures on %COMPUTERNAME% %revisionstring%" > %infofile%
    echo "  start time: %startdate% %starttime%" >> %infofile%
    echo "current time: %current_ddate% %current_ttime%" >> %infofile%
    call %email% %mailToFDSDebug% "making pictures on %COMPUTERNAME% %revisionstring%" %infofile%
  )
  call :GET_TIME MAKEPICS_beg

  echo  Making pictures
  echo    FDS verification cases

  cd %fdsrepo%\Verification\scripts
  call MAKE_FDS_pictures %smokeview% 1> %OUTDIR%\stage5.txt 2>&1

  if %have_matlab%==0 goto skip_matlabplots
    echo    matlab verification plots
    cd %fdsrepo%\Utilities\Matlab
    matlab -automation -wait -noFigureWindows -r "try; run('%fdsrepo%\Utilities\Matlab\FDS_verification_script.m'); catch; end; quit

    echo    matlab validation plots
    cd %fdsrepo%\Utilities\Matlab
    matlab -automation -wait -noFigureWindows -r "try; run('%fdsrepo%\Utilities\Matlab\FDS_validation_script.m'); catch; end; quit

    cd %fdsrepo%\Utilities\Scripts
    validation_git_stats

  :skip_matlabplots

  call :GET_DURATION MAKEPICS %MAKEPICS_beg%

:: -------------------------------------------------------------
::                           stage 6
:: -------------------------------------------------------------

  call :GET_TIME MAKEGUIDES_beg

  echo  Building guides

  echo    FDS Technical Reference
  call :build_guide FDS_Technical_Reference_Guide %fdsrepo%\Manuals\FDS_Technical_Reference_Guide 1> %OUTDIR%\stage6.txt 2>&1

  if have_matlab==0 goto skip_VV
    echo    FDS User
    call :build_guide FDS_User_Guide %fdsrepo%\Manuals\FDS_User_Guide 1>> %OUTDIR%\stage6.txt 2>&1

    echo    FDS Verification
    call :build_guide FDS_Verification_Guide %fdsrepo%\Manuals\FDS_Verification_Guide 1>> %OUTDIR%\stage6.txt 2>&1

    echo    FDS Validation
    call :build_guide FDS_Validation_Guide %fdsrepo%\Manuals\FDS_Validation_Guide 1>> %OUTDIR%\stage6.txt 2>&1
  :skip_VV  

  call :GET_DURATION MAKEGUIDES %MAKEGUIDES_beg%

:skip_lite4

call :GET_DURATION TOTALTIME %TIME_beg%

:: -------------------------------------------------------------
::                           wrap up
:: -------------------------------------------------------------

call :get_datetime stopdate stoptime

echo. > %infofile%
echo . -----------------------------         >> %infofile%
echo .         host: %COMPUTERNAME%          >> %infofile%
echo .        start: %startdate% %starttime% >> %infofile%
echo .         stop: %stopdate% %stoptime%   >> %infofile%
echo .        setup: %DIFF_PRELIM%           >> %infofile%
echo .    run cases: %DIFF_RUNVV%            >> %infofile%
if %lite% == 1 goto skip_lite5
echo .make pictures: %DIFF_MAKEPICS%         >> %infofile%
echo .  make guides: %DIFF_MAKEGUIDES%       >> %infofile%
:skip_lite5
echo .        total: %DIFF_TOTALTIME%        >> %infofile%
echo . -----------------------------         >> %infofile%

copy %infofile% %timingslogfile%

cd %FIREBOTRUNDIR%

sed "s/$/\r/" < %warninglog% > %warninglogpc%
sed "s/$/\r/" < %errorlog% > %errorlogpc%

if exist %emailexe% (
  if %havewarnings% == 0 (
    if %haveerrors% == 0 (
      call %email% %mailToList% "firebot success on %COMPUTERNAME%! %revisionstring%" %infofile%
    ) else (
      echo "start: %startdate% %starttime% " > %infofile%
      echo " stop: %stopdate% %stoptime% " >> %infofile%
      echo. >> %infofile%
      type %errorlogpc% >> %infofile%
      call %email% %mailToList% "firebot failure on %COMPUTERNAME%! %revisionstring%" %infofile%
    )
  ) else (
    if %haveerrors% == 0 (
      echo "start: %startdate% %starttime% " > %infofile%
      echo " stop: %stopdate% %stoptime% " >> %infofile%
      echo. >> %infofile%
      type %warninglogpc% >> %infofile%
      call %email% %mailToList% "firebot success with warnings on %COMPUTERNAME% %revisionstring%" %infofile%
    ) else (
      echo "start: %startdate% %starttime% " > %infofile%
      echo " stop: %stopdate% %stoptime% " >> %infofile%
      echo. >> %infofile%
      type %errorlogpc% >> %infofile%
      echo. >> %infofile%
      type %warninglogpc% >> %infofile%
      call %email% %mailToList% "firebot failure on %COMPUTERNAME%! %revisionstring%" %infofile%
    )
  )
)

echo firebot_win completed
goto :eof

:: -------------------------------------------------------------
:report_errors
:: -------------------------------------------------------------
set stage_label=%1
grep -v " " %OUTDIR%\stage_error.txt | wc -l > %OUTDIR%\stage_nerror.txt
set /p nerrors=<%OUTDIR%\stage_nerror.txt
if %nerrors% GTR 0 (
   echo %stage_label% >> %errorlog%
   echo. >> %errorlog%
   type %OUTDIR%\stage_error.txt >> %errorlog%
   set haveerrors=1
   set haveerrors_now=1
   call :output_abort_message
   exit /b 1
)
exit /b 0

:: -------------------------------------------------------------
:output_abort_message
:: -------------------------------------------------------------
   for %%a in (%errorlogpc%) do (
      set filename=%%~nxa
   )    

  echo ***Fatal error: firebot failure on %COMPUTERNAME% %revisionstring%, error log: %filename%
  sed "s/$/\r/" < %errorlog% > %errorlogpc%
  if exist %emailexe% (
    echo sending email to %mailToList%
    call %email% %mailToList% "firebot failure on %COMPUTERNAME% %revisionstring%" %errorlogpc%
  )
exit /b

:: -------------------------------------------------------------
:get_datetime
:: -------------------------------------------------------------

set arg1=%1
set arg2=%2

date /t > %datefile%
set /p %arg1%=<%datefile%

time /t > %timefile%
set /p %arg2%=<%timefile%

exit /b 0

:: -------------------------------------------------------------
:GET_DURATION
:: -------------------------------------------------------------

:: compute difftime=time2 - time1

set label=%1
set time1=%2

set difftime=DIFF_%label%
call :GET_TIME time2

set /a diff=%time2% - %time1%
set /a diff_h= %diff%/3600
set /a diff_m= (%diff% %% 3600 )/60
set /a diff_s= %diff% %% 60
if %diff% GEQ 3600 set duration= %diff_h%h %diff_m%m %diff_s%s
if %diff% LSS 3600 if %diff% GEQ 60 set duration= %diff_m%m %diff_s%s
if %diff% LSS 3600 if %diff% LSS 60 set duration= %diff_s%s
echo %label%: %duration% >> %stagestatus%
set %difftime%=%duration%
exit /b 0

:: -------------------------------------------------------------
:GET_TIME
:: -------------------------------------------------------------

set arg1=%1

%gettimeexe% > %timefile%
set /p %arg1%=<%timefile%
exit /b 0

:: -------------------------------------------------------------
:chk_repo
:: -------------------------------------------------------------

set repodir=%1

if NOT exist %repodir% (
  echo ***error: repo directory %repodir% does not exist
  echo  firebot aborted
  exit /b 1
)
exit /b 0

:: -------------------------------------------------------------
:cd_repo
:: -------------------------------------------------------------

set repodir=%1
set repobranch=%2

call :chk_repo %repodir% || exit /b 1

cd %repodir%
if "%repobranch%" == "" (
  exit /b 0
)
git rev-parse --abbrev-ref HEAD>current_branch.txt
set /p current_branch=<current_branch.txt
erase current_branch.txt
if "%repobranch%" NEQ "%current_branch%" (
  echo ***error: in repo %repodir% found branch %current_branch%
  echo            was expecting branch %repobranch%
  echo  firebot aborted
  exit /b 1
)
exit /b 0

:: -------------------------------------------------------------
:is_file_installed
:: -------------------------------------------------------------

  set program=%1
  %program% --help 1>> %OUTDIR%\stage_exist.txt 2>&1
  type %OUTDIR%\stage_exist.txt | find /i /c "not recognized" > %OUTDIR%\stage_count.txt
  set /p nothave=<%OUTDIR%\stage_count.txt
  if %nothave% == 1 (
    echo "***Fatal error: %program% not present"
    echo "***Fatal error: %program% not present" > %errorlog%
    echo "firebot run aborted"
    call :output_abort_message
    exit /b 1
  )
  exit /b 0

:: -------------------------------------------------------------
:does_file_exist
:: -------------------------------------------------------------

set file=%1
set outputfile=%2

if NOT exist %file% (
  echo ***Fatal error: problem building %file%. Aborting firebot
  echo ***Fatal error: problem building %file%. Aborting firebot >> %errorlog%
  type %outputfile% >> %errorlog%
  call :output_abort_message
  exit /b 1
)
exit /b 0

:: -------------------------------------------------------------
:find_warnings
:: -------------------------------------------------------------

set search_string=%1
set search_file=%2
set stage=%3

grep -v "commands for target" %search_file% > %OUTDIR%\stage_warning0.txt
grep -v "mpif.h" %OUTDIR%\stage_warning0.txt > %OUTDIR%\stage_warning1.txt
grep -i -A 5 -B 5 %search_string% %OUTDIR%\stage_warning1.txt > %OUTDIR%\stage_warning.txt
type %OUTDIR%\stage_warning.txt | find /v /c "  "> %OUTDIR%\stage_nwarning.txt
set /p nwarnings=<%OUTDIR%\stage_nwarning.txt
if %nwarnings% GTR 0 (
  echo %stage% warnings >> %warninglog%
  echo. >> %warninglog%
  type %OUTDIR%\stage_warning.txt >> %warninglog%
  set havewarnings=1
)
exit /b

:: -------------------------------------------------------------
:find_errors
:: -------------------------------------------------------------

set search_string=%1
set search_file=%2
set stage=%3

grep -v "commands for target" %search_file% > %OUTDIR%\stage_error0.txt
grep -v "mpif.h" %OUTDIR%\stage_error0.txt > %OUTDIR%\stage_error1.txt
grep -i -A 5 -B 5 %search_string% %OUTDIR%\stage_error1.txt > %OUTDIR%\stage_error.txt
type %OUTDIR%\stage_error.txt | find /v /c "  "> %OUTDIR%\stage_nerror.txt
set /p nerrors=<%OUTDIR%\stage_nerror.txt
if %nerrors% GTR 0 (
  echo %stage% errors >> %errorlog%
  echo. >> %errorlog%
  type %OUTDIR%\stage_error.txt >> %errorlog%
  set haveerrors=1
  set haveerrors_now=1
)
exit /b

:: -------------------------------------------------------------
 :git_clean
:: -------------------------------------------------------------

set gitcleandir=%1
call :cd_repo %gitcleandir%  || exit /b 1
git clean -dxf 1>> Nul 2>&1
git add . 1>> Nul 2>&1
git reset --hard HEAD 1>> Nul 2>&1
exit /b /0

:: -------------------------------------------------------------
:build_guide
:: -------------------------------------------------------------

set guide=%1
set guide_dir=%2

set guideout=%OUTDIR%\stage6_%guide%.txt

cd %guide_dir%

pdflatex -interaction nonstopmode %guide% 1> %guideout% 2>&1
bibtex %guide% 1> %guideout% 2>&1
pdflatex -interaction nonstopmode %guide% 1> %guideout% 2>&1
pdflatex -interaction nonstopmode %guide% 1> %guideout% 2>&1
bibtex %guide% 1>> %guideout% 2>&1

type %guideout% | find "Undefined control" > %OUTDIR%\stage_error.txt
type %guideout% | find "! LaTeX Error:" >> %OUTDIR%\stage_error.txt
type %guideout% | find "Fatal error" >> %OUTDIR%\stage_error.txt
type %guideout% | find "Error:" >> %OUTDIR%\stage_error.txt

type %OUTDIR%\stage_error.txt | find /v /c "  "> %OUTDIR%\stage_nerrors.txt
set /p nerrors=<%OUTDIR%\stage_nerrors.txt
if %nerrors% GTR 0 (
  echo Errors from Stage 6 - Build %guide% >> %errorlog%
  type %OUTDIR%\stage_error.txt >> %errorlog%
  set haveerrors=1
)

type %guideout% | find "undefined" > %OUTDIR%\stage_warning.txt
type %guideout% | find "multiply"  >> %OUTDIR%\stage_warning.txt

type %OUTDIR%\stage_warning.txt | find /c ":"> %OUTDIR%\nwarnings.txt
set /p nwarnings=<%OUTDIR%\nwarnings.txt
if %nwarnings% GTR 0 (
  echo Warnings from Stage 6 - Build %guide% >> %warninglog%
  type %OUTDIR%\stage_warning.txt >> %warninglog%
  set havewarnings=1
)
copy %guide%.pdf %fromsummarydir%\manuals

exit /b

:eof
cd %FIREBOTRUNDIR%
