# Flutter 旅程規劃 APP — 實作計畫書

> 將現有的桃園嘉義行 HTML 行程導覽轉為跨平台 Flutter APP，支援建立與編輯多個旅程、Supabase 同步、Google/Apple 登入、邀請碼唯讀分享、離線瀏覽、時程提醒與到點提醒。

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

### Role Matrix

| 功能 | Owner | Guest |
|---|:---:|:---:|
| 瀏覽行程 | ✅ | ✅ |
| 地圖導航 | ✅ | ✅ |
| 時程提醒 | ✅ | ✅ |
| 導航模式 / 到點提醒 | ✅ | ✅ |
| 編輯行程 / 天數 / 停靠點 / 停車場 | ✅ | ❌ |
| 分享管理 | ✅ | ❌ |

## 2. Architecture

- Flutter + Riverpod + GoRouter
- Supabase 作為遠端資料來源
- Drift 作為離線快取
- flutter_local_notifications + geolocator 處理提醒

## 3. Phase Plan

1. Project setup and Supabase schema
2. Core app shell and routing
3. Authentication
4. Trip list and invite-code join flow
5. Trip detail browsing UI
6. Owner editing flows, including delete-trip flow
7. Schedule reminder notifications
8. Navigation mode and arrival reminder
9. Offline support
10. Polish, tests, and release prep

## 3.1 Delete Trip Plan

### Goal

- Owner can safely remove a trip from their account.
- Guest cannot delete a shared trip; guest can only leave the shared trip.
- Deletion must also clean up related days, stops, parking spots, local cache, and scheduled notifications.

### Product Decision

- Phase 1 of delete behavior uses a two-step model:
- `封存旅程` for reversible hiding from the main list.
- `永久刪除` for irreversible removal of all associated data.
- In the short term UI, if only one destructive action is implemented first, prioritize `永久刪除` with a strong confirmation dialog because the current prototype already exposes direct create/read flows.

### User Flow

#### Owner delete flow

1. User opens trip card overflow menu or trip settings.
2. User taps `刪除旅程`.
3. App shows destructive confirmation sheet.
4. Sheet explains impacted data:
	 - 行程天數
	 - 停靠點
	 - 停車場資訊
	 - 分享給其他人的唯讀存取
	 - 本機提醒與到點通知
5. User confirms deletion.
6. App executes delete.
7. Success behavior:
	 - close current trip page if open
	 - remove trip from list
	 - cancel notifications
	 - show snackbar: `已刪除旅程`

#### Guest leave flow

1. Guest opens shared trip card overflow menu.
2. Guest taps `退出旅程`.
3. App confirms removal from shared access only.
4. App deletes `shared_access` record for that user.
5. App removes the trip from `分享給我的` list and clears local reminders for that trip.

### Permission Rules

| Action | Owner | Guest |
|---|:---:|:---:|
| 封存旅程 | ✅ | ❌ |
| 永久刪除旅程 | ✅ | ❌ |
| 退出分享旅程 | ❌ | ✅ |
| 刪除他人 shared_access | ✅ | ❌ |

### Data Deletion Strategy

#### Hard delete scope

Deleting one trip must remove:

- row in `trips`
- related `days`
- related `stops`
- related `parking_spots`
- related `shared_access`
- local cached trip data in Drift
- local scheduled notifications for all stops in the trip
- active navigation-mode in-memory tracking state if the deleted trip is currently open

#### Database behavior

- `days.trip_id -> trips.id` uses `on delete cascade`
- `stops.day_id -> days.id` uses `on delete cascade`
- `parking_spots.stop_id -> stops.id` uses `on delete cascade`
- `shared_access.trip_id -> trips.id` should also use `on delete cascade`

#### Recommendation

- Keep `is_archived` for soft-hide/archive use cases.
- Use SQL `delete from trips where id = :tripId and owner_id = auth.uid()` for permanent deletion.
- Do not implement partial orphan cleanup in app code; rely on FK cascade for remote data integrity.

### UX Spec

#### Entry points

- Trips list card overflow menu
- Trip detail screen app bar action
- Trip settings screen destructive section

#### Confirmation UI

- Title: `刪除旅程？`
- Body: `此動作無法復原，包含天數、停靠點、停車資訊、分享權限與提醒都會一併刪除。`
- Buttons:
	- secondary: `取消`
	- destructive: `確認刪除`

#### Optional stronger confirmation

- For trips with many stops or shared access enabled, require typing the trip title before delete.
- Trigger stronger confirmation when:
	- stop count > 10, or
	- trip has guests, or
	- trip contains future reminders

### Local State / Flutter Implementation Plan

#### State layer

- Add `deleteTrip(String tripId)` to repository/store.
- Add `leaveSharedTrip(String tripId)` for guest flow.
- Ensure list screen listens to state changes and removes deleted item immediately.
- If current route is `/trips/:tripId`, redirect back to `/trips` after delete succeeds.

#### UI layer

- Add overflow menu on `TripCard`.
- Owner menu items:
	- `編輯旅程`
	- `分享設定`
	- `刪除旅程`
- Guest menu items:
	- `退出旅程`
- Add `showModalBottomSheet` or `showDialog` for destructive confirmation.

#### Notification cleanup

- Each stop reminder should use a deterministic notification id.
- `deleteTrip()` must iterate all trip stops and cancel all related notification ids.
- If navigation mode is active on the same trip, exit tracking and clear next-stop target.

### Offline-first Behavior

#### Owner delete while online

- Delete remote first.
- On success, delete local cached rows and local notifications.

#### Owner delete while offline

- Mark trip as `pending_delete` in local DB.
- Remove it from visible list immediately for optimistic UX.
- Queue deletion operation in sync table.
- On reconnect, execute remote delete.
- If remote delete fails, restore visibility and show error state.

#### Guest leave while offline

- Queue shared-access removal.
- Hide trip from UI immediately.
- Cancel related notifications locally.

### Failure Cases

- Network error during delete
	- show snackbar: `刪除失敗，稍後再試`
- Permission denied
	- show snackbar: `你沒有權限刪除此旅程`
- Route opened on deleted trip
	- redirect to trip list and show `旅程不存在或已刪除`
- Shared trip deleted by owner while guest still has page open
	- next refresh or sync detects missing trip and closes detail page

### Test Plan For Delete Feature

#### Unit tests

- owner delete removes trip from store
- guest cannot call owner delete path
- leave shared trip removes only shared item
- delete cleanup cancels related notification ids

#### Widget tests

- owner sees `刪除旅程` action
- guest sees `退出旅程` action only
- confirmation dialog appears with destructive copy
- confirm delete returns user to trip list

#### Integration tests

- create trip -> delete trip -> list no longer shows it
- shared trip as guest -> leave trip -> shared list removes it
- delete trip with reminders -> notifications cancelled
- delete currently opened trip -> app redirects safely to list

### Implementation Order

1. Add store/repository delete methods.
2. Add overflow menu and confirmation dialog in list/detail UI.
3. Implement owner delete in current in-memory store.
4. Implement guest leave flow.
5. Add notification cleanup hooks.
6. Persist behavior in local DB.
7. Wire remote delete to Supabase.
8. Add tests.

## 4. Current Implementation Scope

- 建立 Flutter app 基礎結構
- 建立主題與路由
- 以現有桃園嘉義行資料建立示範 UI
- 建立通知與地圖解析 service stub
- 建立 Supabase 初始 migration 草稿
- 已完成建立旅程的前端 in-memory 流程
- 下一步可直接實作刪除旅程與退出分享旅程

## 5. Next Steps

1. 將示範資料替換為 repository + remote/local data source
2. 完成邀請碼 join flow 與 shared_access 串接
3. 完成 owner 編輯流程、分享管理與刪除旅程流程

## 6. Supabase Integration Record

### Implemented in App

- Flutter app 啟動時會先讀取 `app/.env`，再初始化 Supabase
- Auth 畫面已改為 Email/Password 註冊與登入
- Router 已加入 auth redirect
	- 未登入時導向 `/auth`
	- 已登入時進入 `/trips`
- Trips list 已加入登出入口

### Secrets Handling

- 真實 Supabase credentials 不可寫入 git 追蹤檔案
- 本專案使用 `app/.env` 保存本機開發用 secret
- `app/.env` 已加入 ignore，不會 commit
- 版控內僅保留 `app/.env.example` 作為欄位範本

### Required Environment Variables

在 `app/.env` 內提供以下欄位：

```env
SUPABASE_URL=
SUPABASE_ANON_KEY=
```

說明：

- `SUPABASE_URL`: Supabase project URL
- `SUPABASE_ANON_KEY`: 前端使用的 anon/public key

### Related Files

- `app/.env` 本機 secret 檔案，不進版控
- `app/.env.example` secret 範本
- `app/lib/main.dart` 啟動時載入 dotenv 與 Supabase initialize
- `app/lib/core/supabase/supabase_config.dart` Supabase 設定讀取與初始化
- `app/lib/features/auth/data/auth_service.dart` Supabase auth 封裝
- `app/lib/features/auth/data/auth_provider.dart` auth state provider
- `app/lib/features/auth/presentation/auth_screen.dart` Email/Password auth UI
- `app/lib/core/router/app_router.dart` auth redirect

### Required Supabase SQL

第一次建置專案時，需依序在 Supabase SQL Editor 執行：

1. `supabase/migrations/001_initial_schema.sql`
2. `supabase/migrations/002_child_table_rls.sql`

用途：

- `001_initial_schema.sql` 建立 trips、days、stops、parking_spots、shared_access 與基礎 RLS
- `002_child_table_rls.sql` 補上 days、stops、parking_spots 的 RLS，以及 owner 對 shared_access 的管理權限

### Dashboard Requirements

- Authentication -> Providers -> Email 必須啟用
- 開發測試期間可先關閉 Confirm email，避免 sign up 後還需 email 驗證才能登入

### Verification Checklist

1. `flutter pub get` 成功
2. `flutter analyze` 成功
3. App 啟動不出現缺少 env 的錯誤
4. 可用 Email/Password 建立帳號
5. 登入後可自動導向 `/trips`
6. 登出後可自動回到 `/auth`
