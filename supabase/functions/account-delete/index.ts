import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
Deno.serve(async (req: Request) => {
 const origin=Deno.env.get('APP_ORIGIN')||'';
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Content-Type':'application/json','Cache-Control':'no-store'};
 const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
 if(!origin||req.headers.get('origin')!==origin)return reply(403,{error:'Origin not allowed'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{error:'Method not allowed'});
 if(!req.headers.get('content-type')?.includes('application/json'))return reply(415,{error:'JSON required'});
 try {
 const text=await req.text();if(text.length>4096)return reply(413,{error:'Request too large'});
 const {password,confirmation}=JSON.parse(text);
 if(typeof password!=='string'||password.length>128||confirmation!=='HESABIMI SİL')return reply(400,{error:'Confirmation required'});
 const jwt=req.headers.get('authorization')?.replace(/^Bearer\s+/i,'');if(!jwt)return reply(401,{error:'Authentication required'});
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_ANON_KEY')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const caller=createClient(url,key,{global:{headers:{Authorization:`Bearer ${jwt}`}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data:{user},error}=await caller.auth.getUser(jwt);
 if(error||!user?.email)return reply(401,{error:'Authentication required'});
 const {data:allowed,error:accessError}=await caller.rpc('account_allowed');if(accessError||!allowed)return reply(403,{error:'Account unavailable'});
 const {data:isAdmin,error:roleError}=await caller.rpc('is_admin');if(roleError||isAdmin)return reply(403,{error:'Admin membership must first be removed by a trusted operator'});
 // Reauthenticate with the current password on the server. Never log or persist it.
 const reauth=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:proof,error:reauthError}=await reauth.auth.signInWithPassword({email:user.email,password});
 if(reauthError||proof.user?.id!==user.id)return reply(403,{error:'Reauthentication failed'});
 await reauth.auth.signOut({scope:'local'});
 const privileged=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
 const {error:deleteError}=await privileged.auth.admin.deleteUser(user.id);
 if(deleteError)return reply(500,{error:'Deletion failed'});
 return reply(200,{ok:true});
 } catch {return reply(400,{error:'Request could not be processed'});}
});
