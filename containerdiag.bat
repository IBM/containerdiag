:: /*******************************************************************************
::  * (c) Copyright IBM Corporation 2022.
::  *
::  * Licensed under the Apache License, Version 2.0 (the "License");
::  * you may not use this file except in compliance with the License.
::  * You may obtain a copy of the License at
::  *
::  *    https://www.apache.org/licenses/LICENSE-2.0
::  *
::  * Unless required by applicable law or agreed to in writing, software
::  * distributed under the License is distributed on an "AS IS" BASIS,
::  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
::  * See the License for the specific language governing permissions and
::  * limitations under the License.
::  *******************************************************************************/
:: 
:: Run specified COMMANDS on a specific pod or all pods of a deployment
:: For details, see https://www.ibm.com/support/pages/mustgather-performance-hang-or-high-cpu-issues-websphere-application-server-linux-containers

@echo off

SETLOCAL ENABLEDELAYEDEXPANSION

set "SCRIPTNAME=%~nx0"

goto :start

:usage
  echo usage: !SCRIPTNAME! [options] [-d DEPLOYMENT] [-p POD] COMMANDS...
  echo(
  echo(       -d DEPLOYMENT: Run COMMANDS on all pods in the specified DEPLOYMENT
  echo(       -i IMAGE: The image used for the debug pod (default quay.io/ibm/containerdiag)
  echo(       -k: By default, this script uses oc if available. This options forces the use of kubectl
  echo(       -n NAMESPACE: Namespace (optional; defaults to current namespace)
  echo(       -p POD: Run COMMANDS on the specified POD
  echo(       -q: Do not append the pod name to COMMANDS
  echo(       -v: verbose output to stderr
  echo(
  echo(       COMMANDS will be passed to oc debug node along with the pod name at the end
  echo(       (unless -q is specified in which case the pod name is not appended)
  exit /B 1

:printInfo
  echo [!date! !time!] !SCRIPTNAME!: %*
  goto :eof

:printVerbose
  echo [!date! !time!] !SCRIPTNAME!: %*
  goto :eof

:processPod
  if "!APPEND!" == "1" (
    call :printInfo Processing pod !TARGETPOD! on worker node !WORKER! with %* !TARGETPOD!
    !CTL! debug node/!WORKER! !CTL_DEBUG_FLAGS! --image=!IMAGE! -- %* !TARGETPOD!
  ) else (
    call :printInfo Processing pod !TARGETPOD! on worker node !WORKER! with %*
    !CTL! debug node/!WORKER! !CTL_DEBUG_FLAGS! --image=!IMAGE! -- %*
  )
  goto :eof

:start
  set "NAMESPACE="
  set "VERBOSE=0"
  set "APPEND=1"
  set "CTL=oc"
  set "CTL_DEBUG_FLAGS=-t"
  set "IMAGE=quay.io/ibm/containerdiag:latest"
  set "TARGETDEPLOYMENT="
  set "TARGETPOD="

set "I=0"
for %%x in (%*) do (
   set /A "I+=1"
   set "ARGS[!I!]=%%~x"
)

set /a "REMAININGINDEX=1"

set "KEEPGOING=1"
for /L %%J in (1,1,!I!) do (
  if "!KEEPGOING!" == "1" (
    if /i "!ARGS[%%J]!" == "/?" goto :usage
    if /i "!ARGS[%%J]!" == "-?" goto :usage
    if /i "!ARGS[%%J]!" == "-h" goto :usage
    if /i "!ARGS[%%J]!" == "--help" goto :usage

    set /a "K=%%J+1"
    if /i "!ARGS[%%J]!" == "/d" call set "TARGETDEPLOYMENT=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"
    if /i "!ARGS[%%J]!" == "-d" call set "TARGETDEPLOYMENT=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"

    if /i "!ARGS[%%J]!" == "/p" call set "TARGETPOD=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"
    if /i "!ARGS[%%J]!" == "-p" call set "TARGETPOD=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"

    if /i "!ARGS[%%J]!" == "/i" call set "IMAGE=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"
    if /i "!ARGS[%%J]!" == "-i" call set "IMAGE=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"

    if /i "!ARGS[%%J]!" == "/n" call set "NAMESPACE=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"
    if /i "!ARGS[%%J]!" == "-n" call set "NAMESPACE=%%ARGS[!K!]%%" & set /a "REMAININGINDEX+=2"

    if /i "!ARGS[%%J]!" == "/v" set "VERBOSE=1" & set /a "REMAININGINDEX+=1"
    if /i "!ARGS[%%J]!" == "-v" set "VERBOSE=1" & set /a "REMAININGINDEX+=1"

    if /i "!ARGS[%%J]!" == "/q" set "APPEND=0" & set /a "REMAININGINDEX+=1"
    if /i "!ARGS[%%J]!" == "-q" set "APPEND=0" & set /a "REMAININGINDEX+=1"

    if /i "!ARGS[%%J]!" == "/k" set "CTL=kubectl" & set "CTL_DEBUG_FLAGS=-it" & set /a "REMAININGINDEX+=1"
    if /i "!ARGS[%%J]!" == "-k" set "CTL=kubectl" & set "CTL_DEBUG_FLAGS=-it" & set /a "REMAININGINDEX+=1"

    if /i "!ARGS[%%J]!" == "--" set "KEEPGOING=0" & set /a "REMAININGINDEX+=1"
  )
)

where /q oc
if ERRORLEVEL 1 (
  where /q kubectl
  if ERRORLEVEL 1 (
    echo Could not find the command oc or kubectl on PATH
    goto :usage
  ) else (
    set "CTL=kubectl"
    set "CTL_DEBUG_FLAGS=-it"
  )
)

set "REMAININGARGS="
for /L %%J in (!REMAININGINDEX!,1,!I!) do (
  set "REMAININGARGS=!REMAININGARGS! !ARGS[%%J]!"
)

if "!TARGETDEPLOYMENT!" == "" (
  if "!TARGETPOD!" == "" (
    echo ERROR: Either -d DEPLOYMENT or -p POD must be specified
    goto :usage
  )
)

if "!REMAININGARGS!" == "" echo ERROR: Missing COMMANDS & goto :usage

call :printInfo Script started with !CTL! and !IMAGE!

if "!VERBOSE!" == "1" call :printVerbose Commands: !REMAININGARGS!

if "!NAMESPACE!" == "" (
  for /F "tokens=* USEBACKQ" %%x in (`!CTL! config view --minify --output "jsonpath={..namespace}"`) do set "NAMESPACE=%%x"
  if "!NAMESPACE!" == "" set "NAMESPACE=default"
)

if not "!TARGETDEPLOYMENT!" == "" (
  call :printInfo Querying available replicas for deployment !TARGETDEPLOYMENT! in namespace !NAMESPACE!

  for /F "tokens=* USEBACKQ" %%x in (`!CTL! get deployment !TARGETDEPLOYMENT! "--namespace=!NAMESPACE!" "--output=jsonpath={.status.availableReplicas}"`) do set "AVAILABLEREPLICAS=%%x"
  if "!AVAILABLEREPLICAS!" == "" (
    call :printInfo Error getting deployment information. Ensure you specify the right namespace with -n NAMESPACE
    exit /B 1
  )

  if "!AVAILABLEREPLICAS!" == "0" (
    call :printInfo There are 0 available replicas for this deployment
    exit /B 1
  )

  call :printInfo There are !AVAILABLEREPLICAS! available replicas

  call :printInfo Querying deployment selector label

  for /F "tokens=* USEBACKQ" %%x in (`!CTL! get --raw "/apis/apps/v1/namespaces/!NAMESPACE!/deployments/!TARGETDEPLOYMENT!/scale"`) do set "SELECTORRAW=%%x"
  if "!SELECTORRAW!" == "" (
    call :printInfo Error getting scale information. See previous output.
    exit /B 1
  )

  set "SELECTOR=!SELECTORRAW:*selector":"=!"
  for /f delims^=^"^ tokens^=1 %%a in ("!SELECTOR!") do set "SELECTOR=%%a"
  if "!SELECTOR!" == "" (
    call :printInfo Error getting scale selector from !SELECTORRAW!
    exit /B 1
  )

  call :printInfo Selector labels are !SELECTOR!

  call :printInfo Getting pods by selector

  for /F "tokens=* USEBACKQ" %%x in (`!CTL! get pods --namespace !NAMESPACE! --selector !SELECTOR! --output "jsonpath={range .items[*]}{.metadata.name}{' '}{.spec.nodeName}{'\n'}{end}"`) do (
    call :printInfo Found pod: %%x
    set "TARGETPOD="
    set "WORKER="
    for /F "tokens=1,2 delims= " %%y in ("%%x") do (
      set "TARGETPOD=%%y"
      set "WORKER=%%z"
    )

    if "!TARGETPOD!" == "" (
      call :printInfo Could not find pod name from %%x
      exit /B 1
    )

    if "!WORKER!" == "" (
      call :printInfo Could not find worker from %%x
      exit /B 1
    )

    call :processPod !REMAININGARGS!
  )

) else (
  if not "!TARGETPOD!" == "" (
    call :printInfo Querying worker node for pod !TARGETPOD! in namespace !NAMESPACE!

    for /F "tokens=* USEBACKQ" %%x in (`!CTL! get pod !TARGETPOD! --namespace !NAMESPACE! --output "jsonpath={.spec.nodeName}"`) do set "WORKER=%%x"
    
    if "!WORKER!" == "" (
      call :printInfo Error getting pod information. See previous output. Ensure you specify the right namespace with -n NAMESPACE
      exit /B 1
    )

    call :processPod !REMAININGARGS!
  )
)

call :printInfo Finished
