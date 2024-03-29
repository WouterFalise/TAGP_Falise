:: This batch file handles managing an Erlang node as a Windows service.
::
:: Commands provided:
::
:: * install - install the release as a Windows service
:: * start - start the service and Erlang node
:: * stop - stop the service and Erlang node
:: * restart - run the stop command and start command
:: * uninstall - uninstall the service and kill a running node
:: * ping - check if the node is running
:: * console - start the Erlang release in a `werl` Windows shell
:: * attach - connect to a running node and open an interactive console
:: * remote_console - alias for attach
:: * list - display a listing of installed Erlang services
:: * usage - display available commands

:: Set variables that describe the release
@set rel_name=faliseProject
@set rel_vsn=0.1.0
@set erts_vsn=10.1
@set erl_opts=

:: Discover the release root directory from the directory
:: of this script
@set script_dir=%~dp0
@for %%A in ("%script_dir%\..") do @(
  set release_root_dir=%%~fA
)
@set "rel_dir=%release_root_dir%\releases\%rel_vsn%"

@call :find_erts_dir
@call :find_sys_config
@call :set_boot_script_var

@set service_name=%rel_name%_%rel_vsn%
@set bindir=%erts_dir%\bin
@set vm_args=%rel_dir%\vm.args
@set progname=erl.exe
@set clean_boot_script=%release_root_dir%\bin\start_clean
@set erlsrv="%bindir%\erlsrv.exe"
@set epmd="%bindir%\epmd.exe"
@set escript="%bindir%\escript.exe"
@set werl="%bindir%\werl.exe"
@set nodetool="%release_root_dir%\bin\nodetool"

:: Extract node type and name from vm.args
@for /f "usebackq tokens=1-2" %%I in (`findstr /b "\-name \-sname" "%vm_args%"`) do @(
  set node_type=%%I
  set node_name=%%J
)

@for /f "delims=@ tokens=1-2" %%I in ("%node_name%") do @(
    set node_name=%%I
    set hostname=%%J
)

:: if no hostname is set, attempt to pick one from the env
@if "" == "%hostname%" @(
    if "-sname" == "%node_type%" (
        if not "" == "%COMPUTERNAME%" (
            set "hostname=%COMPUTERNAME%"
        )
    ) else (
        if not "" == "%COMPUTERNAME%" (
            if not "" == "%USERDNSDOMAIN%" (
                set "hostname=%COMPUTERNAME%.%USERDNSDOMAIN%"
            )
        )
    )
)
:: Add @ to hostname if not empty so that we can just concatenate values safely
@if not "" == "%hostname%" @(
    set "hostname=@%hostname%"
)

:: Extract cookie from vm.args
@for /f "usebackq tokens=1-2" %%I in (`findstr /b \-setcookie "%vm_args%"`) do @(
  set cookie=%%J
)

:: Write the erl.ini file to set up paths relative to this script
@call :write_ini

:: Collect any additional VM args into erl_opts
@setlocal EnableDelayedExpansion
@for /f "usebackq tokens=1-2" %%I in (`findstr /r "^[^#]" "%vm_args%"`) do @(
  if not "%%I" == "-name" (
    if not "%%I" == "-sname" (
      if not "%%I" == "-setcookie" (
        set erl_opts=!erl_opts! %%I %%J
      )
    )
  )
)
@endlocal && set erl_opts=%erl_opts%

:: If a start.boot file is not present, copy one from the named .boot file
@if not exist "%rel_dir%\start.boot" (
  copy "%rel_dir%\%rel_name%.boot" "%rel_dir%\start.boot" >nul
)

@if "%1"=="install" @goto install
@if "%1"=="uninstall" @goto uninstall
@if "%1"=="start" @goto start
@if "%1"=="stop" @goto stop
@if "%1"=="restart" @call :stop && @goto start
@if "%1"=="upgrade" @goto relup
@if "%1"=="downgrade" @goto relup
@if "%1"=="console" @goto console
@if "%1"=="ping" @goto ping
@if "%1"=="list" @goto list
@if "%1"=="attach" @goto attach
@if "%1"=="remote_console" @goto attach
@if "%1"=="" @goto usage
@echo Unknown command: "%1"

@goto :eof

:: Find the ERTS dir
:find_erts_dir
@set "possible_erts_dir=%release_root_dir%\erts-%erts_vsn%"
@if exist "%possible_erts_dir%" (
  call :set_erts_dir_from_default
) else (
  call :set_erts_dir_from_erl
)
@goto :eof

:: Set the ERTS dir from the passed in erts_vsn
:set_erts_dir_from_default
@set "erts_dir=%possible_erts_dir%"
@set "rootdir=%release_root_dir%"
@goto :eof

:: Set the ERTS dir from erl
:set_erts_dir_from_erl
@for /f "delims=" %%i in ('where erl') do @(
  set erl=%%i
)
@set dir_cmd="%erl%" -boot no_dot_erlang -noshell -eval "io:format(\"~s\", [filename:nativename(code:root_dir())])." -s init stop
@for /f "delims=" %%i in ('%%dir_cmd%%') do @(
  set erl_root=%%i
)
@set "erts_dir=%erl_root%\erts-%erts_vsn%"
@set "rootdir=%erl_root%"
@goto :eof

:: Find the sys.config file
:find_sys_config
@set "possible_sys=%rel_dir%\sys.config"
@if exist %possible_sys% (
  set sys_config=-config "%possible_sys%"
)
@goto :eof

:: set boot_script variable
:set_boot_script_var
@if exist "%rel_dir%\%rel_name%.boot" (
  set "boot_script=%rel_dir%\%rel_name%"
) else (
  set "boot_script=%rel_dir%\start"
)
@goto :eof

:: Write the erl.ini file
:write_ini
@set erl_ini=%erts_dir%\bin\erl.ini
@set converted_bindir=%bindir:\=\\%
@set converted_rootdir=%rootdir:\=\\%
@echo [erlang] > "%erl_ini%"
@echo Bindir=%converted_bindir% >> "%erl_ini%"
@echo Progname=%progname% >> "%erl_ini%"
@echo Rootdir=%converted_rootdir% >> "%erl_ini%"
@goto :eof

:: Display usage information
:usage
@echo usage: %~n0 ^(install^|uninstall^|start^|stop^|restart^|upgrade^|downgrade^|console^|ping^|list^|attach^|remote_console^)
@goto :eof

:: Install the release as a Windows service
:: or install the specified version passed as argument
:install
set args=%erl_opts% -setcookie %cookie% ++ -rootdir \"%rootdir%\"
set start_erl=%erts_dir%\bin\start_erl.exe
set description=Erlang node %node_name%%hostname% in %rootdir%
@if "" == "%2" (
  :: Install the service
  %erlsrv% add %service_name% %node_type% "%node_name%%hostname%" -c "%description%" -w "%rootdir%" -m "%start_erl%" -args "%args%" -stopaction "init:stop()."
) else (
  :: relup and reldown
  goto relup
)
@goto :eof

:: Uninstall the Windows service
:uninstall
@%erlsrv% remove %service_name%
@%epmd% -kill
@goto :eof

:: Start the Windows service
:start
@%erlsrv% start %service_name%
@goto :eof

:: Stop the Windows service
:stop
@%erlsrv% stop %service_name%
@goto :eof

:: Relup and reldown
:relup
@if "" == "%2" (
  echo Missing version argument
  echo Usage: %rel_name% %1 {version}
  set ERRORLEVEL=1
  exit /b %ERRORLEVEL%
)
@%escript% "%rootdir%/bin/install_upgrade.escript" "install" "{'%rel_name%', \"%node_type%\", '%node_name%%hostname%', '%cookie%'}" "%2" "%3"
@goto :eof

:: Start a console
:console
@set boot=-boot "%boot_script%" -boot_var RELEASE_DIR "%release_root_dir%"
@start "%rel_name% console" %werl% %boot% %sys_config%  ^
       -args_file "%vm_args%"
@goto :eof

:: Ping the running node
:ping
@%escript% %nodetool% ping %node_type% "%node_name%%hostname%" -setcookie "%cookie%"
@goto :eof

:: List installed Erlang services
:list
@%erlsrv% list %service_name%
@goto :eof

:: Attach to a running node
:attach
@set boot=-boot "%clean_boot_script%" -boot_var RELEASE_DIR "%release_root_dir%"
@start "%node_name% attach" %werl% %boot% ^
       -remsh %node_name%%hostname% %node_type% console -setcookie %cookie%
@goto :eof
