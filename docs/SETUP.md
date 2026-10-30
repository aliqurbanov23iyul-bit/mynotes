# ASTRA Phase 2 — Supabase quraşdırması

Bu kod mövcud açıq tema və Vanilla JavaScript ekranlarını saxlayır. Hazırda Supabase konfiqurasiyası boşdur; real hesablar və canlı verilənlər bazası sınaqdan keçirilməyib. Qorunan səhifələr demo məlumatlarına geri düşmür.

## 1. Lokal hazırlıq

Node.js 22+ istifadə edin (test mühiti: Node 24). Layihə kökündə:

```sh
npm ci
npm run vendor
```

`.env.example` faylını `.env` olaraq köçürün və yalnız bu public dəyərləri doldurun:

```dotenv
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
APP_URL=http://127.0.0.1:4173
```

Dəyərləri Supabase layihənizin Connect/API bölməsindən götürün. `SUPABASE_PUBLISHABLE_KEY` `sb_publishable_` ilə başlayan public açar olmalıdır. Secret və service_role açarlarını `.env` və frontend konfiqurasiyasına əlavə etməyin. Legacy anon açarı bu konfiqurasiya generatorunda qəsdən qəbul edilmir.

```sh
npm run configure
npm start
```

`configure` yalnız üç icazəli public dəyəri `assets/js/config.js` moduluna yazır; açarları çıxışa çap etmir. `.env` Git-dən və statik serverdən kənardır. Deploy kökü domen kökü kimi nəzərdə tutulub; APP_URL son slash olmadan yazılır.

## 2. Database migration-ları

Supabase SQL Editor-da aşağıdakı faylları sıra ilə, tam məzmunu ilə icra edin. Alternativ: rəsmi Supabase CLI ilə layihəyə link edib `supabase db push` işlədin. Mövcud production bazada əvvəl backup və ayrıca staging testi edin.

1. `supabase/migrations/202610300001_schema.sql`
2. `supabase/migrations/202610300002_workspace.sql`
3. `supabase/migrations/202610300003_admin.sql`
4. `supabase/migrations/202610300004_profile_version.sql`

Bunlar ilkin migration-lardır; eyni migration-ı SQL Editor-da ikinci dəfə icra etməyin. CLI tətbiq edilmiş migration tarixçəsini izləyir. `public` Data API üçün exposed schema olmalıdır; `private` schema-nı exposed siyahısına əlavə etməyin. Şəxsi cədvəllərin hamısında RLS açıqdır. `private.admin_members`, bloklanmış hesablar, import işarələri və audit qeydləri brauzerdən əlçatan deyil.

`favorite_movies.tmdb_movie_id` gələcək real TMDB ID-ləri üçündür. Cari nümunə kataloqda `catalog_key` istifadə edilir; TMDB ID-si uydurulmur. Eyni film həm sevimli, həm izləniləcək ola bilər.

## 3. Supabase Auth

Authentication → URL Configuration:

- Site URL: APP_URL ilə eyni ünvan.
- Redirect allowlist: `http://127.0.0.1:4173/auth-callback.html` və `http://127.0.0.1:4173/reset-password.html`.
- Production üçün eyni iki dəqiq HTTPS callback URL-i əlavə edin. Geniş wildcard istifadə etməyin.

Email provider-i aktiv edin; **Confirm email** aktiv qalsın. Production-da SMTP və e-poçt göndərmə limitlərini konfiqurasiya edin. Şifrə minimumunu ən azı 12 simvol edin; auth rate limit-lərini saxlayın. Qeydiyyatdan sonra e-poçtu təsdiqləmək lazımdır. PKCE callback axını linkin başladıldığı brauzerdəki verifier-ə bağlıdır; link başqa brauzerdə açılırsa yenidən təsdiq/sıfırlama tələb edin.

- `login.html`: giriş, qeydiyyat, unudulmuş şifrə, təsdiq linki yenidən göndərmə.
- `auth-callback.html`: e-poçt təsdiqindən sonra sessiya yoxlanması.
- `reset-password.html`: linklə açılan sessiyada yeni şifrə.
- `profile.html`: profil, çıxış, bir dəfəlik lokal qeyd importu və hesab silmə.

SDK sessiya tokenlərini brauzer yaddaşında idarə edir; bu, private iş məlumatlarının lokal keşlənməsi demək deyil. XSS riskini azaltmaq üçün yalnız nəzarət edilən skriptlər əlavə edin. Shared cihazda çıxış edin. Supabase `getUser()` ilə sessiya yoxlanılır; RLS və RPC də serverdə yoxlama aparır.

## 4. Admin hesabının təhlükəsiz yaradılması

Əvvəl normal qeydiyyatdan keçin və e-poçtu təsdiqləyin. Admin olacaq hesabın UUID-sini Supabase Auth → Users bölməsindən götürün. Yalnız etibarlı operator SQL Editor-da icra etsin:

```sql
insert into private.admin_members(user_id)
values ('BURADA_TƏSDİQLƏNMİŞ_HESAB_UUID'::uuid)
on conflict do nothing;
```

Bu placeholder-i real hesab UUID-si ilə əvəz edin. İstifadəçi metadata-sında `role=admin` yazmaq səlahiyyət vermir. Frontenddən rol təyin etmək üçün endpoint yoxdur. Admin rolunu ləğv etmək:

```sql
delete from private.admin_members
where user_id = 'BURADA_HESAB_UUID'::uuid;
```

Admin panel `is_admin()` və `admin_api()` vasitəsilə serverdə qorunur. Admin istifadəçi sayı, son 7 gündə uğurlu giriş edən hesab sayı, ümumi qeyd/tapşırıq sayı və iş statuslarını görür. Qeydlərin məzmunu göstərilmir. İstifadəçilərin girişini dayandırmaq/açmaq və draft/scheduled işləri ləğv etmək mümkündür; bu əməliyyatlar audit edilir. Admin hesablarını bu paneldən bloklamaq olmaz. Hesab bloklananda köhnə JWT hələ mövcud olsa da RLS və workspace RPC-ləri məlumat çıxışını rədd edir. Bu, Supabase Auth hesabının özünü ban etmək deyil; tətbiq məlumatlarına çıxış nəzarətidir.

## 5. Hesab silmə Edge Function-u

`supabase/functions/account-delete/index.ts` serverdə işləyir. Frontend yalnız istifadəçinin cari şifrəsini və açıq təsdiq mətnini HTTPS ilə göndərir. Funksiya JWT-ni `auth.getUser(jwt)` ilə yoxlayır, hesabın icazəsini yoxlayır, cari şifrə ilə yenidən autentifikasiya edir və yalnız həmin hesabın ID-si üçün `auth.admin.deleteUser()` çağırır. Göndərilən başqa user_id nəzərə alınmır. Şifrə loglanmır və saxlanmır. Admin hesabı üçün əvvəl etibarlı operator admin üzvlüyünü çıxarmalıdır.

Rəsmi Supabase CLI ilə:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set APP_ORIGIN=https://YOUR_APP_HOST
supabase functions deploy account-delete
```

`APP_ORIGIN` yalnız origin-dir, sonunda slash/path yoxdur. Lokal testdə `http://127.0.0.1:4173` istifadə edin. Funksiya Supabase-in server mühitindəki `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` dəyişənlərindən istifadə edir. Bunlar brauzerə verilmir. `verify_jwt=false` yeni signing key-lərlə uyğundur; funksiya daxilində JWT yoxlaması məcburidir və söndürülməməlidir. Platformanın legacy JWT gate-i əvəzinə explicit Auth yoxlaması var. CLI və Dashboard-da həmin konfiqurasiyanı təsdiqləyin. CORS origin məhdudiyyəti əlavə nəzarətdir; əsas qoruma JWT + cari şifrədir.

Storage bu mərhələdə istifadə edilmir. Gələcəkdə upload əlavə edilərsə hesab silmədən əvvəl Storage obyektlərinin təhlükəsiz təmizlənməsi ayrıca hazırlanmalıdır. Hazırkı FK cascade hesabın database sətirlərini silir.

## 6. Lokal məlumatların importu

Profil → Lokal qeydləri köçür → əvvəlcə başlıqları nəzərdən keçir → yalnız öz qeydlərinizdirsə təsdiqləyin. Server bütün batch-i bir tranzaksiyada yoxlayır və hesab üçün bir dəfəlik import işarəsi saxlayır. Təkrar düymə/şəbəkə retry-si dublikat yaratmır. Lokal `astra-v1` məzmunu avtomatik silinmir. Köhnə lokal tapşırıqlar bu importun hissəsi deyil. Köhnə chat demo tarixçəsi cloud-a köçürülmür.

## 7. HTTPS deploy

```sh
npm run configure
npm test
npm run check
npm run build
```

Yalnız `dist/` qovluğunu HTTPS statik hosta deploy edin; layihə kökünü upload etməyin. `.env`, `supabase/`, `tests/`, `scripts/`, `node_modules/` publik olmamalıdır. `dist/`-dəki konfiqurasiya public-dır. Açarı sonradan dəyişsəniz configure/build/deploy təkrar tələb olunur. Server-side secret-lər yalnız Supabase Edge secrets-dədir.

Hostda `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, HTML üçün `Cache-Control: no-store`, HSTS və uyğun CSP başlıqları əlavə edin. Lokal serverdə nümunə CSP var: self script, inline styles (mövcud UI), Supabase HTTPS connect, object-src none, frame-ancestors none. Custom Supabase domain-i istifadə edilərsə həmin dəqiq origin-i CSP connect-src-ə əlavə edin. `assets/js/config.js` və `service-worker.js` üçün no-store/revalidation tətbiq edin. Auth callback query-lərini log və analytics-dən çıxarın.

PWA yalnız public statik allowlist-i keşləyir. API, Auth sorğuları, URL query-si olan callback-lər, config və şəxsi cavablar Cache Storage-a yazılmır. Köhnə astra-* keşləri yeni worker aktivləşəndə silinir. Offline rejimdə köhnə şəxsi məlumat göstərilmir; şəbəkə lazımdır. Hər yayımdan əvvəl cache versiyasını `scripts/cache.mjs` daxilində artırın və build edin. İlk production yayımdan sonra iOS Safari üzərində təkrar test edin.

## 8. Testlər və məlum sərhədlər

`npm test`: izolyasiya edilmiş PostgreSQL (PGlite) üzərində migration/RLS/RPC testləri; SDK mock ilə Auth lifecycle və Edge authorization; statik server exposure testləri. `npm run check`: səhifə istinadları, JS syntax, ekran render smoke testləri və cache invariants. `supabase/tests/rls.sql`: ayrıca staging/local Supabase SQL smoke suite. Bunlar canlı Supabase Auth, SMTP, Deno Edge deploy və real iki cihazlı brauzer testini əvəz etmir.

Tam nəticələr və 12 ssenarinin statusu `docs/TEST-RESULTS.md` faylındadır. Arxitektura/audit `docs/PHASE2-AUDIT.md` faylındadır. Tarixi `scripts/scaffold`, `phase2-*`, `redesign`, `pets-*`, `finish`, `companions*` skriptlərini yenidən icra etməyin; onlar birdəfəlik müəlliflik köməkçiləridir. Dəstəklənən iş axını yalnız package.json script-ləridir.

Gemini, Claude, Grok, TMDB və JARVIS avtomatik araşdırması qoşulmayıb. AI çat nümunə cavablarla sessiya yaddaşında qalır. Cloud backend aktivləşmədən bu mərhələni production-ready hesab etməyin.

Rəsmi istinadlar: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [User management](https://supabase.com/docs/guides/auth/managing-user-data), [Password reset](https://supabase.com/docs/reference/javascript/auth-resetpasswordforemail), [Server-side user deletion](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser). Migration və Auth yanaşması bu rəsmi API sərhədlərinə əsaslanır.

> Cari Phase 3+ quraşdırması üçün [PRODUCTION.md](PRODUCTION.md), yekun status üçün [FINAL-AUDIT.md](FINAL-AUDIT.md) oxuyun. Bu sənəd Phase 2 bazasını izah edir.
