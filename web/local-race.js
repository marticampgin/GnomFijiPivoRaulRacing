(function (root) {
  'use strict';
  const styles = {handling:'Управляемость', acceleration:'Ускорение', speed:'Скорость', drift:'Дрифт'};
  const items = {fanta:'Fanta', mermaid_rum:'Mermaid Rum', ice_rum:'Ice Rum', stroh80:'Stroh 80', lays_crab:'Lay’s Crab', bfg10k:'BFG 10K'};
  const colors = ['#64e3db','#ffd36b','#ff877b','#a9cfff'];
  const clamp = (value, min, max) => Math.max(min, Math.min(max, Number(value) || 0));
  const time = value => { const ms = Math.max(0, Math.floor((Number(value) || 0) * 1000)); return `${String(Math.floor(ms/60000)).padStart(2,'0')}:${String(Math.floor(ms/1000)%60).padStart(2,'0')}.${String(ms%1000).padStart(3,'0')}`; };
  function element(tag, className, text) { const node = document.createElement(tag); node.className = className || ''; if (text !== undefined) node.textContent = text; return node; }
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
  function create({send, onStart, onExit, onGraphics}) {
    let state = null, pads = [], panes = [], setupSeats = [{device:-1,style_id:'drift',name:'P1'}], chosenLayout = 'side-by-side';
    const layer = element('section','local-race'); layer.hidden = true; layer.id = 'local-race';
    const grid = element('div','local-grid'); layer.append(grid); document.body.append(layer);
    const setup = element('dialog','local-dialog'); setup.id = 'local-setup';
    const setupHeading = element('h2','','Локальная гонка');
    const count = select([1,2,3,4].map(n => [n,`${n} ${n===1?'игрок':'игрока'}`]),1,'Количество игроков');
    const layout = select([['side-by-side','Рядом'],['stacked','Друг над другом']],'side-by-side','Разделение экрана');
    const difficulty = select([['easy','Лёгкие боты'],['normal','Обычные боты'],['hard','Сложные боты']],'normal','Сложность ботов');
    const setupRows = element('div','local-setup-rows'), setupError = element('p','local-error'); setupError.setAttribute('role','alert');
    const start = button('На старт', () => {
      const error = validateSeats(setupSeats,pads); setupError.textContent = error;
      if (error) return;
      start.disabled = true;
      const payload = {type:'local_start',seats:setupSeats.map(seat => ({...seat})),layout:chosenLayout,botDifficulty:difficulty.value};
      (onStart || send)(payload);
    },'arrow-up-right'); start.id = 'local-start';
    const setupActions = element('div','local-actions'); setupActions.append(button('Назад',()=>setup.close(),'x'),start);
    setup.append(setupHeading,count,layout,difficulty,setupRows,setupError,setupActions); document.body.append(setup);
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
    const resume = button('Продолжить',()=>send({type:'local_resume'}),'arrow-up-right'); resume.id = 'local-resume';
    const pauseActions = element('div','local-actions'); pauseActions.append(button('Выйти',()=>{ hide(); onExit?.(); },'x'),resume);
    pause.append(pauseTitle,pauseRows,graphics,pauseError,pauseActions); document.body.append(pause);
    pause.addEventListener('cancel',event=>{event.preventDefault(); if(!resume.disabled)send({type:'local_resume'});});
    const pauseButton = button('',()=>send({type:'local_pause'}),'pause'); pauseButton.title='Пауза'; pauseButton.setAttribute('aria-label','Пауза'); pauseButton.className='local-pause-button'; layer.append(pauseButton);
    function deviceOptions() { return [[-2,'Выберите контроллер'],[-1,'Клавиатура'],...pads.map(pad=>[pad.id,`${pad.name || 'Геймпад'} (${pad.id+1})`])]; }
    function renderSetup() {
      layout.hidden = setupSeats.length !== 2;
      setupRows.replaceChildren(...setupSeats.map((seat,index)=> {
        const row = element('div','local-setup-row'); row.style.setProperty('--seat',colors[index]);
        const device = select(deviceOptions(),seat.device,`Контроллер P${index+1}`);
        device.addEventListener('change',()=>{seat.device=Number(device.value);setupError.textContent='';});
        const style = select(Object.entries(styles),seat.style_id,`Стиль P${index+1}`); style.addEventListener('change',()=>seat.style_id=style.value);
        row.append(element('strong','',`P${index+1}`),device,style); return row;
      }));
    }
    count.addEventListener('change',()=> {
      const number = Number(count.value);
      while(setupSeats.length<number) { const used = new Set(setupSeats.map(seat=>seat.device)); setupSeats.push({device:pads.find(pad=>!used.has(pad.id))?.id ?? -2,style_id:Object.keys(styles)[setupSeats.length%4],name:`P${setupSeats.length+1}`}); }
      setupSeats = setupSeats.slice(0,number); renderSetup();
    });
    layout.addEventListener('change',()=>chosenLayout=layout.value);
    function buildPane(index) {
      const pane = element('section','local-pane'); pane.dataset.seat=index; pane.style.setProperty('--seat',colors[index]);
      const blur = element('div','local-sector-blur');
      const identity = element('div','local-identity'); const inventory = element('div','local-inventory');
      const slots = [0,1].map(slot=> { const node = button('',()=>send({type:'local_use_item',seat:index,slot})); node.className='local-slot'; const img=element('img'),key=element('span','local-slot-key'),empty=element('span','local-slot-empty','−'); img.alt=''; node.append(img,empty,key); inventory.append(node); return {node,img,key,empty}; });
      const lap = element('div','local-lap'), lapValue=element('strong'), clock=element('span'); lap.append(element('span','','КРУГ'),lapValue,clock);
      const rank = element('div','local-rank'), rankValue=element('strong'), total=element('span'); rank.append(rankValue,total,element('small','','МЕСТО'));
      const health = element('div','local-health'), healthValue=element('strong'), healthBar=element('progress'); healthBar.max=100; healthBar.setAttribute('aria-label',`Прочность P${index+1}`); health.append(element('span','','ПРОЧНОСТЬ'),healthValue,healthBar);
      const crystals=element('div','local-crystals'), crystalIcon=element('img'), crystalValue=element('strong','',0); crystalIcon.src='/assets/icons/crystal-shard.svg';crystalIcon.alt='';crystals.append(crystalIcon,crystalValue);crystals.setAttribute('aria-label',`Осколки P${index+1}`);
      const drift = element('div','local-drift'), driftLabel=element('span','','ДРИФТ'), driftTrack=element('div','local-drift-segments');
      const driftBars=[0,1,2].map(level=>{const bar=element('progress');bar.max=1;bar.setAttribute('aria-label',`Дрифт P${index+1}, уровень ${level+1}`);driftTrack.append(bar);return bar;});drift.append(driftLabel,driftTrack);
      const speed = element('div','local-speed'), speedValue=element('strong'), reverse=element('b','local-reverse','R'); reverse.hidden=true;reverse.setAttribute('aria-label','Задний ход');speed.append(reverse,speedValue,element('span','','км/ч'));
      const effects=element('div','local-effects'), map=element('canvas','local-map'); map.width=160;map.height=160;map.setAttribute('aria-label',`Карта P${index+1}`);
      const countdown=element('div','local-countdown'), finish=element('div','local-finish'), finishTitle=element('strong'),finishTime=element('span');
      const ready=button('Ещё заезд',()=>send({type:'local_ready',seat:index}),'rotate-ccw'); finish.append(finishTitle,finishTime,ready); finish.hidden=true;
      pane.append(blur,identity,inventory,crystals,lap,rank,health,drift,speed,effects,map,countdown,finish);
      return {pane,blur,identity,slots,crystals,crystalValue,lapValue,clock,rankValue,total,healthValue,healthBar,driftLabel,driftBars,speedValue,reverse,effects,map,countdown,finish,finishTitle,finishTime,ready};
    }
    function drawMap(canvas, descriptor, players, id) {
      const ctx=canvas.getContext('2d'); if(!ctx)return; ctx.clearRect(0,0,canvas.width,canvas.height);
      const projection=root.GnomTrackMap?.project(descriptor,canvas.width,canvas.height,12); if(!projection)return;
      ctx.lineCap='round';ctx.lineJoin='round';ctx.beginPath();projection.points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.lineWidth=8;ctx.strokeStyle='#131715';ctx.stroke();ctx.lineWidth=3;ctx.strokeStyle='#f5f7f4';ctx.stroke();
      const [from,to]=projection.points;const angle=Math.atan2(to[1]-from[1],to[0]-from[0]);
      ctx.save();ctx.translate(...from);ctx.rotate(angle);ctx.beginPath();ctx.moveTo(7,0);ctx.lineTo(-4,-4);ctx.lineTo(-4,4);ctx.closePath();ctx.fillStyle='#e5ff58';ctx.fill();ctx.restore();
      for(const player of players) { const pos=player.worldPosition || player.position; if(!Array.isArray(pos))continue;const point=projection.worldToMap(pos[0],pos.length===3?pos[2]:pos[1]);if(!point)continue;ctx.beginPath();ctx.arc(...point,player.id===id?5:3,0,Math.PI*2);ctx.fillStyle=player.id===id?'#e5ff58':colors[player.seat]||'#f5f7f4';ctx.fill(); }
    }
    function renderPause() {
      if(!state)return;
      const disconnected=state.disconnected || [];
      pauseTitle.textContent=disconnected.length?'Контроллер отключён':'Пауза'; resume.disabled=disconnected.length>0;
      pauseRows.replaceChildren(...state.seats.map((seat,index)=> {
        const row=element('div','local-setup-row');row.style.setProperty('--seat',colors[index]);
        const devices=select(deviceOptions(),seat.device,`Контроллер P${index+1}`);
        devices.addEventListener('change',()=> {
          const device=Number(devices.value);
          const duplicate=state.seats.some((other,otherIndex)=>otherIndex!==index&&other.device===device);
          if(device < -1 || duplicate) {pauseError.textContent=duplicate?'Этот контроллер уже назначен другому игроку.':'Выберите подключённый контроллер.';devices.value=String(seat.device);return;}
          pauseError.textContent='';send({type:'local_assign',seat:index,device});
        });
        const recover=button('На трассу',()=>send({type:'local_recover',seat:index}),'rotate-ccw'); recover.disabled=Boolean(seat.finished);
        row.append(element('strong','',`P${index+1}`),devices,recover);return row;
      }));
    }
    let pauseSignature='', overview=null;
    function update(next) {
      if(next.error) { setupError.textContent=next.error;pauseError.textContent=next.error;start.disabled=false;return; }
      if(!Array.isArray(next.seats)||!next.seats.length)return;
      state=next;start.disabled=false;if(setup.open)setup.close();layer.hidden=false;
      const signature=`${next.seats.length}:${next.layout}`;
      if(grid.dataset.layout!==signature) {
        grid.dataset.layout=signature;grid.className=`local-grid players-${next.seats.length} ${next.layout==='stacked'?'stacked':''}`;
        panes=next.seats.map((_,index)=>buildPane(index));grid.replaceChildren(...panes.map(p=>p.pane));overview=null;
        if(next.seats.length===3) {const panel=element('section','local-overview'),map=element('canvas'),list=element('ol');map.width=260;map.height=260;panel.append(element('h3','','ЗАМОК И ВОДОПАДЫ'),map,list);grid.append(panel);overview={map,list};}
      }
      next.seats.forEach((seat,index)=> {
        const p=panes[index];p.identity.textContent=`P${index+1} / ${(styles[seat.styleId] || styles.drift).toUpperCase()}`;
        p.blur.style.backdropFilter=`blur(${clamp(seat.blurIntensity,0,1)*(next.graphics?.reducedEffects?.6:3)}px)`;
        p.lapValue.textContent=`${seat.lap || 1} / ${seat.laps || 3}`;p.clock.textContent=time(seat.elapsed);p.rankValue.textContent=seat.rank || '-';p.total.textContent=`/ ${next.players?.length || 10}`;
        p.healthValue.textContent=Math.ceil(clamp(seat.health,0,seat.maxHealth || 100));p.healthBar.max=seat.maxHealth || 100;p.healthBar.value=clamp(seat.health,0,p.healthBar.max);p.healthBar.classList.toggle('critical',p.healthBar.value/p.healthBar.max<.35);
        p.speedValue.textContent=Math.round(Number(seat.speed)||0);p.reverse.hidden=!seat.reverse;
        p.crystalValue.textContent=clamp(seat.shards,0,seat.shardCap||20);p.crystals.title=`Осколки: ${p.crystalValue.textContent} / ${seat.shardCap||20}`;
        p.driftBars.forEach((bar,level)=>bar.value=clamp(seat.driftSegments?.[level],0,1));p.driftLabel.textContent=`ДРИФТ ${['','I','II','III'][clamp(seat.driftLevel,0,3)]}`;
        p.slots.forEach(({node,img,key,empty},slot)=> { const item=seat.items?.[slot];const valid=Object.hasOwn(items,item);img.hidden=!valid;empty.hidden=valid;if(valid && img.dataset.item!==item){img.src=`/assets/items/${item}.png`;img.dataset.item=item;}key.textContent=seat.device===-1?['Q','E'][slot]:['LB','RB'][slot];node.disabled=!valid||!seat.canUseItems||next.paused;node.title=valid?items[item]:'Пусто';node.setAttribute('aria-label',`P${index+1}, предмет ${slot+1}: ${valid?items[item]:'пусто'}`); });
        const labels={...items,burn:'Горение',invulnerable:'Защита',recovery:'Восстановление'};
        const effects={...seat.effects};if(seat.invulnerableRemaining>0)effects.invulnerable=seat.invulnerableRemaining;if(seat.destroyedRemaining>0)effects.recovery=seat.destroyedRemaining;
        p.effects.replaceChildren(...Object.entries(effects).filter(([key,value])=>labels[key]&&Number(value?.remaining ?? value)>0).map(([key,value])=>element('span',`local-effect ${key}`,`${labels[key]} ${Math.ceil(Number(value?.remaining ?? value))} с`)));
        const driving=seat.driving||{};
        if(driving.start_boost_remaining>0)p.effects.prepend(element('span','local-effect start-boost','СТАРТ'));
        if(driving.slipstream_boost_remaining>0)p.effects.prepend(element('span','local-effect slipstream','ПОТОК'));
        else if(driving.slipstream_charge>0)p.effects.prepend(element('span','local-effect slipstream',`ПОТОК ${Math.round(clamp(driving.slipstream_charge,0,1)*100)}%`));
        if(seat.boost>0&&!(driving.start_boost_remaining>0)&&!(driving.slipstream_boost_remaining>0))p.effects.prepend(element('span','local-effect drift-boost','УСКОРЕНИЕ'));
        const results=next.phase==='results';
        p.countdown.textContent=next.countdown>0?Math.ceil(next.countdown):'';p.finish.hidden=!seat.finished&&!results;p.finishTitle.textContent=seat.dnf?'DNF':`${seat.rank || '-'} МЕСТО`;p.finishTime.textContent=time(seat.elapsed);p.ready.textContent=!results?'Ждём остальных':seat.ready?'Готов':'Ещё заезд';p.ready.disabled=!results||Boolean(seat.ready)||next.paused;
        drawMap(p.map,next.trackDescriptor,next.players || [],seat.id);
      });
      if(overview) {drawMap(overview.map,next.trackDescriptor,next.players || [],null);overview.list.replaceChildren(...[...(next.players || [])].sort((a,b)=>(a.rank || 99)-(b.rank || 99)).map(player=> {
        const local=next.seats.findIndex(seat=>seat.id===player.id);
        const row=element('li');row.append(element('strong','',String(player.rank || '-')),element('span','',local>=0?`P${local+1} ${styles[next.seats[local].styleId] || ''}`:player.name || 'Бот'));
        if(local>=0)row.style.color=colors[local];return row;
      }));}
      qualityInputs.forEach(input=>input.checked=input.value===(next.graphics?.quality || 'standard'));reduced.checked=Boolean(next.graphics?.reducedEffects);
      if(next.paused) {const key=JSON.stringify([next.seats.map(s=>s.device),next.disconnected,pads]);if(key!==pauseSignature){renderPause();pauseSignature=key;}if(!pause.open)pause.showModal();} else {if(pause.open)pause.close();pauseSignature='';pauseError.textContent='';}
    }
    function updateDevices(devices) {const next=(devices || []).filter(pad=>Number.isInteger(pad.id)&&pad.id>=0);if(JSON.stringify(pads)===JSON.stringify(next))return;pads=next;if(setup.open)renderSetup();if(pause.open){renderPause();pauseSignature='';}}
    function hide() {layer.hidden=true;setup.close();pause.close();state=null;}
    function showSetup() {start.disabled=false;setupError.textContent='';renderSetup();setup.showModal();}
    function destroy() {layer.remove();setup.remove();pause.remove();}
    return {showSetup,update,updateDevices,hide,destroy,showError:message=>update({error:String(message)})};
  }
  root.GnomLocalUI=Object.freeze({create,validateSeats,formatTime:time});
})(globalThis);
