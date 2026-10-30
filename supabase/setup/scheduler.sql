-- Run manually in trusted Supabase SQL Editor AFTER configuring Vault and Edge secrets.
-- Never put scheduler secrets into browser configuration or source control.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
-- Create Vault secrets named astra_project_url and astra_scheduler_secret in Dashboard.
-- astra_scheduler_secret must equal the Edge SCHEDULER_SECRET; astra_project_url is the HTTPS Supabase project origin.
select cron.schedule('astra-runtime-minute','* * * * *',$job$
 select net.http_post(
 url := (select decrypted_secret from vault.decrypted_secrets where name='astra_project_url')||'/functions/v1/scheduler',
 headers := jsonb_build_object('Content-Type','application/json','x-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='astra_scheduler_secret')),
 body := '{}'::jsonb,timeout_milliseconds := 170000
 );
$job$);
-- To stop all scheduled calls: select cron.unschedule('astra-runtime-minute');
-- Paid automation additionally requires runtime automation_enabled + user AutoPilot + note opt-in + budgets.
