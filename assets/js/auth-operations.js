// Pure adapter allows authentication lifecycle tests without a live Supabase account.
export function createAuthOperations(client,appUrl){return {
 async session(){const {data:{session},error}=await client.auth.getSession();if(error)throw error;if(!session)return null;const {data:{user},error:invalid}=await client.auth.getUser();if(invalid){if(invalid.status===401||invalid.status===403||['session_not_found','refresh_token_not_found','bad_jwt'].includes(invalid.code)){await client.auth.signOut({scope:'local'});return null;}throw invalid;}if(!user){await client.auth.signOut({scope:'local'});return null;}return user;},
 async signup(email,password,name){return client.auth.signUp({email,password,options:{data:{display_name:name},emailRedirectTo:appUrl+'/auth-callback.html'}});},
 async login(email,password){return client.auth.signInWithPassword({email,password});},
 async forgot(email){return client.auth.resetPasswordForEmail(email,{redirectTo:appUrl+'/reset-password.html'});},
 async resend(email){return client.auth.resend({type:'signup',email,options:{emailRedirectTo:appUrl+'/auth-callback.html'}});},
 async updatePassword(password){return client.auth.updateUser({password});},
 async logout(){return client.auth.signOut();}
};}
