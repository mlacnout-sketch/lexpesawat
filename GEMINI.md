# ZIVPN-NetReset - Technical Documentation

Dokumen ini berisi panduan teknis, struktur proyek, dan konfigurasi build untuk aplikasi **ZIVPN-NetReset**. Aplikasi ini adalah *micro-tool* berbasis Flutter yang menggunakan **Shizuku** untuk melakukan otomatisasi sistem (seperti Airplane Mode reset) tanpa akses root penuh.

## 1. Arsitektur Proyek

### Core Logic (Dart)
*   **`lib/service.dart`**: Otak aplikasi.
    *   Mengelola koneksi ke Shizuku (`pingBinder`, `runCommand`).
    *   Logika monitoring koneksi internet (ping Google).
    *   Strategi **Anti-Kill**: Menggunakan perintah `dumpsys deviceidle` dan `oom_score_adj` untuk mencegah OS mematikan aplikasi.
*   **`lib/dashboard.dart`**: UI Utama. Menampilkan status monitoring dan tombol kontrol manual.
*   **`lib/main.dart`**: Entry point. Menggunakan `MaterialApp` standar.

### Android Native Layer (Kotlin/Java)
Karena ini adalah aplikasi yang sangat bergantung pada sistem Android, konfigurasi native sangat krusial.
*   **`android/app/src/main/kotlin/com/zivpn/netreset/MainActivity.kt`**:
    *   Mewarisi `io.flutter.embedding.android.FlutterActivity`.
    *   Tidak ada logika custom yang berat di sini, hanya jembatan Flutter V2 standard.
*   **`android/app/src/main/AndroidManifest.xml`**:
    *   Mendeklarasikan `<provider ... ShizukuProvider>` agar bisa menerima binder.
    *   Permission penting: `QUERY_ALL_PACKAGES` (untuk melihat Shizuku app).
    *   **PENTING**: Jangan gunakan `android:name="io.flutter.app.FlutterApplication"`. Gunakan default Android Application agar kompatibel dengan Flutter V2 Embedding.

## 2. Konfigurasi Build (STRICT)

Konfigurasi ini telah diuji dan **WAJIB** dipertahankan untuk menghindari kegagalan build CI/CD.

| Komponen | Versi / Nilai | Alasan |
| :--- | :--- | :--- |
| **Flutter SDK** | `3.27.0` (Stable) | Mendukung Dart 3.6+, performa lebih baik. |
| **Java Version** | **17** | Wajib untuk AGP 8.x dan library modern. |
| **Compile SDK** | **35** | Syarat `url_launcher_android` dan `shizuku_api`. |
| **Min SDK** | **24** | Syarat `shizuku_api` modern. Jangan turunkan ke 21! |
| **NDK Version** | `27.0.12077973` | Syarat build environment terbaru. |
| **AGP Version** | `8.7.2` | Plugin Android Gradle terbaru. |
| **Gradle Wrapper** | `8.10.2` | Pasangan AGP 8.7.2. |

### Dependencies (pubspec.yaml)
*   **`shizuku_api: 1.2.1`**: Versi ini dipaku (pinned) tanpa `^` untuk menghindari konflik Dart SDK yang terlalu tinggi pada versi 1.2.2+.
*   `url_launcher`: Versi standar terbaru.

## 3. Strategi Anti-Crash & Stability

### Masalah R8 / Proguard
Aplikasi menggunakan **R8** untuk build release. Konfigurasi di `android/app/proguard-rules.pro` sangat kritis:
*   **Keep Shizuku**: `-keep class rikka.shizuku.** { *; }` agar binder tidak hilang.
*   **Suppress Play Core**: `-dontwarn com.google.android.play.core.**`. Kita tidak menggunakan Dynamic Features, jadi warning ini aman diabaikan. Jika tidak di-suppress, build akan gagal.

### Masalah Resources
*   **Vector Icon**: Menggunakan `ic_launcher.xml` (Adaptive) di folder `mipmap-anydpi-v26`.
*   **Placeholder**: Folder `mipmap-hdpi`, `xhdpi`, dll berisi file dummy yang valid (bukan 0 bytes) atau dihapus jika Adaptive Icon sudah cukup. (Saat ini strategi kita: andalkan Adaptive Icon + file valid jika ada).

## 4. GitHub Actions Workflow
Workflow ada di `.github/workflows/build_netreset.yml`.
*   Tidak lagi menggunakan `flutter create .` secara agresif.
*   Menggunakan `build.gradle` dan `settings.gradle.kts` yang sudah kita commit secara manual (statis).
*   Melakukan signing APK menggunakan Keystore yang disimpan di GitHub Secrets.

## 5. Instruksi Pengembangan Selanjutnya
Jika ingin memodifikasi kode:
1.  **Jangan ubah versi Gradle/AGP** sembarangan tanpa cek kompatibilitas Java 17.
2.  Jika mengubah `lib/service.dart`, pastikan logika `_strengthenBackground()` selalu dibungkus `try-catch` agar aplikasi tidak crash jika user mematikan Shizuku.
3.  Selalu cek `proguard-rules.pro` jika menambahkan library native baru.

---
*Dokumentasi dibuat otomatis oleh Gemini CLI - 26 Januari 2026*
