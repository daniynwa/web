# Deployment Guide — Regular Investor Ecosystem (DEV)

Panduan men-deploy seluruh ekosistem (Regular Investor + R-IDX Terminal) ke
sebuah server DEV menggunakan **Docker Compose**. Ditujukan untuk pengujian
fungsi & fitur sebelum produksi.

> Baca bersama [README.md](./README.md) (arsitektur) dan [TASKS.md](./TASKS.md) (status fitur).

---

## 1. Arsitektur yang Di-deploy

Satu file [`docker-compose.yml`](./docker-compose.yml) di root menjalankan 7 service:

| Service | Image/Build | Port (host:container) | Fungsi |
|---|---|---|---|
| `db` | mariadb:latest | `3306:3306` | Database bersama |
| `redis` | redis:7-alpine | — (internal) | Cache terminal backend |
| `app` | `./regular-investor` | `3000:4321` | Regular Investor (Astro SSR) — auth, news, subs |
| `ml_engine` | `./regular-investor/ml-engine` | — (internal :8000) | **Engine RI**: DSS premium + harga portfolio |
| `terminal-backend` | `./ridx-terminal/backend` | `8001:8001` | **Engine Terminal**: OmniQuant (XGBoost/LightGBM) |
| `terminal-frontend` | `./ridx-terminal/frontend` | `3001:80` | UI Terminal (React→Nginx) |
| `nginx` | nginx:alpine | `80:80` | Reverse proxy host-based |

> ⚠️ **Dua engine ML terpisah** (lihat README). `ml_engine` (:8000) melayani
> analisis Premium di regular-investor. `terminal-backend` (:8001) melayani
> R-IDX Terminal. Keduanya wajib hidup.

Network: `apps_net` (`172.20.10.0/28`). Volume persisten: `ri_db_data`,
`ridx_redis`, `ridx_models`, `ridx_data`, `ri_ml_models`, `ri_ml_data`.

---

## 2. Prasyarat Server

- Linux x86_64 (Ubuntu 22.04+ disarankan)
- **Docker Engine 24+** & **Docker Compose v2** (`docker compose version`)
- RAM **minimal 4 GB** (8 GB disarankan — ML training berat), disk ≥ 20 GB
- Port host bebas: `80`, `3000`, `3001`, `3306`, `8001`
- Git

```bash
# Instal Docker (Ubuntu)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # logout/login agar berlaku
docker compose version
```

---

## 3. Clone & Struktur

```bash
git clone <repo-url> web
cd web
ls    # harus ada: docker-compose.yml, .env.example, nginx/, regular-investor/, ridx-terminal/
```

---

## 4. Konfigurasi Environment

```bash
cp .env.example .env
nano .env
```

Isi minimal yang **wajib** diganti:

```env
# Secret HMAC sesi (KRITIS). RI_USER_SECRET di terminal-backend otomatis
# di-set = USER_SECRET oleh compose, jadi cukup isi sini sekali.
USER_SECRET=<random 32+ char>
ADMIN_SECRET=<random 32+ char>
ADMIN_PASSWORD=<password admin kuat>

# Database
DB_ROOT_PASSWORD=<kuat>
DB_PASSWORD=<kuat>

# URL publik (dipakai OAuth redirect, CORS terminal, dan DI-BAKE ke frontend)
APP_URL=http://<IP-atau-domain-DEV>:3000
TERMINAL_URL=http://<IP-atau-domain-DEV>:3001

# Opsional: Google OAuth
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
```

Generate secret acak:
```bash
openssl rand -hex 32
# atau: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

> **Penting soal `APP_URL`:** nilai ini di-_bake_ ke build frontend terminal
> (`VITE_RI_URL`) untuk panggilan lintas-origin (watchlist/alerts). Jika diubah,
> **terminal-frontend harus di-build ulang** (lihat §9).

---

## 5. (Produksi/Domain) DNS & Nginx Host-based — Opsional di DEV

Untuk DEV cepat, **lewati ini** dan akses langsung via port (`:3000`, `:3001`).
Untuk uji routing nginx dengan subdomain, arahkan DNS atau `/etc/hosts`:

```
<IP-server>  regular-investor.local  terminal.regular-investor.local
```
Lalu sesuaikan `server_name` di [`nginx/nginx.conf`](./nginx/nginx.conf) dan akses
`http://regular-investor.local` / `http://terminal.regular-investor.local`.

---

## 6. Build & Jalankan

```bash
docker compose up -d --build
docker compose ps        # semua service "running"/"healthy"
```

Saat **pertama** kali, `db` otomatis menjalankan `regular-investor/database/schema.sql`
+ `seed.sql` (skema lengkap sudah termasuk semua tabel: user_features, watchlists,
price_alerts, dss_configs, kolom agreement, plan trial).

Pantau startup:
```bash
docker compose logs -f db          # tunggu "ready for connections"
docker compose logs -f ml_engine   # start lambat (~60s), tunggu uvicorn ready
docker compose logs -f terminal-backend
```

---

## 7. Migrasi Database (hanya untuk DB yang SUDAH ADA)

Jika `db` adalah instance baru (volume kosong), **lewati** — `schema.sql` sudah
membuat semuanya. Jika Anda memasang ke DB lama yang sudah berisi data, jalankan
migrasi berurutan:

```bash
for m in 001_terminal_tier 002_watchlist_alerts 003_subscription_agreement 004_terminal_trial; do
  docker compose exec -T db sh -c \
    'mariadb -u root -p"$MYSQL_ROOT_PASSWORD" regular_investor' \
    < regular-investor/database/migrations/${m}.sql
  echo "applied: ${m}"
done
```

---

## 8. Training Model ML

Saat awal, kedua engine berjalan dalam **mode mock/heuristik** sampai model `.pkl`
dilatih. Model disimpan di volume (persisten lintas restart).

### 8a. Engine Regular Investor (`ml_engine`) — DSS Premium
```bash
# Masuk ke container dan jalankan pipeline auto-train
docker compose exec ml_engine python auto_trainer.py            # fetch + train
# opsi:
docker compose exec ml_engine python auto_trainer.py --fetch-only
docker compose exec ml_engine python auto_trainer.py --train-only
```
- Membaca daftar ticker dari `data/Daftar Saham.xlsx` (sudah di-mount).
- Output model → volume `ri_ml_models` (`/app/models`), data → `ri_ml_data` (`/app/data`).
- Proses fetch ~900 ticker bisa lama (rate-limit yfinance) — biarkan berjalan.

### 8b. Engine Terminal (`terminal-backend`) — OmniQuant *(opsional, Fase G)*
```bash
docker compose exec terminal-backend python -m app.ml_engine.auto_train
```
> Catatan: path internal `auto_train.py` mengacu ke `backend/...`; bila error path,
> ini bagian Fase G yang belum difinalkan. Untuk DEV sekarang fokus ke 8a.

Setelah training, restart agar model dimuat ke memori:
```bash
docker compose restart ml_engine terminal-backend
```

---

## 9. Rebuild Setelah Perubahan

```bash
# Perubahan kode RI (app)
docker compose up -d --build app

# Perubahan terminal backend
docker compose up -d --build terminal-backend

# Perubahan terminal frontend ATAU mengubah APP_URL (VITE_RI_URL di-bake!)
docker compose up -d --build terminal-frontend

# Perubahan ml-engine RI
docker compose up -d --build ml_engine
```

---

## 10. Verifikasi Tiap Fitur (Smoke Test)

```bash
# 1. Health engine
curl -fsS http://localhost:8001/api/health        # terminal-backend → {"status":"ok",...}
docker compose exec ml_engine curl -fsS http://localhost:8000/health   # ml_engine RI

# 2. Regular Investor hidup
curl -fsSI http://localhost:3000/                 # 200
curl -fsSI http://localhost:3000/pricing          # halaman paket + agreement
curl -fsSI http://localhost:3000/syarat-langganan # perjanjian berlangganan

# 3. Terminal UI
curl -fsSI http://localhost:3001/                 # 200 (SPA)
```

Uji alur lewat browser:
- [ ] Daftar/login user → `/portfolio/login`
- [ ] `/pricing` → modal **Perjanjian Berlangganan** muncul, tombol bayar terkunci sampai dicentang
- [ ] **Trial**: tombol "Coba Gratis 1 Hari" → setuju → masuk Terminal; cek tidak bisa trial 2×
- [ ] **Analisis Premium DSS**: login premium → fitur analisis (memakai `ml_engine` RI :8000)
- [ ] **Terminal**: `/portfolio/profile` → "Buka Terminal" → data saham, indikator, OmniQuant, News Feed
- [ ] **Watchlist/Alert** di terminal (memanggil API RI lintas-origin — cek CORS)
- [ ] Admin: `/admin` → konfirmasi subscription terminal → role/feature ter-update

---

## 11. Operasional Harian

```bash
docker compose ps                      # status
docker compose logs -f <service>       # log realtime
docker compose restart <service>       # restart satu service
docker compose down                    # stop semua (volume tetap)
docker compose down -v                 # stop + HAPUS volume (reset total — hati-hati)
```

**Cron kedaluwarsa langganan** (`scripts/expire-subscriptions.js`) — jalankan harian.
⚠️ Image `app` produksi hanya berisi `dist/` (tidak ada `scripts/`/`src/`), jadi script
ini **tidak** bisa di-`exec` di container `app`. Jalankan lewat container Node sekali-pakai
yang me-mount folder repo (butuh `node_modules` sudah terinstal di `regular-investor/`):

```bash
docker run --rm --network apps_net \
  -e DB_HOST=db -e DB_PORT=3306 \
  -e DB_USER=ri_user -e DB_PASSWORD="$DB_PASSWORD" -e DB_NAME=regular_investor \
  -v "$PWD/regular-investor:/app" -w /app node:22-alpine \
  node scripts/expire-subscriptions.js
```
Jadwalkan via `crontab -e` di host (mis. tiap 02:00). _Mengemas job ini ke dalam
image/penjadwal adalah pekerjaan ops (Fase H)._

Backup database:
```bash
docker compose exec -T db sh -c \
  'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" regular_investor' \
  > backup_$(date +%F).sql
```

---

## 12. Troubleshooting

| Gejala | Penyebab & Solusi |
|---|---|
| Terminal menolak akses (401/403) walau sudah langganan | `USER_SECRET` (app) ≠ `RI_USER_SECRET` (terminal). Di compose otomatis sama; pastikan `.env` punya `USER_SECRET`, lalu `up -d --build`. |
| Watchlist/News error CORS di terminal | `TERMINAL_URL` salah, atau frontend di-build dengan `APP_URL` lama. Rebuild `terminal-frontend`. |
| Analisis Premium gagal / timeout | `ml_engine` belum siap (start ~60s) atau model belum dilatih (mode mock). Cek `docker compose logs ml_engine`. |
| Trial bisa diklaim berulang | Pastikan migrasi `004` terpasang & tabel `subscriptions.plan_type` punya `terminal_trial`. |
| News feed kosong sebagian | Beberapa RSS (mis. Bloomberg) kadang diblokir/timeout — feed lain tetap tampil (by design). |
| `db` gagal start, port 3306 bentrok | MySQL host lain aktif. Stop, atau ubah mapping port `db` di compose. |
| Model ML hilang setelah `down -v` | `-v` menghapus volume model. Latih ulang (§8) atau backup volume sebelum reset. |

---

## 13. Checklist Keamanan DEV→Prod

- [ ] Ganti semua secret default (`USER_SECRET`, `ADMIN_SECRET`, `ADMIN_PASSWORD`, DB password)
- [ ] Jangan commit `.env`
- [ ] Tutup port DB (`3306`) dari publik (firewall) — hanya internal
- [ ] Aktifkan HTTPS: tambah `listen 443` + sertifikat (Let's Encrypt) di `nginx/nginx.conf`
- [ ] Set `server_name` nginx ke domain asli; `APP_URL`/`TERMINAL_URL` ke `https://...`
- [ ] Konfirmasi `JURISDICTION_CITY` & isi Perjanjian Berlangganan (tinjau legal)
- [ ] Jadwalkan `expire-subscriptions.js` (cron harian)

---

## Catatan Konsolidasi Engine (rencana ke depan)

Saat ini `ml_engine` (RI) dan `terminal-backend` (Terminal) berjalan terpisah dan
tumpang tindih (yfinance, indikator, AHP/TOPSIS/SAW). Rencana: konsolidasi ke satu
engine setelah analisa **akurasi & kestabilan** masing-masing di DEV. Sampai itu
diputuskan, pertahankan keduanya.
