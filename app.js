(() => {
  'use strict';

  const layoutStyle = document.createElement('style');
  layoutStyle.id = 'global-page-layout';
  layoutStyle.textContent = `
    @view-transition { navigation: auto; }

    html { min-height: 100%; }
    body {
      min-height: 100vh !important;
      min-height: 100dvh !important;
      display: flex !important;
      flex-direction: column !important;
      overflow-x: hidden;
      opacity: 1;
      transform: translateY(0);
      transition: opacity .16s ease, transform .16s ease;
    }
    body.page-leaving {
      opacity: 0;
      transform: translateY(4px);
    }
    ::view-transition-old(root) { animation: siteFadeOut .16s ease both; }
    ::view-transition-new(root) { animation: siteFadeIn .2s ease both; }
    @keyframes siteFadeOut { to { opacity: 0; transform: translateY(4px); } }
    @keyframes siteFadeIn { from { opacity: 0; transform: translateY(4px); } to { opacity: 1; transform: translateY(0); } }

    footer {
      margin-top: auto !important;
      flex: 0 0 auto !important;
      width: 100% !important;
    }

    img, video, iframe, canvas, svg { max-width: 100%; }
    main, .container, section, article, form, .glass, .card, .panel, .row { min-width: 0; }

    table th,
    table td {
      text-align: center !important;
      vertical-align: middle !important;
      padding: 14px 16px !important;
      line-height: 1.35 !important;
    }

    table th > *,
    table td > * {
      vertical-align: middle;
    }

    table td > .match-team-cell,
    table td > .team-cell,
    table td > .actions {
      justify-content: center !important;
      align-items: center !important;
      margin-left: auto !important;
      margin-right: auto !important;
    }

    button,
    .btn,
    a.btn,
    .tab,
    .filter,
    .btn-login,
    [role='button'] {
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      text-align: center !important;
      min-height: 40px;
      padding: 10px 16px !important;
      line-height: 1.2 !important;
      vertical-align: middle !important;
      gap: 8px;
    }

    .btn-login {
      background: transparent !important;
      border: 1px solid rgba(52,211,153,.12) !important;
      color: #f0fdf4 !important;
      box-shadow: none !important;
      transition: background-color .2s ease, border-color .2s ease, color .2s ease, box-shadow .2s ease !important;
    }
    .btn-login:hover,
    .btn-login:focus-visible {
      background: rgba(52,211,153,.12) !important;
      border-color: rgba(52,211,153,.48) !important;
      color: #34d399 !important;
      box-shadow: 0 0 0 1px rgba(52,211,153,.06), 0 0 18px rgba(52,211,153,.08) !important;
    }

    .badge,
    .status,
    .round-badge,
    .application-status,
    .team-game-badge,
    .team-rank,
    .hero-tag {
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      text-align: center !important;
      min-height: 28px;
      padding: 6px 10px !important;
      line-height: 1.2 !important;
    }

    .mini,
    .stat-card {
      display: flex !important;
      flex-direction: column !important;
      align-items: center !important;
      justify-content: center !important;
      text-align: center !important;
      padding: 14px 12px !important;
    }

    input:not([type='checkbox']):not([type='radio']):not([type='range']):not([type='file']),
    select {
      min-height: 42px;
      padding: 10px 14px !important;
      line-height: 1.2 !important;
      max-width: 100%;
    }

    .search input:not([type='checkbox']):not([type='radio']):not([type='range']):not([type='file']) {
      padding-left: 52px !important;
    }

    textarea {
      padding: 12px 14px !important;
      line-height: 1.45 !important;
      max-width: 100%;
    }

    .actions {
      align-items: center !important;
      gap: 10px !important;
      flex-wrap: wrap !important;
    }

    @media (max-width: 760px) {
      nav {
        width: 100% !important;
        min-height: 58px !important;
        height: auto !important;
        padding: 8px 14px !important;
        gap: 10px !important;
      }
      nav .logo {
        flex: 0 0 auto;
        font-size: 19px !important;
      }
      .nav-links {
        flex: 1 1 auto !important;
        min-width: 0 !important;
        max-width: calc(100vw - 105px) !important;
        gap: 6px !important;
        overflow-x: auto !important;
        overflow-y: hidden !important;
        -webkit-overflow-scrolling: touch;
        scrollbar-width: none;
        justify-content: flex-start !important;
        padding: 2px 0 !important;
      }
      .nav-links::-webkit-scrollbar { display: none; }
      .nav-links li { flex: 0 0 auto; }
      .nav-links a {
        white-space: nowrap !important;
        font-size: 12px !important;
      }
      .btn-login {
        min-height: 36px !important;
        padding: 8px 12px !important;
      }

      .container {
        width: 100% !important;
        max-width: 100% !important;
        padding-left: 16px !important;
        padding-right: 16px !important;
      }

      .hero h1,
      .profile-hero h1 {
        font-size: clamp(32px, 10vw, 42px) !important;
        overflow-wrap: anywhere;
      }
      .hero p,
      .profile-handle {
        font-size: 15px !important;
        line-height: 1.5 !important;
      }
      .section-title { font-size: clamp(24px, 7vw, 30px) !important; }

      .grid,
      .stats-grid,
      .cards-grid,
      .tournament-grid,
      .admin-grid {
        grid-template-columns: 1fr !important;
      }

      .row,
      .team-bottom,
      .player-bottom,
      .application-row {
        flex-direction: column !important;
        align-items: stretch !important;
      }
      .actions { width: 100%; }
      .actions > .btn,
      .actions > button,
      .actions > a.btn {
        flex: 1 1 160px;
      }

      table th,
      table td {
        padding: 12px 10px !important;
        font-size: 12px !important;
      }

      .table-wrap,
      .table-wrapper,
      .matches-table,
      .standings-table,
      .admin-table {
        overflow-x: auto !important;
        -webkit-overflow-scrolling: touch;
      }

      button,
      .btn,
      a.btn,
      .tab,
      .filter,
      [role='button'] {
        min-height: 42px;
      }

      input,
      select,
      textarea,
      button {
        font-size: 16px;
      }
    }

    @media (max-width: 480px) {
      .container { padding-left: 12px !important; padding-right: 12px !important; }
      .profile-hero { padding-left: 6px !important; padding-right: 6px !important; }
      .statline { grid-template-columns: repeat(2, minmax(0, 1fr)) !important; }
      .tabs, .filters { max-width: 100%; overflow-x: auto; justify-content: flex-start !important; scrollbar-width: none; }
      .tabs::-webkit-scrollbar, .filters::-webkit-scrollbar { display: none; }
      .tab, .filter { flex: 0 0 auto; }
    }

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        scroll-behavior: auto !important;
        transition-duration: .01ms !important;
        animation-duration: .01ms !important;
        animation-iteration-count: 1 !important;
      }
      body.page-leaving { transform: none; }
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

      const roster = [...form.querySelectorAll('.player-card')].map((card, index) => {
        const inputs = [...card.querySelectorAll('input')];
        const texts = inputs.filter(i => i.type === 'text');
        return {
          full_name: texts[0]?.value?.trim() || '',
          city: texts[1]?.value?.trim() || '',
          email: inputs.find(i => i.type === 'email')?.value?.trim() || '',
          phone: inputs.find(i => i.type === 'tel')?.value?.trim() || '',
          steam_url: inputs.find(i => i.type === 'url')?.value?.trim() || '',
          game_hours: Number(inputs.filter(i => i.type === 'number')[0]?.value || 0),
          mmr: Number(inputs.filter(i => i.type === 'number')[1]?.value || 0),
          reserve: tournament.teamSize ? index >= tournament.teamSize : index >= 5,
          captain: index === 0
        };
      }).filter(p => p.full_name || p.email || p.steam_url);

      const { data, error } = await client.rpc('submit_tournament_application', {
        p_tournament_id: tournamentId,
        p_team_name: name,
        p_tag: tag,
        p_roster: roster
      });
      if (error) throw error;

      const row = Array.isArray(data) ? data[0] : data;
      if (!row?.team_id) throw new Error('Сервер не вернул созданную команду.');
      return { id: row.team_id, applicationId: row.application_id, status: row.application_status };
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

  function installPageTransitions() {
    if (!document.body || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    window.addEventListener('pageshow', () => document.body?.classList.remove('page-leaving'));
    document.addEventListener('click', event => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const link = event.target.closest?.('a[href]');
      if (!link || link.target === '_blank' || link.hasAttribute('download') || link.dataset.noTransition !== undefined) return;
      const rawHref = link.getAttribute('href') || '';
      if (!rawHref || rawHref.startsWith('#') || rawHref.startsWith('mailto:') || rawHref.startsWith('tel:') || rawHref.startsWith('javascript:')) return;
      let target;
      try { target = new URL(link.href, location.href); } catch (_) { return; }
      if (target.origin !== location.origin) return;
      if (target.pathname === location.pathname && target.search === location.search && target.hash) return;
      event.preventDefault();
      document.body.classList.add('page-leaving');
      setTimeout(() => { location.href = target.href; }, 145);
    });
  }
  installPageTransitions();

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
        alert('Для регистрации команды сначала войдите в аккаунт.');
        window.location.replace(`login.html?return=${encodeURIComponent(location.pathname + location.search)}`);
        return;
      }
      teamForm.addEventListener('submit', async event => {
        event.preventDefault(); event.stopImmediatePropagation();
        const button = teamForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const result = await api.registerTeam(teamForm);
          alert(`Заявка отправлена. Статус: ${result.status}.`);
          window.location.replace('profile.html');
        } catch (error) { showError(error.message); if (button) button.disabled = false; }
      }, true);
    }
  });
})();