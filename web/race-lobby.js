(function (root) {
  'use strict';
  const styles = [
    ['handling', 'Управляемость', 'circle-dot'], ['acceleration', 'Ускорение', 'zap'],
    ['speed', 'Скорость', 'gauge'], ['drift', 'Дрифт', 'route'],
  ];
  const colors = ['#04ced8', '#ffda38', '#fa817a', '#92baff'];
  function element(tag, className, text) {
    const node = document.createElement(tag); node.className = className || '';
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function icon(name) { const img = element('img'); img.src = `/assets/icons/${name}.svg`; img.alt = ''; return img; }
  function button(className, label, action, iconName) {
    const node = element('button', className); node.type = 'button';
    if (iconName) node.append(icon(iconName));
    node.append(element('span', '', label)); node.addEventListener('click', action); return node;
  }
  function stepper(label, name, iconName, onChange) {
    let options = [], value;
    const node = element('div', 'lobby-stepper'); node.tabIndex = 0;
    node.setAttribute('role', 'spinbutton'); node.setAttribute('aria-label', label);
    node.setAttribute('data-menu-adjust', ''); node.dataset.focusKey = name;
    const caption = element('span', 'lobby-option-label', label), output = element('strong', 'lobby-option-value');
    const arrows = [-1, 1].map((amount, index) => {
      const arrow = button('lobby-arrow', '', () => { node.focus({preventScroll:true}); adjust(amount); }, index ? 'chevron-right' : 'chevron-left');
      arrow.tabIndex = -1; arrow.title = `${label}: ${index ? 'следующее' : 'предыдущее'} значение`;
      arrow.setAttribute('aria-label', arrow.title); return arrow;
    });
    function available() { return options.filter(option => !option.disabled); }
    function adjust(amount) {
      const allowed = available(), current = allowed.findIndex(option => option.value === value);
      const index = current < 0 ? (amount > 0 ? 0 : allowed.length - 1) : Math.max(0, Math.min(allowed.length - 1, current + amount));
      const next = allowed[index]; if (next && next.value !== value) onChange(next.value);
    }
    node.addEventListener('menu-adjust', event => adjust(event.detail.amount));
    node.append(icon(iconName), caption, arrows[0], output, arrows[1]);
    return {node, set(nextOptions, nextValue) {
      options = nextOptions; value = nextValue;
      const index = options.findIndex(option => option.value === value), selected = options[index];
      output.textContent = selected?.label || 'Не подключён';
      node.setAttribute('aria-valuemin', '0'); node.setAttribute('aria-valuemax', String(Math.max(0, options.length - 1)));
      node.setAttribute('aria-valuenow', String(Math.max(0, index))); node.setAttribute('aria-valuetext', output.textContent);
      const allowed = available(), position = allowed.findIndex(option => option.value === value);
      arrows[0].disabled = !allowed.length || position === 0; arrows[1].disabled = !allowed.length || position === allowed.length - 1;
    }};
  }
  function create(actions) {
    let selectedSeat = 0, state = null;
    const node = element('dialog', 'race-lobby'); node.id = 'local-setup'; node.setAttribute('aria-label', 'Локальная гонка');
    const header = element('header', 'lobby-header'), heading = element('h2', '', 'Локальная гонка');
    const title = element('div', 'lobby-title'); title.append(icon('flag'), heading);
    header.append(title, element('span', 'lobby-wordmark', 'GNOM FIJI'));
    const seats = element('div', 'lobby-seats'); seats.setAttribute('aria-label', 'Игроки');
    const seatButtons = Array.from({length:4}, (_, index) => {
      const seat = button('lobby-seat', '', () => {
        selectedSeat = index;
        if (index >= state.seats.length) actions.onCount(index + 1);
        else update(state);
      });
      seat.dataset.focusKey = `lobby-seat-${index}`; seat.style.setProperty('--seat-color', colors[index]);
      seats.append(seat); return seat;
    });
    const body = element('div', 'lobby-body'), showroom = element('section', 'lobby-showroom');
    const model = element('div', 'lobby-model'), kart = element('img', 'lobby-kart');
    kart.src = '/assets/lobby-kart.png'; kart.alt = 'Гном в красном колпаке за рулём бирюзового карта'; kart.draggable = false;
    model.append(kart);
    const styleSection = element('section', 'lobby-styles'), styleHeading = element('h3', '', 'Стиль вождения');
    const styleChoices = element('div', 'lobby-style-choices'); styleChoices.setAttribute('role', 'group');
    styleChoices.setAttribute('aria-label', 'Стиль вождения');
    const styleButtons = styles.map(([id, label, symbol]) => {
      const choice = button('lobby-style', label, () => actions.onStyle(selectedSeat, id), symbol);
      choice.dataset.styleId = id; choice.dataset.focusKey = `lobby-style-${id}`; styleChoices.append(choice); return choice;
    });
    styleSection.append(styleHeading, styleChoices); showroom.append(model, styleSection);
    const race = element('section', 'lobby-race'), raceHeading = element('h3', '', 'Заезд');
    const track = element('figure', 'lobby-track'), trackImage = element('img'); trackImage.src = '/assets/lobby-paddock.jpg'; trackImage.alt = 'Замок, озеро и водопады';
    const trackCaption = element('figcaption'); trackCaption.append(element('strong', '', 'Замок и водопады'));
    const raceInfo = element('span', '', '3 круга · 10 гонщиков'); trackCaption.append(raceInfo); track.append(trackImage, trackCaption);
    const options = element('div', 'lobby-options');
    const count = stepper('Игроки', 'lobby-count', 'users', actions.onCount);
    const difficulty = stepper('Боты', 'lobby-difficulty', 'bot', actions.onDifficulty);
    const layout = stepper('Экран', 'lobby-layout', 'maximize', actions.onLayout);
    options.append(count.node, difficulty.node, layout.node);
    const player = element('div', 'lobby-player-settings');
    const device = stepper('Устройство', 'lobby-device', 'gamepad-2', value => actions.onDevice(selectedSeat, value));
    const controls = button('lobby-controls-button', 'Управление', () => actions.onControls(selectedSeat), 'settings-2');
    controls.dataset.focusKey = 'lobby-controls'; controls.dataset.menuDown = 'lobby-start'; player.append(device.node, controls);
    race.append(raceHeading, track, options, player); body.append(showroom, race);
    const error = element('p', 'lobby-error'); error.setAttribute('role', 'alert');
    const footer = element('footer', 'lobby-footer');
    const back = button('lobby-back', 'Назад', actions.onBack, 'arrow-left'); back.id = 'local-setup-back';
    const start = button('lobby-start', 'На старт', actions.onStart, 'arrow-right'); start.id = 'local-start'; start.setAttribute('data-menu-default', '');
    start.dataset.focusKey = 'lobby-start'; start.dataset.menuUp = 'lobby-controls';
    const startText = start.querySelector('span'); footer.append(back, start);
    node.append(header, seats, body, error, footer);
    function update(next) {
      state = next; const visibleSeats = next.tutorial ? next.seats.slice(0, 1) : next.seats;
      selectedSeat = Math.min(selectedSeat, visibleSeats.length - 1);
      node.dataset.tutorial = String(Boolean(next.tutorial));
      heading.textContent = next.tutorial ? 'Обучение' : 'Локальная гонка';
      node.setAttribute('aria-label', heading.textContent);
      startText.textContent = next.tutorial ? 'Начать' : 'На старт';
      raceInfo.textContent = next.tutorial ? 'Практика вождения' : '3 круга · 10 гонщиков';
      for (let index = 0; index < 4; index++) {
        const seat = visibleSeats[index], target = seatButtons[index], pad = seat && next.pads.find(p => p.id === seat.device);
        const connected = seat && (seat.device === -1 || pad);
        target.hidden = Boolean(next.tutorial && index);
        target.classList.toggle('is-empty', !seat); target.classList.toggle('is-missing', Boolean(seat && !connected));
        target.setAttribute('aria-pressed', String(index === selectedSeat));
        const subtitle = !seat ? 'Добавить' : seat.device === -1 ? 'Клавиатура' : pad ? 'Геймпад' : 'Не подключён';
        target.setAttribute('aria-label', `P${index + 1}: ${subtitle}`);
        const label = element('span', 'lobby-seat-label'); label.append(element('strong', '', `P${index + 1}`), element('small', '', subtitle));
        target.replaceChildren(icon(!seat ? 'plus' : seat.device === -1 ? 'keyboard' : 'gamepad-2'), label);
      }
      const current = visibleSeats[selectedSeat];
      styleHeading.textContent = `Стиль вождения${visibleSeats.length > 1 ? ` · P${selectedSeat + 1}` : ''}`;
      styleChoices.setAttribute('aria-label', `Стиль P${selectedSeat + 1}`);
      for (const choice of styleButtons) choice.setAttribute('aria-pressed', String(choice.dataset.styleId === current.style_id));
      count.node.hidden = difficulty.node.hidden = Boolean(next.tutorial);
      count.set([1, 2, 3, 4].map(value => ({value, label:String(value)})), visibleSeats.length);
      difficulty.set([['easy','Лёгкие'],['normal','Обычные'],['hard','Сложные']].map(([value,label]) => ({value,label})), next.difficulty);
      layout.node.hidden = next.tutorial || visibleSeats.length !== 2;
      layout.set([['side-by-side','Рядом'],['stacked','Друг над другом']].map(([value,label]) => ({value,label})), next.layout);
      const devices = [{value:-1,label:'Клавиатура'}, ...next.pads.map(p => ({value:p.id,label:`Геймпад ${p.id + 1}`}))];
      if (!devices.some(option => option.value === current.device)) devices.unshift({value:current.device,label:'Не подключён',disabled:true});
      device.set(devices.map(option => ({...option, disabled:option.disabled || visibleSeats.some((seat,index) => index !== selectedSeat && seat.device === option.value)})), current.device);
      device.node.setAttribute('aria-label', `Контроллер P${selectedSeat + 1}`);
      controls.setAttribute('aria-label', `Управление P${selectedSeat + 1}`);
    }
    return {node, heading, start, error, update, close:() => node.close(), destroy:() => node.remove()};
  }
  root.GnomRaceLobby = Object.freeze({create});
})(globalThis);
