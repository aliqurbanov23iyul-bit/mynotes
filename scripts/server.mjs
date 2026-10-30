import http from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
export function createServer(root=process.cwd()){
 const pages=new Set(['index.html','notes.html','discover.html','ai.html','login.html','auth-callback.html','reset-password.html','profile.html','offline.html','admin/index.html','admin/users.html','admin/ai-management.html','admin/jarvis.html','admin/movies.html','admin/settings.html','manifest.json','service-worker.js']);
 return http.createServer(async(req,res)=>{
 res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Cache-Control','no-store');
 res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://*.supabase.co wss://*.supabase.co http://127.0.0.1:54321; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'");
 if(!['GET','HEAD'].includes(req.method)){res.writeHead(405).end();return;}
 try{const url=new URL(req.url,'http://localhost');let route=decodeURIComponent(url.pathname);if(route.includes('\\')||route.includes('\0'))throw Error();if(route.endsWith('/'))route+='index.html';route=route.slice(1);const file=path.resolve(root,route);const allowed=pages.has(route)||(/^assets\/(css|js|icons|images)\/[a-zA-Z0-9_./-]+$/.test(route)&&!route.split('/').some(p=>p.startsWith('.'))&&['.js','.css','.svg','.png'].includes(path.extname(route)));if(!allowed||!file.startsWith(path.resolve(root)+path.sep)){res.writeHead(404).end();return;}const body=await readFile(file);res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.css':'text/css','.js':'text/javascript','.json':'application/json','.svg':'image/svg+xml','.png':'image/png'})[path.extname(file)]);res.writeHead(200);res.end(req.method==='HEAD'?undefined:body);}catch{res.writeHead(404).end('Tapılmadı');}
 });
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))createServer().listen(4173,'127.0.0.1',()=>console.log('ASTRA: http://127.0.0.1:4173'));
