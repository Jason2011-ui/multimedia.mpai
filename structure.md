# Struktur Proyek multimediaMPAI

Proyek ini adalah satu halaman web statis yang dibangun dalam satu file utama.

## File utama
- `index.html`
  - Berisi seluruh markup HTML, gaya CSS, dan logika JavaScript.
  - Mencakup:
    - Navbar tetap dengan navigasi antar halaman internal.
    - Modal untuk `Masuk` dan `Daftar`.
    - Halaman internal (`page-section`) untuk:
      - `beranda` (hero)
      - `class` (kelas Multimedia)
      - `tim` (penanggung jawab dan anggota)
      - `sosmed` (tautan media sosial)
      - `absensi` (absensi digital)
      - `admin` (panel kontrol admin)
    - Footer sederhana.
    - Integrasi Supabase melalui script CDN `@supabase/supabase-js`.
    - Konfigurasi Supabase dan helper database untuk autentikasi, pengguna, dan absensi.

## Folder aset
- `assets/`
  - Berisi gambar profil yang ditampilkan pada halaman tim.
  - Gambar digunakan di kartu profil `teacher` dan `student`.

## Dokumentasi
- `README.md`
  - Penjelasan umum mengenai website.
  - Cara menjalankan dan mempersiapkan Supabase.

## Catatan penting
- Tidak ada file CSS terpisah; gaya ditulis langsung di dalam `index.html`.
- Tidak ada file JavaScript terpisah; logika script juga ditulis langsung di dalam `index.html`.
- Aplikasi ini menggunakan lokal HTML/JS dan Supabase sebagai backend.
