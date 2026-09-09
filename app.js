(() => {
  'use strict';

  const SUPABASE_URL = 'https://wijtkxzleuqdaabfiwsh.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_q5uwQ3c6b37snDhO2lV7Hg_kZpOEyh0';

  if (!window.supabase?.createClient) {
    console.error('Supabase client library is not loaded');
    return;
  }

  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });

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
    async getTournamentBundle(id = 'dota2-winter-2026') {
      const { data: tournament, error: tError } = await client.from('tournaments').select('*').eq('id', id).maybeSingle();
      if (tError) throw tError;
      if (!tournament) throw new Error('Турнир не найден');

      const { data: teams, error: teamsError } = await client
        .from('teams')
        .select('*')
        .eq('tournament_id', tournament.id)
        .order('group_position', { ascending: true, nullsFirst: false });
      if (teamsError) throw teamsError;

      let legacy = null;
      try {
        const legacyResponse = await nativeFetch('data/tournament-dota2-2026.json');
        if (legacyResponse.ok) legacy = await legacyResponse.json();
      } catch (_) {}
      const legacyTeams = new Map((legacy?.teams || []).map(team => [team.id, team]));

      return {
        tournament: {
          id: tournament.id,
          name: tournament.name,
          game: tournament.game,
          description: tournament.description,
          startDate: tournament.start_date,
          endDate: tournament.end_date,
          format: tournament.format,
          status: tournament.status,
          maxTeams: tournament.max_teams,
          winner: tournament.winner_team_id,
          runnerUp: tournament.runner_up_team_id
        },
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
    async registerTeam(form) {
      const session = await this.getSession();
      if (!session) throw new Error('Сначала войдите в аккаунт.');

      const teamInputs = form.querySelector('.form-section .form-row')?.querySelectorAll('input') || [];
      const name = teamInputs[0]?.value?.trim();
      const tag = teamInputs[1]?.value?.trim()?.toUpperCase();
      if (!name || !tag) throw new Error('Укажите название и тег команды.');

      const params = new URLSearchParams(location.search);
      const tournamentId = params.get('tournament') || params.get('id') || 'dota2-winter-2026';
      const roster = [...form.querySelectorAll('.player-card')].map((card, index) => {
        const inputs = [...card.querySelectorAll('input')];
        const captainBox = card.querySelector('.captain-checkbox');
        return {
          full_name: inputs.find(i => i.type === 'text')?.value?.trim() || '',
          city: inputs.filter(i => i.type === 'text')[1]?.value?.trim() || '',
          email: inputs.find(i => i.type === 'email')?.value?.trim() || '',
          phone: inputs.find(i => i.type === 'tel')?.value?.trim() || '',
          steam_url: inputs.find(i => i.type === 'url')?.value?.trim() || '',
          game_hours: Number(inputs.filter(i => i.type === 'number')[0]?.value || 0),
          mmr: Number(inputs.filter(i => i.type === 'number')[1]?.value || 0),
          reserve: index >= 5,
          captain: index === 0 || Boolean(captainBox?.checked)
        };
      });

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

  // Compatibility layer: existing pages can keep fetching the old JSON path,
  // but the data now comes from Supabase.
  const nativeFetch = window.fetch.bind(window);
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

  async function syncNav() {
    const session = await api.getSession().catch(() => null);
    document.querySelectorAll('.profile-link').forEach(el => el.style.display = session ? 'list-item' : 'none');
    document.querySelectorAll('.login-link').forEach(el => el.style.display = session ? 'none' : 'list-item');
    document.querySelectorAll('.logout-link').forEach(el => el.style.display = session ? 'list-item' : 'none');
  }

  window.logout = async () => {
    await client.auth.signOut();
    location.href = 'index.html';
  };

  function showError(message) {
    alert(message || 'Произошла ошибка. Попробуйте ещё раз.');
  }

  document.addEventListener('DOMContentLoaded', async () => {
    await syncNav();
    client.auth.onAuthStateChange(() => syncNav());

    const loginForm = document.getElementById('loginForm');
    if (loginForm) {
      loginForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        const email = document.getElementById('loginEmail')?.value?.trim();
        const password = document.getElementById('loginPassword')?.value || '';
        const button = loginForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const { error } = await client.auth.signInWithPassword({ email, password });
          if (error) throw error;
          const next = new URLSearchParams(location.search).get('return');
          location.href = next || 'index.html';
        } catch (error) {
          showError(error.message);
          if (button) button.disabled = false;
        }
      }, true);
    }

    const registerForm = document.getElementById('registerForm');
    if (registerForm) {
      registerForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        const nickname = document.getElementById('regNickname')?.value?.trim();
        const email = document.getElementById('regEmail')?.value?.trim();
        const password = document.getElementById('regPassword')?.value || '';
        const confirm = document.getElementById('regPasswordConfirm')?.value || '';
        if (password !== confirm) return showError('Пароли не совпадают');
        const button = registerForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const { data, error } = await client.auth.signUp({
            email,
            password,
            options: { data: { nickname }, emailRedirectTo: `${location.origin}/login.html` }
          });
          if (error) throw error;
          if (data.session) location.href = 'profile.html';
          else {
            alert('Аккаунт создан. Подтвердите email по ссылке в письме, затем войдите.');
            location.href = 'login.html';
          }
        } catch (error) {
          showError(error.message);
          if (button) button.disabled = false;
        }
      }, true);
    }

    const teamForm = document.getElementById('registerTeamForm');
    if (teamForm) {
      const session = await api.getSession().catch(() => null);
      if (!session) {
        alert('Для регистрации команды необходимо войти в аккаунт.');
        location.href = `login.html?return=${encodeURIComponent(location.pathname + location.search)}`;
        return;
      }
      teamForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        event.stopImmediatePropagation();
        const button = teamForm.querySelector('button[type="submit"]');
        if (button) button.disabled = true;
        try {
          const team = await api.registerTeam(teamForm);
          alert('Заявка команды отправлена на рассмотрение.');
          location.href = `team.html?id=${encodeURIComponent(team.id)}`;
        } catch (error) {
          showError(error.message);
          if (button) button.disabled = false;
        }
      }, true);
    }

    if (location.pathname.endsWith('/profile.html') || location.pathname.endsWith('profile.html')) {
      const session = await api.getSession().catch(() => null);
      if (!session) {
        location.href = 'login.html';
        return;
      }
      const profile = await api.getProfile().catch(() => null);
      const nickname = profile?.nickname || session.user.user_metadata?.nickname || session.user.email?.split('@')[0] || 'Player';
      const h1 = document.querySelector('.profile-hero h1');
      const avatar = document.querySelector('.profile-avatar');
      const handle = document.querySelector('.profile-handle');
      const teamBadge = document.querySelector('.profile-team');
      if (h1) h1.textContent = nickname;
      if (avatar) avatar.textContent = nickname.charAt(0).toUpperCase();
      if (handle) handle.textContent = `@${nickname} · ${session.user.email}`;

      const { data: ownedTeams } = await client.from('teams').select('name').eq('owner_id', session.user.id).limit(1);
      if (teamBadge) teamBadge.textContent = ownedTeams?.[0]?.name || 'Без команды';
    }
  });
})();
