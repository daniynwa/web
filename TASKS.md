# TASKS.md — Roadmap Ekosistem Regular Investor

Dokumen ini melacak seluruh pekerjaan pengembangan ekosistem yang mencakup
**regular-investor** (portal berita & subscription) dan **ridx-terminal**
(Bloomberg-inspired IDX terminal). Dibaca bersama [README.md](./README.md).

---

## Status Saat Ini

### regular-investor — Produksi
- [x] Auth: login/register email, Google OAuth, HMAC session token
- [x] Subscription: plan bulanan/tahunan, konfirmasi manual admin
- [x] News: artikel publik, kategori, featured
- [x] Premium articles: CRUD admin, akses subscriber
- [x] Portfolio tracker: CRUD saham, harga live Yahoo Finance
- [x] DSS AHP/SAW/TOPSIS (JavaScript) — fitur existing RI
- [x] Admin panel: user, artikel, subscription, settings
- [x] Docker Compose + Dockerfile

### ridx-terminal — Fase 1-4 Selesai
- [x] **Fase 1** — Backend + Data Pipeline
  - `yf_fetcher.py`: OHLCV + fundamental via yfinance
  - `preparator.py`: 22 indikator teknikal via pandas-ta
  - `endpoints_stock.py`: GET /api/stock/{ticker}, /history, /indicators
- [x] **Fase 2** — OmniQuant ML Engine
  - `data_prep.py`: feature extraction + label generation (binary/ternary)
  - `trainers.py`: XGBoostTrainer + LightGBMTrainer
  - `ensemble.py`: stacking meta-model
  - `omniquant.py`: inference engine (ML mode + mock/heuristic fallback)
  - `auto_train.py`: pipeline fetch data → training → save .pkl
  - `endpoints_predict.py`: GET /api/predict/{ticker}, /dashboard
- [x] **Fase 3** — Frontend Shell
  - React 19 + Vite 8 + Tailwind v4 + Zustand v5
  - `GridPanel.tsx`, `terminalStore.ts`, `StatusBar.tsx`
  - Tema gelap Bloomberg-style
- [x] **Fase 4** — Widget Visualisasi
  - `TvChart.tsx`: candlestick dengan lightweight-charts v5
  - `TopBar.tsx`: pencarian ticker, Ctrl+K, dropdown history
  - `MarketStats.tsx`: fundamental + konsensus analis + ROE + profit margin
  - `MLSignal.tsx`: BUY/HOLD/SELL badge + confidence bar + DSS reasoning
  - `TechIndicators.tsx`: 8 indikator utama dari 22
  - `Watchlist.tsx`: 10 ticker LQ45 clickable

### Belum Dimulai
- [ ] Fase 5: Redis caching (ridx-terminal)
- [ ] Integrasi auth antar service
- [ ] Terminal subscription tier di regular-investor
- [ ] Watchlist & Price Alerts
- [ ] Root Docker Compose ekosistem

---

## Fase A — Integrasi Auth Antar Service ✅ SELESAI
**Tujuan:** Regular Investor menjadi auth hub. R-IDX Terminal memvalidasi token RI
sebelum melayani request. User yang tidak punya subscription terminal ditolak.

**Status:** Implementasi selesai. Backend lolos `py_compile`. Typecheck frontend
belum dijalankan (Node tidak tersedia di environment dev saat ini) — lihat
"Verifikasi Manual" di bawah.

### A1. Auth Middleware di Python Backend ✅
**File:** `ridx-terminal/backend/app/core/auth.py`

- [x] Fungsi `_verify_ri_token(token) -> dict | None` — decode base64 envelope,
  verifikasi HMAC-SHA256 dengan `RI_USER_SECRET`, cek expiry 7 hari
- [x] Dependency `require_terminal_access(request)` — baca Bearer header /
  cookie `ri_terminal_session`, cek role/feature, raise 401/403
- [x] `RI_USER_SECRET` ditambah ke `config.py`, `backend/.env`, `docker-compose.yml`
- [x] Dependency diterapkan ke 3 endpoint `endpoints_stock.py` + 2 endpoint `endpoints_predict.py`
- [x] `GET /api/health` tetap public (tidak diberi dependency)

### A2. Endpoint Access Token di Regular Investor ✅
**File:** `regular-investor/src/pages/api/terminal/access-token.ts`

- [x] `GET /api/terminal/access-token` — verifikasi `ri_user_session`,
  cek `hasTerminalAccess()`, generate token via `createTerminalToken()` dengan `features[]`,
  return `{ ok, token, terminalUrl }`
- [x] `createTerminalToken()` ditambah ke `user-auth.js`
- [x] `getUserFeatures()` + `hasTerminalAccess()` ditambah ke `subscription.js`
  (forward-compatible: fallback ke baseline role jika tabel `user_features` belum ada)

> Catatan desain: token saat ini berumur sama dengan sesi RI (7 hari, divalidasi
> backend). Handoff token 60 detik + nonce store adalah hardening opsional yang
> ditunda ke Fase H — SPA statis tidak bisa set HttpOnly cookie sendiri, jadi
> token disimpan di localStorage.

### A3. Auth Handler di Frontend Terminal ✅
**File:** `ridx-terminal/frontend/src/lib/auth.ts`, `components/AuthGate.tsx`

- [x] `resolveAuth()` handle route `/auth?token=` → POST `/api/auth/verify` →
  simpan token ke localStorage, strip token dari URL, redirect ke `/`
- [x] Gagal/expired → redirect ke `VITE_RI_URL/pricing?error=...`
- [x] `apiClient.ts` menyertakan `Authorization: Bearer <token>`, handle 401/403 → redirect RI
- [x] `AuthGate.tsx` membungkus `App` (di `main.tsx`) dengan splash + layar "no access"

### A4. Endpoint Verify di Python Backend ✅
**File:** `ridx-terminal/backend/app/api/endpoints_auth.py`

- [x] `POST /api/auth/verify` (public) — return `{ valid, user_id, role, features[], reason? }`
- [x] `GET /api/auth/me` (protected) — echo user dari Bearer token
- [x] Router didaftarkan di `main.py`

### Verifikasi Manual (belum dijalankan)
- [ ] Set `RI_USER_SECRET` (backend) == `USER_SECRET` (RI) dengan nilai acak nyata di produksi
- [ ] Set `TERMINAL_URL` di env RI, `VITE_RI_URL` di env frontend terminal
- [ ] Jalankan `tsc --noEmit` di frontend terminal saat Node tersedia
- [ ] Uji end-to-end: login RI → `/api/terminal/access-token` → redirect `/auth` → terminal terbuka
- [ ] Uji negatif: user `free` ditolak (403 → layar no-access), token kedaluwarsa (401 → redirect)

---

## Fase B — Terminal Subscription di Regular Investor ✅ SELESAI
**Tujuan:** Admin bisa jual plan Terminal. User bisa upgrade. Sistem otomatis
mengelola akses berdasarkan subscription aktif.

### B1. Schema Migration ✅
**File:** `regular-investor/database/schema.sql` + `database/migrations/001_terminal_tier.sql`

- [x] `users.role` ENUM extend `'terminal'` (inline di schema + ALTER di migrasi)
- [x] `subscriptions.plan_type` ENUM extend `'terminal_monthly'`, `'terminal_yearly'`
- [x] Tabel `user_features` (PK user_id+feature, idx expires_at, FK CASCADE)
- [x] Harga plan di `site_settings`: `terminal_monthly_price=150000`, `terminal_yearly_price=1500000`
- [x] File migrasi terpisah untuk DB existing + backfill feature flags subscriber aktif

### B2. Update subscription.js ✅
**File:** `regular-investor/src/lib/subscription.js`

- [x] `PLANS` extend `terminal_monthly` + `terminal_yearly` dengan field `tier`
- [x] `confirmSubscription()` pakai `plan.tier`, panggil `grantTierFeatures()`
  (INSERT ... ON DUPLICATE KEY UPDATE, expires_at = end_date, toleran tabel hilang)
- [x] `cancelSubscription()` panggil `reconcileUserAccess()`
- [x] `reconcileUserAccess(userId)` baru — re-derive role (terminal>premium>free)
  dari sub aktif + rebuild `user_features`

### B3. Halaman Pricing ✅
**File:** `regular-investor/src/pages/pricing.astro` (baru)

- [x] 2 kolom (Premium / Terminal) + toggle Bulanan/Tahunan, harga dari `PLANS`
- [x] CTA → POST `/api/user/subscribe`, modal instruksi transfer + tombol WhatsApp
- [x] Public; jika belum login → redirect `/portfolio/login?redirect=/pricing`
- [x] Tampilkan pesan error dari terminal (`?error=no_access|token_expired|...`)

### B4. Update Admin Panel ✅
**File:** `regular-investor/src/pages/admin/subscribers/index.astro`

- [x] Label paket map 4 plan_type + badge "TERMINAL" untuk plan terminal
- [x] Konfirmasi/cancel sudah lewat `confirmSubscription`/`cancelSubscription` (B2)

### B5. Tombol Masuk Terminal ✅
**File:** `regular-investor/src/pages/portfolio/profile.astro`

- [x] Kartu "R-IDX Terminal" — tombol "Buka Terminal" jika `role === 'terminal'`,
  CTA "Lihat Paket" jika belum
- [x] Klik → fetch `/api/terminal/access-token` → redirect `terminalUrl`/`redirectTo`
- [x] Label membership map plan terminal dengan benar

### B6. Cron Job: Expire Subscription Harian ✅
**File:** `regular-investor/scripts/expire-subscriptions.js` (baru)

- [x] Query sub `active` + `end_date < CURDATE()` → set `expired`
- [x] `reconcileUserAccess()` per user terdampak (downgrade role + bersihkan features)
- [ ] Jadwalkan via cron/Docker entrypoint (operasional — saat deployment)

### Verifikasi Manual (belum dijalankan)
- [ ] Jalankan migrasi `001_terminal_tier.sql` di DB existing
- [ ] Uji: beli plan terminal → admin konfirmasi → role jadi `terminal` + `user_features` terisi
- [ ] Uji: tombol "Buka Terminal" di profil → redirect ke terminal (butuh Fase A env benar)
- [ ] Uji: jalankan `expire-subscriptions.js` → sub lewat tanggal jadi `expired`, role turun

---

## Fase C — Redis Caching (R-IDX Terminal Fase 5) ✅ SELESAI
**Tujuan:** Lindungi dari rate limit Yahoo Finance. Semua data market di-cache.

### C1. Setup Redis ✅
- [x] Service `redis` (redis:7-alpine, maxmemory 256mb, allkeys-lru) di `docker-compose.yml`
  + volume `ridx-redis`, healthcheck, `backend` depends_on redis healthy
- [x] `REDIS_URL=redis://ridx-redis:6379/0` di env backend
- [x] Dependency `redis>=5.0.0` di `requirements.txt`
- [x] `REDIS_URL` + `CACHE_TTL_OHLCV` di `config.py`

### C2. Cache Layer di Python Backend ✅
**File:** `ridx-terminal/backend/app/core/cache.py` (baru)

- [x] `get_cached(key, ttl, fetch_fn)` — two-tier: Redis (L2) → in-process (L1) → fetch
  - Graceful degradation: error Redis apa pun → fallback in-process / direct fetch
  - L1 punya per-key TTL + capacity guard (512 entri, evict expired/oldest)
  - Nilai di-pickle (mendukung DataFrame, dict, pydantic model)
  - Exception dari `fetch_fn` TIDAK di-cache (404/503 selalu fresh)
- [x] `invalidate(key)` + `invalidate_ticker(symbol)` (scan & hapus per ticker)
- [x] Refactor `yf_fetcher.py`:
  - `fetch_ohlcv()` → key `ohlcv:{symbol}:{period}`, TTL 30 menit
  - `_get_info()` (shared price+fundamental, satu `.info` call) → key `info:{symbol}`, TTL 5 menit
  - `fetch_current_price()` & `fetch_fundamental()` membaca info cache yang sama
- [x] `DELETE /api/cache/{ticker}` (protected) — `endpoints_cache.py`, didaftarkan di `main.py`

> Catatan desain: price & fundamental berasal dari satu `yf_ticker.info` call,
> jadi keduanya berbagi cache `info:{symbol}` @ 5 menit (bukan 1 jam terpisah).
> Ini lebih benar — menghindari menyajikan harga basi 1 jam — dan hemat satu
> network call. `CACHE_TTL_OHLCV` bisa diatur via env.

### Verifikasi Manual (belum dijalankan)
- [ ] `docker compose up` → cek log "Connected to Redis cache"
- [ ] Hit `/api/stock/BBCA` 2x → call kedua dari cache (cek log, tidak ada "Fetched ... rows")
- [ ] Matikan Redis → backend tetap jalan (log "Redis unavailable ... falling back")
- [ ] `DELETE /api/cache/BBCA` → call berikutnya fetch ulang dari Yahoo Finance

---

## Fase D — Watchlist & Price Alerts ✅ SELESAI
**Tujuan:** User terminal bisa simpan watchlist dan set alert harga.
Data disimpan di MariaDB RI yang sudah ada; terminal mengaksesnya lewat API RI
dengan Bearer token (lihat catatan lintas-service).

### D1. Schema Database ✅
**File:** `regular-investor/database/schema.sql` + `database/migrations/002_watchlist_alerts.sql`

- [x] Tabel `watchlists` (UNIQUE user_id+stock_code, FK CASCADE)
- [x] Tabel `price_alerts` — kolom `direction` (bukan `condition`, reserved word MySQL),
  `target_price`, `triggered`, `triggered_at`
- [x] Tabel `dss_configs` (algorithm ENUM, config_json JSON, is_default)
- [x] Migrasi 002 idempoten untuk DB existing

### D2. API Watchlist di Regular Investor ✅
**File:** `src/pages/api/user/watchlist/index.ts` + `[code].ts`, `src/lib/watchlist-queries.js`

- [x] `GET /api/user/watchlist` — semua watchlist user
- [x] `POST /api/user/watchlist` — tambah `{ stock_code, notes? }` (idempoten ON DUPLICATE KEY)
- [x] `DELETE /api/user/watchlist/:code` — hapus
- [x] Semua route: `verifyUserAuth` (Bearer/cookie) + CORS + handler `OPTIONS`

### D3. API Price Alerts di Regular Investor ✅
**File:** `src/pages/api/user/alerts/index.ts` + `[id].ts` + `check.ts`, `src/lib/alert-queries.js`

- [x] `GET /api/user/alerts` — semua alert
- [x] `POST /api/user/alerts` — buat `{ stock_code, direction, target_price }` (validasi)
- [x] `DELETE /api/user/alerts/:id` — hapus
- [x] `POST /api/user/alerts/check` — body `{ prices }`, evaluasi alert aktif,
  tandai yang terpicu, kembalikan daftar triggered

### D4. Widget Watchlist di Terminal Frontend ✅
**File:** `ridx-terminal/frontend/src/components/widgets/Watchlist.tsx` + `services/riClient.ts`

- [x] `riClient.ts` baru — panggil API RI (`VITE_RI_URL`) dengan Bearer token
- [x] Fetch watchlist user dari RI, harga live per ticker dari backend (`/quote`)
- [x] Tambah ticker (input + Enter) & hapus (× per baris)
- [x] Badge merah berkedip pada ticker yang alert-nya terpicu (via `checkAlerts`)
- [x] Endpoint backend baru `GET /api/stock/{ticker}/quote` (harga saja, tanpa indikator)

### Catatan Lintas-Service (penting untuk deployment)
- Terminal frontend memanggil **API RI langsung** (bukan via backend Python),
  karena data watchlist/alert ada di DB RI. Auth: Bearer token (sama dengan sesi RI).
- RI endpoint kini menerima Bearer **atau** cookie via `verifyUserAuth()`.
- CORS: `src/lib/cors.js` me-reflect origin dari `TERMINAL_URL` (+ localhost dev).
  Set `TERMINAL_URL` di env RI dan `VITE_RI_URL` di env frontend terminal.

### Tambahan B7 — Trial Terminal 1 Hari (24 jam) ✅ SELESAI
**Tujuan:** Pengguna bisa mencoba R-IDX Terminal gratis 24 jam sebelum berlangganan.

- [x] `plan_type` ENUM += `terminal_trial` (schema + `migrations/004_terminal_trial.sql`)
- [x] `PLANS.terminal_trial` (price 0, days 1, tier terminal, trial:true) + `TRIAL_HOURS=24`
- [x] `startTrial()` — buat subscription `terminal_trial` aktif instan (tanpa admin/bayar),
  grant `user_features` dengan **expiry presisi `NOW()+24 jam`** (bukan berbasis tanggal)
- [x] `hasUsedTrial()` + `isTrialEligible()` — 1× per akun, hanya jika belum punya akses terminal
- [x] **Enforcement presisi 24 jam** (bukan role-based):
  - Trial TIDAK mengubah `role` → akses lewat `user_features` yang auto-expire
  - Token terminal diberi field `exp` = `getTerminalAccessExpiry()` → token lama pun mati di 24 jam
  - `exp` dihormati di `user-auth.js verifyUserToken` (Bearer) DAN Python `_verify_ri_token`
- [x] `POST /api/user/trial` — wajib setuju agreement, cek eligibility
- [x] UI: tombol "Coba Gratis 1 Hari" di kartu Terminal (`pricing.astro`) untuk yang eligible;
  `profile.astro` pakai `hasTerminalAccess` (user trial lihat tombol "Buka Terminal") + hint trial

> Keputusan desain: trial pakai `user_features.expires_at` (DATETIME presisi) sebagai
> sumber kebenaran akses, bukan `role`/`end_date` (DATE). Ini membuat akses berakhir
> tepat 24 jam tanpa bergantung cron, dan field `exp` pada token menutup celah token 7-hari.

### Belum Termasuk (kandidat iterasi lanjut)
- [ ] UI manajemen alert penuh di terminal (saat ini hanya badge; CRUD alert via API sudah siap)
- [ ] `dss_configs` baru ada tabel + (belum ada API/UI) — disiapkan untuk fitur DSS terminal

### Verifikasi Manual (belum dijalankan)
- [ ] Jalankan migrasi `002_watchlist_alerts.sql`
- [ ] Set `TERMINAL_URL` (RI) + `VITE_RI_URL` (terminal) agar CORS & fetch jalan
- [ ] Tambah ticker di widget → muncul + harga live; reload → persist
- [ ] Buat alert via `POST /api/user/alerts` → saat harga lewat target, badge merah muncul

---

## Fase E — News Feed Integration ✅ SELESAI
**Tujuan:** Panel "News Feed" di terminal menampilkan berita pasar teragregasi
dari beberapa RSS (Bloomberg + media ekonomi Indonesia).

> **Perubahan desain:** rencana awal (artikel RI per-ticker) diganti menjadi
> **agregasi RSS** sesuai sumber yang diberikan user. Fetch/parse RSS ada di
> backend Python (punya cache Fase C, tanpa masalah CORS). Artikel RI per-ticker
> bisa ditambahkan kemudian sebagai feed tambahan.

### E1. RSS Aggregator di Backend Python ✅
**File:** `ridx-terminal/backend/app/services/news_fetcher.py`, `api/endpoints_news.py`

- [x] `feedparser>=6.0.0` di requirements; `NEWS_CACHE_TTL/MAX_ITEMS/PER_FEED` di config
- [x] `FEEDS`: Bloomberg Markets, Antara Ekonomi, Detik Finance, Kontan Keuangan, CNBC Indonesia
- [x] `news_fetcher.get_news(ticker?, limit?)`:
  - fetch tiap feed paralel (ThreadPoolExecutor), cache per-feed (`news:feed:<url>`, 10 mnt)
  - normalisasi (strip HTML, parse tanggal → ISO UTC), feed gagal → di-skip
  - sort terbaru dulu, filter keyword ticker opsional
- [x] Schema `NewsItem` + `NewsResponse`
- [x] `GET /api/news?ticker=&limit=` (protected) — blocking I/O via `run_in_threadpool`
- [x] Router didaftarkan di `main.py`

### E2. Widget News di Terminal Frontend ✅
**File:** `ridx-terminal/frontend/src/components/widgets/NewsFeed.tsx`

- [x] `apiClient.getNews(ticker?, limit?)` + tipe `NewsItem`/`NewsResponse`
- [x] Toggle "SEMUA" / ticker aktif (filter keyword)
- [x] Tampilkan sumber + judul + waktu relatif (baru saja / m / j / h)
- [x] Klik judul → buka artikel asli di tab baru
- [x] Wire ke `App.tsx` menggantikan placeholder

### Verifikasi
- [x] Backend lolos `py_compile`
- [x] Frontend lolos `tsc --noEmit` (seluruh proyek terminal)
- [ ] Runtime: `docker compose up` → `/api/news` mengembalikan item; cek feed yang
  kadang down (Bloomberg RSS sering dibatasi) tetap graceful (feed lain jalan)

---

## Fase F — Root Docker Compose & Deployment ✅ SELESAI
**Tujuan:** Satu file compose di `web/` untuk menjalankan seluruh ekosistem.

### F1. `web/docker-compose.yml` ✅
- [x] `db` — MariaDB shared, mount `regular-investor/database/schema.sql` + `seed.sql`, healthcheck
- [x] `redis` — Redis 7 alpine (256mb, allkeys-lru), volume `ridx_redis`, healthcheck
- [x] `app` — regular-investor (Astro), env `USER_SECRET`, `APP_URL`, `TERMINAL_URL`, `ML_ENGINE_URL`, DB, OAuth
- [x] `terminal-backend` — FastAPI OmniQuant + **Premium DSS** (port 8001), `RI_USER_SECRET=${USER_SECRET}`, `REDIS_URL`,
  CORS, **network alias `backend`** (agar nginx internal frontend `proxy_pass http://backend:8001` resolve)
- [x] `terminal-frontend` — React→Nginx, build-arg `VITE_RI_URL`/`VITE_API_URL`
- [x] `nginx` — reverse proxy publik (host-based)
- [x] Network `apps_net` `172.20.10.0/28`; volumes db/redis/ridx_models/ridx_data

> ✅ KONSOLIDASI ENGINE (lihat Fase J) — **satu engine Python** di `terminal-backend`:
> - `/api/v1/analyze|quote|quotes/batch|fundamentals` → **Premium DSS** RI
>   (`api/premium/dss/run.ts` → `dss-hybrid`, `lib/stock.js`, `fundamental-fetcher.js`)
> - `/api/stock|predict|news|market` → **R-IDX Terminal**
>
> `regular-investor/ml-engine` (engine kedua) **sudah dihapus**. `app` memanggil DSS
> via `ML_ENGINE_URL=http://terminal-backend:8001`. `src/lib/dss.js` (versi JS) tetap tidak dipakai.

### F2. Env & standalone compose ✅
- [x] `web/.env.example` — semua variabel (USER_SECRET, DB, APP_URL, TERMINAL_URL, OAuth)
- [x] `regular-investor/docker-compose.yml` — tambah `TERMINAL_URL`
- [x] `ridx-terminal/docker-compose.yml` — `RI_USER_SECRET` + `REDIS_URL` (sudah dari Fase A/C)
- [x] `ridx-terminal/frontend/Dockerfile` — ARG/ENV `VITE_RI_URL`, `VITE_API_URL`

### F3. Nginx Reverse Proxy ✅
**File:** `web/nginx/nginx.conf`

- [x] `regular-investor.com` → `app:4321`
- [x] `terminal.regular-investor.com` → `terminal-frontend:80` (yang mem-proxy `/api` → `backend:8001`)
- [x] Default server tolak host tak dikenal (`return 444`)
- [ ] SSL termination (produksi — tambah listen 443 + cert saat deploy)

### Verifikasi
- [x] Ketiga compose lolos parse YAML (root: db, redis, app, terminal-backend, terminal-frontend, nginx)
- [ ] `docker compose up -d --build` (perlu Docker; tidak tersedia di environment dev ini)
- [ ] Set domain di hosts (lokal) atau DNS (produksi); isi `.env` dari `.env.example`

> Catatan: untuk lokal tanpa domain, akses langsung via port: app `:3000`,
> terminal `:3001`, backend `:8001`. Nginx host-based untuk produksi/domain.

---

## Fase G — ML Model Training (One-time + Periodic) ✅ SELESAI
**Tujuan:** Model XGBoost + LightGBM terlatih dengan data IDX nyata.
Backend kini berjalan dalam **mode ML** (model `.pkl` terlatih & tersimpan).

> **Perbaikan pipeline (prasyarat sebelum training jalan benar):**
> - **Path model dibetulkan** → `backend/models/` (cocok dengan Docker volume
>   `ridx_models:/app/models` & verifikasi G1). Sebelumnya tersebar ke
>   `backend/app/models/` sehingga model tak ikut ter-persist di Docker.
>   Path kini terpusat di `app/ml_engine/paths.py` (anchored ke `__file__`,
>   bekerja terlepas dari CWD) dan dipakai trainers/ensemble/omniquant/auto_train.
> - **Sumber ticker dibetulkan** → `auto_train` memuat `Daftar Saham *.xlsx`
>   (957 ticker), bukan fallback 50-nama hardcoded.
> - **Bug kontaminasi data dibetulkan** → registry IDX kini di-prime dari xlsx
>   SEBELUM fetch, agar `normalize_ticker()` menambahkan `.JK` untuk semua kode.
>   Tanpa ini, kode di luar 50-nama gagal 404 (mis. ARTO, ISAT) atau lebih buruk
>   menarik saham US bernama sama (mis. CTRA) → data training tercemar diam-diam.

### G1. Jalankan Training Pertama Kali ✅
**File:** `ridx-terminal/backend/app/ml_engine/auto_train.py` + `paths.py` (baru)

- [x] `.JK` tickers dari `Daftar Saham *.xlsx` diverifikasi benar (957 ticker,
  registry di-prime sebelum fetch)
- [x] Jalankan dari `ridx-terminal/backend/`:
  `python -m app.ml_engine.auto_train [--universe liquid|lq45|bisnis27|kompas100|all] [--tickers ...] [--limit N] [--period 5y]`
  - Step 1: Fetch OHLCV (default 5y) per ticker IDX
  - Step 2: Hitung 22 indikator teknikal per ticker (skip 200 baris awal SMA200)
  - Step 3: Simpan ke `backend/data/training_data.csv`
  - Step 4: Training XGBoost + LightGBM + Ensemble (stacking LogReg)
  - Step 5: Simpan `.pkl` ke `backend/models/`
- [x] Verifikasi: `backend/models/{xgb_model,lgbm_model,ensemble_meta}.pkl` tersedia
- [x] Test: prediksi BBCA → **ML mode** (XGB/LGBM proba nyata, bukan mock)

> **Universe training = konstituen indeks likuiditas IDX (bukan seluruh ~957).**
> Bursa Indonesia banyak saham tidak likuid / "gorengan" yang harganya digerakkan
> bandar — pola teknikalnya menyesatkan model. Karena itu universe dibatasi ke
> konstituen indeks resmi yang dikurasi IDX (likuiditas + kapitalisasi + tata kelola):
> - `LQ45` (45), `BISNIS27` (27), `KOMPAS100` (100) → di `services/idx_tickers.py`
> - `LIQUID_UNIVERSE` = union ketiganya = **100 nama** (LQ45 & Bisnis27 ⊂ Kompas100)
> - Default `--universe liquid`. `--universe all` tetap tersedia untuk ~957 (hati-hati).
>
> Catatan: pakai keanggotaan indeks lebih benar daripada filter harga mentah —
> mis. GOTO sempat di Rp50 (gocap) tapi sangat likuid; filter "harga>50" naif akan
> salah membuangnya. List di-snapshot 2026-06, refresh tiap kuartal dari IDX.
>
> Smoke test awal (LQ45, ~42 ticker, 44.200 baris): XGBoost acc **0.755** /
> AUC **0.837**, LightGBM 0.752, Ensemble 0.753 (bobot learned XGB 0.63 / LGBM 0.37).

### G2. Jadwalkan Re-training Periodik ✅
**File:** `ridx-terminal/backend/scripts/retrain_cron.sh` (baru)

- [x] Script `retrain_cron.sh` — pilih venv/python otomatis, jalankan `auto_train`,
  dukung `LIMIT`/`PERIOD` via env
- [x] Backup model lama (`models/backup_<timestamp>/`) sebelum overwrite;
  **restore otomatis jika training gagal**
- [x] Contoh crontab (per 3 bulan) terdokumentasi di header script
- [x] Docker: `terminal-backend` kini mount xlsx (`/app/data/Daftar Saham.xlsx`)
  + env `IDX_TICKERS_FILE` agar retraining di kontainer pakai universe penuh
- [ ] Aktifkan jadwal di scheduler produksi (operasional — saat deployment)

### Verifikasi Manual (belum dijalankan)
- [ ] Jalankan `auto_train` untuk universe penuh ~957 ticker (one-time, di server)
- [ ] `docker compose up` → cek log "OmniQuant ML Models successfully loaded"
- [ ] `GET /api/predict/BBCA` via API → field menunjukkan ML mode (bukan `[Mock Engine Active]`)

---

## Fase H — Polish & Monitoring
**Tujuan:** Kesiapan production — error handling, logging, monitoring dasar.

### H1. Error Handling & Edge Cases
- [ ] regular-investor: Halaman `/pricing?error=subscription_expired` untuk user yang akses terminal tapi subscription sudah expired
- [ ] Terminal frontend: Graceful degradation jika backend tidak tersedia (tampilkan pesan, bukan crash)
- [ ] Backend Python: Fallback ke heuristic mode jika model `.pkl` tidak ditemukan (sudah ada, verifikasi)
- [ ] Backend Python: Rate limit handling dari yfinance — retry dengan backoff eksponensial

### H2. Logging
- [ ] regular-investor: Log setiap akses `/api/terminal/access-token` dengan userId dan timestamp
- [ ] Terminal backend: Log setiap request yang ditolak karena auth (401/403) dengan userId dari token

### H3. Admin Dashboard Tambahan di RI
- [ ] Statistik subscriber Terminal (berapa aktif, berapa expired bulan ini)
- [ ] Tombol manual trigger "expire subscription" untuk admin

---

## Subscription Agreement (tambahan, di luar fase A–H) ✅ SELESAI
**Tujuan:** Sebelum membayar (Premium maupun Terminal), pengguna wajib melihat
& menyetujui Perjanjian Berlangganan; persetujuan direkam ke DB.

- [x] `src/data/agreement.js` — sumber kebenaran: 11 pasal + `AGREEMENT_VERSION`,
  `PROVIDER_NAME` (Regular Investor), `JURISDICTION_CITY`, `RISK_SUMMARY`, `PREAMBLE`
  - Pasal kunci: disclaimer risiko trading (Pasal 6), pembatasan tanggung jawab +
    cap nominal (Pasal 7), akurasi data pihak ketiga (Pasal 8), penghentian layanan
    (Pasal 10), force majeure & hukum (Pasal 11)
- [x] `src/components/AgreementModal.astro` — modal scrollable + checkbox wajib,
  expose `window.requireAgreement(): Promise<boolean>` & `window.AGREEMENT_VERSION`
- [x] `src/pages/syarat-langganan.astro` — halaman penuh dapat dibaca (publik)
- [x] Gate di checkout: `pricing.astro` (Premium+Terminal) & `premium/subscribe.astro`
  → `await requireAgreement()` sebelum POST; kirim `agreed` + `agreementVersion`
- [x] `subscribe.ts` — tolak jika `!agreed`; pakai versi server (anti-spoof), 409 jika versi klien usang
- [x] `createSubscription(userId, planType, { agreementVersion })` — wajib versi, simpan `agreed_at`
- [x] Schema + `migrations/003_subscription_agreement.sql` — kolom `agreement_version`, `agreed_at`

> Catatan: `JURISDICTION_CITY = 'Jakarta Selatan'` & redaksi pasal = template,
> perlu dikonfirmasi/ditinjau pengacara. Pasal pembayaran menyebut recurring
> (sesuai permintaan), walau sistem transfer saat ini masih manual.

### Verifikasi Manual (belum dijalankan)
- [ ] Jalankan migrasi `003_subscription_agreement.sql`
- [ ] Checkout Premium & Terminal → modal agreement muncul, tombol bayar terkunci
  sampai checkbox dicentang
- [ ] Cek baris `subscriptions` punya `agreement_version` + `agreed_at` terisi

---

## Fase I — Market Overview Home & Halaman Saham Bertab ✅ SELESAI
**Tujuan:** Halaman utama terminal tidak langsung menampilkan satu emiten (BBCA),
melainkan ringkasan pasar (indeks global/Asia + top gainers/losers IDX). Saat
pengguna mencari saham, tampil halaman bertab (Overview / Technicals / News)
dengan period selector — Technicals lengkap bergaya Bloomberg.

**Status:** Implementasi selesai. Backend lolos `py_compile`; frontend lolos
`tsc --noEmit` (tsconfig.app.json). Runtime/Docker = "Verifikasi Manual" di bawah.

### I1. Backend — Market Overview ✅
**File:** `ridx-terminal/backend/app/api/endpoints_market.py` (baru),
`services/yf_fetcher.py`, `services/idx_tickers.py`

- [x] `GET /api/market/indices` — IHSG (^JKSE), Nikkei, Hang Seng, Straits Times,
  S&P 500, NASDAQ. Reuse `fetch_current_price` (simbol `^...` lolos `normalize_ticker`),
  cache `market:indices` 5 menit
- [x] `GET /api/market/movers?limit=5` — top gainers/losers LQ45. Helper
  `fetch_change_batch()` (satu `yf.download(period=2d)`, cache 5 menit) + konstanta `LQ45_TICKERS`
- [x] Skema `IndexQuote`, `Mover`, `MoversResponse`; router didaftarkan di `main.py`

### I2. Backend — Technicals ✅
**File:** `ridx-terminal/backend/app/api/endpoints_technicals.py` (baru),
`services/technicals.py` (baru), `models/schemas.py`

- [x] `GET /api/stock/{ticker}/technicals?period=6mo` — satu payload untuk tab Technicals,
  cache `technicals:{symbol}:{period}` (TTL OHLCV)
- [x] `services/technicals.py`: `build_series` (OHLCV + SMA20/50, Bollinger, RSI, MACD,
  volume MA20), `compute_signal` (agregasi 8 indikator → BUY/NEUTRAL/SELL + overall),
  `compute_momentum` (5D/20D/60D, ATR, vol ratio), `compute_moving_averages`,
  `compute_pivots` (pivot classic), `compute_fibonacci`
- [x] Skema: `TechnicalsPoint/Response`, `SignalItem/TechnicalSignal`, `MomentumStats`,
  `MovingAverageItem`, `PivotPoints`, `FibonacciLevel(s)`; reuse `preparator.compute_all_indicators`

### I3. Frontend — Home & Tabs ✅
**File:** `ridx-terminal/frontend/src/components/views/*`, `charts/*`, `store/terminalStore.ts`,
`App.tsx`, `services/apiClient.ts`

- [x] `activeTicker` jadi `string | null` (default `null` = home) + `goHome()`; `App.tsx`
  jadi router tipis (null → `MarketOverview`, selain itu → `StockPage`)
- [x] `MarketOverview.tsx` — baris indeks + tabel Top Gainers/Losers (klik baris → buka saham) + News
- [x] `StockPage.tsx` — header (EQ, ticker, nama, harga, %chg, currency, exchange) + period
  selector (1MO–MAX, default 6MO) + REFRESH + tab bar (OVERVIEW / FINANCIALS-disabled / TECHNICALS / NEWS)
- [x] `tabs/OverviewTab.tsx` — grid lama (chart period-aware + MarketStats + MLSignal + TechIndicators + Watchlist)
- [x] `tabs/TechnicalsTab.tsx` — 4 chart (Price/BB, RSI, MACD, Volume) + Technical Signal +
  Momentum & Volatility + Moving Averages + Support/Resistance + Fibonacci
- [x] `charts/LineChart.tsx` & `charts/HistogramChart.tsx` — wrapper lightweight-charts reusable
- [x] `apiClient`: `getIndices`, `getMovers`, `getTechnicals` + tipe terkait
- [x] `TopBar` logo → `goHome()`, tampilkan `MARKETS` saat home; `NewsFeed` sembunyikan
  toggle per-ticker saat home
- [x] `StockDashboard.tsx` lama diserap ke `OverviewTab.tsx` (dihapus)

### Tab FINANCIALS — Ditunda
- [ ] Konten Financials (cashflow, balance sheet, margin detail, target harga) — perlu ekspansi
  `FundamentalData` + `fetch_fundamental`; saat ini tab ditampilkan nonaktif ("Segera")

### Verifikasi Manual (belum dijalankan)
- [ ] `GET /api/market/indices` & `/api/market/movers?limit=5` mengembalikan data (cache hit di call ke-2)
- [ ] `GET /api/stock/BBCA/technicals?period=6mo` → series + signal + momentum + MA + pivot + fibonacci
- [ ] Buka terminal → Market Overview (bukan BBCA); klik gainer/loser → StockPage
- [ ] Cari BBCA → tab OVERVIEW & TECHNICALS tampil; ubah period → chart/angka berubah
- [ ] `docker compose up -d --build terminal-backend terminal-frontend`

---

## Fase J — Konsolidasi Engine ML (DSS → terminal-backend) ✅ SELESAI
**Tujuan:** Hilangkan engine Python ganda. Premium DSS RI dipindah ke
`terminal-backend` sebagai router `/api/v1/*`, lalu `regular-investor/ml-engine`
dihapus. Satu backend Python untuk OmniQuant + DSS.

### J1. Port DSS ke terminal-backend ✅
**File:** `ridx-terminal/backend/app/dss/` (baru) + `app/api/endpoints_dss.py`

- [x] `features.py` (compute_all_features + FEATURE_COLUMNS DSS), `scoring.py`
  (technical/fundamental/ml/risk), `decision.py` (AHP/TOPSIS/SAW + `run_full_analysis`)
  — port verbatim dari `ml-engine/data_service.py` (paritas output)
- [x] `data.py` — adapter ke `yf_fetcher` terminal (reuse Redis cache, mapping
  kolom OHLCV lowercase + fundamental key RI: roe/npm/dividendYield ×100)
- [x] `ml.py` — inferensi XGB+LGBM+Ensemble (reuse trainer terminal); **LSTM dibuang**
  (sudah nonaktif di engine lama). Model `dss_*.pkl` terpisah dari OmniQuant
- [x] `train.py` — latih model DSS pada universe 100-likuid (split kronologis)
- [x] `endpoints_dss.py` — `/api/v1/analyze` (GET+POST/CSV), `/quote`, `/quotes/batch`,
  `/fundamentals`; **internal, tanpa auth** (dipanggil server-to-server seperti ml-engine dulu)
- [x] Router didaftarkan + model DSS di-load saat startup (`main.py`)

### J2. Repoint Regular Investor ✅
- [x] 4 file klien (`dss-hybrid/index.js`, `fundamental-fetcher.js`, `lib/stock.js`,
  `api/premium/dss/run.ts`) → `ML_ENGINE_URL` default `http://terminal-backend:8001`
- [x] Root `docker-compose.yml`: `app.ML_ENGINE_URL=http://terminal-backend:8001`,
  `depends_on: terminal-backend`

### J3. Bongkar ml-engine ✅
- [x] Hapus service `ml_engine` + volume `ri_ml_models`/`ri_ml_data` + mount xlsx (kedua compose)
- [x] Hapus folder `regular-investor/ml-engine/`
- [x] Update `DEPLOY.md` (arsitektur, §8 training, troubleshooting, catatan konsolidasi) + TASKS F1

> Catatan: model DSS ~0.55 AUC (realistis untuk arah harian; ML hanya 1 dari 4
> kriteria). `dividendYield ×100` adalah quirk warisan yfinance yang dipertahankan
> demi paritas. Bug `der`/`currentRatio = None` untuk bank juga sama seperti engine lama.

### Verifikasi Manual (belum dijalankan — perlu Docker)
- [ ] `docker compose up -d --build app terminal-backend`
- [ ] `curl http://localhost:8001/api/v1/analyze/BBCA` → `{"ok":true,...}`
- [ ] Login Premium → Analisis DSS jalan (via terminal-backend); harga portfolio ter-sync
- [ ] `docker compose exec terminal-backend python -m app.dss.train` → model DSS terlatih

---

## Prioritas Eksekusi

```
Minggu 1-2:  Fase A (Auth Integration) ← paling kritikal, semua bergantung ini
Minggu 3:    Fase B (Terminal Subscription di RI)
Minggu 4:    Fase C (Redis Caching) + Fase G (ML Training)
Minggu 5-6:  Fase D (Watchlist & Alerts)
Minggu 7:    Fase E (News Feed) + Fase F (Root Docker Compose)
Minggu 8:    Fase H (Polish & Monitoring)
```

---

## Catatan Teknis Penting

### Token Format (shared antara RI dan Terminal)
Token yang dihasilkan `user-auth.js` di RI:
```
base64(
  JSON.stringify({
    data: JSON.stringify({ userId, email, name, role, features[], ts }),
    sig:  hmac_sha256_base64(data, USER_SECRET)
  })
)
```
Python backend harus decode format ini persis (bukan JWT standar).
Lihat `regular-investor/src/lib/user-auth.js` fungsi `createUserToken()` dan `verifyUserToken()`.

### Lightweight Charts v5 Breaking Change
Di `TvChart.tsx`, API v5 berbeda dari v4:
```typescript
// v4 (JANGAN gunakan):
chart.addCandlestickSeries(options)

// v5 (BENAR):
import { CandlestickSeries } from 'lightweight-charts'
chart.addSeries(CandlestickSeries, options)
```

### IDX Ticker Convention
Backend Python otomatis menambahkan suffix `.JK` untuk ticker IDX.
Contoh: `BBCA` → `BBCA.JK` saat request ke yfinance.
Jangan tambahkan `.JK` dari frontend — biarkan backend yang handle.

### pandas-ta di Python 3.13
pandas-ta versi `0.3.14b1` memerlukan pin numpy `<2.0` untuk kompatibilitas.
Jika ada error, tambahkan `numpy<2.0` ke `requirements.txt`.
