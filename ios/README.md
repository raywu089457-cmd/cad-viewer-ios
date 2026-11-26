# CAD Viewer（iOS）

一個 App，三條路徑，按檔案類型自動分工：

| 副檔名 | 引擎 | 理由 |
|---|---|---|
| `.dxf` | **SwiftDXF + SwiftUI Canvas**（原生） | 純 Swift、MIT、零依賴，手勢與縮放全部原生 |
| `.dwg` | **WKWebView + LibreDWG wasm**（內嵌網頁） | DWG 沒有可用的開源原生解析器，這是實測唯一能正確開圖的路 |
| `.pdf` | **PDFKit**（系統框架） | 系統已經是完整的 PDF 引擎，自己畫只會更差 |

## 目錄

```
ios/
├── DXFGeometry/         # 幾何核心：攤平、取景、座標變換（純 Swift，可測）
├── CADViewer/           # SwiftUI + WebKit 應用層
├── web/                 # DWG 網頁檢視器（Vite + @mlightcad）
└── project.yml          # XcodeGen 設定，產生 .xcodeproj
```

`SwiftDXF` 是 SPM 依賴（`from: "0.6.0"`），沒有把上游原始碼放進這個 repo。

`DXFGeometry` 刻意不依賴 UIKit / CoreGraphics / SwiftUI，因為只有它能被完整測試；
SwiftUI、WebKit 與 PDFKit 那幾層只能在真機或模擬器上驗證。

## 建置

```bash
# 1. 產生 DWG 檢視器的網頁產物（只需在 web/ 有改動時重跑）
./web/build-for-ios.sh

# 2. 產生 Xcode 專案
brew install xcodegen && xcodegen generate

# 3. 開啟
open CADViewer.xcodeproj
```

`web/build-for-ios.sh` 會把建置結果複製到
`CADViewer/Sources/CADViewer/Resources/dwgviewer`，SwiftPM 的
`.copy("Resources/dwgviewer")` 再把它塞進 App bundle。

## 兩個引擎怎麼接

### DXF：原生，不經過網頁

`SwiftDXF` 讀檔後是一個語意模型（`SPLINE` 是控制點、`HATCH` 是邊界、
`LWPOLYLINE` 帶 bulge）。`DXFGeometry.SceneBuilder` 把它攤平成折線加文字：

- 弧、圓、橢圓、bulge、NURBS spline 都依弦高容差細分成折線
- ACI 色票還原成 RGB，ByLayer 由圖層表解出
- 尺寸（DIMENSION）依定義點重建延伸線與尺寸線，數值畫在文字位置

`DrawingCanvas` 用 `Canvas` 逐條畫，並在每次繪製前用
`ViewTransform.isVisible` 剔除畫面外的圖元 —— 放大看細節時這是能否流暢的關鍵。

### DWG：WKWebView，但用自訂 scheme

不能直接用 `file://`：`fetch`、Web Worker、`WebAssembly.instantiateStreaming`
在上面都受限，LibreDWG 的 wasm 因此載不起來。`ViewerSchemeHandler` 用
`WKURLSchemeHandler` 把 bundle 裡的檔案用 `cadviewer://` 提供，於是網頁有正常的
origin，wasm 與 worker 照常運作。

MIME type 必須正確（`application/wasm`、`text/javascript`），否則 WebKit
會拒絕串流編譯。

原生只負責三件事：把 DWG 位元組交給頁面（透過 `/__dwg__` 端點）、顯示進度、
轉發錯誤。格式知識全部留在網頁端。

## 已驗證的範圍

- `DXFGeometry`：圖元攤平、色票、取景、縮放/平移算式、副檔名路由、錯誤訊息、
  bundle 路徑逃逸與 MIME type。CI 跑 `swift test`，本機跑 wasm harness。
- 真實樣本（LibreDWG 的測試圖紙）：`samples/example_r12.dxf` 切成十段都得到結果，
  `samples/` 三張 DWG 都在真實瀏覽器裡開過一次。數字以 harness 與 CI 的輸出為準，
  不寫在文件裡——寫死的數字會過時，而且讀者無法複查。
- DWG 網頁檢視器在 WebKit（Safari 引擎）手機尺寸下正常開圖，零 console 錯誤
- SwiftUI / WebKit / PDFKit 層的**型別檢查**：靠 `verification/stubs/` 的平台 stub，
  用真正的 `swiftc -typecheck`。它抓到過 5 個只靠 `-parse` 看不到的真缺陷。

尚未在真機驗證的（需要 macOS）：

- 手勢手感，以及 `WKURLSchemeHandler` 在 iOS 上的實際載入
- stub 的 `body` 從不執行，所以型別檢查證明能編譯，不證明畫面正確

## 授權

| 元件 | 授權 | 注意 |
|---|---|---|
| SwiftDXF | MIT | 可商用 |
| DXFGeometry / CADViewer | 你的 | — |
| @mlightcad/* | MIT | — |
| LibreDWG（wasm） | **GPL-3.0** | 閉源上架需換成 ODA Drawings SDK |

DWG 這條路徑的最終授權問題不在程式，在 LibreDWG 的 GPL。要上架且不想開源，
只能接 ODA 的商業 SDK —— 那時把 `DWGViewer` 換成原生實作即可，
`DrawingKind` 的路由不需要改。
