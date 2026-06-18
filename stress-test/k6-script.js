import http from 'k6/http';
import { check, sleep } from 'k6';

// Konfigurasi ini akan ditimpa oleh variabel --vus dan --duration dari CLI
export const options = {
    vus: 10,
    duration: '30s',
    thresholds: {
        http_req_duration: ['p(95)<1000'], // 95% request harus selesai di bawah 1 detik
        http_req_failed: ['rate<0.05'],    // Tingkat error maksimal 5%
    },
};

// Membaca target URL dari environment variable (default diset ke dev server lewat VPN)
const WEB_URL = __ENV.WEB_URL || 'http://app.regular-investor.local';
const TERMINAL_URL = __ENV.TERMINAL_URL || 'http://terminal.regular-investor.local';

export default function () {
    // 1. Simulasi Load Frontend Web Utama (Astro SSR)
    let resWeb = http.get(`${WEB_URL}/`);
    check(resWeb, {
        'Web Frontend merespon dengan status 200': (r) => r.status === 200,
    });

    // 2. Simulasi Load Halaman Pricing Web
    let resPricing = http.get(`${WEB_URL}/pricing`);
    check(resPricing, {
        'Web Pricing merespon dengan status 200': (r) => r.status === 200,
    });

    // 3. Simulasi Load Halaman Portfolio Web
    let resPorto = http.get(`${WEB_URL}/portfolio`);
    check(resPorto, {
        'Web Portfolio merespon dengan status 200': (r) => r.status === 200,
    });

    // 4. Simulasi Load Halaman Article/Technology Web
    let resTech = http.get(`${WEB_URL}/technology`);
    check(resTech, {
        'Web Technology Article merespon dengan status 200': (r) => r.status === 200,
    });

    // 5. Simulasi Load Frontend Terminal (React)
    let resTerminal = http.get(`${TERMINAL_URL}/`);
    check(resTerminal, {
        'Terminal Frontend merespon dengan status 200': (r) => r.status === 200,
    });

    /* 
    CATATAN UNTUK ENDPOINT API BACKEND (FastAPI):
    Jika Anda memiliki endpoint spesifik yang tidak membutuhkan login (public),
    misalnya /api/v1/market/status, Anda bisa menambahkan test-nya seperti di bawah:
    */
    // let resApi = http.get(`${TERMINAL_URL}/api/v1/health`); // Ganti dengan endpoint yg ada
    // check(resApi, {
    //     'Backend API merespon dengan status 200': (r) => r.status === 200,
    // });

    // Istirahat 1 detik agar tidak terlalu membebani secara konstan tak terbatas (opsional)
    sleep(1);
}
