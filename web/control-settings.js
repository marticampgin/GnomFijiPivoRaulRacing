(function (root) {
  'use strict';
  const keys = ['keyboard', 'gamepad', 'deadzone', 'steering'];
  let nextId = 0;

  function defaultProfile() {
    return {keyboard:'arcade', gamepad:'arcade', deadzone:0.2, steering:1};
  }

  function normalize(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    if (Object.keys(value).length !== keys.length || !keys.every(key => Object.hasOwn(value, key))) return null;
    if (!['arcade', 'both', 'wasd', 'arrows'].includes(value.keyboard)) return null;
    if (!['arcade', 'standard', 'alternate'].includes(value.gamepad)) return null;
    if (!Number.isFinite(value.deadzone) || value.deadzone < 0.05 || value.deadzone > 0.35) return null;
    if (!Number.isFinite(value.steering) || value.steering < 0.5 || value.steering > 1.5) return null;
    return {keyboard:value.keyboard, gamepad:value.gamepad, deadzone:value.deadzone, steering:value.steering};
  }

  function create({profile, onChange, device = -1} = {}) {
    let current = normalize(profile) || defaultProfile();
    let activeDevice = device;
    const prefix = `control-settings-${++nextId}`;
    const fields = {};
    function element(tag, className, text) {
      const node = document.createElement(tag);
      node.className = className || '';
      if (text !== undefined) node.textContent = text;
      return node;
    }
    const node = element('fieldset', 'control-settings');
    node.append(element('legend', '', 'Управление'));
    const grid = element('div', 'control-settings-grid');
    node.append(grid);

    function row(key, title, input) {
      const wrapper = element('div', 'control-settings-row');
      const label = element('label', '', title);
      input.id = `${prefix}-${key}`;
      label.htmlFor = input.id;
      input.dataset.control = key;
      wrapper.append(label, input);
      grid.append(wrapper);
      fields[key] = {input, wrapper};
      return wrapper;
    }

    function commit(key, value) {
      const candidate = normalize({...current, [key]:value});
      if (!candidate) return update(current);
      current = candidate;
      showBindings();
      onChange?.({...current});
    }

    function select(key, title, options) {
      const input = element('select');
      for (const [value, title] of options) {
        const option = element('option', '', title);
        option.value = value;
        input.append(option);
      }
      row(key, title, input);
      input.addEventListener('change', () => commit(key, input.value));
    }

    function range(key, title, min, max, step, format) {
      const input = element('input');
      input.type = 'range';
      input.min = String(min);
      input.max = String(max);
      input.step = String(step);
      const wrapper = row(key, title, input);
      const output = element('output');
      output.htmlFor = input.id;
      wrapper.append(output);
      fields[key].output = output;
      fields[key].format = format;
      function preview() {
        const text = format(Number(input.value));
        output.value = text;
        input.setAttribute('aria-valuetext', text);
      }
      input.addEventListener('input', preview);
      input.addEventListener('change', () => {
        preview();
        commit(key, Number(input.value));
      });
    }

    select('keyboard', 'Клавиатура', [['arcade', 'Аркада · Space / C'], ['both', 'WASD + стрелки'], ['wasd', 'WASD'], ['arrows', 'Стрелки']]);
    select('gamepad', 'Геймпад', [['arcade', 'Аркада · A / B'], ['standard', 'Курки · RT / LT'], ['alternate', 'Курки · задний вид B']]);
    const bindings=element('dl','control-bindings');node.append(bindings);
    function showBindings() {
      const keyboard=current.keyboard==='arcade'?[['Газ / тормоз','Space / C'],['Поворот','A / D'],['Дрифт','Shift / E'],['Турбо','Противоположная Shift / E'],['Предмет','Q'],['Вид назад','F'],['Пауза','Tab / Esc']]
        :[['Газ / тормоз',current.keyboard==='arrows'?'↑ / ↓':'W / S'],['Поворот',current.keyboard==='arrows'?'← / →':'A / D'],['Дрифт','Shift / E'],['Турбо','Противоположная Shift / E'],['Предмет','Q'],['Вид назад','C'],['Пауза','Esc']];
      const gamepad=current.gamepad==='arcade'?['A / B','LS','LB / RB','Противоположная LB / RB','Y','X','Menu']
        :['RT / LT','LS','LB / RB','Противоположная LB / RB','Y',current.gamepad==='alternate'?'B':'X','Menu'];
      bindings.replaceChildren(...keyboard.flatMap(([label,key],i)=>[element('dt','',label),element('dd','',activeDevice >= 0 ? gamepad[i] : key)]));
    }
    range('deadzone', 'Мёртвая зона', 0.05, 0.35, 0.01, value => `${Math.round(value * 100)}%`);
    range('steering', 'Чувствительность', 0.5, 1.5, 0.05, value => `${value.toFixed(2)}×`);

    const reset = element('button', 'control-settings-reset');
    reset.type = 'button';
    reset.title = 'Сбросить управление';
    reset.setAttribute('aria-label', reset.title);
    const icon = element('img');
    icon.src = '/assets/icons/rotate-ccw.svg';
    icon.alt = '';
    reset.append(icon);
    reset.addEventListener('click', () => {
      update(defaultProfile());
      onChange?.({...current});
    });
    node.append(reset);

    function update(profile) {
      const next = normalize(profile);
      if (!next) return false;
      current = next;
      showBindings();
      for (const key of keys) {
        const field = fields[key];
        field.input.value = String(current[key]);
        if (field.output) {
          const text = field.format(current[key]);
          field.output.value = text;
          field.input.setAttribute('aria-valuetext', text);
        }
      }
      return true;
    }

    update(current);
    function setDevice(value) {
      const focused=Object.keys(fields).find(key=>fields[key].input===document.activeElement);
      activeDevice = Number(value);
      fields.keyboard.wrapper.hidden = activeDevice >= 0;
      fields.gamepad.wrapper.hidden = activeDevice < 0;
      fields.deadzone.wrapper.hidden = activeDevice < 0;
      showBindings();
      if(focused&&fields[focused].wrapper.hidden)fields[activeDevice>=0?'gamepad':focused==='deadzone'?'steering':'keyboard'].input.focus({preventScroll:true});
    }
    setDevice(device);
    return {node, update, setDevice, destroy:() => node.remove()};
  }

  root.GnomControlSettings = {defaultProfile, normalize, create};
})(typeof window !== 'undefined' ? window : globalThis);
