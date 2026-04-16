# Flutter 旅程規劃 APP — 實作計畫書

> 將現有的桃園嘉義行 HTML 行程導覽轉為跨平台 Flutter APP。現階段已完成 Flutter 殼層、Supabase Auth、旅程/停靠點 CRUD 的主要骨架，並已接上分享碼加入、刪除旅程、退出分享旅程；離線快取、真正通知排程、到點提醒與第三方登入仍在後續範圍內。

## 1. Data Model

### Supabase Tables

```
users (Supabase Auth)
trips
days
stops
parking_spots
shared_access
```

### Current Notes

- `trips` 已實際使用 `share_code` 與 `is_archived` 欄位
- `days.trip_id -> trips.id`、`stops.day_id -> days.id`、`parking_spots.stop_id -> stops.id`、`shared_access.trip_id -> trips.id` 都已使用 `on delete cascade`
- App 目前以 Supabase 為唯一正式資料來源，Drift 仍未接線

### Role Matrix

| 功能 | Owner | Guest |
|---|:---:|:---:|
| 瀏覽行程 | ✅ | ✅ |
| 分享碼加入旅程 | ❌ | ✅ |
| 查看分享碼 | ✅ | ❌ |
| 地圖外開導航 | ✅ | ✅ |
| 導航模式畫面 | ✅ | ✅ |
| 新增 / 編輯 / 刪除停靠點 | ✅ | ❌ |
| 停靠點排序 | ✅ | ❌ |
| 刪除旅程 | ✅ | ❌ |
| 退出分享旅程 | ❌ | ✅ |
| 分享管理 UI | ⏳ | ❌ |
| 真正時程提醒 / 到點提醒 | ⏳ | ⏳ |

## 2. Architecture

### Current

- Flutter + Riverpod + GoRouter
- Supabase Auth + PostgREST 作為正式遠端資料來源
- `TripStore` 作為前端同步中的 state/store 層
- `TripService` / `StopService` / `ParkingSpotService` 分別處理 trips、stops、parking_spots 的遠端資料操作
- `NotificationService` 目前為記憶體 stub，僅追蹤 notification id，尚未真正接上 `flutter_local_notifications`
- `NavigationModeScreen` 目前為導航模式 UI 佔位頁，尚未接入 `geolocator`

### Target

- Drift 作為離線快取與 sync queue
- `flutter_local_notifications` 處理時程提醒
- `geolocator` 處理到點提醒與前景定位
- Google / Apple Sign-In 作為 Email/Password 之後的登入擴充

## 3. Phase Plan

| Phase | 狀態 | 說明 |
|---|---|---|
| 1. Project setup and Supabase schema | 已完成 | Flutter 專案、主題、路由、Supabase migration 已建立 |
| 2. Core app shell and routing | 已完成 | `/auth`、`/trips`、`/trips/:tripId`、停靠點表單、導航模式路由已接好 |
| 3. Authentication | 部分完成 | 已完成 Email/Password；Google/Apple 尚未實作 |
| 4. Trip list and invite-code join flow | 已完成 | 旅程載入、建立旅程、分享碼加入、owner/shared 分組皆可用 |
| 5. Trip detail browsing UI | 已完成 | 明細頁、天數 tabs、停靠點列表、分享碼顯示、外開地圖已可使用 |
| 6. Owner editing flows, including delete-trip flow | 部分完成 | 已完成停靠點新增/編輯/刪除/排序、刪除旅程、退出分享；旅程資訊編輯與分享管理尚未完成 |
| 7. Schedule reminder notifications | 進行中 | 目前只有 notification id 追蹤 stub，尚未實際排程系統通知 |
| 8. Navigation mode and arrival reminder | 進行中 | 已有導航模式頁面與文案，尚未接入定位與到點判斷 |
| 9. Offline support | 尚未開始 | Drift、同步佇列、衝突處理都還沒接線 |
| 10. Polish, tests, and release prep | 進行中 | 目前只有少量 model / widget test，尚未覆蓋主要流程 |

## 3.1 Delete / Leave Trip 現況

### 已完成

- Owner 可在旅程列表卡片與旅程明細頁刪除旅程
- Guest 可在旅程列表卡片與旅程明細頁退出分享旅程
- 刪除 / 退出前皆有確認對話框
- 刪除旅程後會從列表移除，若在明細頁執行則會導回 `/trips`
- 退出分享旅程後會從「分享給我的」列表移除，若在明細頁執行則會導回 `/trips`
- 刪除與退出都會呼叫 `NotificationService.cancelTripReminders(tripId)` 清掉目前追蹤中的提醒 id
- 遠端刪除直接依賴 Supabase `delete` + FK cascade，不在 App 端做孤兒資料清理

### 目前限制

- 尚未提供 `封存旅程` UI，只有永久刪除
- 尚未實作較強確認機制，例如輸入旅程名稱後才能刪除
- 尚未接入 Drift，本機快取清理仍不存在
- 尚未處理離線刪除佇列與回補
- 尚未清理導航模式中的即時追蹤狀態，因為目前尚未真的啟用定位追蹤

### Current Permission Rules

| Action | Owner | Guest |
|---|:---:|:---:|
| 永久刪除旅程 | ✅ | ❌ |
| 退出分享旅程 | ❌ | ✅ |
| 刪除停靠點 | ✅ | ❌ |
| 調整停靠點順序 | ✅ | ❌ |
| 查看分享碼 | ✅ | ❌ |

### Current Data Deletion Strategy

- 遠端主流程：`delete from trips where id = :tripId and owner_id = auth.uid()`
- `shared_access` 的 guest leave 流程：刪除該 user 對應的 `shared_access` row
- 關聯刪除依靠資料庫 cascade
- 本機目前只會取消記憶體中的 reminder tracking，不含實際 OS-level notification cleanup

### Remaining Work

- 加入 `is_archived` 對應 UI 與封存列表
- 對大量停靠點 / 已分享旅程加入更強刪除確認
- 補上離線刪除與同步失敗回復策略
- 為 delete / leave flow 增加 widget / integration tests

## 4. Current Implementation Scope

### 已完成

- 建立 Flutter app 基礎結構、主題與 GoRouter 路由
- App 啟動時載入 `app/.env` 並初始化 Supabase
- Email/Password 註冊、登入、登出與 auth redirect
- 從 Supabase 讀取 owner trips 與 shared trips
- 建立旅程後自動建立對應 `days`
- 旅程列表分為「我的旅程」與「分享給我的」
- 透過分享碼加入旅程，並寫入 `shared_access`
- 旅程明細頁顯示天數 tabs、停靠點清單、旅程摘要
- Owner 可查看並複製分享碼
- Owner 可新增、編輯、刪除、拖曳排序停靠點
- 停靠點可編輯時間、備註、標籤、地圖連結、重點標記與多筆停車場資訊
- 停靠點與停車場資訊皆直接寫入 Supabase
- 地圖連結可使用外部地圖 App 開啟
- 已實作刪除旅程與退出分享旅程流程

### 已存在但仍是 Stub / Placeholder

- `NotificationService` 只在記憶體中追蹤 reminder ids
- `NavigationModeScreen` 只有導航模式示意 UI
- `maps_url_parser.dart` 尚未成為完整導航整合流程的一部分

### 尚未完成

- Google / Apple 登入
- 旅程基本資訊編輯
- 分享管理 UI，例如查看已加入成員、移除 guest
- Drift 本機資料庫與離線瀏覽
- 真正的本機通知排程與取消
- geofence / 到點提醒 / 前景定位
- 全面測試與 release 準備

## 5. Next Steps

1. 補完 `flutter_local_notifications` 與 `geolocator`，把目前 notification / navigation stub 換成真正功能
2. 導入 Drift，建立離線快取、同步佇列與 pending delete / leave 機制
3. 完成旅程層級的 owner 編輯流程，例如旅程標題、日期、封存與分享管理
4. 補齊 delete / leave / join / stop CRUD 的 widget 與 integration tests
5. 規劃 Google / Apple Sign-In，讓登入方式從 Email/Password 擴充

## 6. Supabase Integration Record

### Implemented in App

- Flutter app 啟動時會先讀取 `app/.env`，再初始化 Supabase
- Auth 畫面已改為 Email/Password 註冊與登入
- Router 已加入 auth redirect
  - 未登入時導向 `/auth`
  - 已登入時進入 `/trips`
- Trips list 已加入登出入口
- Trips / days / stops / parking_spots / shared_access 已實際讀寫 Supabase
- 建立旅程時會建立 trip row 與 day rows
- 加入分享旅程時會依分享碼寫入 `shared_access`
- 刪除旅程與退出分享旅程都已直接操作 Supabase

### Secrets Handling

- 真實 Supabase credentials 不可寫入 git 追蹤檔案
- 本專案只接受編譯期注入的 secrets，不在 runtime 讀取 Flutter asset
- 可用 `--dart-define` 或 `--dart-define-from-file=app/.env` 提供設定
- `app/.env` 可作為本機 `--dart-define-from-file` 的輸入檔，且已加入 ignore，不會 commit
- 版控內保留 `app/.env.example` 作為欄位範本

### Required Environment Variables

提供以下欄位：

```env
SUPABASE_URL=
SUPABASE_ANON_KEY=
```

範例：

```bash
flutter run --dart-define-from-file=app/.env
flutter build web --dart-define-from-file=app/.env
```

說明：

- `SUPABASE_URL`: Supabase project URL
- `SUPABASE_ANON_KEY`: 前端使用的 anon/public key

### Related Files

- `app/.env` 本機 `--dart-define-from-file` 輸入檔，不進版控
- `app/.env.example` secret 範本
- `app/lib/main.dart` 啟動與 Supabase initialize
- `app/lib/core/supabase/supabase_config.dart` 從 compile-time define 讀取 Supabase 設定並初始化
- `app/lib/core/router/app_router.dart` auth redirect 與 app routes
- `app/lib/features/auth/data/auth_service.dart` Supabase auth 封裝
- `app/lib/features/auth/data/auth_provider.dart` auth state provider
- `app/lib/features/auth/presentation/auth_screen.dart` Email/Password auth UI
- `app/lib/features/trips/data/trip_service.dart` 旅程、分享碼加入、刪除、退出分享的 Supabase 操作
- `app/lib/features/trips/data/trip_store.dart` app 內同步 state 與資料刷新入口
- `app/lib/features/trip_detail/data/stop_service.dart` 停靠點資料操作
- `app/lib/features/trip_detail/data/parking_spot_service.dart` 停車場資料操作

### Required Supabase SQL

第一次建置專案時，需依序在 Supabase SQL Editor 執行：

1. `supabase/migrations/001_initial_schema.sql`
2. `supabase/migrations/002_child_table_rls.sql`
3. `supabase/migrations/003_local_dev_rls_backfill.sql`

用途：

- `001_initial_schema.sql` 建立 trips、days、stops、parking_spots、shared_access 與基礎 RLS
- `002_child_table_rls.sql` 補上 days、stops、parking_spots 的 RLS，以及 owner 對 shared_access 的管理權限
- `003_local_dev_rls_backfill.sql` 以 idempotent 方式補齊本地開發常漏掉的 child table / shared_access policies，並新增 guest 可自行退出分享旅程的 delete policy

### Dashboard Requirements

- Authentication -> Providers -> Email 必須啟用
- 開發測試期間可先關閉 Confirm email，避免 sign up 後還需 email 驗證才能登入

## 7. Verification Checklist

### 已可驗證

1. `flutter pub get` 成功
2. App 啟動時可載入 `app/.env` 並初始化 Supabase
3. 可用 Email/Password 建立帳號與登入
4. 登入後會自動導向 `/trips`
5. 可建立旅程並自動生成天數
6. 可透過分享碼加入旅程
7. 可新增、編輯、刪除、排序停靠點
8. Owner 可刪除旅程，Guest 可退出分享旅程
9. 登出後可自動回到 `/auth`

### 仍需驗證 / 待補測試

1. `flutter analyze` 全綠
2. delete / leave / join / stop CRUD 的完整 widget tests
3. 提醒排程與取消的真正裝置驗證
4. geolocator 導航模式與到點提醒整合驗證
5. 離線模式與同步衝突驗證
