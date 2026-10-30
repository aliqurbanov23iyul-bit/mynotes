import {getClient} from './supabase-client.js';
import {invoke} from './services/runtime-service.js';
export async function detachPush(){if(!('serviceWorker'in navigator))return;try{const registration=await navigator.serviceWorker.getRegistration();const subscription=await registration?.pushManager?.getSubscription();if(!subscription)return;try{await invoke('push-subscription',{action:'remove',endpoint:subscription.endpoint});}finally{await subscription.unsubscribe();}}catch{/* Sign-out must remain available even when the network is offline. */}}
