# ASTRA — şəxsi AI köməkçi PWA

Mövcud HTML5/CSS3/Vanilla JavaScript bazası saxlanılıb. Dörd əsas bölmə: Ana səhifə, Qeydlər, Kəşf et, AI. Ayrıca admin, Supabase Auth/RLS, provider adapterləri, JARVIS queue, TMDB proxy və notification strukturu var. Default dark navy tema, istəyə bağlı əvvəlki açıq tema və rəqəmsal yoldaşlar saxlanılır.

**Cari vəziyyət:** bu workspace-də Supabase və provider açarları yoxdur. Canlı API, production migration/deploy və pullu AI sorğusu icra edilməyib. Bağlantı olmayanda uydurma məlumat göstərilmir. Production hazırlığı canlı yoxlamalardan sonra təsdiqlənməlidir.

- [Tam quraşdırma, API-lər, scheduler, büdcə, admin və deploy](docs/PRODUCTION.md)
- [Yekun audit, dəyişən fayllar, 30 ssenari və qalan məhdudiyyətlər](docs/FINAL-AUDIT.md)
- [Əvvəlki Supabase/Auth/admin quraşdırması](docs/SETUP.md)

```sh
npm ci
npm run vendor
# .env.example → .env; real public Supabase URL/key və APP_URL
npm run configure
npm start
```

Lokal: http://127.0.0.1:4173 · Hesab: /profile.html · Admin: /admin/

```sh
npm test
npm run check
npm run build
npm run check:package
```

Yalnız `dist/` yayımlanır. Vercel üçün `vercel.json` var. `supabase/.env.example` yalnız Edge secret adlarını göstərir; real provider/service/VAPID/scheduler açarları frontendə yazılmır. Migration-lar `supabase/migrations/`, Cron quraşdırması `supabase/setup/scheduler.sql` daxilindədir.

Default olaraq AI, AutoPilot, memory, notification consent və maliyyə limitləri bağlıdır. İstifadəçi/provider məlumat ötürülməsi və ödəniş icazəsi açıq şəkildə verilmədən AI çağırılmır. Köhnə şəxsi məlumatlar kütləvi silinmir; lokal qeyd importu preview və təsdiq tələb edir. Test fixture-ləri runtime-a daxil deyil.

Struktur: `assets/js/` — UI və xidmət adapterləri; `supabase/functions/` — 7 server endpoint-i və shared providerlər; `supabase/migrations/` — schema/RLS/runtime; `tests/` — PostgreSQL + SDK/HTTP/DOM mock testləri; `scripts/` — dəstəklənən build/server/check əmrləri; `docs/archive/` — tarixi müəlliflik materialları, deploy edilmir.
