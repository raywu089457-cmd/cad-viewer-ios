# 在 Mac 上建置與驗證

Linux CI 驗的是幾何、路由、訊息與 DWG 網頁引擎。它**驗不到**的是：這個 app 到底會不會
在 iOS 上跑起來、手勢用起來怎樣、畫面長什麼樣。那份清單在最後。

這份文件寫的是「拿到一台 Mac 之後照著做」的步驟，不是概論。

---

## 一、要裝什麼

| 項目 | 版本 | 為什麼 |
|---|---|---|
| **Xcode** | 15 或更新（含 iOS 17.0 SDK） | `ios/project.yml` 的 `deploymentTarget: iOS "17.0"` |
| **XcodeGen** | `brew install xcodegen` | repo 裡沒有 `.xcodeproj`，它由 `project.yml` 產生 |
| **Node.js** | 18 以上，建議 20 LTS | 建 DWG 網頁引擎；`package-lock.json` 有 104 個套件 |
| **Apple ID**（免費即可） | — | 真機要簽名；免費帳號的 build 七天到期 |

不需要：CocoaPods、Carthage、另外安裝 Swift（Xcode 內建）。

Node 的版本沒有在 `package.json` 的 `engines` 裡指定，所以不會被擋——但也就不會提醒你。
太舊的 Node 會在 `npm ci` 或 `vite build` 那步失敗。

---

## 二、建置（順序不能換）

```bash
git clone https://github.com/raywu089457-cmd/cad-viewer-ios.git
cd cad-viewer-ios

# ① 先建 DWG 引擎。沒這步，DWG 打開是空白佔位頁。
cd ios/web && ./build-for-ios.sh && cd ../..

# ② 產生 Xcode 專案
cd ios && xcodegen generate && cd ..

# ③ 開起來
open ios/CADViewer.xcodeproj
```

### 第 ① 步為什麼不能跳

`ios/CADViewer/Sources/CADViewer/Resources/dwgviewer/` 在乾淨的 clone 裡**只有一個佔位頁**
`index.html`。真正的引擎（`assets/`，約 17 MB，含 10 MB 的 LibreDWG wasm）被 `.gitignore`
排除，因為把 17 MB 的產物放進 git 不划算。

那個佔位頁自己會寫「執行 `ios/web/build-for-ios.sh`」——但只有你去開一個 DWG 檔才看得到它。
所以「建置成功、DXF 正常、DWG 一片空白」是這個專案最容易踩的順序錯誤。

`build-for-ios.sh` 會 `npm ci`（抓約 40 MB 依賴）、`vite build`、然後把 `dist/` 複製到上面
那個位置。跑完會印出大小。

---

## 三、真機簽名

```
Xcode → 選 CADViewer target → Signing & Capabilities
      → Team 選你的 Apple ID
      → Bundle Identifier 改掉 com.example.cadviewer
      → 接上 iPhone（並在手機上「信任這台電腦」）
      → Run
```

`com.example.cadviewer` 來自 `project.yml` 的 `bundleIdPrefix`，是佔位值，不能拿去簽名。

**模擬器**可以跳過簽名。但模擬器測不到「從檔案 App 開啟」的完整流程，而那正是這個 app
存在的理由——所以真機那一輪不能省。

---

## 四、驗證清單

Linux 上**驗不了**的就在這裡。請照順序做，哪一項不對就停下來。

| # | 動作 | 應該看到 | 為什麼這一項沒被 CI 驗過 |
|---|---|---|---|
| 1 | 開 `samples/example_r12.dxf` | 線圖，約 1400 條線 | 幾何驗過，畫面沒有 |
| 2 | 開 `samples/example_2018.dwg` | 同一張圖由 wasm 引擎畫出 | 網頁端在 Chromium 驗過，`WKWebView` 沒有 |
| 3 | 開任何一個 PDF | 內嵌顯示、可縮放 | `PDFKit` 在 Linux 只有 stub |
| 4 | **雙指縮放 + 單指拖** | 不打架、不抖、不跳 | 手感 |
| 5 | **連開兩個不同的檔** | 第二個不沿用第一個的縮放位置 | `@State` 的初始化只生效一次，這是實機才會遇到的形態 |
| 6 | 開完一個，**從檔案 App 分享另一個過來** | 正確替換，不是疊在上面 | `onOpenURL` 與 scene 生命週期 |
| 7 | 把 `.txt` 改名成 `.dwg` 再開 | 「不是 DWG」的說明，不是空白畫布 | `DWGHeader` 的判斷驗過，但驗的是函式不是流程 |
| 8 | 打開一張圖後**刪掉那個檔案**再切回 app | 有話說的錯誤，不是崩潰 | 錯誤分類驗過，`Data(contentsOf:)` 真的失敗沒有 |

第 4、5、6 是最可能出問題的三項。它們都動過，都沒有在真機上看過。

### 樣本裡沒有 PDF

`samples/` 只有 3 個 DWG 和 1 個 DXF。第 3 項要自己找一個 PDF。

---

## 五、編譯不過的話

三種最可能的，這三種在 repo 裡都有對應的東西可以對照：

**`SwiftDXF` resolve 不到。** `ios/CADViewer/Package.swift` 寫 `from: "0.6.0"`。
Xcode 的 *File → Packages → Resolve Package Versions* 跑一次。

**`ObservationMacros` 找不到。** `@Observable` 需要這個 macro plugin。CI 的 Linux 工具鏈有它，
wasm SDK 沒有，Xcode 的 macOS 工具鏈應該有。真的沒有的話，那是工具鏈的問題，不是這個 repo 的。

**資源沒被複製進 bundle。** `Package.swift` 裡是 `.copy("Resources/dwgviewer")`，那是一個
*目錄* 的複製。如果第 ① 步沒跑，目錄裡只有一個檔案，bundle 還是會成功——只是 DWG 壞掉。

把錯誤訊息貼出來就好，這份文件沒有要假裝涵蓋所有情況。

---

## 六、CI 已經驗過什麼（不用再驗一次）

放這裡是為了讓你知道上面那張表為什麼只有八項：

- **DXF 幾何**：`verification/dxf-geometry-harness` 在 wasm 裡真跑，項數以它自己的輸出為準
- **Swift 邏輯**：`swift test`，真編譯真執行
- **app 層型別**：`verification/check-types.sh` 用平台 stub 對所有 app 檔案做 `swiftc -typecheck`
- **DWG 網頁引擎**：無頭 Chromium 真的載入、開圖、重開、回全圖
- **座標**：一個與 Swift 端零共用的讀取器，直接比對檔案裡的數字
- **每個檢查都會失敗**：`verification/check-the-checks.mjs` 複製一棵樹、改壞一處、要求非零退出

型別檢查的界線要看清楚：stub 的 `body` **從不執行**。編得過不代表畫得對。
