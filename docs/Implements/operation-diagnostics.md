# 操作紀錄

目前開發階段所有版本預設啟用。從登入頁、旅程列表或啟動失敗頁的「操作紀錄」進入；也可使用 App 的 `/diagnostics` 路由，登入前可用。

- 「記錄操作」即時停止或恢復收集；關閉不清除現有紀錄。
- 可暫停自動捲動、搜尋文字／操作 ID／請求 ID，並依類型和結果篩選。
- 點選紀錄檢視詳情，可複製單筆；「複製全部 JSON」包含所有保留紀錄，不受畫面篩選影響。
- 重啟、重新整理、手動清除或登出會清除紀錄。沒有寫入本機儲存或自動上傳；複製後的剪貼簿內容由使用者管理。

## 追查方式

先找到操作的「開始」，搜尋該筆 `operationId`，即可串起子操作、request、response、登入刷新重試、錯誤與還原結果。相同 HTTP 請求的兩筆紀錄共用 `requestId`。HTTP 耗時包含呼叫端讀取回應串流的時間；串流未被讀取時不會提前載入完整回應。

HTTP 包裝透過 Supabase 的 `httpClient` 注入點涵蓋 Auth、PostgREST、RPC 與 Storage。Realtime 另外記錄訂閱狀態及收到的異動摘要。外部 OAuth 頁面、外部地圖、圖片元件的下載與底層 WebSocket 封包不在 HTTP 旁錄範圍。

## 資料與上限

儲存器最多保留 500 筆或 5 MiB，超出淘汰最舊紀錄。每個 request／response body 最多旁錄 8 KiB；過大、不完整、二進位與無法解析的內容只保留大小及省略／截斷標記。Auth body 一律省略。

只有已知 JSON 欄位和安全的結構／狀態值會保留；姓名、電子郵件、旅程／地點文字、備註、位置、照片、憑證與簽名連結不保留原文。識別碼使用本次執行一致的代號；識別碼代號表另設 4096 筆上限，之後的新識別碼顯示省略。未知欄位名稱也不保留。錯誤保留型別、已識別的原因分類、錯誤代碼和套件來源行號；不保留不確定的原始訊息或絕對路徑。

匯出的 JSON 含 `formatVersion`、UTC 時間、關聯 ID、結果與截斷標記。畫面與匯出使用同一份遮蔽後的資料；一般使用者提示仍使用易懂文案。

## 驗證

使用 `flutter test` 執行診斷單元、HTTP 串流、Widget 與服務流程測試。服務測試使用假的 HTTP 回應驗證實際 TripStore、照片服務與登入刷新，不存取正式專案資料。

需要產生窄螢幕畫面預覽時，執行：

```shell
flutter test --dart-define=DIAGNOSTICS_PREVIEW=true test/diagnostic_startup_test.dart
```

畫面輸出至 `app/build/diagnostics_preview.png`。
