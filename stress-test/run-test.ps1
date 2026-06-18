param (
    [string]$WebUrl = "http://app.regular-investor.local",
    [string]$TerminalUrl = "http://terminal.regular-investor.local",
    [int]$Vus = 500,
    [string]$Duration = "30s"
)

# Ganti variabel ini dengan IP/Domain VPN Anda jika Anda tidak menggunakan host lokal.
# Contoh eksekusi: .\run-test.ps1 -WebUrl "http://192.168.1.100" -TerminalUrl "http://192.168.1.101"

$k6Path = ".\k6.exe"

# Cek apakah k6 sudah didownload
if (-Not (Test-Path $k6Path)) {
    Write-Host "k6 executable tidak ditemukan di folder ini." -ForegroundColor Yellow
    Write-Host "Mendownload k6 v0.49.0 untuk Windows (amd64)..." -ForegroundColor Cyan
    
    $zipUrl = "https://github.com/grafana/k6/releases/download/v0.49.0/k6-v0.49.0-windows-amd64.zip"
    $zipPath = ".\k6.zip"
    
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
        
        Write-Host "Mengekstrak k6..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath ".\k6-extracted" -Force
        
        # Pindahkan k6.exe ke folder stress-test
        Move-Item -Path ".\k6-extracted\k6-v0.49.0-windows-amd64\k6.exe" -Destination $k6Path -Force
        
        # Bersihkan file sementara
        Remove-Item -Path $zipPath -Force
        Remove-Item -Path ".\k6-extracted" -Recurse -Force
        
        Write-Host "k6 berhasil didownload dan diekstrak." -ForegroundColor Green
    } catch {
        Write-Error "Gagal mendownload k6. Pastikan Anda memiliki koneksi internet, atau Anda bisa mendownloadnya manual dari https://k6.io/docs/get-started/installation/"
        exit
    }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "  Memulai Stress Test menggunakan k6" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "Web URL Target      : $WebUrl" -ForegroundColor Cyan
Write-Host "Terminal URL Target : $TerminalUrl" -ForegroundColor Cyan
Write-Host "Virtual Users (VUs) : $Vus" -ForegroundColor Cyan
Write-Host "Durasi              : $Duration" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host ""

# Mengeset environment variable agar dibaca oleh script k6 javascript
$env:WEB_URL = $WebUrl
$env:TERMINAL_URL = $TerminalUrl

# Menjalankan k6
& $k6Path run --vus $Vus --duration $Duration .\k6-script.js

Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "Stress test selesai." -ForegroundColor Green
