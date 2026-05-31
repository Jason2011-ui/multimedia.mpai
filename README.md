# multimediampai

## Deskripsi Website

Website ini adalah aplikasi landing page dan dashboard untuk Eskul Multimedia MTs Plus Al Ishlah. Seluruh aplikasi berada di dalam `index.html`, yang menggabungkan:

- HTML untuk struktur halaman dan konten.
- CSS internal untuk desain gelap modern, tata letak grid, dan responsif.
- JavaScript internal untuk navigasi internal, autentikasi, absensi digital, dan panel admin.
- Integrasi `Supabase` sebagai backend untuk menyimpan data pengguna dan absensi.

## Fitur Utama

- Halaman `Beranda` yang memperkenalkan Eskul Multimedia dengan tombol ajakan bergabung.
- Halaman `Kelas Multimedia` yang menampilkan lima bidang utama: Desain Grafis, Konten Creator, Multimedia, Vokal, dan Sastra.
- Halaman `Tim` yang menampilkan penanggung jawab dan anggota tim.
- Halaman `Sosial Media` dengan tautan ke Instagram, TikTok, YouTube, dan Discord.
- Halaman `Absensi Digital` untuk mencatat kehadiran.
- Panel `Admin` untuk mengelola pengguna dan absensi dari backend.
- Tab admin `Rekap & Profile` untuk melihat semua profile, rekap Hadir/Izin/Sakit/Alfa, nilai kehadiran, dan export Excel.
- Modal `Masuk` dan `Daftar` untuk autentikasi pengguna.

## Struktur Proyek

- `index.html` : file utama aplikasi.
- `assets/` : kumpulan gambar profil dan aset visual.
- `README.md` : penjelasan proyek dan cara pakai.
- `structure.md` : dokumentasi struktur file proyek.

## Cara Menjalankan

1. Buka `index.html` langsung di browser.
2. Pastikan koneksi internet tersedia untuk memuat font Google dan library Font Awesome / Supabase.
3. Jika ingin menggunakan backend Supabase, isi nilai `SUPABASE_URL` dan `SUPABASE_KEY` di file `index.html`.

## Konfigurasi Supabase

Di dalam `index.html` terdapat konstanta:

- `SUPABASE_URL`
- `SUPABASE_KEY`

Isi nilai tersebut dengan endpoint dan kunci publik (anon/public key) dari proyek Supabase kamu.

### Setup backend Supabase

Jalankan seluruh isi file `supabase_setup.sql` di Supabase Dashboard > SQL Editor.

File tersebut membuat:

- tabel `users`, `absensi`, dan `mm_sessions`;
- session token backend untuk login/register;
- RPC backend untuk absensi, admin, profile, dan public counter;
- validasi server-side untuk `Hadir` agar wajib radius sekolah;
- RLS tertutup agar browser tidak bisa insert/select tabel langsung.

Admin awal:

- username: `admin`
- password: `admin123`

Setelah login sebagai admin, ubah role akun anggota dari `pengunjung` menjadi `anggota`.

## Catatan Tambahan

- Semua komponen frontend berada di satu file untuk kemudahan pengeditan.
- Aplikasi ini cocok untuk demo lokal atau sebagai prototype Eskul Multimedia.
- Untuk produksi, disarankan memisahkan CSS dan JavaScript ke file terpisah dan menggunakan kebijakan keamanan Supabase yang lebih ketat.
