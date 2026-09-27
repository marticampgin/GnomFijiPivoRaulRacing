(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const ui = Object.fromEntries(['hub','hud','canvas','join-button','profile-button','profile-dialog','menu-dialog','result-dialog'].map(id => [id, $(id)]));
  let session = null, receiver = null, engineReady = false, inRace = false, busy = false;
  let lastState = null, lastFinish = false, restarting = false, mergeId = null;
  let mapProjection = null, mapHash = null;
  const graphicsKey = 'gnom.graphics.v1';
  let graphics = { quality:'standard', reducedEffects:matchMedia('(prefers-reduced-motion:reduce)').matches };
  try {
    const saved = JSON.parse(localStorage.getItem(graphicsKey));
    if (saved && ['standard','low'].includes(saved.quality) && typeof saved.reducedEffects === 'boolean') graphics = { quality:saved.quality, reducedEffects:saved.reducedEffects };
  } catch { /* Browser storage is optional; the current session still works. */ }
  const formatTime = (seconds) => {
    const ms = Math.max(0, Math.round(seconds * 1000));
    return `${String(Math.floor(ms / 60000)).padStart(2,'0')}:${String(Math.floor(ms / 1000) % 60).padStart(2,'0')}.${String(ms % 1000).padStart(3,'0')}`;
  };
  function send(message) { receiver?.(JSON.stringify(message)); }
  function applyGraphics() {
    for (const input of document.querySelectorAll('input[name="quality"]')) input.checked = input.value === graphics.quality;
    $('reduced-effects').checked = graphics.reducedEffects;
    send({type:'graphics', quality:graphics.quality, reduced_effects:graphics.reducedEffects});
  }
  function saveGraphics() {
    try { localStorage.setItem(graphicsKey, JSON.stringify(graphics)); } catch { /* Storage may be disabled. */ }
    applyGraphics();
  }
  for (const input of document.querySelectorAll('input[name="quality"]')) input.addEventListener('change', () => {
    if (input.checked) { graphics.quality = input.value; saveGraphics(); }
  });
  $('reduced-effects').addEventListener('change', event => { graphics.reducedEffects = event.target.checked; saveGraphics(); });
  applyGraphics();
  function setError(message) { $('hub-error').textContent = message; $('hub-error').hidden = !message; }
  function updateReady() { ui['join-button'].disabled = !engineReady || !session || busy; ui['profile-button'].disabled = !session || busy; }
  function messageFor(error) {
    const messages = { csrf_rejected:'Сессия изменилась. Обновите страницу.', origin_rejected:'Адрес игры не совпадает с адресом сервера.', attempt_invalid:'Попытка входа истекла. Повторите вход.', rate_limited:'Слишком много запросов. Попробуйте немного позже.', account_required:'Нужен вход в аккаунт.', unavailable:'Сервер временно недоступен.' };
    return messages[error.message] || 'Не удалось выполнить запрос. Повторите попытку.';
  }
  async function api(path, body) {
    const response = await fetch(path, { method:body === undefined ? 'GET' : 'POST', credentials:'same-origin', cache:'no-store', headers:body === undefined ? {} : {'Content-Type':'application/json','X-CSRF-Token':session?.csrfToken || ''}, ...(body === undefined ? {} : {body:JSON.stringify(body)}) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'unavailable');
    return result;
  }
  function applySession(value) {
    session = value;
    $('profile-name').textContent = value.user.displayName;
    $('account-name').textContent = value.user.displayName;
    $('connection-label').textContent = 'Сервер доступен';
    $('logout-button').hidden = value.user.kind !== 'account';
    $('merge-section').hidden = !value.mergeAvailable;
    $('merge-label').textContent = `Перенести в аккаунт «${value.user.displayName}»`;
    $('merge-confirm').checked = false;
    $('merge-button').disabled = true;
    const profiles = value.devProfiles || [];
    $('dev-profiles').hidden = profiles.length === 0;
    $('profile-list').replaceChildren(...profiles.map(profile => {
      const button = document.createElement('button');
      button.className = 'secondary-button';
      button.textContent = profile.displayName;
      button.dataset.profileId = profile.id;
      button.addEventListener('click', () => login(profile.id));
      return button;
    }));
    updateReady();
  }
  async function login(profileId) {
    if (busy) return;
    busy = true; updateReady();
    $('profile-feedback').textContent = '';
    for (const button of $('profile-list').children) button.disabled = true;
    try {
      const attempt = await api('/api/auth/attempt', {provider:'dev'});
      applySession(await api('/api/auth/dev', {profileId, ...attempt}));
      mergeId = null;
      $('profile-feedback').textContent = 'Вход выполнен';
    } catch(error) { $('profile-feedback').textContent = messageFor(error); }
    finally { busy = false; updateReady(); for (const button of $('profile-list').children) button.disabled = false; }
  }
  async function join() {
    if (busy || !session || !engineReady) return;
    busy = true; updateReady(); setError('');
    $('reconnect-button').disabled = true;
    try {
      const connection = await api('/api/race/ticket', {});
      inRace = true; lastFinish = false; restarting = false;
      ui.hub.hidden = true; ui.hud.hidden = false;
      $('disconnect').hidden = true;
      send({type:'join', url:connection.websocketUrl, ticket:connection.ticket, compatibility:connection.compatibility});
      send({type:'input_enabled', enabled:!document.querySelector('dialog[open]')});
      send({type:'focus', visible:!document.hidden});
      ui.canvas.focus();
    } catch(error) { setError(messageFor(error)); if (inRace) $('disconnect').hidden = false; }
    finally { busy = false; updateReady(); $('reconnect-button').disabled = false; }
  }
  function leave() {
    send({type:'leave'}); inRace = false; lastFinish = false;
    for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close();
    ui.hub.hidden = false; ui.hud.hidden = true;
    ui['join-button'].focus();
  }
  function openDialog(dialog) {
    if (dialog.open) return;
    send({type:'input_enabled', enabled:false});
    dialog.showModal();
  }
  for (const dialog of document.querySelectorAll('dialog')) {
    dialog.querySelector('.close-dialog')?.addEventListener('click', () => dialog.close());
    dialog.addEventListener('close', () => {
      const enabled = !document.querySelector('dialog[open]');
      send({type:'input_enabled', enabled});
      if (inRace && enabled) ui.canvas.focus();
    });
  }
  ui['join-button'].addEventListener('click', join);
  ui['profile-button'].addEventListener('click', () => openDialog(ui['profile-dialog']));
  $('menu-button').addEventListener('click', () => openDialog(ui['menu-dialog']));
  $('resume-button').addEventListener('click', () => ui['menu-dialog'].close());
  $('recover-button').addEventListener('click', () => { send({type:'recover'}); ui['menu-dialog'].close(); });
  for (const id of ['exit-button','result-exit','disconnect-exit']) $(id).addEventListener('click', leave);
  $('reconnect-button').addEventListener('click', () => lastState?.status === 'update_required' ? window.location.reload() : join());
  $('restart-button').addEventListener('click', () => { restarting = true; send({type:'restart'}); ui['result-dialog'].close(); });
  $('fullscreen-button').addEventListener('click', async () => {
    try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); } catch { /* Optional browser capability. */ }
  });
  $('logout-button').addEventListener('click', async () => {
    if (busy) return;
    busy = true;
    try { applySession(await api('/api/auth/logout', {})); mergeId = null; $('profile-feedback').textContent = 'Вы вышли из аккаунта'; }
    catch(error) { $('profile-feedback').textContent = messageFor(error); }
    finally { busy = false; updateReady(); }
  });
  $('merge-confirm').addEventListener('change', () => { $('merge-button').disabled = !$('merge-confirm').checked; });
  $('merge-button').addEventListener('click', async () => {
    if (busy || !$('merge-confirm').checked) return;
    busy = true; $('merge-button').disabled = true;
    mergeId ||= crypto.randomUUID();
    try {
      await api('/api/guest/merge', {targetAccountId:session.user.id, confirmed:true, mergeId});
      applySession(await api('/api/me'));
      $('profile-feedback').textContent = 'Прогресс перенесён';
    } catch(error) { $('profile-feedback').textContent = messageFor(error); $('merge-button').disabled = false; }
    finally { busy = false; updateReady(); }
  });
  document.addEventListener('visibilitychange', () => send({type:'focus', visible:!document.hidden}));
  window.addEventListener('blur', () => send({type:'focus', visible:false}));
  window.addEventListener('focus', () => send({type:'focus', visible:!document.hidden}));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && inRace && !document.querySelector('dialog[open]')) { event.preventDefault(); openDialog(ui['menu-dialog']); }
  });
  function drawMap(players, currentId, descriptor) {
    const canvas = $('minimap'), context = canvas.getContext('2d');
    context.clearRect(0,0,canvas.width,canvas.height);
    if (!mapProjection || descriptor?.simulation_hash !== mapHash) {
      mapProjection = window.GnomTrackMap.project(descriptor, canvas.width, canvas.height);
      mapHash = mapProjection?.hash;
    }
    if (!mapProjection) return;
    context.strokeStyle = '#617268'; context.lineWidth = 12;
    context.lineJoin = 'round'; context.lineCap = 'round';
    context.beginPath();
    mapProjection.points.forEach(([x,z], index) => index ? context.lineTo(x,z) : context.moveTo(x,z));
    context.closePath(); context.stroke();
    context.fillStyle = '#f5f7f4';
    context.fillRect(mapProjection.start[0]-3, mapProjection.start[1]-5, 6, 10);
    for (const player of players) {
      const [x,,z] = player.worldPosition || [0,0,0];
      const location = mapProjection.worldToMap(x,z);
      if (!location) continue;
      context.beginPath(); context.arc(...location,player.id === currentId ? 6 : 4,0,2*Math.PI);
      context.fillStyle = player.id === currentId ? '#e5ff58' : '#f5f7f4'; context.fill();
    }
  }
  function render(state) {
    lastState = state;
    if (!inRace) return;
    $('participant-count').textContent = String(state.players.length).padStart(2,'0');
    $('speed').textContent = Math.round(state.speed).toString();
    $('lap').textContent = `${state.lap} / 3`;
    $('time').textContent = formatTime(state.elapsed);
    $('ping').textContent = `${state.ping} мс`;
    const healthy = ['connected','countdown','racing','finished'].includes(state.status);
    $('network-status').textContent = healthy ? 'На связи' : state.status === 'connecting' ? 'Подключение' : 'Нет связи';
    const disconnected = !healthy && state.status !== 'connecting';
    $('disconnect').hidden = !disconnected;
    $('disconnect-title').textContent = state.status === 'update_required' ? 'Нужна новая версия игры' : 'Соединение прервано';
    $('reconnect-button').textContent = state.status === 'update_required' ? 'ОБНОВИТЬ ИГРУ' : 'ПЕРЕПОДКЛЮЧИТЬСЯ';
    $('countdown').hidden = state.countdown <= 0 || disconnected;
    $('countdown').textContent = state.countdown > 0 ? Math.ceil(state.countdown) : '';
    $('drift-fill').style.width = `${Math.round(Math.min(1, state.boost > 0 ? state.boost/2 : state.drift)*100)}%`;
    document.querySelector('.drift').classList.toggle('boost', state.boost > 0);
    $('boost-label').textContent = state.boost > 0 ? 'УСКОРЕНИЕ' : 'ЗАРЯД';
    const rowLimit = matchMedia('(max-height:520px) and (orientation:landscape)').matches ? 3 : 4;
    const leaders = state.players.slice(0,rowLimit);
    const currentPlayer = state.players.find(player => player.id === state.playerId);
    if (currentPlayer && !leaders.some(player => player.id === state.playerId)) leaders[rowLimit-1] = currentPlayer;
    $('racers').replaceChildren(...leaders.map(player => {
      const row = document.createElement('li');
      row.className = player.id === state.playerId ? 'self' : '';
      const number = document.createElement('span'), name = document.createElement('span'), mark = document.createElement('em');
      number.textContent = String(player.position).padStart(2,'0'); name.textContent = player.name;
      mark.textContent = player.id === state.playerId ? 'ВЫ' : player.connected ? '' : 'OFF';
      row.append(number,name,mark); return row;
    }));
    drawMap(state.players,state.playerId,state.track);
    if (!state.finished) { lastFinish = false; restarting = false; }
    if (state.finished && !lastFinish && !restarting) {
      lastFinish = true; $('finish-time').textContent = formatTime(state.elapsed); openDialog(ui['result-dialog']);
    }
  }
  window.GnomHost = {
    register(callback) { receiver = callback; engineReady = true; applyGraphics(); $('load-state').hidden = true; updateReady(); },
    update(json) { render(JSON.parse(json)); },
    get state() { return lastState; },
    async boot(config) {
      const missing = Engine.getMissingFeatures({threads:false});
      if (missing.length) { $('load-label').textContent = 'Браузер не поддерживает WebGL 2.0'; setError('Игра недоступна в этом браузере.'); return; }
      const engine = new Engine({...config, focusCanvas:false, ensureCrossOriginIsolationHeaders:false});
      try {
        await engine.startGame({canvas:ui.canvas, onProgress:(current,total) => {
          const percentage = total ? Math.round(current/total*100) : 0;
          $('load-progress').value = percentage; $('load-label').textContent = `Загрузка игры · ${percentage}%`;
        }});
      } catch(error) { engineReady = false; updateReady(); setError('Не удалось загрузить игру. Обновите страницу.'); console.error(error); }
    },
  };
  api('/api/auth/bootstrap').then(applySession).catch(error => { $('connection-label').textContent = 'Сервер недоступен'; setError(messageFor(error)); });
})();
