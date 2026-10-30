# 儲存／檔案／列印 現況審核

審核對象：`main` @ `14f9ce0`（v0.2.2）。方法：讀 `lib/data/document.dart`、`lib/main.dart`、`bin/tallynote.dart`、`pubspec.yaml`，並實際跑 CLI 與測試。

## 一句總結

**「唔會失去你打嘅字」呢部分係齊嘅；「同外面世界交換檔案」呢部分完全冇。**
資料只存在 app 內部（SharedPreferences 一個 JSON blob），冇檔案、冇匯出、冇匯入、冇列印。

---

## 1. 逐項對照

| 你問嘅 | 狀態 | 實際情況 | 位置 |
|---|---|---|---|
| **儲存（保存進度）** | ✅ 齊 | 停手 400ms 自動寫；⌘/Ctrl+S 即寫；切 sheet、app 退到背景、關閉前都會 flush | `main.dart` `_onText` / `_saveNow` / `_flush` / `didChangeAppLifecycleState` |
| | ✅ | 摺疊區塊時存**完整源文**，唔會存摺疊後嘅投影 | `_contentToSave` |
| | ✅ | 損壞 JSON → 抄去 `tallynote.sheets.v1.bak`、`_keepBackup` 阻止覆寫 | `document.dart:150` |
| **格式（存成咩）** | ⚠️ 只有一種 | 內部 JSON：`{v:2, folders:[…], sheets:[{id,title,content,folderId,pinned,customTitle,updated}]}`；key `tallynote.sheets.v1` | `document.dart:168` |
| | ❌ | 冇 Markdown／CSV／TXT／PDF；冇 `.tallynote` 檔案 | — |
| **另存檔（Save As）** | ⚠️ 只係 app 內 | ⌘/Ctrl+⇧D 複製一個新 sheet（標題加 `(copy)`），**唔係檔案** | `document.dart` `duplicate()` |
| **開舊檔（外部檔案）** | ❌ 冇 | GUI 完全冇 import；只有 CLI `tallynote -f note.txt` 讀純文字逐行計 | `bin/tallynote.dart:87` |
| **開新檔** | ⚠️ 只有「新 sheet」 | `⌘N` / 「New sheet」建立空白 sheet；冇「新檔案」概念 | `main.dart` / `sidebar.dart` |
| **Print** | ❌ 完全冇 | 冇 `printing`/`pdf` 依賴、冇任何列印或輸出 PDF 路徑 | — |
| **備份／還原** | ⚠️ 半套 | 只有「壞檔自動 .bak」；冇手動「匯出備份」「匯入備份」 | `document.dart:150` |
| **多檔／工作區** | ❌ | 所有 sheet 放同一個 store，冇「一個檔案 = 一組 sheet」 | — |
| **匯率快取** | ✅ | `tallynote.rates.v1` + `tallynote.rates.date.v1` | `rates.dart` |

### 一個要指出的落差

最初嘅設計筆記（`~/.hermes/cache/scratch/tallynote-design.md`，唔在 repo）寫「local JSON files with `.tallynote` extension」，但**實作由頭到尾都係 SharedPreferences，冇任何檔案**。repo 內冇任何文件再提 `.tallynote`，所以現時冇矛盾文件，只有「未做嘅承諾」。要麼補實作（P3），要麼在 roadmap 明確寫「檔案格式暫緩」。

---

## 2. 建議（按「唔會後悔」排序）

| 優先 | 做乜 | 為何先做 | 估時 |
|---|---|---|---|
| **P0** | **匯出／匯入 JSON 備份**（`tallynote-backup-2026-10-30.json`，全部 sheet + folders） | 唯一能救「換機／重裝」的功能；唔使改架構，讀寫同一個 payload | 半日 |
| **P1** | **匯出 Markdown / CSV**（唯讀快照，CSV 每行 `line,answer`） | 純文字、零依賴，桌面已可用；貼去報告／Excel 即刻用 | 一日 |
| **P2** | **Print → PDF**（`printing` + `pdf`，A4、等寬字、保留答案欄） | 你要嘅 print；同一條路徑順便做「匯出 PDF」 | 一日 |
| **P3** | 真 `.tallynote` 檔案（開啟／另存） | 要 `file_picker` + 定檔案格式 + 同 prefs 並存策略（建議：prefs 存「最近」，檔案存「專案」） | 兩日 |

**平台注意**
- `share_plus`（手機分享）／`file_picker`（開檔）／`printing` 都係平台 plugin：Android 直接；Windows/Linux 桌面要 XDG portal 或 zenity，Linux 要加依賴；Web 用 anchor download + `Printing.layoutPdf`。
- macOS／iOS 唔喺範圍，所以唔使處理 share sheet。

---

## 3. 明確唔建議

- 唔好把所有 sheet 變成一個個檔案（會令「開 app 即刻有嘢打」變慢，亦要處理檔案同步衝突）。
- 唔好做雲端同步（同離線定位衝突）。
- 唔好做「自動備份到某資料夾」——用戶唔知幾時寫、幾時刪；寧願手動一鍵匯出。

---

## 4. 驗證方法

- CLI：`dart run bin/tallynote.dart -f <file>`（讀檔）、`echo "1+1" | …`（stdin）
- 儲存：`flutter test test/save_safety_test.dart test/storage_hardening_test.dart`（5 個測試覆蓋 fold-save、跨 sheet debounce、lifecycle flush、壞檔 .bak）
- 全套：`flutter analyze` + `flutter test` → 84 tests
