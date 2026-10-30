import {mkdir,cp,copyFile,readdir,rm,lstat} from 'node:fs/promises';
import path from 'node:path';import {fileURLToPath} from 'node:url';
if(process.env.SUPABASE_URL||process.env.SUPABASE_PUBLISHABLE_KEY)await import('./configure.mjs');
await import('./vendor.mjs');await import('./markdown-vendor.mjs');await import('./cache.mjs');
const root=path.resolve(fileURLToPath(new URL('../',import.meta.url))),target=path.resolve('dist');if(path.dirname(target)!==root||path.basename(target)!=='dist')throw Error('Build path outside project');const info=await lstat(target).catch(()=>null);if(info?.isSymbolicLink())throw Error('Refusing linked output directory');console.log('Verified generated output: '+target);await rm(target,{recursive:true,force:true});await mkdir(target,{recursive:true});
for(const file of await readdir('.'))if(file.endsWith('.html')||['manifest.json','service-worker.js'].includes(file))await copyFile(file,'dist/'+file);
await cp('admin','dist/admin',{recursive:true});await cp('assets','dist/assets',{recursive:true,filter:src=>!src.includes('preview')&&!/pets[\\/](luna|milo|peach)\.png$/.test(src)&&!src.endsWith('prompts.md')});
console.log('dist/ hazırdır. Yalnız frontend faylları; .env və supabase/functions daxil deyil.');
