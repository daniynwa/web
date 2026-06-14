# Regular Investor Ecosystem

Platform investasi Indonesia yang terdiri dari dua layanan terintegrasi: portal berita & analisis **Regular Investor** dan terminal data pasar saham **R-IDX Terminal**.

---

## Gambaran Sistem

```
                        INTERNET
                           │
              ┌────────────┴────────────┐
              │         Nginx           │
              │   (Reverse Proxy)       │
              └──────┬──────────┬───────┘
                     │          │
          :3000       │          │  :3001
    regular-investor  │          │  ridx-terminal (frontend)
                      │          │
    ┌─────────────────▼──┐  ┌───▼──────────────────────┐
    │  regular-investor  │  │   ridx-terminal/frontend  │
    │  Astro v6 + SSR    │  │   React 19 + Vite 8       │
    │  Node.js           │  │   Nginx (serve static)    │
    │                    │  └───────────┬───────────────┘
    │  ✅ Auth (SSO Hub)  │              │ API calls
    │  ✅ Subscriptions   │              │ Bearer token
    │  ✅ News & Articles │  ┌───────────▼───────────────┐
    │  ✅ Portfolio       │  │   ridx-terminal/backend   │
    │  ✅ Premium DSS     │  │   Python FastAPI :8001    │
    │     (→ ml_engine)  │  │   (OmniQuant terminal)    │
    │  ✅ Admin Panel     │  │  ✅ Market Data (YFinance) │
    │                    │  │  ✅ 22 Technical Indicators│
    └────────┬───────────┘  │  ✅ OmniQuant ML Engine   │
             │  token        │     XGBoost + LightGBM   │
             │  verify       │  ⬜ Auth Middleware       │
             └──────────────►│  ⬜ Redis Caching         │
                            └───────────────────────────┘
                                         │
                    ┌────────────────────┴──────────────┐
                    │          MariaDB (Shared)          │
                    │          :3306 (internal)          │
                    │                                    │
                    │  users, subscriptions, portfolios  │
                    │  articles, watchlists, alerts      │
                    │  dss_configs, user_features        │
                    └────────────────────────────────────┘
```

---

## Struktur Direktori

```
web/
├── README.md                   ← dokumen ini
├── TASKS.md                    ← roadmap & status seluruh ekosistem
├── docker-compose.yml          ← compose untuk semua service (dibuat di fase integrasi)
│
├── regular-investor/           ← Astro v6 SSR — Auth, News, Subscription
│   ├── src/
│   │   ├── lib/
│   │   │   ├── user-auth.js    ← HMAC token auth (SSO hub)
│   │   │   ├── subscription.js ← plan management + trial
│   │   │   ├── dss-hybrid/     ← thin client ke ml-engine RI (/api/v1/analyze)
│   │   │   ├── dss.js          ← AHP/SAW/TOPSIS (JS, LEGACY — tidak dipakai)
│   │   │   └── stock.js        ← harga portfolio (→ ml-engine RI)
│   │   ├── pages/
│   │   │   ├── api/user/       ← login, register, me, subscription, trial
│   │   │   ├── api/premium/dss ← analisis premium (→ ml-engine RI :8000)
│   │   │   ├── api/admin/      ← artikel, subscriptions, users
│   │   │   └── api/portfolio/  ← CRUD portfolio
│   ├── ml-engine/             ← Python engine RI (:8000) — DSS premium + quotes
│   ├── database/
│   │   ├── schema.sql
│   │   └── seed.sql
│   └── docker-compose.yml      ← compose lokal RI (akan digantikan root compose)
│
└── ridx-terminal/              ← Bloomberg-inspired IDX Terminal
    ├── backend/                ← Python FastAPI + ML Engine
    │   ├── app/
    │   │   ├── api/            ← endpoints_stock.py, endpoints_predict.py
    │   │   ├── ml_engine/      ← omniquant.py, trainers.py, ensemble.py
    │   │   ├── services/       ← yf_fetcher.py, preparator.py, idx_tickers.py
    │   │   └── core/           ← config.py (+ auth.py akan ditambahkan)
    │   ├── models/             ← xgb_model.pkl, lgbm_model.pkl (dihasilkan auto_train)
    │   └── data/               ← training_data.csv (dihasilkan auto_train)
    ├── frontend/               ← React 19 + Vite 8 + Tailwind v4
    │   └── src/
    │       ├── components/
    │       │   ├── charts/     ← TvChart.tsx (lightweight-charts v5)
    │       │   ├── layout/     ← TopBar, GridPanel, StatusBar
    │       │   └── widgets/    ← MarketStats, MLSignal, TechIndicators, Watchlist
    │       ├── services/       ← apiClient.ts
    │       └── store/          ← terminalStore.ts (Zustand v5)
    └── docker-compose.yml      ← compose lokal terminal
```

---

## Subscription Tiers

| Tier | Harga | Akses |
|---|---|---|
| **free** | Gratis | Berita publik |
| **premium** (bulanan) | Rp 50.000/bln | + Artikel premium + OmniQuant DSS (RI) |
| **premium** (tahunan) | Rp 600.000/thn | Sama, hemat 2 bulan |
| **terminal** (bulanan) | Rp 150.000/bln | Semua premium + R-IDX Terminal penuh |
| **terminal** (tahunan) | Rp 1.500.000/thn | Sama, hemat 2 bulan |

---

## Tech Stack

| Komponen | Teknologi | Versi |
|---|---|---|
| regular-investor frontend | Astro + Tailwind CSS | v6 + v4 |
| regular-investor backend | Node.js + `@astrojs/node` | ≥22.12.0 |
| ridx-terminal frontend | React + Vite + Tailwind CSS | 19 + 8 + v4 |
| ridx-terminal charts | lightweight-charts | v5 |
| ridx-terminal state | Zustand | v5 |
| ridx-terminal backend | Python FastAPI + Uvicorn | Python 3.13 |
| ML Engine | XGBoost + LightGBM + scikit-learn | 2.x + 4.x |
| Technical Indicators | pandas-ta | 0.3.14b1 |
| Market Data | yfinance | ≥0.2.40 |
| Database | MariaDB | latest |
| Cache | Redis | 7 alpine |
| Container | Docker Compose | v2 |

---

## API Endpoints

### Regular Investor (Node.js)
```
POST /api/user/register          Daftar akun baru
POST /api/user/login             Login email/password
GET  /api/user/me                Info user + status subscription
POST /api/user/logout            Logout (hapus cookie)
GET  /api/user/auth/google       Mulai Google OAuth flow
GET  /api/user/subscription      Status subscription aktif

POST /api/user/subscription/create   Buat order subscription baru
GET  /api/terminal/access-token      Token untuk redirect ke terminal (auth)

GET  /api/admin/subscriptions        Daftar semua subscription (admin)
POST /api/admin/subscriptions/:id    Konfirmasi/cancel subscription
GET  /api/admin/users                Manajemen user (admin)
```

### R-IDX Terminal Backend (Python FastAPI)
```
GET  /api/stock/{ticker}             Harga + fundamental + 22 indikator
GET  /api/stock/{ticker}/history     OHLCV historis (1mo/3mo/6mo/1y/2y/5y)
GET  /api/stock/{ticker}/indicators  22 indikator teknikal saja
GET  /api/stock/{ticker}/dashboard   Payload lengkap untuk UI terminal
GET  /api/predict/{ticker}           OmniQuant ML prediction (BUY/HOLD/SELL)
GET  /api/health                     Health check
```

---

## Variabel Environment

Buat file `.env` di root `web/` (atau di masing-masing project):

```bash
# ── Shared Secret (HARUS sama di kedua service) ──────────────────────
USER_SECRET=ganti_string_acak_min_32_karakter
ADMIN_SECRET=ganti_string_admin_acak
INTERNAL_SECRET=token_rahasia_inter_service

# ── Database ─────────────────────────────────────────────────────────
DB_ROOT_PASSWORD=root_password
DB_USER=ri_user
DB_PASSWORD=db_password_aman

# ── App URLs ─────────────────────────────────────────────────────────
APP_URL=https://regular-investor.com
TERMINAL_URL=https://terminal.regular-investor.com

# ── Google OAuth ─────────────────────────────────────────────────────
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
```

---

## Development: Menjalankan Lokal

### Regular Investor
```bash
cd regular-investor
npm install
npm run dev          # http://localhost:4321
```

### R-IDX Terminal Backend
```bash
cd ridx-terminal/backend
python -m venv .venv
.venv/Scripts/activate      # Windows
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

### R-IDX Terminal Frontend
```bash
cd ridx-terminal/frontend
npm install
npm run dev          # http://localhost:3000 → proxy ke backend :8001
```

### Docker (Semua Service)
```bash
cd web
docker compose up -d
```

---

## Training ML Model

Jalankan sekali sebelum deployment atau saat ingin update model:

```bash
cd ridx-terminal
python -m backend.app.ml_engine.auto_train
# atau hanya fetch data:
python -m backend.app.ml_engine.auto_train --fetch-only
# atau hanya training dari CSV yang sudah ada:
python -m backend.app.ml_engine.auto_train --train-only
```

Model tersimpan di `ridx-terminal/backend/models/*.pkl`.

---

## Status Pengembangan

Lihat [TASKS.md](./TASKS.md) untuk status lengkap setiap fase.

| Komponen | Status |
|---|---|
| Regular Investor: core platform | Produksi |
| Regular Investor: premium articles | Produksi |
| Regular Investor: portfolio tracker | Produksi |
| Regular Investor: DSS AHP/SAW/TOPSIS | Produksi |
| R-IDX Terminal: backend + ML engine | Selesai (Fase 1-4) |
| R-IDX Terminal: frontend UI | Selesai (Fase 1-4) |
| Integrasi Auth antar service (Fase A) | Selesai |
| Terminal subscription tier di RI (Fase B) | Selesai |
| Trial Terminal 24 jam | Selesai |
| Subscription Agreement (gate checkout) | Selesai |
| Redis caching terminal (Fase C) | Selesai |
| Watchlist & Price Alerts (Fase D) | Selesai |
| News Feed RSS (Fase E) | Selesai |
| Root Docker Compose + Nginx (Fase F) | Selesai |
| ML model training (Fase G) | Belum dimulai |
