import {readFileSync,writeFileSync,existsSync} from 'node:fs';
if(existsSync('.env'))process.loadEnvFile('.env');
const supabaseUrl=process.env.SUPABASE_URL||'',publishableKey=process.env.SUPABASE_PUBLISHABLE_KEY||'',appUrl=process.env.APP_URL||'';
if(!supabaseUrl||!publishableKey||!appUrl)throw Error('SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY və APP_URL tələb olunur.');
const url=new URL(supabaseUrl);if(url.protocol!=='https:'&&!['localhost','127.0.0.1'].includes(url.hostname))throw Error('HTTPS tələb olunur.');
if(!publishableKey.startsWith('sb_publishable_'))throw Error('Yalnız Supabase publishable key qəbul edilir; secret/service_role qəbul edilmir.');
const app=new URL(appUrl);if(app.protocol!=='https:'&&!['localhost','127.0.0.1'].includes(app.hostname))throw Error('APP_URL HTTPS olmalıdır.');
writeFileSync('assets/js/config.js',`// Public configuration: no server secrets.\nexport const config=Object.freeze(${JSON.stringify({supabaseUrl:url.origin,publishableKey,appUrl:app.href.replace(/\/$/,'')})});\n`);
console.log('Public konfiqurasiya yaradıldı. Heç bir açar çap edilmədi.');
