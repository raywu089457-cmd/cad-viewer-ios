@echo off
set SW=C:\Users\ray\AppData\Local\Programs\Swift
set PATH=%SW%\Toolchains\6.4.3+Asserts\usr\bin;%SW%\Runtimes\6.4.3\usr\bin;%PATH%
set P=%TEMP%\wasmsdk\swift-6.4.3-RELEASE_wasm.artifactbundle\swift-6.4.3-RELEASE_wasm\wasm32-unknown-wasip1
set FLAGS=-target wasm32-unknown-wasip1 -sdk %P%\WASI.sdk -resource-dir %P%\swift.xctoolchain\usr\lib\swift_static -static
node "%~dp0mkfiles.js"
cd /d "%~dp0"
swiftc.exe %FLAGS% -O -o scenecheck.wasm @files-exe.txt > buildlog-tool.txt 2>&1
echo TOOL_RC=%ERRORLEVEL% >> buildlog-tool.txt
swiftc.exe %FLAGS% -O -o verify.wasm @files-verify.txt > buildlog-verify.txt 2>&1
echo VERIFY_RC=%ERRORLEVEL% >> buildlog-verify.txt
