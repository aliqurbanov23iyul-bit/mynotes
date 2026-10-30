import {getClient,unwrap} from './supabase-client.js';
import {config} from './config.js';
import {createAuthOperations} from './auth-operations.js';
export async function requireSession(){return createAuthOperations(await getClient(),config.appUrl).session();}
export async function logout(){const c=await getClient();await unwrap(c.auth.signOut());location.replace(new URL('../../login.html',import.meta.url));}
export async function watchSession(userId,onInvalid){const c=await getClient();return c.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||(session&&session.user.id!==userId))setTimeout(onInvalid,0);});}
