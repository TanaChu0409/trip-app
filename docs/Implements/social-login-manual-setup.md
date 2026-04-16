# Google / Apple 社交登入手動設定步驟

## 前置：取得 Supabase Callback URL

1. 登入 [Supabase Dashboard](https://supabase.com/dashboard)
2. 進入你的專案 → **Project Settings → API**
3. 複製 **Project URL**，格式為 `https://<PROJECT_REF>.supabase.co`
4. OAuth callback URL 為：`https://<PROJECT_REF>.supabase.co/auth/v1/callback`（後面步驟會用到）

---

## Part 1：設定 Google Sign-In

### Step 1 — Google Cloud Console：建立 OAuth 2.0 Client ID

1. 前往 [Google Cloud Console](https://console.cloud.google.com/) → 選擇或建立一個專案
2. 左側導航 → **APIs & Services → OAuth consent screen**
   - User type 選 **External** → Create
   - 填入 App name（如 `Trip Planner`）、User support email、Developer contact email
   - Scopes 保留預設（`email`, `profile`, `openid`）→ Save and Continue 到底 → **Back to Dashboard**
3. 左側 → **APIs & Services → Credentials → + CREATE CREDENTIALS → OAuth client ID**
4. Application type 選 **Web application**
5. Name 填 `Trip Planner (Supabase)`
6. **Authorized redirect URIs** → Add URI：
   ```
   https://<PROJECT_REF>.supabase.co/auth/v1/callback
   ```
7. 點 **Create** → 複製顯示的 **Client ID** 和 **Client secret**

### Step 2 — Supabase Dashboard：啟用 Google Provider

1. Supabase Dashboard → **Authentication → Providers → Google**
2. 開啟 **Enable Sign in with Google**
3. 貼入剛才複製的 **Client ID** 和 **Client Secret**
4. 點 **Save**

---

## Part 2：設定 Apple Sign-In

> **前提**：需要付費的 Apple Developer 帳號（$99/年）

### Step 1 — Apple Developer：建立 App ID（若尚未有）

1. 前往 [Apple Developer → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. 點 **+** → 選 **App IDs** → Continue
3. Type 選 **App** → Continue
4. Description 填 `Trip Planner App`，Bundle ID 填 `com.example.tripplannerapp`（需與 Xcode 一致）
5. 在 Capabilities 列表勾選 **Sign In with Apple** → Continue → Register

### Step 2 — Apple Developer：建立 Service ID（Web/Supabase 用）

1. Identifiers → **+** → 選 **Services IDs** → Continue
2. Description 填 `Trip Planner Supabase`，Identifier 填 `com.example.tripplannerapp.supabase`
3. Register
4. 點進剛才建立的 Service ID → 勾選 **Sign In with Apple** → 點旁邊 **Configure**
5. **Primary App ID** 選剛才的 `com.example.tripplannerapp`
6. **Domains and Subdomains** 填：
   ```
   <PROJECT_REF>.supabase.co
   ```
7. **Return URLs** 填：
   ```
   https://<PROJECT_REF>.supabase.co/auth/v1/callback
   ```
8. 點 **Next** → **Done** → **Continue** → **Save**

### Step 3 — Apple Developer：建立 Sign In with Apple Key

1. 左側 → **Keys → +**
2. Key Name 填 `Trip Planner Supabase Key`
3. 勾選 **Sign In with Apple** → 點旁邊 **Configure** → Primary App ID 選 `com.example.tripplannerapp` → Save
4. Continue → Register
5. **下載 .p8 檔案**（只能下載一次！）並記下：
   - **Key ID**（10 碼英數字，頁面有顯示）
   - **Team ID**（登入後右上角帳號名旁，或 Membership 頁面）

### Step 4 — Supabase Dashboard：啟用 Apple Provider

1. Supabase Dashboard → **Authentication → Providers → Apple**
2. 開啟 **Enable Sign in with Apple**
3. 填入：

   | 欄位 | 值 |
   |---|---|
   | Service ID (client_id) | `com.example.tripplannerapp.supabase` |
   | Apple Team ID | 你的 Team ID（10 碼） |
   | Key ID | 你的 Key ID（10 碼） |
   | Private Key (.p8) | 貼入 .p8 檔案的完整內容（包含 `-----BEGIN PRIVATE KEY-----` 那幾行） |

4. 點 **Save**

---

## Part 3：設定 Supabase Redirect URLs

1. Supabase Dashboard → **Authentication → URL Configuration**
2. **Site URL**（開發時用 localhost，正式上線再改）：
   ```
   http://localhost:3000
   ```
3. **Redirect URLs** → Add → 依序新增：

   | 環境 | URL |
   |---|---|
   | Mobile（Android & iOS） | `com.example.tripplannerapp://login-callback` |
   | Web 開發 | `http://localhost:3000` |
   | Web 正式（若有） | `https://your-production-domain.com` |

4. 點 **Save**

---

## Part 4：驗證設定

完成以上步驟後，執行下列指令測試：

```bash
# Web 測試
flutter run -d chrome --web-port 3000

# Android 測試（需實機或模擬器）
flutter run -d android

# iOS 測試（需 Mac + Xcode）
flutter run -d ios
```

**驗收項目：**

- Google 登入 → 瀏覽器跳出 Google 授權頁 → 同意後自動回 app 並導向 `/trips` ✓
- Apple 登入 → 輸入 Apple ID → 同意後回 app 並導向 `/trips` ✓（僅 iOS / Web）
- 取消授權流程 → 回到登入頁，而非白屏 ✓
- 原有 Email / Password 登入不受影響 ✓
- signOut 後再用社交帳號登入仍正常 ✓
