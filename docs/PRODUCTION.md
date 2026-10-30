# ASTRA — real xidmətlərə keçid və production quraşdırması

30 oktyabr 2026. Bu sənəd Phase 2 təlimatını yeni AI, JARVIS, TMDB və bildiriş modulları üçün genişləndirir. **Hazırkı workspace-də real Supabase konfiqurasiyası və provider açarları yoxdur. Heç bir pullu inference sorğusu, production migration və ya canlı deploy icra edilməyib.**

## Arxitektura

Vanilla JS/HTML/CSS → Supabase Auth + owner RLS → authenticated Edge Functions → rəsmi AI/TMDB endpoint-ləri. Provider açarları yalnız Edge secrets-dədir. Admin UI açarları qəbul etmir və göstərmir.

- `assets/js/chat-ui.js`, `services/chat-service.js`: persistent söhbətlər, seçim, SSE, dayandırma, adlandırma/silmə, cavabdan qeyd yaratma.
- `assets/js/movie-ui.js`, `services/movie-service.js`: TMDB axtarış, detallı film, region, janr/əhval/vaxt/şirkət üzrə seçim və yaddaş statusları.
- `assets/js/runtime-ui.js`: activity/material/proposal mərkəzi, istifadəçi büdcəsi, yaddaş, bildiriş və push icazələri.
- `assets/js/admin-runtime-ui.js`: provider konfiqurasiyası, faktiki usage cəmləri, sistem limitləri, status yoxlaması və kodlaşdırılmış xətalar.
- `supabase/functions/_shared/ai/providers/`: Gemini, Claude, Grok streaming adapterləri.
- `supabase/functions/_shared/ai/router.ts`: seçim, maksimum 1–3 cəhd, rezervasiya, usage settlement, approved memory.
- `supabase/functions/_shared/ai/analysis.ts`: etibarsız qeyd mətnindən yoxlanılan təklif JSON-u.
- `supabase/functions/ai-chat`, `jarvis`, `scheduler`, `movie-proxy`, `push-subscription`, `integration-status`, `account-delete`.
- `supabase/migrations/`: 11 ardıcıl migration. `private` schema exposed edilmir.

## 1. Frontend və Supabase

Node.js 22+ (test: 24.21.0):

```sh
npm ci
npm run vendor
```

`.env.example` → `.env`. Yalnız həqiqi public dəyərləri yazın:

```dotenv
SUPABASE_URL=
SUPABASE_PUBLISHABLE_KEY=
APP_URL=
```

URL və `sb_publishable_` açarını Supabase Dashboard-dan götürün. `APP_URL` domen kökü, son slash olmadan: lokal üçün `http://127.0.0.1:4173`, production üçün öz HTTPS origin-iniz. Service/secret/provider açarları bu fayla yazılmır.

```sh
npm run configure
npm start
```

URL: http://127.0.0.1:4173. Konfiqurasiya boşdursa real məlumat əvəzinə bağlantı vəziyyəti göstərilir. Saxta login və demo fallback yoxdur.

Auth email provider, email təsdiqi, SMTP, rate limit və exact redirect-ləri [Phase 2 quraşdırmasına](SETUP.md) əsasən qurun. Redirect-lər: `APP_URL/auth-callback.html`, `APP_URL/reset-password.html`. Minimum 12 simvolluq yeni şifrə konfiqurasiyası tövsiyə olunur. Mövcud daha qısa şifrəli hesabın giriş forması onu bloklamır; server siyasəti əsasdır.

## 2. Migration-lar

Əvvəl staging və backup. Mövcud tətbiq olunmuş migration-ları yenidən icra etməyin. İlk quraşdırmada 001 → 011 hamısını sıra ilə tətbiq edin. Phase 2 artıq tətbiq olunubsa yalnız yeni 005–011 fayllarını tətbiq edin:

- 005: runtime schema, consent, conversations, messages, usage, memory, materials, notifications və provider config.
- 006: büdcə, təhlükəsiz service RPC-ləri, queue/lease/confirmation/publication.
- 007: həqiqi notification yaradılması, real admin runtime əməliyyatları.
- 008: watched/disliked statusları, push claim-once.
- 009: həqiqi completion timestamp, şəxsi usage cəmləri və opt-in film bildirişi.
- 010: per-note consent ilə avtomatik analiz növbəsi və proposal publication.
- 011: indekslər, stale işlərin dayandırılması, pin/category dəyişikliklərində təkrar AI xərcinin qarşısı və push lease expiry.

Rəsmi Supabase CLI ilə:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

`private` schema üçün Data API exposure açmayın. Açar, prompt və şəxsi məzmun `app_settings`-ə qoyulmur. Provider config-də yalnız model/endpoint/qiymət/limit var; açarlar yoxdur. Miqrasiyalar real şəxsi cədvəlləri kütləvi silmir. Əvvəl tamamlanmış tapşırıqlara uydurma completed_at tarixi əlavə edilmir.

## 3. Edge secrets və deploy

Server dəyişənlərinin adları `supabase/.env.example` daxilindədir. Gerçək dəyərləri Supabase Dashboard → Edge Functions → Secrets və ya CLI-nin məxfi env-file axını ilə əlavə edin. Onları source control-a və shell arqumentlərinə açıq açar kimi yazmayın.

| Dəyişən | Məqsəd |
|---|---|
| APP_ORIGIN | İcazəli frontend origin-i; slash/path yoxdur |
| GEMINI_API_KEY | Google server API açarı |
| ANTHROPIC_API_KEY | Anthropic server API açarı |
| XAI_API_KEY | xAI server API açarı |
| TMDB_READ_TOKEN | TMDB API Read Access Token |
| SCHEDULER_SECRET | Minimum 32 simvolluq kriptoqrafik təsadüfi worker sirri |
| VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY | Web Push VAPID cütü |
| VAPID_SUBJECT | VAPID üçün etibarlı mailto: və ya HTTPS subject |

Supabase runtime öz `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` dəyərlərini serverdə təmin edir. Bunları frontendə çıxarmayın.

```sh
supabase functions deploy account-delete
supabase functions deploy ai-chat
supabase functions deploy jarvis
supabase functions deploy scheduler
supabase functions deploy movie-proxy
supabase functions deploy push-subscription
supabase functions deploy integration-status
```

`supabase/config.toml`-da gateway legacy JWT yoxlaması söndürülüb. İstifadəçi endpoint-lərinin hamısı funksiyanın içində `auth.getUser(jwt)` və `account_allowed()` yoxlaması aparır. Admin metadata probe əlavə `is_admin()` tələb edir. Scheduler yalnız ayrıca server sirrini qəbul edir; brauzerə bu sirr verilmir. Bu daxili yoxlamaları çıxarmayın.

## 4. Model və qiymət konfiqurasiyası

Trusted operator Phase 2 qaydası ilə admin hesabını təyin etsin. Admin → AI modelləri:

1. Cari rəsmi model ID-si və hesabınızda ona çıxış olduğunu yoxlayın.
2. Cari qiyməti USD / 1 milyon giriş və çıxış tokeni kimi yazın.
3. Context və maksimum çıxış token limitlərini rəsmi sənəddən götürün.
4. Uyğun imkanları seçin: `short`, `analysis`, `study`.
5. Yalnız bundan sonra provider-i aktiv edin.

**Model adı və qiymətlər seed edilmir.** İşləməyən/köhnə model adı ilə real nəticə görüntüsü yaradılmır. Qiymət tier-i context uzunluğu, cache və reasoning-ə görə dəyişirsə, seçdiyiniz limitlərə uyğun konservativ yuxarı qiymət yazın və hesab console-sunda ayrıca billing hard cap təyin edin. Yeni qiymət/model yayılanda konfiqurasiya operator tərəfindən yoxlanmalıdır; avtomatik qiymət scraping-i yoxdur.

| Provider | Default rəsmi endpoint sərhədi |
|---|---|
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse` |
| Claude | `https://api.anthropic.com/v1/messages` |
| Grok | `https://api.x.ai/v1/responses` |

UI endpoint override eyni rəsmi host daxilindədir; başqa host və credential/query/hash qəbul edilmir. HTTP redirect-lər izlənmir. Yeni regional host lazım olarsa allowlist-i şüurlu dəyişib test edin. xAI üçün `store:false` göndərilir; bunun digər provider retention siyasətlərini ləğv etdiyi iddia edilmir.

Admin metadata status düyməsi model/configuration endpoint-inə GET sorğusu edir, inference yaratmır. Uğurlu metadata probe bütün model inference-lərinin işlədiyi anlamına gəlmir. Probe edilməyibsə UI “yoxlanmayıb” deyir.

## 5. Büdcə və istifadəçi təsdiqi

Default: sistem AI deaktiv, provider-lər deaktiv, global və şəxsi büdcələr 0, şəxsi sorğu limitləri 0, paid_consent=false, fallback=false, memory=false.

Admin → Parametrlər → AI sistemi, global günlük/aylıq USD, maksimum cəhdlər və default seçim. İstifadəçi → Hesabım → məlumat ötürülməsinə/ödənişə açıq razılıq, şəxsi USD və request limitləri. Müvafiq razılıq olmadan provider çağırılmır.

- UTC günü/ayı üzrə hər provider cəhdi sayılır; frontend mesaj sayı ilə eyni deyil.
- DB transaction + global row lock maksimum konfiqurasiya olunmuş context və çıxış üçün konservativ rezerv yaradır. Bu, qısa sorğuda da böyük model üçün böyük rezerv tələb edə bilər.
- Provider usage metadatası varsa faktiki token sayları ilə təxmini xərc yenilənir. Bu, provider invoice-u deyil.
- Timeout/cancel/yarımçıq cavabda provider-in xərci bilinmədiyi üçün rezerv saxlanılır. “Xərc olmadı” fərziyyəsi edilmir.
- Nəticəsi bilinməyən sorğu avtomatik təkrar edilmir. Fallback yalnız uyğun 429/502/503/504 xətasında, mətn çıxmamışdan əvvəl, Auto + fallback razılığı və yeni büdcə yoxlaması ilə mümkündür.
- Hesab silinəndə şəxsi usage sətirləri silinir, amma istifadəçi ID-si və məzmun saxlamayan anonim financial cəmlər global büdcəni qoruyur. Onlar invoice zəmanəti deyil.

Operator billed usage ilə rezervləri periodik tutuşdurmalıdır. Mövcud kod billing reconciliation/refund UI-si və qiymət tier-lərinin tam avtomatik hesablanmasını təqdim etmir.

## 6. JARVIS AutoPilot

1. Admin funksional `features.jarvis` interfeysini və server `automation_enabled` seçimini aktiv edir.
2. İstifadəçi AutoPilot və qeydlərə giriş razılığını aktiv edir.
3. Hər qeyddə ayrıca “AI analizinə icazə” seçilir. Ümumi razılıq bütün qeydləri avtomatik açmır.
4. Cron icazəli dəyişən qeydi bir dəfə analiz növbəsinə əlavə edir. “JARVIS analizi” düyməsi ilə ayrıca manual analiz də mümkündür.
5. AI tarix, vaxt, mövzu və hazırlıq ehtiyacına dair təklif verir. Tarix heç vaxt təsdiqsiz planlaşdırılmır: istifadəçi öz cihazının yerli vaxtında dəqiq icra vaxtını seçir.
6. Təsdiqlənmiş hazırlıq işi serverdə, telefon bağlı olsa da, növbəyə uyğun icra edilə bilər. Hər dispatch və publication mərhələsində permission/source version yoxlanır.
7. Material hesabda saxlanır, bildiriş üçün ayrıca razılıq varsa xəbər yaradılır.

Növbə hər cron çağırışında ən çox 1 iş götürür. `FOR UPDATE SKIP LOCKED`, 3 dəqiqəlik lease, təsadüfi lease token, source version və unique dedupe istifadə olunur. Cəhd limiti 3-dür. Dispatch edilmədən lease itibsə məhdud retry mümkündür; provider-ə göndərilmiş sorğunun taleyi bilinmirsə avtomatik replay edilmir. Xarici provider-lər ümumi exactly-once API təmin etmədiyindən “provider mütləq bir dəfə hesablayacaq” zəmanəti verilmir. Materialın iki dəfə publication edilməməsi DB ilə qorunur.

AutoPilot/notes access revokasiyası və job cancel aktiv işi dayandırmağa çalışır və nəticənin saxlanmasını rədd edir. Artıq provider-ə göndərilmiş sorğunun xərcini geri almaq mümkün olmaya bilər. Mənbə qeyd dəyişərsə köhnə iş publish edilmir.

Hazırda **müstəqil web research qoşulmayıb**. Material model biliyinə əsaslanan izah, nümunə və testdir; mənbələrin yoxlanıldığı və mətni verilməmiş konkret ev tapşırığının həll edildiyi iddia edilmir. AI mənbə linkləri versə belə onlar tətbiq tərəfindən təsdiqlənmiş sayılmır. Tapşırıq/təqvim üçün deterministic briefing var; ayrıca per-task/per-event AI analizi bu versiyada yoxdur.

## 7. Cron

Scheduler sirrini kriptoqrafik RNG ilə öz mühitinizdə yaradın; log və repo-da saxlamayın. Eyni dəyəri Edge `SCHEDULER_SECRET` və Supabase Vault-da `astra_scheduler_secret` kimi saxlayın. Vault-da `astra_project_url` həqiqi HTTPS Supabase origin-i olmalıdır.

Trusted SQL Editor-da `supabase/setup/scheduler.sql` faylını nəzərdən keçirib icra edin. pg_cron/pg_net/Vault imkanları layihədə aktiv olmalıdır. Bu sənəd avtomatik run edilməyib. Dayandırmaq:

```sql
select cron.unschedule('astra-runtime-minute');
```

Admin automation switch AI/JARVIS növbəsini dayandırır. İstifadəçi opted-in gündəlik xatırlatmalarını ayrıca söndürə bilər. Cron işləməzsə telefon özü server işlərini əvəz etmir.

## 8. TMDB

Read token-i serverdə saxlayın. Axtarış, trend, popular, janrlar, detallar, trailer və region üzrə watch-provider məlumatları proxy-dən alınır. Public TMDB cavabları serverdə 30 dəqiqə cache edilir; istifadəçinin private cavabları service worker-a yazılmır. İlkin film kataloqu yoxdur. Janr/əhval/müddət/şirkət seçimi TMDB discover + sadə alqoritmdən istifadə edir, AI sorğusu göndərmir.

Rəsmi, dəyişdirilməmiş TMDB loqosu `assets/icons/tmdb.svg` daxilindədir. UI-də tələb olunan notice və JustWatch krediti var. Qanuni izləmə düyməsi yalnız provider metadata-sında uyğun region linki olduqda göstərilir; bu, pirat və ya uydurulmuş deep link deyil. TMDB watch linki provider seçimləri səhifəsinə aparır. AZ/TR/US regionları mövcuddur; əlçatanlıq dəyişə bilər. Treyler yalnız doğrulanmış YouTube video key-dən qurulur.

TMDB-nin şəxsi/non-commercial və commercial istifadəyə dair şərtlərini layihənizin faktiki istifadəsinə görə rəsmi mənbədən yoxlayın. API lisenziyası və streaming platformasına giriş özü bu kodla verilmir.

## 9. Bildirişlər və iOS

Yeni hesabda bildiriş razılığı default false-dur. Hesabım bölməsində tətbiqdaxili bildiriş, daily/weekly briefing, günün filmi və push seçimləri ayrıdır. Push üçün VAPID server config və brauzerin ayrıca icazəsi də tələb olunur. Prompt yalnız istifadəçinin düyməyə toxunması ilə açılır. Hər hesabda maksimum 5 device subscription saxlanır.

iOS/iPadOS-da Web Push Home Screen web app üçün iOS 16.4+ şəraitində dəstəklənir; cihaz/brauzer məhdudiyyətləri ayrıca yoxlanmalıdır. Dəstək olmayanda tətbiqdaxili mərkəz işləyir. Push ekranında məxfi qeyd/tapşırıq mətni göstərilmir, generic “Yeni bildirişin var” mesajı gedir. Göndəriş cəhdi claim-once-dur; nəticəsi bilinməyən göndərişləri kor-koranə retry etməmək duplicate riskini azaldır, amma çatdırılma zəmanəti deyil.

Task reminder: 15 dəqiqə, calendar: 30 dəqiqə pəncərəsi. Daily briefing seçilmiş timezone-da 08:00-dan sonra, weekly summary bazar günü 18:00-dan sonra yaradılır. Cron gec işləyərsə gecikmə mümkündür. Köhnə tapşırığın completion tarixi bilinmirsə həftəlik completion statistikası üçün tarix uydurulmur.

## 10. Deploy və backup

```sh
npm test
npm run check
npm run build
npm run check:package
```

Vercel üçün repo kökündə `vercel.json` var. Yalnız public `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `APP_URL` frontend build environment-ə daxil edin. Vercel outputDirectory `dist`-dir. Provider/service/scheduler/VAPID private açarları Vercel frontend build dəyişənlərinə yox, Supabase Edge secrets-ə qoyulur. Başqa static hostda yalnız dist/ yayımlayın. Domen kökü deployment nəzərdə tutulub.

Build yalnız layihə daxilindəki yoxlanılmış `dist/` qovluğunu yenidən yaradır; source və database məlumatlarını silmir. Tarixi müəlliflik skriptlərini yenidən işə salmayın. Dəstəklənən əmrlər package.json daxilindədir.

HTTPS, CSP, HSTS, no-referrer və nosniff konfiqurasiya nümunəsi vercel.json-dadır. Custom Supabase domain-i varsa CSP connect-src-ə həmin dəqiq origin-i əlavə edin. Service worker/config revalidation başlıqlarını saxlayın. Auth callback query-lərini analytics və access-log payload-larına daxil etməyin. Native file upload bu versiyada dəstəklənmir; saxta əlavə etmə düyməsi saxlanılmayıb.

Database backup/PITR planınıza uyğun aktivləşdirilməli, ayrıca staging-də restore sınağı edilməlidir. Migration öncəsi backup və Edge secrets-in ayrıca təhlükəsiz idarəsi operator məsuliyyətidir; bu sessiyada backup və restore icra edilməyib. Ephemeral rate/cache/log cədvəllərinin retention siyasətini ayrıca təyin edin; şəxsi məlumatlara avtomatik mass-delete işi yoxdur.

## 11. Buraxılış qərarı

Kod + lokal testlər hazır olsa da canlı Auth/SMTP, provider billing və streaming, Cron, Deno npm runtime, push çatdırılması, real TMDB region məlumatı, HTTPS və fiziki iPhone testləri tələb olunur. Bunlar tamamlanmadan production-ready sertifikasiyası yoxdur. Tam 30 ssenari matrisi `FINAL-AUDIT.md` daxilindədir.

## Rəsmi API istinadları

- [Gemini text generation](https://ai.google.dev/gemini-api/docs/text-generation), [Generate Content reference](https://ai.google.dev/api/generate-content), [pricing](https://ai.google.dev/gemini-api/docs/pricing).
- [Claude Messages](https://platform.claude.com/docs/en/api/messages), [streaming](https://platform.claude.com/docs/en/build-with-claude/streaming), [pricing](https://platform.claude.com/docs/en/about-claude/pricing).
- [xAI Responses](https://docs.x.ai/developers/model-capabilities/text/generate-text), [streaming](https://docs.x.ai/developers/model-capabilities/text/streaming), [models/pricing](https://docs.x.ai/developers/models).
- [TMDB attribution](https://developer.themoviedb.org/docs/faq), [image basics](https://developer.themoviedb.org/docs/image-basics), [watch providers / JustWatch](https://developer.themoviedb.org/reference/movie-watch-providers).
- [WebKit: iOS Home Screen Web Push](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/).
- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
