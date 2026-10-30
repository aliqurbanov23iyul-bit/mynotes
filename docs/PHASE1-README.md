# ASTRA — Phase 1

Azərbaycan dilində, Vanilla JavaScript ilə hazırlanmış lokal frontend demo.

## Başlatmaq

Node.js 20+ tələb olunur. Asılılıq quraşdırmaq lazım deyil.

```sh
npm start
```

Tətbiq: http://127.0.0.1:4173
Admin: http://127.0.0.1:4173/admin/

Server işləyərkən yoxlamalar:

```sh
npm run check
```

## Struktur

- `index.html`, `notes.html`, `discover.html`, `ai.html`: istifadəçi ekranları
- `admin/`: altı ayrıca demo idarəetmə səhifəsi
- `assets/css/style.css`: ortaq responsive dizayn sistemi
- `assets/js/app.js`: ortaq komponentlər, ekranlar və hadisələr
- `assets/js/data-service.js`: backend ilə əvəz edilə bilən lokal data-service və nümunə kataloq
- `manifest.json`, `service-worker.js`: PWA və offline statik keş
- `scripts/`: lokal server, yoxlamalar və ikon generatoru

Qeydlər, tapşırıqlar, çat və seçimlər `astra-v1` localStorage açarında saxlanır. Məxfi məlumatlar üçün uyğun deyil. Brauzer yaddaşı bloklandıqda sessiya yaddaşı istifadə edilir və saxlamada bildiriş göstərilir.

Admin giriş nəzarəti olmayan demo interfeysdir. Heç bir API açarı saxlanmır. AI cavabları əvvəlcədən hazırlanıb, fayllar oxunmur və göndərilmir, JARVIS avtomatlaşdırması işləmir. Film kataloqu nümunədir, posterlər illüstrativdir. Günün filmi admin seçimi ilə lokal dəyişir. Təqvim digər günlər üçün boş demo vəziyyətini göstərir; yeni tapşırıqlar bu günə əlavə edilir.

PWA ilk uğurlu açılışdan sonra əsas istifadəçi və admin səhifələrini keşləyir. Quraşdırma üçün localhost və ya HTTPS lazımdır. iPhone-da HTTPS ünvanını Safari-də açıb Paylaş → Ana ekrana əlavə et seçin. iOS quraşdırma və offline davranışı real cihazda ayrıca yoxlanmalıdır. Keş strategiyası network-first-dir; yayımdan sonra statik fayllar dəyişdikdə service-worker keş versiyasını artırın.

Növbəti mərhələ üçün server autentifikasiyası və admin səlahiyyətləri, API proxy-ləri, verilənlər bazası və real icazə mexanizmi tələb olunur.

## Açıq tema və avtomatik AI seçimi

İnterfeys açıq lavanda, nanə və ağ səthlərlə yeniləndi. Ortaq SVG ikonları `assets/js/icons.js` modulundadır. Animasiya effektləri `prefers-reduced-motion` seçiminə hörmət edir.

AI ekranında model seçimi yoxdur. `assets/js/ai-router.js` demo limiti idarə edir: hər model üçün gündə 3 mesaj; Gemini → Claude → Grok. Hamısı bitdikdə mesaj göndərilməsi dayandırılır və bildiriş göstərilir. Limitlər UTC gününə görə yenilənir, brauzerdə lokal saxlanır. Bu, real provayder limitlərini ölçmür; backend mərhələsində server tərəfli limit və xəta idarəetməsi ilə əvəz edilməlidir.

## ASTRA pet dostları

Bütün ekranlarda Orbit (işıq kürəsi), Nova (minimal robot), Prism (kristal) seçilə bilər. Bir və ya bir neçə pet eyni vaxtda göstərilir. `Yoldaşlar` düyməsi seçim panelini açır. Petə toxunmaq növbəti bölmə məsləhətini göstərir. Sakit rejim balonu gizlədir; petlər qalır. Bütün petləri seçimdən çıxarmaq mümkündür; `Köməkçi seç` düyməsi onları geri qaytarır.

Seçimlər `astra-pets` açarında lokal saxlanır. Bu modul ekran görüntüsü almır, mətnləri və qeydləri analiz etmir, şəbəkəyə məlumat göndərmir. Kursor istiqamətinə yüngül hərəkət və nəfəsalma animasiyası var; reduced-motion aktiv olduqda söndürülür. Məsləhətlər bölməyə görə əvvəlcədən yazılmış Azərbaycan dilində demo mətnləridir.

Hazırkı köməkçilər yüngül, kodla çəkilmiş SVG aktivləridir: `assets/images/pets/orbit.svg`, `nova.svg`, `prism.svg`. Əvvəlki heyvan konseptləri və ImageGen promptları arxiv olaraq saxlanır, interfeysdə istifadə edilmir.
