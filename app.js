(() => {
  'use strict';

  // Global page layout: keeps the copyright footer at the bottom on short pages,
  // while letting it follow content naturally on long pages. All current pages
  // load app.js, so this also becomes the default for future pages that use it.
  const layoutStyle = document.createElement('style');
  layoutStyle.id = 'global-page-layout';
  layoutStyle.textContent = `
    html { min-height: 100%; }
    body {
      min-height: 100vh !important;
      min-height: 100dvh !important;
      display: flex !important;
      flex-direction: column !important;
    }
    footer {
      margin-top: auto !important;
      flex: 0 0 auto !important;
      width: 100% !important;
    }
  `;
  (document.head || document.documentElement).appendChild(layoutStyle);

  const SUPABASE_URL = 'https://wijtkxzleuqdaabfiwsh.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_q5uwQ3c6b37snDhO2lV7Hg_kZpOEyh0';

  if (!window.supabase?.createClient) {
    console.error('Supabase client library is not loaded');
    return;
  }

  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      storage: window.localStorage,
      storageKey: 'esports-auth'
    }
  });

  const nativeFetch = window.fetch.bind(window);

  function mapTournament(t) {
    return {
      id: t.id,
      name: t.name,
      game: t.game,
      description: t.description,
      startDate: t.start_date,
      endDate: t.end_date,
      format: t.format,
      status: t.status,
      maxTeams: t.max_teams,
      winner: t.winner_team_id,
      runnerUp: t.runner_up_team_id,
      registrationOpensAt: t.registration_opens_at,
      registrationClosesAt: t.registration_closes_at,
      teamSize: t.team_size,
      maxReserves: t.max_reserves,
      playoffs: t.playoffs || {}
    };
  }

  const api = {
    client,

    async getSession() {
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      return data.session;
    },

    async getProfile() {
      const session = await this.getSession();
      if (!session) return null;
      const { data, error } = await client.from('profiles').select('*').eq('id', session.user.id).maybeSingle();
      if (error) throw error;
      return data;
    },

    async listTournaments() {
      const { data, error } = await client.from('tournaments').select('*').order('created_at', { ascending: false });
      if (error) throw error;
      return (data || []).map(mapTournament);
    },

    async getTournament(id) {
      const { data, error } = await client.from('tournaments').select('*').eq('id', id).maybeSingle();
      if (error) throw error;
      return data ? mapTournament(data) : null;
    },

    async getTournamentBundle(id = 'dota2-winter-2026') {
      const { data: tournament, error: tError } = await client.from('tournaments').select('*').eq('id', id).maybeSingle();
      if (tError) throw tError;
      if (!tournament) throw new Error('Турнир не найден');

      const { data: teams, error: teamsError } = await client.from('teams').select('*').eq('tournament_id', tournament.id).order('group_position', { ascending: true, nullsFirst: false });
      if (teamsError) throw teamsError;

      let legacy = null;
      if (id === 'dota2-winter-2026') {
        try {
          const legacyResponse = await nativeFetch('data/tournament-dota2-2026.json');
          if (legacyResponse.ok) legacy = await legacyResponse.json();
        } catch (_) {}
      }
      const legacyTeams = new Map((legacy?.teams || []).map(team => [team.id, team]));

      return {
        tournament: mapTournament(tournament),
        teams: (teams || []).map(t => ({
          id: t.id,
          name: t.name,
          tag: t.tag,
          logo: t.logo,
          region: t.region,
          groupStage: t.group_stage || {},
          players: (t.roster_public?.length ? t.roster_public : legacyTeams.get(t.id)?.players) || []
        })),
        playoffs: (tournament.playoffs && Object.keys(tournament.playoffs).length ? tournament.playoffs : legacy?.playoffs) || { upperBracket: {}, lowerBracket: {}, grandFinal: null }
      };
    },

    async getMyApplications() {
      const session = await this.getSession();
      if (!session) return [];
      const { data: apps, error } = await client.from('tournament_applications').select('id,tournament_id,team_id,status,submitted_at,reviewed_at').eq('submitted_by', session.user.id).order('submitted_at', { ascending: false });
      if (error) throw error;
      if (!apps?.length) return [];

      const teamIds = [...new Set(apps.map(a => a.team_id))];
      const tournamentIds = [...new Set(apps.map(a => a.tournament_id))];
      const [{ data: teams }, { data: tournaments }] = await Promise.all([
        client.from('teams').select('id,name,tag').in('id', teamIds),
        client.from('tournaments').select('id,name,game,status').in('id', tournamentIds)
      ]);
      const teamMap = new Map((teams || []).map(x => [x.id, x]));
      const tournamentMap = new Map((tournaments || []).map(x => [x.id, x]));
      return apps.map(a => ({ ...a, team: teamMap.get(a.team_id) || null, tournament: tournamentMap.get(a.tournament_id) || null }));
    },

    async registerTeam(form) {
      const session = await this.getSession();
      if (!session) throw new Error('Сначала войдите в аккаунт.');

      const teamInputs = form.querySelector('.form-section .form-row')?.querySelectorAll('input') || [];
      const name = teamInputs[0]?.value?.trim();
      const tag = teamInputs[1]?.value?.trim()?.toUpperCase();
      if (!name || !tag) throw new Error('Укажите название и тег команды.');

      const params = new URLSearchParams(location.search);
      const tournamentId = params.get('tournament') || params.get('id');
      if (!tournamentId) throw new Error('Не указан турнир.');

      const tournament = await this.getTournament(tournamentId);
      if (!tournament) throw new Error('Турнир не найден.');
      if (tournament.status !== 'registration') throw new Error('Регистрация на этот турнир сейчас закрыта.');
      const now = Date.now();
      if (tournament.registrationOpensAt && now < new Date(tournament.registrationOpensAt).getTime()) throw new Error('Регистрация ещё не началась.');
      if (tournament.registrationClosesAt && now > new Date(tournament.registrationClosesAt).getTime()) throw new Error('Регистрация уже завершена.');

      const roster = [...form.querySelectorAll('.player-card')].map((card, index) => {
        const inputs = [...card.querySelectorAll('input')];
        const texts = inputs.filter(i => i.type === 'text');
        const captainBox = card.querySelector('.captain-checkbox');
        return {
          full_name: texts[0]?.value?.trim() || '',
          city: texts[1]?.value?.trim() || '',
          email: inputs.find(i => i.type === 'email')?.value?.trim() || '',
          phone: inputs.find(i => i.type === 'tel')?.value?.trim() || '',
          steam_url: inputs.find(i => i.type === 'url')?.value?.trim() || '',
          game_hours: Number(inputs.filter(i => i.type === 'number')[0]?.value || 0),
          mmr: Number(inputs.filter(i => i.type === 'number')[1]?.value || 0),
          reserve: tournament.teamSize ? index >= tournament.teamSize : index >= 5,
          captain: index === 0 || Boolean(captainBox?.checked)
        };
      }).filter(p => p.full_name || p.email || p.steam_url);

      if (tournament.teamSize && roster.filter(p => !p.reserve).length < tournament.teamSize) {
        throw new Error(`Нужно заполнить минимум ${tournament.teamSize} игроков основного состава.`);
      }

      const { data: team, error: teamError } = await client.from('teams').insert({
        tournament_id: tournamentId,
        name,
        tag,
        logo: tag.slice(0, 3),
        region: 'Россия',
        owner_id: session.user.id,
        roster_public: []
      }).select('id').single();
      if (teamError) throw teamError;

      const { error: appError } = await client.from('tournament_applications').insert({
        tournament_id: tournamentId,
        team_id: team.id,
        submitted_by: session.user.id,
        roster_private: roster
      });
      if (appError) throw appError;
      return team;
    }
  };

  window.EsportsAPI = api;

  window.fetch = async (resource, init) => {
    const url = typeof resource === 'string' ? resource : resource?.url || '';
    if (/data\/tournament-dota2-2026\.json(?:\?|$)/.test(url)) {
      try {
        const data = await api.getTournamentBundle('dota2-winter-2026');
        return new Response(JSON.stringify(data), { status: 200, headers: { 'Content-Type': 'application/json' } });
      } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
      }
    }
    return nativeFetch(resource, init);
  };

  function renderNav(session) {
    document.querySelectorAll('.profile-link').forEach(el => { el.style.display = session ? 'list-item' : 'none'; });
    document.querySelectorAll('.login-link').forEach(el => { el.style.display = session ? 'none' : 'list-item'; });
    document.querySelectorAll('.logout-link').forEach(el => { el.style.display = session ? 'list-item' : 'none'; });
  }

  async function getInitialSession() {
    try { return await api.getSession(); }
    catch (error) { console.error('Не удалось получить сессию:', error); return null; }
  }

  window.logout = async () => {
    try { await client.auth.signOut(); }
    finally { window.location.replace('index.html'); }
  };

  function showError(message) { alert(message || 'Произошла ошибка. Попробуйте ещё раз.'); }

  function safeReturnUrl(value, fallback = 'profile.html') {
    if (!value) return fallback;
    try {
      const candidate = new URL(value, location.origin);
      if (candidate.origin !== location.origin) return fallback;
      return `${candidate.pathname}${candidate.search}${candidate.hash}`;
    } catch (_) { return fallback; }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    const initialSession = await getInitialSession();
    renderNav(initialSession);
    client.auth.onAuthStateChange((_event, session) => renderNav(session));

    const loginForm = document.getElementById('loginForm');
    if (loginForm) {
      const returnParam = new URLSearchParams(location.search).get('return');
      if (initialSession) { window.location.replace(safeReturnUrl(returnParam)); return; }
      loginForm.addEventListener('submit', async event => {
        event.preventDefault(); event.stopImmediatePropagation();
        const email = document.getElementById('loginEmail')?.value?.trim();
        const password = document.getElementById('loginPassword')?.value || '';
        const button = loginForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const { data, error } = await client.auth.signInWithPassword({ email, password });
          if (error) throw error;
          if (!data.session) throw new Error('Не удалось создать сессию. Попробуйте войти ещё раз.');
          renderNav(data.session);
          window.location.replace(safeReturnUrl(returnParam));
        } catch (error) { showError(error.message); if (button) button.disabled = false; }
      }, true);
    }

    const registerForm = document.getElementById('registerForm');
    if (registerForm) {
      registerForm.addEventListener('submit', async event => {
        event.preventDefault(); event.stopImmediatePropagation();
        const nickname = document.getElementById('regNickname')?.value?.trim();
        const email = document.getElementById('regEmail')?.value?.trim();
        const password = document.getElementById('regPassword')?.value || '';
        const confirm = document.getElementById('regPasswordConfirm')?.value || '';
        if (password !== confirm) return showError('Пароли не совпадают');
        const button = registerForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const { data, error } = await client.auth.signUp({ email, password, options: { data: { nickname }, emailRedirectTo: `${location.origin}/login.html` } });
          if (error) throw error;
          if (data.session) window.location.replace('profile.html');
          else { alert('Аккаунт создан. Подтвердите email по ссылке в письме, затем войдите.'); window.location.replace('login.html'); }
        } catch (error) { showError(error.message); if (button) button.disabled = false; }
      }, true);
    }

    const teamForm = document.getElementById('registerTeamForm');
    if (teamForm) {
      if (!initialSession) {
        alert('Для регистрации команды необходимо войти в аккаунт.');
        location.href = `login.html?return=${encodeURIComponent(location.pathname + location.search)}`;
        return;
      }
      const tournamentId = new URLSearchParams(location.search).get('tournament') || new URLSearchParams(location.search).get('id');
      const tournament = tournamentId ? await api.getTournament(tournamentId).catch(() => null) : null;
      if (!tournament || tournament.status !== 'registration') {
        const button = teamForm.querySelector('button[type="submit"]');
        if (button) { button.disabled = true; button.textContent = tournament?.status === 'draft' ? 'Турнир в черновике' : 'Регистрация закрыта'; }
      }
      teamForm.addEventListener('submit', async event => {
        event.preventDefault(); event.stopImmediatePropagation();
        const button = teamForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const team = await api.registerTeam(teamForm);
          alert('Заявка команды отправлена на рассмотрение.');
          location.href = `team.html?id=${encodeURIComponent(team.id)}`;
        } catch (error) { showError(error.message); if (button) button.disabled = false; }
      }, true);
    }

    if (location.pathname.endsWith('/profile.html') || location.pathname.endsWith('profile.html')) {
      if (!initialSession) { location.replace('login.html?return=profile.html'); return; }
      const profile = await api.getProfile().catch(() => null);
      const nickname = profile?.nickname || initialSession.user.user_metadata?.nickname || initialSession.user.email?.split('@')[0] || 'Player';
      const h1 = document.querySelector('.profile-hero h1');
      const avatar = document.querySelector('.profile-avatar');
      const handle = document.querySelector('.profile-handle');
      const teamBadge = document.querySelector('.profile-team');
      if (h1) h1.textContent = nickname;
      if (avatar) avatar.textContent = nickname.charAt(0).toUpperCase();
      if (handle) handle.textContent = `@${nickname} · ${initialSession.user.email}`;
      const { data: ownedTeams } = await client.from('teams').select('name').eq('owner_id', initialSession.user.id).limit(1);
      if (teamBadge) teamBadge.textContent = ownedTeams?.[0]?.name || 'Без команды';

      const list = document.getElementById('applicationsList');
      if (list) {
        const apps = await api.getMyApplications().catch(() => []);
        const statusText = { pending: 'На рассмотрении', approved: 'Одобрена', rejected: 'Отклонена' };
        list.innerHTML = apps.length ? apps.map(a => `
          <div class="application-row glass">
            <div><strong>${a.tournament?.name || a.tournament_id}</strong><span>${a.team?.name || 'Команда'} · ${a.tournament?.game || ''}</span></div>
            <span class="application-status status-${a.status}">${statusText[a.status] || a.status}</span>
          </div>`).join('') : '<div class="glass empty-state"><strong>Заявок пока нет</strong>Здесь появятся заявки команд, отправленные на турниры.</div>';
      }
    }
  });
})();
