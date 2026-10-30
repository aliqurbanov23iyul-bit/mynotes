import {getClient,unwrap} from '../supabase-client.js';
export const adminService={async call(operation,args={}){const c=await getClient();return unwrap(c.rpc('admin_api',{operation,args}));},async runtime(operation,args={}){return unwrap((await getClient()).rpc('runtime_admin',{operation,args}));},async allowed(){return unwrap((await getClient()).rpc('is_admin'));}};
