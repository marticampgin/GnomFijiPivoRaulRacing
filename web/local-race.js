(function (root) {
  'use strict';
  const styles = {handling:'Управляемость', acceleration:'Ускорение', speed:'Скорость', drift:'Дрифт'};
  const items = {fanta:'Fanta', mermaid_rum:'Mermaid Rum', ice_rum:'Ice Rum', stroh80:'Stroh 80', lays_crab:'Lay’s Crab', bfg10k:'BFG 10K', crystal_shield:'Кристальный щит', seeker:'Кристальная ракета', rear_trap:'Рунная ловушка'};
  const warnings = {rear:'РАКЕТА СЗАДИ',front:'РАКЕТА ВПЕРЕДИ',left:'РАКЕТА СЛЕВА',right:'РАКЕТА СПРАВА'};
  const colors = ['#64e3db','#ffd36b','#ff877b','#a9cfff'];
  const clamp = (value, min, max) => Math.max(min, Math.min(max, Number(value) || 0));
  const time = value => { const ms = Math.max(0, Math.floor((Number(value) || 0) * 1000)); return `${String(Math.floor(ms/60000)).padStart(2,'0')}:${String(Math.floor(ms/1000)%60).padStart(2,'0')}.${String(ms%1000).padStart(3,'0')}`; };
  function element(tag, className, text) { const node = document.createElement(tag); node.className = className || ''; if (text !== undefined) node.textContent = text; return node; }
  function effectBadge(id, label, seconds) {
    const compact=label.match(/\d+%/)?.[0]||({'start-boost':'СТ','slipstream':'ПТ','drift-boost':'ДР'}[id]||'');
    const node=element('span',`local-effect ${id}`),icon=element('img'),name=element('span','local-effect-name',seconds===null&&/\d+%/.test(label)?label.replace(/\s+\d+%$/,''):label),timer=element('b','',seconds===null?compact:`${seconds}с`);
    const item=id==='burn'?'stroh80':['invulnerable','weapon_guard'].includes(id)?'crystal_shield':id;
    icon.src=Object.hasOwn(items,item)?`/assets/items/${item}.png`:`/assets/icons/${id==='recovery'?'rotate-ccw':'arrow-up-right'}.svg`;icon.alt='';
    node.title=seconds===null?label:`${label}: ${seconds} с`;node.setAttribute('aria-label',node.title);node.append(icon,name,timer);return node;
  }
  function button(label, action, icon) { const node = element('button','local-button',label); node.type = 'button'; if (icon) { const img = element('img'); img.src = `/assets/icons/${icon}.svg`; img.alt = ''; node.prepend(img); } node.addEventListener('click', action); return node; }
  function select(options, value, label) { const node = element('select'); node.setAttribute('aria-label',label); for (const [id,name] of options) { const option = element('option','',name); option.value = id; node.append(option); } node.value = String(value); return node; }
  function validateSeats(seats, pads) {
    if (!Array.isArray(seats) || seats.length < 1 || seats.length > 4) return 'Выберите от одного до четырёх игроков.';
    const used = new Set();
    for (const seat of seats) {
      if (!Number.isInteger(seat.device) || (seat.device !== -1 && !pads.some(pad => pad.id === seat.device))) return 'Подключите контроллер для каждого игрока.';
      if (used.has(seat.device)) return 'Каждому игроку нужен отдельный контроллер.';
      if (!Object.hasOwn(styles,seat.style_id)) return 'Выберите стиль каждого игрока.';
      used.add(seat.device);
    }
    return '';
  }
  function create({send, onStart, onExit, onGraphics, onResume}) {
    let state = null, pads = [], panes = [], setupSeats = [{device:-1,style_id:'drift',name:'P1'}], chosenLayout = 'side-by-side', chosenDifficulty = 'normal';
    const manualDevices = new Set();
    let tutorialSetup = false, tutorialSeat = null, tutorialManualDevice = false;
    const activeSetupSeats = () => tutorialSetup ? [tutorialSeat] : setupSeats;
    const controls = root.GnomControlSettings;
    let savedProfiles = Array.from({length:4},()=>controls.defaultProfile());
    try {const saved=JSON.parse(localStorage.getItem('gnom.local-controls.v1'));if(saved?.version===1&&Array.isArray(saved.profiles))savedProfiles=savedProfiles.map((profile,i)=>controls.normalize(saved.profiles[i])||profile);} catch { /* Storage is optional. */ }
    function saveProfile(index,profile) {savedProfiles[index]={...profile};try{localStorage.setItem('gnom.local-controls.v1',JSON.stringify({version:1,profiles:savedProfiles}));}catch{/* Storage is optional. */}}
    function profileEditor(index,profile,live,device) {
      const details=element('details','local-controls'),summary=element('summary','',`Управление P${index+1}`);details.append(summary);
      details.dataset.focusKey=`controls-${index}`;summary.dataset.focusKey=`controls-summary-${index}`;
      const editor=controls.create({profile,device,onChange:value=>{saveProfile(index,value);if(live)send({type:'local_controls',seat:index,controls:value});}});details.append(editor.node);
      for(const field of editor.node.querySelectorAll('input,select,button'))field.dataset.focusKey=`control-${index}-${field.dataset.control||'reset'}`;
      return details;
    }
    function preserveRows(container,render) {
      const active=container.contains(document.activeElement)?document.activeElement.dataset.focusKey:null;
      const expanded=new Set(Array.from(container.querySelectorAll('details[open]')).map(node=>node.dataset.focusKey));
      render();
      for(const detail of container.querySelectorAll('details'))detail.open=expanded.has(detail.dataset.focusKey);
      if(active)Array.from(container.querySelectorAll('[data-focus-key]')).find(node=>node.dataset.focusKey===active)?.focus({preventScroll:true});
    }
    const layer = element('section','local-race'); layer.hidden = true; layer.id = 'local-race';
    const grid = element('div','local-grid'); layer.append(grid); document.body.append(layer);
    const trackStatus=element('div','local-track-status');trackStatus.hidden=true;trackStatus.setAttribute('role','status');layer.append(trackStatus);
    const lobby = root.GnomRaceLobby.create({
      onStart:startSetup,
      onBack:()=>lobby.close(),
      onCount:changeSeatCount,
      onStyle(index,id) {
        const seats=activeSetupSeats();
        if(!seats[index]||!Object.hasOwn(styles,id))return;
        seats[index].style_id=id;renderSetup();
      },
      onDevice(index,device) {
        const seats=activeSetupSeats();
        if(!seats[index]||!Number.isInteger(device))return;
        const occupied=seats.some((seat,other)=>other!==index&&seat.device===device);
        if(device < -1 || (device>=0&&!pads.some(pad=>pad.id===device)) || occupied) {
          setupError.textContent=occupied?'Этот контроллер уже назначен другому игроку.':'Выберите подключённый контроллер.';
          renderSetup();return;
        }
        seats[index].device=device;
        if(tutorialSetup)tutorialManualDevice=true;else manualDevices.add(index);
        setupError.textContent='';renderSetup();
      },
      onControls:openSetupControls,
      onDifficulty(value) {if(['easy','normal','hard'].includes(value)){chosenDifficulty=value;renderSetup();}},
      onLayout(value) {if(['side-by-side','stacked'].includes(value)){chosenLayout=value;renderSetup();}},
    });
    const {node:setup,start,error:setupError}=lobby;
    document.body.append(setup);
    function startSetup() {
      if(start.disabled)return;
      const seats=activeSetupSeats();
      const error = validateSeats(seats,pads); setupError.textContent = error;
      if (error) return;
      start.disabled = true;
      const payload = {type:'local_start',seats:seats.map((seat,index) => ({...seat,controls:savedProfiles[index]})),layout:tutorialSetup?'side-by-side':chosenLayout,botDifficulty:tutorialSetup?'easy':chosenDifficulty,...(tutorialSetup?{tutorial:true}:{})};
      (onStart || send)(payload);
    }
    let setupControlEditor=null,setupControlSeat=-1,setupControlOpener=null,setupControlFocusKey=null;
    const playerControls=element('dialog','local-dialog');playerControls.id='local-player-controls';
    const playerControlsTitle=element('h2');playerControlsTitle.id='local-player-controls-title';
    playerControls.setAttribute('aria-labelledby',playerControlsTitle.id);
    const playerControlsBody=element('div');
    const playerControlsBack=button('Назад',()=>playerControls.close(),'x');playerControlsBack.id='local-player-controls-back';
    const playerControlsActions=element('div','local-actions');playerControlsActions.append(playerControlsBack);
    playerControls.append(playerControlsTitle,playerControlsBody,playerControlsActions);document.body.append(playerControls);
    function openSetupControls(index) {
      const seat=activeSetupSeats()[index];
      if(!seat||!setup.open)return;
      setupControlEditor?.destroy();setupControlSeat=index;
      setupControlOpener=document.activeElement;setupControlFocusKey=setupControlOpener?.dataset.focusKey;
      playerControlsTitle.textContent=`Управление P${index+1}`;
      setupControlEditor=controls.create({profile:savedProfiles[index],device:seat.device,onChange:value=>saveProfile(index,value)});
      for(const field of setupControlEditor.node.querySelectorAll('input,select,button'))field.dataset.focusKey=`setup-control-${index}-${field.dataset.control||'reset'}`;
      playerControlsBody.replaceChildren(setupControlEditor.node);playerControls.showModal();
    }
    playerControls.addEventListener('close',()=> {
      if(playerControls.open)return;
      setupControlEditor?.destroy();setupControlEditor=null;setupControlSeat=-1;
      if(setup.open) {
        const opener=setupControlOpener?.isConnected?setupControlOpener:Array.from(setup.querySelectorAll('[data-focus-key]')).find(node=>node.dataset.focusKey===setupControlFocusKey);
        opener?.focus({preventScroll:true});
      }
      setupControlOpener=null;setupControlFocusKey=null;
    });
    setup.addEventListener('close',()=>{if(!setup.open)playerControls.close();});
    const pause = element('dialog','local-dialog'); pause.id = 'local-pause';
    const pauseTitle = element('h2','','Пауза'), pauseRows = element('div','local-setup-rows'), pauseError = element('p','local-error'); pauseError.setAttribute('role','alert');
    const graphics = element('fieldset','local-graphics'), qualityOptions = element('div','local-quality-options');
    graphics.append(element('legend','','Графика'),qualityOptions);
    const qualityInputs = ['standard','low'].map(quality=> {
      const label=element('label'),input=element('input');input.type='radio';input.name='local-graphics-quality';input.value=quality;
      input.addEventListener('change',()=>{if(input.checked)onGraphics?.({quality,reducedEffects:reduced.checked});});
      label.append(input,element('span','',quality==='standard'?'Standard':'Low'));qualityOptions.append(label);return input;
    });
    const reducedLabel=element('label','local-reduced-effects'),reduced=element('input');reduced.type='checkbox';reduced.id='local-reduced-effects';
    reduced.addEventListener('change',()=>onGraphics?.({quality:qualityInputs.find(input=>input.checked)?.value || 'standard',reducedEffects:reduced.checked}));
    reducedLabel.append(reduced,element('span','','Снизить интенсивность эффектов'));graphics.append(reducedLabel);
    const resume = button('Продолжить',()=>send({type:'local_resume'}),'arrow-up-right'); resume.id = 'local-resume'; resume.setAttribute('data-menu-default','');
    const pauseSettings=element('dialog','local-dialog');pauseSettings.id='local-settings';
    const settingsTitle=element('h2','','Игроки и настройки');
    const settingsBack=button('Назад',()=>pauseSettings.close(),'x');
    pauseSettings.append(settingsTitle,pauseRows,graphics,settingsBack);document.body.append(pauseSettings);
    const pauseActions = element('div','local-pause-actions'); pauseActions.append(resume,button('Настройки',()=>pauseSettings.showModal()),button('В меню',()=>{ hide(); onExit?.(); },'x'));
    pause.append(pauseTitle,pauseError,pauseActions); document.body.append(pause,pauseSettings);
    pause.addEventListener('cancel',event=>{event.preventDefault(); if(!resume.disabled)send({type:'local_resume'});});
    const pauseButton = button('',()=>send({type:'local_pause'}),'pause'); pauseButton.title='Пауза'; pauseButton.setAttribute('aria-label','Пауза'); pauseButton.className='local-pause-button'; layer.append(pauseButton);
    const lesson=element('section','local-lesson');lesson.hidden=true;
    const lessonCount=element('span','local-lesson-count'),lessonTitle=element('strong'),lessonProgress=element('progress'),lessonKeys=element('div','local-lesson-keys'),lessonActions=element('div','local-actions');lessonProgress.max=1;lessonProgress.setAttribute('aria-label','Прогресс упражнения');
    lessonActions.append(button('Повторить',()=>send({type:'local_tutorial_retry'}),'rotate-ccw'),button('В меню',()=>{hide();onExit?.();},'x'));
    lessonActions.firstElementChild.setAttribute('data-menu-default','');
    lesson.append(lessonCount,lessonTitle,lessonKeys,lessonProgress,lessonActions);layer.append(lesson);
    function deviceOptions(current) { return [[-2,'Выберите контроллер'],[-1,'Клавиатура'],...pads.map(pad=>[pad.id,`${pad.name || 'Геймпад'} (${pad.id+1})`]),...(current>=0&&!pads.some(pad=>pad.id===current)?[[current,'Контроллер отключён']]:[])]; }
    function markDevices(select,seats,index) {for(const option of select.options)option.disabled=Number(option.value)<-1||seats.some((seat,other)=>other!==index&&seat.device===Number(option.value));}
    function preferController() {
      if(state||(tutorialSetup?tutorialManualDevice:manualDevices.has(0)))return;
      const seats=activeSetupSeats(),first=seats[0],otherDevices=new Set(seats.slice(1).map(seat=>seat.device));
      if(first.device>=0&&pads.some(pad=>pad.id===first.device))return;
      first.device=pads.find(pad=>!otherDevices.has(pad.id))?.id??(otherDevices.has(-1)?-2:-1);
    }
    function renderSetup() {
      lobby.update({seats:activeSetupSeats(),pads,layout:chosenLayout,difficulty:chosenDifficulty,tutorial:tutorialSetup});
      if(setupControlEditor) {
        const seat=activeSetupSeats()[setupControlSeat];
        if(seat)setupControlEditor.setDevice(seat.device);
        else playerControls.close();
      }
    }
    function changeSeatCount(number) {
      if(tutorialSetup||!Number.isInteger(number)||number<1||number>4)return;
      while(setupSeats.length<number) { const used = new Set(setupSeats.map(seat=>seat.device)); setupSeats.push({device:pads.find(pad=>!used.has(pad.id))?.id ?? (used.has(-1)?-2:-1),style_id:Object.keys(styles)[setupSeats.length%4],name:`P${setupSeats.length+1}`}); }
      for(const index of manualDevices)if(index>=number)manualDevices.delete(index);
      setupSeats = setupSeats.slice(0,number);setupError.textContent='';renderSetup();
    }
    function buildPane(index) {
      const pane = element('section','local-pane'); pane.dataset.seat=index; pane.style.setProperty('--seat',colors[index]);
      const blur = element('div','local-sector-blur');
      const identity = element('div','local-identity'); const inventory = element('div','local-inventory');
      const slots = [0,1].map(slot=> { const node = slot===0?button('',()=>send({type:'local_use_item',seat:index})):element('div'); node.className=`local-slot${slot?' local-slot-next':''}`; const img=element('img'),key=element('span','local-slot-key'),empty=element('span','local-slot-empty','−'); img.alt=''; node.append(img,empty,key); inventory.append(node); return {node,img,key,empty}; });
      const lap = element('div','local-lap'), lapValue=element('strong'), clock=element('span'); lap.append(element('span','','КРУГ'),lapValue,clock);
      const rank = element('div','local-rank'), rankValue=element('strong'), total=element('span'); rank.append(rankValue,total,element('small','','МЕСТО'));
      const health = element('div','local-health'), healthValue=element('strong'), healthBar=element('progress'); healthBar.max=100; healthBar.setAttribute('aria-label',`Прочность P${index+1}`); health.append(element('span','','ПРОЧНОСТЬ'),healthValue,healthBar);
      const crystals=element('div','local-crystals'), crystalIcon=element('img'), crystalValue=element('strong','',0); crystalIcon.src='/assets/icons/crystal-shard.svg';crystalIcon.alt='';crystals.append(crystalIcon,crystalValue);crystals.setAttribute('aria-label',`Осколки P${index+1}`);
      const drift = element('div','local-drift'), driftLabel=element('span','','ДРИФТ'), driftTrack=element('div','local-drift-segments');
      const driftBars=[0,1,2].map(level=>{const bar=element('progress');bar.max=1;bar.setAttribute('aria-label',`Дрифт P${index+1}, уровень ${level+1}`);driftTrack.append(bar);return bar;});drift.append(driftLabel,driftTrack);
      const driftTiming=element('div','drift-timing'),driftGauge=element('progress'),driftCue=element('span','local-drift-cue');driftGauge.max=1;driftGauge.setAttribute('aria-label',`Тайминг турбо P${index+1}`);driftTiming.append(driftGauge);drift.append(driftTiming,driftCue);
      const speed = element('div','local-speed'), speedValue=element('strong'), reverse=element('b','local-reverse','R'); reverse.hidden=true;reverse.setAttribute('aria-label','Задний ход');speed.append(reverse,speedValue,element('span','','км/ч'));
      const effects=element('div','local-effects'), map=element('canvas','local-map'); map.width=160;map.height=160;map.setAttribute('aria-label',`Карта P${index+1}`);
      const warning=element('div','local-attack-warning');warning.hidden=true;warning.setAttribute('role','status');
      const countdown=element('div','local-countdown'), finish=element('div','local-finish'), finishTitle=element('strong'),finishTime=element('span');
      const ready=button('Ещё заезд',()=>send({type:'local_ready',seat:index}),'rotate-ccw'); finish.append(finishTitle,finishTime,ready); finish.hidden=true;
      pane.append(blur,identity,inventory,crystals,lap,rank,health,drift,speed,effects,map,warning,countdown,finish);
      return {pane,blur,identity,slots,crystals,crystalValue,lapValue,clock,rankValue,total,healthValue,healthBar,driftLabel,driftBars,driftTiming,driftGauge,driftCue,speedValue,reverse,effects,map,warning,countdown,finish,finishTitle,finishTime,ready};
    }
    function drawMap(canvas, descriptor, players, id) {
      const ctx=canvas.getContext('2d'); if(!ctx)return; ctx.clearRect(0,0,canvas.width,canvas.height);
      const projection=root.GnomTrackMap?.project(descriptor,canvas.width,canvas.height,12); if(!projection)return;
      ctx.lineCap='round';ctx.lineJoin='round';ctx.beginPath();projection.points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.lineWidth=8;ctx.strokeStyle='#131715';ctx.stroke();ctx.lineWidth=3;ctx.strokeStyle='#f5f7f4';ctx.stroke();
      ctx.lineWidth=2;ctx.strokeStyle='#64e3db';for(const route of projection.shortcuts){ctx.beginPath();route.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.stroke();}
      const [from,to]=projection.points;const angle=Math.atan2(to[1]-from[1],to[0]-from[0]);
      ctx.save();ctx.translate(...from);ctx.rotate(angle);ctx.beginPath();ctx.moveTo(7,0);ctx.lineTo(-4,-4);ctx.lineTo(-4,4);ctx.closePath();ctx.fillStyle='#e5ff58';ctx.fill();ctx.restore();
      for(const player of players) { const pos=player.worldPosition || player.position; if(!Array.isArray(pos))continue;const point=projection.worldToMap(pos[0],pos.length===3?pos[2]:pos[1]);if(!point)continue;ctx.beginPath();ctx.arc(...point,player.id===id?5:3,0,Math.PI*2);ctx.fillStyle=player.id===id?'#e5ff58':colors[player.seat]||'#f5f7f4';ctx.fill(); }
    }
    function renderPause() {
      if(!state)return;
      const disconnected=state.disconnected || [];
      pauseTitle.textContent=disconnected.length?'Контроллер отключён':'Пауза'; resume.disabled=disconnected.length>0;
      settingsTitle.textContent=disconnected.length?'Переподключение':'Игроки и настройки';
      preserveRows(pauseRows,()=>pauseRows.replaceChildren(...state.seats.map((seat,index)=> {
        const row=element('div','local-setup-row');row.style.setProperty('--seat',colors[index]);
        const devices=select(deviceOptions(seat.device),seat.device,`Контроллер P${index+1}`);devices.dataset.focusKey=`device-${index}`;markDevices(devices,state.seats,index);
        devices.addEventListener('change',()=> {
          const device=Number(devices.value);
          const duplicate=state.seats.some((other,otherIndex)=>otherIndex!==index&&other.device===device);
          if(device < -1 || duplicate) {pauseError.textContent=duplicate?'Этот контроллер уже назначен другому игроку.':'Выберите подключённый контроллер.';devices.value=String(seat.device);return;}
          pauseError.textContent='';send({type:'local_assign',seat:index,device});
        });
        const recover=button('На трассу',()=>send({type:'local_recover',seat:index}),'rotate-ccw'); recover.disabled=Boolean(seat.finished);
        recover.dataset.focusKey=`recover-${index}`;
        row.append(element('strong','',`P${index+1}`),devices,recover,profileEditor(index,seat.controls||savedProfiles[index],true,seat.device));return row;
      })));
    }
    let pauseSignature='', overview=null;
    function update(next) {
      if(next.error) { setupError.textContent=next.error;pauseError.textContent=next.error;start.disabled=false;return; }
      if(!Array.isArray(next.seats)||!next.seats.length)return;
      state=next;layer.dataset.phase=next.phase;start.disabled=false;playerControls.close();if(setup.open)lobby.close();layer.hidden=false;
      const tutorial=next.tutorial||{};lesson.hidden=!tutorial.step;layer.classList.toggle('tutorial-active',!lesson.hidden);
      const trackEvent=next.trackEvent||{},trackPhase=trackEvent.phase;
      trackStatus.hidden=Boolean(tutorial.step)||!['warning','active'].includes(trackPhase);
      layer.classList.toggle('track-event-visible',!trackStatus.hidden);
      trackStatus.classList.toggle('warning',trackPhase==='warning');
      trackStatus.textContent=trackStatus.hidden?'':trackPhase==='warning'?`ТРАССА МЕНЯЕТСЯ · ${Math.ceil(clamp(trackEvent.remaining,0,99))} с`:'НОВЫЕ ПРЕПЯТСТВИЯ';
      if(!lesson.hidden){
        const titles={drive:'Разгон',brake:'Остановка',reverse:'Задний ход',drift:'Дрифт и турбо',items:'Предметы по очереди'};
        lessonCount.textContent=`ОБУЧЕНИЕ ${Math.min(tutorial.stage+1,tutorial.total)} / ${tutorial.total}`;lessonTitle.textContent=tutorial.complete?'Готово к гонке':titles[tutorial.step]||'';
        lessonProgress.value=clamp(tutorial.progress,0,1);lessonProgress.hidden=Boolean(tutorial.complete);lessonKeys.hidden=Boolean(tutorial.complete);
        const first=next.seats[0],profile=first.controls||savedProfiles[0],keyboard=first.device===-1,arrows=profile.keyboard==='arrows';
        const bindings=keyboard?(profile.keyboard==='arcade'?{drive:['Space'],brake:['C'],reverse:['C'],drift:['Удерживать Shift','Турбо E'],items:['Q']}:{drive:[arrows?'↑':'W'],brake:[arrows?'↓':'S'],reverse:[arrows?'↓':'S'],drift:['Удерживать Shift','Турбо E'],items:['Q']}):(profile.gamepad==='arcade'?{drive:['A'],brake:['B'],reverse:['B'],drift:['Удерживать LB','Турбо RB'],items:['Y']}:{drive:['RT'],brake:['LT'],reverse:['LT'],drift:['Удерживать LB','Турбо RB'],items:['Y']});
        lessonKeys.replaceChildren(...(bindings[tutorial.step]||[]).map(key=>element('kbd','',key)));
      }
      const signature=`${next.seats.length}:${next.layout}`;
      if(grid.dataset.layout!==signature) {
        grid.dataset.layout=signature;grid.className=`local-grid players-${next.seats.length} ${next.layout==='stacked'?'stacked':''}`;
        panes=next.seats.map((_,index)=>buildPane(index));grid.replaceChildren(...panes.map(p=>p.pane));overview=null;
        if(next.seats.length===3) {const panel=element('section','local-overview'),map=element('canvas'),list=element('ol');map.width=260;map.height=260;panel.append(element('h3','','ЗАМОК И ВОДОПАДЫ'),map,list);grid.append(panel);overview={map,list};}
      }
      next.seats.forEach((seat,index)=> {
        const p=panes[index];p.ready.dataset.menuDevice=seat.device;p.identity.textContent=`P${index+1} / ${(styles[seat.styleId] || styles.drift).toUpperCase()}`;
        p.blur.style.backdropFilter=`blur(${clamp(seat.blurIntensity,0,1)*(next.graphics?.reducedEffects?.6:3)}px)`;
        p.lapValue.textContent=`${seat.lap || 1} / ${seat.laps || 3}`;p.clock.textContent=time(seat.elapsed);p.rankValue.textContent=seat.rank || '-';p.total.textContent=`/ ${next.players?.length || 10}`;
        p.healthValue.textContent=Math.ceil(clamp(seat.health,0,seat.maxHealth || 100));p.healthBar.max=seat.maxHealth || 100;p.healthBar.value=clamp(seat.health,0,p.healthBar.max);p.healthBar.classList.toggle('critical',p.healthBar.value/p.healthBar.max<.35);
        p.speedValue.textContent=Math.round(Number(seat.speed)||0);p.reverse.hidden=!seat.reverse;
        p.crystalValue.textContent=clamp(seat.shards,0,seat.shardCap||20);p.crystals.title=`Осколки: ${p.crystalValue.textContent} / ${seat.shardCap||20}`;
        p.driftBars.forEach((bar,level)=>bar.value=clamp(seat.driftSegments?.[level],0,1));p.driftLabel.textContent=`ДРИФТ ${['','I','II','III'][clamp(seat.driftLevel,0,3)]}`;
        const profile=seat.controls||savedProfiles[index];
        p.slots.forEach(({node,img,key,empty},slot)=> { const item=seat.items?.[slot];const valid=Object.hasOwn(items,item);img.hidden=!valid;empty.hidden=valid;if(valid && img.dataset.item!==item){img.src=`/assets/items/${item}.png`;img.dataset.item=item;}key.textContent=slot?'ДАЛЕЕ':seat.device===-1?'Q':'Y';if(slot===0)node.disabled=!valid||!seat.canUseItems||next.paused;node.title=valid?items[item]:'Пусто';node.setAttribute('aria-label',`P${index+1}, ${slot?'следующий':'текущий'} предмет: ${valid?items[item]:'пусто'}`); });
        p.driftGauge.value=clamp(seat.drift,0,1);p.driftTiming.style.setProperty('--timing-start',`${clamp(seat.driftWindowStart??.65,0,1)*100}%`);
        p.driftTiming.dataset.feedback=seat.driftFeedback||'';
        const opposite=seat.device===-1?(seat.driftOwner===-1?'E':'Shift'):(seat.driftOwner===-1?'RB':'LB');
        const feedback={early:'РАНО',late:'ПОЗДНО',success:'ТУРБО',complete:'3 / 3'};
        p.driftCue.textContent=feedback[seat.driftFeedback]||(seat.driftActive?`${opposite}${seat.driftFeedback==='ready'?' · СЕЙЧАС':''}`:'');
        const labels={...items,crystal_shield:'Щит',weapon_guard:'Защита от удара',burn:'Горение',invulnerable:'Защита',recovery:'Восстановление'};
        p.warning.hidden=!Object.hasOwn(warnings,seat.attackWarning);p.warning.textContent=p.warning.hidden?'':`! ${warnings[seat.attackWarning]}`;
        const effects={...seat.effects};if(seat.invulnerableRemaining>0)effects.invulnerable=seat.invulnerableRemaining;if(seat.destroyedRemaining>0)effects.recovery=seat.destroyedRemaining;
        p.effects.replaceChildren(...Object.entries(effects).filter(([key,value])=>labels[key]&&Number(value?.remaining ?? value)>0).map(([key,value])=>effectBadge(key,labels[key],Math.ceil(Number(value?.remaining ?? value)))));
        const driving=seat.driving||{};
        if(driving.start_boost_remaining>0)p.effects.prepend(effectBadge('start-boost','СТАРТ',null));
        if(driving.slipstream_boost_remaining>0)p.effects.prepend(effectBadge('slipstream','ПОТОК',null));
        else if(driving.slipstream_charge>0)p.effects.prepend(effectBadge('slipstream',`ПОТОК ${Math.round(clamp(driving.slipstream_charge,0,1)*100)}%`,null));
        if(seat.boost>0&&!(driving.start_boost_remaining>0)&&!(driving.slipstream_boost_remaining>0))p.effects.prepend(effectBadge('drift-boost','УСКОРЕНИЕ',null));
        const results=next.phase==='results';
        p.pane.classList.toggle('is-finished',Boolean(seat.finished)||results);
        p.countdown.textContent=next.countdown>0?Math.ceil(next.countdown):'';p.finish.hidden=!seat.finished&&!results;p.finishTitle.textContent=seat.dnf?'DNF':`${seat.rank || '-'} МЕСТО`;p.finishTime.textContent=time(seat.elapsed);p.ready.textContent=!results?'Ждём остальных':seat.ready?'Готов':`${seat.device===-1?'Enter':'A'} · Ещё заезд`;p.ready.disabled=!results||Boolean(seat.ready)||next.paused;
        drawMap(p.map,next.trackDescriptor,next.players || [],seat.id);
      });
      if(overview) {drawMap(overview.map,next.trackDescriptor,next.players || [],null);overview.list.replaceChildren(...[...(next.players || [])].sort((a,b)=>(a.rank || 99)-(b.rank || 99)).map(player=> {
        const local=next.seats.findIndex(seat=>seat.id===player.id);
        const row=element('li');row.append(element('strong','',String(player.rank || '-')),element('span','',local>=0?`P${local+1} ${styles[next.seats[local].styleId] || ''}`:player.name || 'Бот'));
        if(local>=0)row.style.color=colors[local];return row;
      }));}
      qualityInputs.forEach(input=>input.checked=input.value===(next.graphics?.quality || 'standard'));reduced.checked=Boolean(next.graphics?.reducedEffects);
      if(next.paused) {const key=JSON.stringify([next.seats.map(s=>s.device),next.disconnected,pads]),changed=key!==pauseSignature;if(changed){renderPause();pauseSignature=key;}if(!pause.open)pause.showModal();if(changed&&next.disconnected?.length&&!pauseSettings.open)pauseSettings.showModal();} else {pauseSettings.close();if(pause.open){pause.close();onResume?.();}pauseSignature='';pauseError.textContent='';}
    }
    function updateDevices(devices) {const next=(devices || []).filter(pad=>Number.isInteger(pad.id)&&pad.id>=0).sort((a,b)=>a.id-b.id);if(JSON.stringify(pads)===JSON.stringify(next))return;pads=next;preferController();if(setup.open)renderSetup();if(pause.open){renderPause();pauseSignature='';}}
    function hide() {layer.hidden=true;playerControls.close();lobby.close();pauseSettings.close();pause.close();state=null;}
    function showSetup({tutorial=false}={}) {
      tutorialSetup=tutorial;
      // Training borrows P1's initial choices, not the multiplayer device reservation.
      if(tutorial){tutorialSeat={...setupSeats[0]};tutorialManualDevice=manualDevices.has(0);}
      preferController();start.disabled=false;setupError.textContent='';renderSetup();setup.showModal();
    }
    function handleMenuAction({action,device,container}) {
      if(container===lesson&&state?.tutorial?.complete&&(action==='back'||action==='menu')){hide();onExit?.();return true;}
      if(container!==layer||state?.phase!=='results')return false;
      const index=state.seats.findIndex(seat=>seat.device===device);
      if(action==='confirm'){if(index>=0&&!state.seats[index].ready&&!state.paused)send({type:'local_ready',seat:index});return true;}
      if(action==='back'||action==='menu'){if(index===0){hide();onExit?.();}return true;}
      return true;
    }
    function destroy() {setupControlEditor?.destroy();playerControls.remove();layer.remove();lobby.destroy();pauseSettings.remove();pause.remove();}
    return {showSetup,update,updateDevices,hide,destroy,handleMenuAction,getDefaultProfile:()=>({...savedProfiles[0]}),setDefaultProfile:profile=>{const valid=controls.normalize(profile);if(valid)saveProfile(0,valid);},menuScope:()=>!layer.hidden?(state?.tutorial?.complete?lesson:state?.phase==='results'?layer:null):null,showError:message=>update({error:String(message)})};
  }
  root.GnomLocalUI=Object.freeze({create,validateSeats,formatTime:time});
})(globalThis);
