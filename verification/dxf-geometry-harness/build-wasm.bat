@echo off
REM Builds the harnesses for wasm32-wasip1, for a machine without an Apple SDK.
REM
REM Needs the Swift 6.4.3 Windows toolchain and the "Swift SDK for WebAssembly" unpacked,
REM plus a local checkout of SwiftDXF (the SPM dependency cannot be fetched for wasm here,
REM so its sources are compiled in directly).
REM
REM   git clone https://github.com/SecondMouseAU/SwiftDXF.git ..\..\SwiftDXF
REM
REM On a Mac, run.sh is the simpler path.
setlocal
set SW=C:\Users\ray\AppData\Local\Programs\Swift
set PATH=%SW%\Toolchains\6.4.3+Asserts\usr\bin;%SW%\Runtimes\6.4.3\usr\bin;%PATH%
set SDK=%TEMP%\wasmsdk\swift-6.4.3-RELEASE_wasm.artifactbundle\swift-6.4.3-RELEASE_wasm\wasm32-unknown-wasip1
if not exist "%SDK%" (
  echo wasm SDK not found at %SDK%
  exit /b 1
)
set FLAGS=-target wasm32-unknown-wasip1 -sdk %SDK%\WASI.sdk -resource-dir %SDK%\swift.xctoolchain\usr\lib\swift_static -static

cd /d "%~dp0"
where node >nul 2>nul || (echo node is required & exit /b 1)
node mkfiles.js || exit /b 1
if exist scenecheck.wasm del scenecheck.wasm
if exist verify.wasm del verify.wasm

swiftc.exe %FLAGS% -O -o scenecheck.wasm @files-exe.txt > buildlog-tool.txt 2>&1
set TOOL_RC=%ERRORLEVEL%
echo TOOL_RC=%TOOL_RC% >> buildlog-tool.txt

swiftc.exe %FLAGS% -O -o verify.wasm @files-verify.txt > buildlog-verify.txt 2>&1
set VERIFY_RC=%ERRORLEVEL%
echo VERIFY_RC=%VERIFY_RC% >> buildlog-verify.txt

REM A stale wasm from an earlier build looks exactly like a fresh one, so a failure here
REM must stop the script rather than leave something runnable behind.
if not "%TOOL_RC%"=="0" (
  echo scenecheck failed to compile, see buildlog-tool.txt
  exit /b 1
)
if not "%VERIFY_RC%"=="0" (
  echo verify failed to compile, see buildlog-verify.txt
  exit /b 1
)
echo built scenecheck.wasm and verify.wasm
