import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const STEAM_API_KEY = Deno.env.get('STEAM_WEB_API_KEY') || '';
const SITE_ORIGINS = (Deno.env.get('SITE_ORIGINS') || 'https://mysite-esports-platform.vercel.app,http://localhost:3000,http://127.0.0.1:3000').split(',').map(x=>x.trim()).filter(Boolean);
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/steam-auth`;

const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const anon = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

function allowedOrigin(origin:string|null){ return !!origin && SITE_ORIGINS.includes(origin); }
function cors(origin:string|null){ const allowed=allowedOrigin(origin)?origin!:SITE_ORIGINS[0]; return {'Access-Control-Allow-Origin':allowed,'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Vary':'Origin'}; }
function json(body:unknown,status=200,origin:string|null=null){ return new Response(JSON.stringify(body),{status,headers:{...cors(origin),'content-type':'application/json; charset=utf-8','cache-control':'no-store'}}); }
function safeReturnUrl(raw:string|undefined){ const fallback=`${SITE_ORIGINS[0]}/profile.html`; if(!raw)return fallback; try{const u=new URL(raw); if(!SITE_ORIGINS.includes(u.origin))return fallback; return u.toString();}catch{return fallback;} }
function token(){ const b=new Uint8Array(32); crypto.getRandomValues(b); return Array.from(b,x=>x.toString(16).padStart(2,'0')).join(''); }
function redirectWith(url:string,key:string,value:string){ const u=new URL(url); u.searchParams.set(key,value); return new Response(null,{status:302,headers:{location:u.toString(),'cache-control':'no-store'}}); }
function steamAuthUrl(mode:string,state:string){ const cb=new URL(FUNCTION_URL); cb.searchParams.set('mode',mode); cb.searchParams.set('state',state); const a=new URL('https://steamcommunity.com/openid/login'); a.searchParams.set('openid.ns','http://specs.openid.net/auth/2.0'); a.searchParams.set('openid.mode','checkid_setup'); a.searchParams.set('openid.return_to',cb.toString()); a.searchParams.set('openid.realm',SUPABASE_URL); a.searchParams.set('openid.identity','http://specs.openid.net/auth/2.0/identifier_select'); a.searchParams.set('openid.claimed_id','http://specs.openid.net/auth/2.0/identifier_select'); return a.toString(); }
async function verifySteam(url:URL){ const p=new URLSearchParams(); for(const [k,v] of url.searchParams.entries())if(k.startsWith('openid.'))p.set(k,v); if(p.get('openid.mode')!=='id_res')throw new Error('Steam отменил или не подтвердил вход'); p.set('openid.mode','check_authentication'); const r=await fetch('https://steamcommunity.com/openid/login',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:p.toString()}); const txt=await r.text(); if(!r.ok||!/(^|\n)is_valid:true(\n|$)/.test(txt))throw new Error('Steam не подтвердил подлинность ответа'); const claimed=url.searchParams.get('openid.claimed_id')||''; const m=claimed.match(/^https?:\/\/steamcommunity\.com\/openid\/id\/([0-9]{17})\/?$/); if(!m)throw new Error('SteamID64 не найден'); return m[1]; }
async function steamSummary(steamid:string){ if(!STEAM_API_KEY)return null; const u=new URL('https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/'); u.searchParams.set('key',STEAM_API_KEY); u.searchParams.set('steamids',steamid); const r=await fetch(u); if(!r.ok)throw new Error('Steam Web API временно недоступен'); const j=await r.json(); return j?.response?.players?.[0]||null; }
async function userFromJwt(req:Request){ const auth=req.headers.get('authorization')||''; const jwt=auth.toLowerCase().startsWith('bearer ')?auth.slice(7):''; if(!jwt)return null; const {data:{user},error}=await anon.auth.getUser(jwt); return error?null:user; }

Deno.serve(async(req:Request)=>{
  const origin=req.headers.get('origin'); if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors(origin)});
  const url=new URL(req.url); let body:any={}; if(req.method==='POST'){try{body=await req.json();}catch{}}
  const mode=url.searchParams.get('mode')||body?.mode||'start';

  if(req.method==='POST'&&mode==='start'){
    if(!allowedOrigin(origin))return json({error:'Недопустимый источник запроса'},403,origin);
    const user=await userFromJwt(req); if(!user)return json({error:'Необходим вход в аккаунт'},401,origin);
    const returnUrl=safeReturnUrl(body?.returnUrl),state=token(); const {error}=await service.rpc('steam_create_link_session',{p_user_id:user.id,p_token:state,p_return_url:returnUrl}); if(error)return json({error:error.message},400,origin); return json({url:steamAuthUrl('callback',state)},200,origin);
  }
  if(req.method==='POST'&&mode==='login-start'){
    if(!allowedOrigin(origin))return json({error:'Недопустимый источник запроса'},403,origin);
    const returnUrl=safeReturnUrl(body?.returnUrl),state=token(); const {error}=await service.rpc('steam_create_login_session',{p_token:state,p_return_url:returnUrl}); if(error)return json({error:error.message},400,origin); return json({url:steamAuthUrl('login-callback',state)},200,origin);
  }
  if(req.method==='GET'&&mode==='callback'){
    const state=url.searchParams.get('state')||''; let fallback=`${SITE_ORIGINS[0]}/player-edit.html`;
    try{ if(!state)throw new Error('Отсутствует state'); const steamid=await verifySteam(url); const summary=await steamSummary(steamid).catch(()=>null); const profileUrl=summary?.profileurl||`https://steamcommunity.com/profiles/${steamid}/`; const {data:returnUrl,error}=await service.rpc('steam_consume_link_session',{p_token:state,p_steam_id:steamid,p_profile_url:profileUrl,p_persona_name:summary?.personaname||null,p_avatar_url:summary?.avatarfull||null}); if(error)throw new Error(error.message); fallback=safeReturnUrl(returnUrl||undefined); return redirectWith(fallback,'steam','linked'); }
    catch(e){const target=new URL(fallback); target.searchParams.set('steam','error'); target.searchParams.set('steam_message',(e instanceof Error?e.message:'Ошибка Steam').slice(0,180)); return new Response(null,{status:302,headers:{location:target.toString(),'cache-control':'no-store'}});}
  }
  if(req.method==='GET'&&mode==='login-callback'){
    const state=url.searchParams.get('state')||''; let returnUrl=`${SITE_ORIGINS[0]}/profile.html`;
    try{ if(!state)throw new Error('Отсутствует state'); const {data:stored,error:se}=await service.rpc('steam_consume_login_session',{p_token:state}); if(se)throw new Error(se.message); returnUrl=safeReturnUrl(stored||undefined); const steamid=await verifySteam(url); const {data:p,error:pe}=await service.from('profiles').select('id').eq('steam_id',steamid).maybeSingle(); if(pe)throw new Error(pe.message); if(!p?.id){const target=new URL(`${new URL(returnUrl).origin}/login.html`); target.searchParams.set('steam','not_linked'); return new Response(null,{status:302,headers:{location:target.toString(),'cache-control':'no-store'}});} const exchange=token(); const {error:xe}=await service.rpc('steam_create_login_exchange',{p_token:exchange,p_user_id:p.id,p_return_url:returnUrl}); if(xe)throw new Error(xe.message); const complete=new URL(`${new URL(returnUrl).origin}/steam-login-complete.html`); complete.searchParams.set('code',exchange); return new Response(null,{status:302,headers:{location:complete.toString(),'cache-control':'no-store'}}); }
    catch(e){const target=new URL(`${new URL(returnUrl).origin}/login.html`); target.searchParams.set('steam','error'); target.searchParams.set('steam_message',(e instanceof Error?e.message:'Ошибка Steam').slice(0,180)); return new Response(null,{status:302,headers:{location:target.toString(),'cache-control':'no-store'}});}
  }
  if(req.method==='POST'&&mode==='exchange'){
    if(!allowedOrigin(origin))return json({error:'Недопустимый источник запроса'},403,origin); if(!body?.code)return json({error:'Код входа отсутствует'},400,origin);
    const {data:rows,error}=await service.rpc('steam_consume_login_exchange',{p_token:String(body.code)}); if(error)return json({error:error.message},400,origin); const row=Array.isArray(rows)?rows[0]:rows; if(!row?.user_id)return json({error:'Код входа недействителен'},400,origin);
    const {data:userData,error:ue}=await service.auth.admin.getUserById(row.user_id); const email=userData?.user?.email; if(ue||!email)return json({error:'У аккаунта отсутствует email для создания сессии'},400,origin);
    const {data:link,error:le}=await service.auth.admin.generateLink({type:'magiclink',email}); const hash=link?.properties?.hashed_token; if(le||!hash)return json({error:le?.message||'Не удалось создать сессию'},500,origin);
    const {data:verified,error:ve}=await anon.auth.verifyOtp({token_hash:hash,type:'magiclink'}); if(ve||!verified.session)return json({error:ve?.message||'Не удалось подтвердить сессию'},500,origin);
    return json({access_token:verified.session.access_token,refresh_token:verified.session.refresh_token,returnUrl:safeReturnUrl(row.return_url)},200,origin);
  }
  if(req.method==='POST'&&mode==='refresh'){
    if(!allowedOrigin(origin))return json({error:'Недопустимый источник запроса'},403,origin); const user=await userFromJwt(req); if(!user)return json({error:'Необходим вход в аккаунт'},401,origin); if(!STEAM_API_KEY)return json({error:'STEAM_WEB_API_KEY пока не настроен на сервере'},503,origin);
    const {data:p,error:pe}=await service.from('profiles').select('steam_id,avatar_source').eq('id',user.id).maybeSingle(); if(pe||!p?.steam_id)return json({error:pe?.message||'Steam не привязан'},400,origin); const summary=await steamSummary(p.steam_id); if(!summary)return json({error:'Steam-профиль не найден'},404,origin);
    const patch:any={steam_profile_url:summary.profileurl||`https://steamcommunity.com/profiles/${p.steam_id}/`,steam_persona_name:summary.personaname||null,steam_avatar_url:summary.avatarfull||null,updated_at:new Date().toISOString()}; if(p.avatar_source==='steam'&&summary.avatarfull)patch.avatar_url=summary.avatarfull; const {error:up}=await service.from('profiles').update(patch).eq('id',user.id); if(up)return json({error:up.message},400,origin); return json({ok:true,steam_id:p.steam_id,persona_name:patch.steam_persona_name,avatar_url:patch.steam_avatar_url,profile_url:patch.steam_profile_url},200,origin);
  }
  return json({error:'Маршрут не найден'},404,origin);
});
