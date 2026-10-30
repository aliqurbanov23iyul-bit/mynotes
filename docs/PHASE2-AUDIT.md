# Phase 2 audit və arxitektura

## Mövcud bazanın auditi

10 HTML ekranı, CSS dizayn sistemi, app.js hadisələri, data-service, movie catalog, AI demo router, pet modulu, manifest, service worker, ikonlar və illüstrasiyalar, lokal server və bütün müəlliflik/yoxlama skriptləri nəzərdən keçirildi. Mövcud ekranlar sıfırdan yazılmadı. Açıq tema, naviqasiya, kartlar, modallar və rəqəmsal köməkçilər saxlanıldı.

Əvvəlki risklər: localStorage şəxsi state-i, yalnız demo admin, bütün faylları verən development server, network-first runtime keş, yalnız gün nömrəsini saxlayan təqvim, tarixsiz demo tapşırıqlar, uydurma admin statistikası. Bunlar yeni hesab sistemi ilə əvəz edildi.

## Sərhədlər

Browser → Supabase JS SDK → Auth / PostgREST / məhdud SECURITY DEFINER RPC → PostgreSQL RLS.

- `config.js`: yalnız URL, publishable key, APP_URL.
- `supabase-client.js`: singleton SDK, bağlantı və xətaların təqdimatı.
- `auth-operations.js`, `auth-service.js`, `auth-page.js`: giriş lifecycle, guard və profil.
- `data-service.js`: əvvəlki istifadəçi interfeysinə uyğun export + statik katalog.
- `services/workspace-service.js`: memory-only state, encode/decode, RPC storage.
- `services/movie-service.js`: hazırkı kataloq və gələcək TMDB adapter sərhədi.
- `services/jarvis-service.js`: owner-scoped list/draft/cancel; worker yoxdur.
- `services/admin-service.js`, `admin-ui.js`: serverdə icazə yoxlanan real stats/əməliyyatlar.
- `supabase/functions/account-delete`: cari şifrə ilə təkrar yoxlama və server-side self deletion.

## Yaddaşa yazma modeli

Mövcud frontend ekranlarının state formasını saxlamaq üçün save_workspace RPC bir tranzaksiyada account snapshot-u yazır. Profil sətri kilidlənir və expected_version yoxlanılır. Digər cihazın dəyişikliyi itirilmir: 40001 toqquşması qaytarılır, UI server state-ini yeniləyir və istifadəçidən retry gözləyir. Qeyd redaktorunun mətni modaldadır və avtomatik silinmir. Bunun qiyməti hər saxlamada bütün owner workspace payload-ının göndərilməsidir (4 MB hədd). Böyük həcm üçün gələcək mərhələdə dəyişiklik əsaslı RPC-lərə keçmək lazımdır; server həddi aşılanda əməliyyat rədd olunur.

RPC-lər istifadəçi ID-sini payload-dan götürmür. auth.uid() əsasdır. Sənəd ID-si başqa hesaba məxsusdursa əməliyyat rədd edilir. Funksiyalar fixed boş search_path, tam schema adları və məhdud execute grant-ları ilə hazırlanıb. Table CRUD RLS də ayrıca aktivdir. Adi istifadəçinin admin rolu serverin private cədvəlində yoxlanılır; profil metadata-sından oxunmur. Adminlərə şəxsi məzmun üçün ümumi SELECT policy verilmir.

State brauzerdə yalnız sessiya yaddaşındadır. Auth SDK tokenləri öz yaddaş mexanizmi ilə saxlayır. Pet seçimi qeyri-məxfi localStorage seçimidir. Başqa hesaba keçid və SIGNED_OUT zamanı workspace yaddaşı və DOM təmizlənir. Focus və Yenilə düyməsi məlumatı serverdən yenidən yükləyir. Redaktor açıq olanda auto-refresh edilmir. WebSocket realtime əlavə edilməyib; hazırkı istifadə üçün pull-on-focus və revision conflict kifayətdir.

## Əlavə olunan ekranlar

login.html, auth-callback.html, reset-password.html və profile.html. Offline vəziyyəti üçün offline.html. Eyni CSS dizayn sistemindən istifadə edilir. Qeydlərin axtarışı yüklənmiş owner workspace üzərində aparılır. Kateqoriya/sabitləmə və updated_at üzrə sıralama var. Tapşırıqlarda tarix, vaxt, description, prioritet və redaktə əlavə edilib. Təqvim hadisələri selected date üzrə göstərilir.

## Məlumat modeli qeydləri

JARVIS source_note_id owner ilə kompozit FK-dir; başqa hesabın qeydinə bağlana bilməz. Mənbə qeyd silinərsə bağlı işlər cascade ilə silinir. Hesab silinərsə bütün şəxsi sətirlər cascade olur. AutoPilot və qeyd icazəsi default false-dur. Model konfiqurasiya limitləri yalnız gələcək üçün parametrlərdir; real AI istifadəsi kimi təqdim edilmir. Admin activity metriyi son 7 gündə uğurlu giriş sayıdır, anonim səhifə ziyarəti deyil.

## Əsas çatışmayan xarici addım

İstifadəçi Supabase layihəsini seçməli, migration-ları tətbiq etməli, public konfiqurasiyanı doldurmalı, Auth/SMTP/redirect-ləri və Edge Function-u deploy etməli, admin üzvlüyünü trusted SQL ilə verməlidir. Bu hesabın credential-ları mövcud olmadığı üçün həmin addımlar görülməyib. Təlimat docs/SETUP.md daxilindədir.
