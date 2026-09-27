(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const ui = Object.fromEntries(['hub','hud','canvas','join-button','profile-button','profile-dialog','menu-dialog','result-dialog'].map(id => [id, $(id)]));
  let session = null, receiver = null, engineReady = false, inRace = false, busy = false;
  let lastState = null, lastFinish = false, restarting = false, mergeId = null;
  let mapProjection = null, mapHash = null;
  let raceId = null, musicContext = null, musicTimer = null, musicStep = 0;
  let musicEnabled = true;
  let localMode = false;
  const localUI = window.GnomLocalUI.create({
    send(message) {
      send(message);
      if (['local_resume','local_use_item','local_recover'].includes(message.type)) ui.canvas.focus();
    },
    onStart(payload) { send(payload); },
    onExit() { leave(); },
    onGraphics(value) { graphics = value; saveGraphics(); },
  });
  const itemLabels = {fanta:'Fanta', mermaid_rum:'Mermaid Rum', ice_rum:'Ice Rum', stroh80:'Stroh 80', lays_crab:'Lay’s Crab', bfg10k:'BFG 10K', crystal_shield:'Кристальный щит', seeker:'Кристальная ракета', rear_trap:'Рунная ловушка'};
  function renderItems(state) {
    for (let slot = 0; slot < 2; slot++) {
      const button = $(`item-slot-${slot}`), id = state.items?.[slot], label = itemLabels[id];
      const icon = button.querySelector('img');
      if (label) icon.src = `/assets/items/${id}.png`;
      else icon.removeAttribute('src');
      icon.hidden = !label; button.querySelector('.empty-slot').hidden = !!label;
      button.disabled = !label || !state.canUseItems;
      button.title = label ? `${label} · ${slot === 0 ? 'Q' : 'E'}` : `Пустой слот ${slot + 1}`;
      button.setAttribute('aria-label', button.title);
    }
    const maximum = Math.max(1, Number(state.maxHealth) || 100);
    const health = Math.max(0, Math.min(maximum, Number(state.health ?? maximum)));
    $('health-fill').style.width = `${health / maximum * 100}%`;
    $('health-value').textContent = String(Math.ceil(health));
    const meter = document.querySelector('.health-meter');
    meter.setAttribute('aria-valuemax', String(maximum)); meter.setAttribute('aria-valuenow', String(health));
    meter.classList.toggle('critical', health / maximum < .3);
    const remaining = Math.max(0, Number(state.destroyedRemaining) || 0);
    $('destroyed-status').hidden = remaining <= 0;
    $('destroyed-status').textContent = remaining > 0 ? `ВОССТАНОВЛЕНИЕ · ${Math.ceil(remaining)}` : '';
    const effects = {...state.effects};
    if (state.invulnerableRemaining > 0) effects.invulnerable = {remaining:state.invulnerableRemaining};
    const labels = {...itemLabels, burn:'Горение', invulnerable:'Защита', weapon_guard:'Защита от удара'};
    const warnings = {rear:'РАКЕТА СЗАДИ',front:'РАКЕТА ВПЕРЕДИ',left:'РАКЕТА СЛЕВА',right:'РАКЕТА СПРАВА'};
    $('attack-warning').hidden = !Object.hasOwn(warnings,state.attackWarning);
    $('attack-warning').textContent = $('attack-warning').hidden ? '' : `! ${warnings[state.attackWarning]}`;
    $('item-effects').replaceChildren(...Object.entries(effects).filter(([id, effect]) => labels[id] && Number(effect?.remaining ?? effect) > 0).map(([id, effect]) => {
      const badge = document.createElement('span'), icon = document.createElement('img'), timer = document.createElement('b');
      badge.className = `item-effect ${id}`; badge.title = labels[id]; badge.setAttribute('aria-label', `${labels[id]}: ${Math.ceil(Number(effect?.remaining ?? effect))} с`);
      icon.src = `/assets/items/${id === 'burn' ? 'stroh80' : ['invulnerable','weapon_guard'].includes(id) ? 'crystal_shield' : id}.png`; icon.alt = '';
      timer.textContent = `${Math.ceil(Number(effect?.remaining ?? effect))}с`; badge.append(icon,timer); return badge;
    }));
    const blur = Math.max(0, Math.min(1, Number(state.blurIntensity) || 0));
    ui.canvas.style.filter = blur > 0 && inRace ? `blur(${blur * (graphics.reducedEffects ? .6 : 3)}px)` : '';
  }
  for (let slot = 0; slot < 2; slot++) $(`item-slot-${slot}`).addEventListener('click', () => {
    if (inRace && lastState?.canUseItems && itemLabels[lastState.items?.[slot]] && !document.querySelector('dialog[open]')) send({type:'use_item', slot});
    ui.canvas.focus();
  });
  const styleLabels = {handling:'Управляемость', acceleration:'Ускорение', speed:'Скорость', drift:'Дрифт'};
  const validStyle = value => Object.hasOwn(styleLabels, value);
  let selectedStyle = 'handling', joinedStyle = null;
  try {
    const saved = localStorage.getItem('gnom.style.v1');
    if (validStyle(saved)) selectedStyle = saved;
  } catch { /* Optional storage. */ }
  function applyStyle(value) {
    if (!validStyle(value)) return;
    selectedStyle = value;
    for (const input of document.querySelectorAll('input[name="driving-style"]')) input.checked = input.value === value;
    $('selected-style').textContent = styleLabels[value];
    try { localStorage.setItem('gnom.style.v1', value); } catch { /* Optional storage. */ }
  }
  for (const input of document.querySelectorAll('input[name="driving-style"]')) input.addEventListener('change', () => {
    if (!busy && !inRace && input.checked) applyStyle(input.value);
  });
  applyStyle(selectedStyle);
  try { musicEnabled = localStorage.getItem('gnom.music.v1') !== 'off'; } catch { /* Optional storage. */ }
  $('music-enabled').checked = musicEnabled;
  function stopMusic() {
    clearInterval(musicTimer); musicTimer = null; musicStep = 0;
  }
  function updateMusic() {
    const active = musicEnabled && inRace && lastState?.status === 'racing' && lastState?.lap === 3 && !document.hidden;
    if (!active || musicContext?.state !== 'running') { stopMusic(); return; }
    if (musicTimer) return;
    // Original final-lap motif; generated locally, with no downloaded audio dependency.
    const melody = [64,67,71,76,74,71,67,69,64,67,71,79,76,74,71,67];
    const beat = () => {
      const now = musicContext.currentTime;
      for (const [note, volume, duration] of [[melody[musicStep % melody.length], .032, .14], [musicStep % 4 === 0 ? 40 : 47, .035, .1]]) {
        const oscillator = musicContext.createOscillator(), gain = musicContext.createGain();
        oscillator.type = 'triangle'; oscillator.frequency.value = 440 * 2 ** ((note - 69) / 12);
        gain.gain.setValueAtTime(0, now); gain.gain.linearRampToValueAtTime(volume, now + .012); gain.gain.exponentialRampToValueAtTime(.0001, now + duration);
        oscillator.connect(gain); gain.connect(musicContext.destination); oscillator.start(now); oscillator.stop(now + duration + .01);
        oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
      }
      musicStep++;
    };
    beat(); musicTimer = setInterval(beat, 160);
  }
  function unlockMusic() {
    if (!musicEnabled) return;
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) return;
    musicContext ||= new Audio();
    musicContext.resume().then(updateMusic).catch(() => {});
  }
  $('music-enabled').addEventListener('change', event => {
    musicEnabled = event.target.checked;
    try { localStorage.setItem('gnom.music.v1', musicEnabled ? 'on' : 'off'); } catch { /* Optional storage. */ }
    if (musicEnabled) unlockMusic(); else stopMusic();
  });
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
    if (lastState && inRace && !localMode) renderItems(lastState);
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
  function updateReady() {
    ui['join-button'].disabled = !engineReady || busy;
    ui['profile-button'].disabled = busy;
    $('local-button').disabled = !engineReady || busy;
    $('driving-style').disabled = busy || inRace;
  }
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
    if (busy || !engineReady) return;
    unlockMusic();
    busy = true; updateReady(); setError('');
    $('reconnect-button').disabled = true;
    try {
      if (!session) applySession(await api('/api/auth/bootstrap'));
      const styleId = inRace ? (validStyle(lastState?.nextStyleId) ? lastState.nextStyleId : validStyle(lastState?.styleId) ? lastState.styleId : joinedStyle || selectedStyle) : selectedStyle;
      const connection = await api('/api/race/ticket', {styleId});
      joinedStyle = validStyle(connection.styleId) ? connection.styleId : styleId;
      applyStyle(joinedStyle);
      $('active-style').textContent = styleLabels[joinedStyle];
      $('next-style').hidden = true;
      inRace = true; lastFinish = false; restarting = false; raceId = null;
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
    send({type:localMode ? 'local_leave' : 'leave'}); inRace = false; lastFinish = false;
    localMode = false; localUI.hide();
    raceId = null; restarting = false; stopMusic();
    joinedStyle = null; lastState = null; updateReady();
    ui.canvas.style.filter = '';
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
  ui['result-dialog'].addEventListener('cancel', event => event.preventDefault());
  ui['join-button'].addEventListener('click', join);
  $('local-button').addEventListener('click', () => { send({type:'local_devices'}); localUI.showSetup(); });
  ui['profile-button'].addEventListener('click', async () => {
    if (busy) return;
    busy = true; updateReady(); setError('');
    try {
      if (!session) applySession(await api('/api/auth/bootstrap'));
      openDialog(ui['profile-dialog']);
    } catch (error) { setError(messageFor(error)); }
    finally { busy = false; updateReady(); }
  });
  $('menu-button').addEventListener('click', () => openDialog(ui['menu-dialog']));
  $('resume-button').addEventListener('click', () => ui['menu-dialog'].close());
  $('recover-button').addEventListener('click', () => { send({type:'recover'}); ui['menu-dialog'].close(); });
  for (const id of ['exit-button','result-exit','disconnect-exit']) $(id).addEventListener('click', leave);
  $('reconnect-button').addEventListener('click', () => lastState?.status === 'update_required' ? window.location.reload() : join());
  $('restart-button').addEventListener('click', () => {
    if (!lastState?.canRestart || restarting) return;
    unlockMusic(); restarting = true; $('restart-button').disabled = true;
    send({type:'restart', race_id:lastState.raceId});
  });
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
  document.addEventListener('visibilitychange', () => { send({type:'focus', visible:!document.hidden}); updateMusic(); });
  window.addEventListener('blur', () => send({type:'focus', visible:false}));
  window.addEventListener('focus', () => send({type:'focus', visible:!document.hidden}));
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && inRace && !localMode && !document.querySelector('dialog[open]')) { event.preventDefault(); openDialog(ui['menu-dialog']); }
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
    renderItems(state);
    if (validStyle(state.styleId)) {
      joinedStyle = state.styleId;
      $('active-style').textContent = styleLabels[joinedStyle];
      const nextStyle = validStyle(state.nextStyleId) ? state.nextStyleId : joinedStyle;
      if (nextStyle !== selectedStyle) applyStyle(nextStyle);
      $('next-style').hidden = nextStyle === joinedStyle;
      $('next-style-name').textContent = styleLabels[nextStyle];
    }
    if (state.raceId !== raceId) {
      raceId = state.raceId; lastFinish = false; restarting = false;
      ui['result-dialog'].close(); stopMusic();
    }
    $('participant-count').textContent = String(state.players.length).padStart(2,'0');
    $('speed').textContent = Math.round(state.speed).toString();
    $('reverse').hidden = !state.reverse;
    $('lap').textContent = `${state.lap} / 3`;
    $('time').textContent = formatTime(state.elapsed);
    $('ping').textContent = `${state.ping} мс`;
    const healthy = ['connected','countdown','racing','finished','results','spectating'].includes(state.status);
    $('network-status').textContent = healthy ? 'На связи' : state.status === 'connecting' ? 'Подключение' : 'Нет связи';
    const disconnected = !healthy && state.status !== 'connecting';
    if (disconnected && ui['result-dialog'].open) { ui['result-dialog'].close(); lastFinish = false; }
    $('race-status').textContent = state.spectating ? 'ОЖИДАНИЕ ЗАЕЗДА' : 'НА ТРАССЕ';
    $('disconnect').hidden = !disconnected;
    $('disconnect-title').textContent = state.status === 'update_required' ? 'Нужна новая версия игры' : 'Соединение прервано';
    $('reconnect-button').textContent = state.status === 'update_required' ? 'ОБНОВИТЬ ИГРУ' : 'ПЕРЕПОДКЛЮЧИТЬСЯ';
    $('countdown').hidden = state.countdown <= 0 || disconnected;
    $('countdown').textContent = state.countdown > 0 ? Math.ceil(state.countdown) : '';
    $('shards').textContent=String(state.shards||0);
    $('drift-level').textContent=['','I','II','III'][Math.max(0,Math.min(3,state.driftLevel||0))];
    document.querySelectorAll('.network-drift-segments progress').forEach((bar,index)=>bar.value=state.driftSegments?.[index]||0);
    document.querySelector('.drift').classList.toggle('boost', state.boost > 0);
    const driving=state.driving||{};
    $('boost-label').textContent = driving.start_boost_remaining>0?'СТАРТ':driving.slipstream_boost_remaining>0?'ПОТОК':state.boost>0?'УСКОРЕНИЕ':driving.slipstream_charge>0?`ПОТОК ${Math.round(driving.slipstream_charge*100)}%`:'ЗАРЯД';
    const rowLimit = matchMedia('(max-height:520px) and (orientation:landscape)').matches ? 3 : 4;
    const leaders = state.players.slice(0,rowLimit);
    const currentPlayer = state.players.find(player => player.id === state.playerId);
    if (currentPlayer && !leaders.some(player => player.id === state.playerId)) leaders[rowLimit-1] = currentPlayer;
    $('racers').replaceChildren(...leaders.map(player => {
      const row = document.createElement('li');
      row.className = player.id === state.playerId ? 'self' : '';
      const number = document.createElement('span'), name = document.createElement('span'), mark = document.createElement('em');
      number.textContent = String(player.position).padStart(2,'0'); name.textContent = player.name;
      mark.textContent = player.id === state.playerId ? 'ВЫ' : player.isBot ? 'БОТ' : player.connected ? '' : 'OFF';
      row.append(number,name,mark); return row;
    }));
    drawMap(state.players,state.playerId,state.track);
    const finished = state.finished || state.phase === 'results';
    if (!finished) { lastFinish = false; restarting = false; }
    if (finished) {
      const complete = state.phase === 'results';
      $('result-title').textContent = complete ? 'Результаты заезда' : 'Вы финишировали';
      $('finish-time').textContent = state.spectating ? 'Следующий заезд' : currentPlayer?.dnf ? 'Без финиша' : formatTime(state.elapsed);
      $('result-status').textContent = state.spectating ? 'Ожидаем готовности участников' : !complete ? 'Остальные участники продолжают гонку' : state.repeatReady ? 'Готовы. Ожидаем остальных игроков' : 'Заезд завершён';
      if (state.repeatReady) restarting = false;
      $('restart-button').disabled = !state.canRestart || restarting || disconnected;
      $('restart-button').textContent = state.repeatReady ? 'ГОТОВЫ К СТАРТУ' : restarting ? 'ПОДТВЕРЖДЕНИЕ...' : 'ЕЩЁ ЗАЕЗД';
      $('result-racers').replaceChildren(...state.players.map(player => {
        const row = document.createElement('li'); row.className = player.id === state.playerId ? 'self' : '';
        const place = document.createElement('span'), name = document.createElement('span'), result = document.createElement('span');
        place.textContent = String(player.position).padStart(2,'0');
        name.textContent = `${player.name}${player.isBot ? ' · БОТ' : player.id === state.playerId ? ' · ВЫ' : ''}`;
        result.textContent = player.dnf ? 'НФ' : player.finished ? formatTime(player.elapsed) : 'В гонке';
        if (complete && player.ready && !player.isBot) result.textContent += ' · Готов';
        row.append(place,name,result); return row;
      }));
      if (!lastFinish && !disconnected) { lastFinish = true; openDialog(ui['result-dialog']); }
    }
    updateMusic();
  }
  window.GnomHost = {
    register(callback) { receiver = callback; engineReady = true; applyGraphics(); $('load-state').hidden = true; updateReady(); },
    update(json) {
      const state = JSON.parse(json);
      if (state.mode === 'local_devices') { localUI.updateDevices(state.devices); return; }
      if (state.mode === 'local_error') { localUI.showError('Устройство недоступно или назначено дважды. Проверьте состав.'); return; }
      if (state.mode === 'local') {
        if (!localMode) {
          localMode = true; inRace = true; stopMusic();
          ui.hub.hidden = true; ui.hud.hidden = true; ui.canvas.style.filter = '';
          ui.canvas.focus(); updateReady();
        }
        lastState = state;
        localUI.updateDevices(state.devices);
        localUI.update(state);
        return;
      }
      if (!localMode) render(state);
    },
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
  $('connection-label').textContent = 'Локальная игра';
  setInterval(() => { if (engineReady && !inRace) send({type:'local_devices'}); }, 1000);
})();
