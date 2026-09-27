(function (root) {
  'use strict';

  // Edges and repeats are per device, so a held button cannot confirm a new screen.
  function createPadReader() {
    const previous = new Map();
    function read(pads, now, detailed = false) {
      const actions = [];
      const connected = new Set();
      for (const pad of pads || []) {
        if (!pad || pad.connected === false || pad.mapping !== 'standard') continue;
        connected.add(pad.index);
        const emit = action => actions.push(detailed ? {action, device:pad.index} : action);
        const pressed = index => Boolean(pad.buttons[index]?.pressed);
        const x = Number(pad.axes[0]) || 0, y = Number(pad.axes[1]) || 0;
        const old = previous.get(pad.index);
        const threshold = old?.direction ? 0.4 : 0.55;
        const direction = pressed(12) ? 'up' : pressed(13) ? 'down' : pressed(14) ? 'left' : pressed(15) ? 'right'
          : Math.max(Math.abs(x), Math.abs(y)) < threshold ? null
          : Math.abs(x) > Math.abs(y) ? x < 0 ? 'left' : 'right' : y < 0 ? 'up' : 'down';
        const current = {confirm:pressed(0), back:pressed(1), menu:pressed(9), direction};
        if (old) {
          for (const action of ['confirm','back']) {
            current[`${action}Armed`] = current[action] && (!old[action] || old[`${action}Armed`]);
            if (!current[action] && old[action] && old[`${action}Armed`]) emit(action);
          }
          if (current.menu && !old.menu) emit('menu');
          if (direction && (direction !== old.direction || now >= old.repeatAt)) {
            emit(direction);
            current.repeatAt = now + (direction !== old.direction ? 360 : 130);
          } else current.repeatAt = old.repeatAt;
        } else current.repeatAt = now + 360;
        previous.set(pad.index, current);
      }
      for (const index of previous.keys()) if (!connected.has(index)) previous.delete(index);
      return actions;
    }
    read.cancel = () => {
      for (const value of previous.values()) { value.confirmArmed = false; value.backArmed = false; }
    };
    return read;
  }

  function create({scope, onMenu, onBack, onAction, onDevice, allowMenu = () => true} = {}) {
    const doc = root.document, read = createPadReader();
    let frame = 0, lastScope = null, source = 'keyboard', device = -1;
    const remembered = new WeakMap();
    let detectedPads = new Set();
    const hints = doc.createElement('div');
    hints.className = 'menu-hints'; hints.setAttribute('aria-hidden', 'true');
    const selector = 'button, input:not([type="hidden"]), select, summary, a[href], [tabindex="0"]';
    function visible(node) {
      if (!node || node.matches(':disabled') || node.closest('[hidden], [inert]') || !node.getClientRects().length) return false;
      // Chromium can retain layout rectangles inside a closed details element.
      for (let parent = node.parentElement; parent; parent = parent.parentElement) {
        if (parent.tagName === 'DETAILS' && !parent.open) {
          const summary = Array.from(parent.children).find(child => child.tagName === 'SUMMARY');
          if (!summary?.contains(node)) return false;
        }
      }
      const style = root.getComputedStyle(node);
      return style.visibility !== 'hidden' && style.display !== 'none';
    }
    function choices(container) { return Array.from(container.querySelectorAll(selector)).filter(node => node.tabIndex >= 0 && visible(node)); }
    function focus(node) {
      node?.focus({preventScroll:true});
      node?.scrollIntoView({block:'nearest', inline:'nearest'});
      if (lastScope?.contains(node)) remembered.set(lastScope, node);
    }
    function showHints(container) {
      if (!container) { hints.remove(); return; }
      const results = container.dataset.phase === 'results';
      const active = doc.activeElement;
      const adjusting = active?.hasAttribute('data-menu-adjust') || active?.tagName === 'SELECT' || active?.type === 'range';
      const entries = adjusting ? [['← →', 'Изменить']] : [[source === 'gamepad' ? 'A' : 'Enter', results ? 'Готов' : 'Выбрать']];
      if (container.id !== 'hub') entries.push([source === 'gamepad' ? 'B' : 'Esc', results ? 'В меню · P1' : 'Назад']);
      hints.replaceChildren(...entries.map(([key, label]) => {
        const span = doc.createElement('span'), glyph = doc.createElement('kbd');
        glyph.textContent = key; span.append(glyph, doc.createTextNode(label)); return span;
      }));
      if (hints.parentElement !== container) container.append(hints);
    }
    function ensure(container) {
      if (!container) { lastScope = null; showHints(null); read.cancel(); return []; }
      const nodes = choices(container);
      const changed=container!==lastScope;
      if (changed) read.cancel();
      lastScope=container;
      if (changed || !nodes.includes(doc.activeElement)) {
        const saved = remembered.get(container);
        focus(nodes.includes(saved) ? saved : nodes.find(node => node.hasAttribute('data-menu-default')) || nodes[0]);
      }
      showHints(container);
      return nodes;
    }
    function neighbor(active, nodes, direction) {
      const from = active?.getBoundingClientRect();
      if (!from) return nodes[0];
      const horizontal = direction === 'left' || direction === 'right';
      const sign = direction === 'left' || direction === 'up' ? -1 : 1;
      const center = rect => horizontal ? (rect.left + rect.right) / 2 : (rect.top + rect.bottom) / 2;
      const cross = rect => horizontal ? (rect.top + rect.bottom) / 2 : (rect.left + rect.right) / 2;
      const candidates = nodes.filter(node => node !== active).map(node => {
        const rect = node.getBoundingClientRect(), forward = (center(rect) - center(from)) * sign;
        const perpendicular = Math.abs(cross(rect) - cross(from));
        const overlap = horizontal ? rect.top < from.bottom && rect.bottom > from.top : rect.left < from.right && rect.right > from.left;
        return {node, forward, perpendicular, overlap};
      }).filter(value => value.forward > 2 && (value.overlap || value.perpendicular <= value.forward * 0.75));
      candidates.sort((a,b) => Number(b.overlap) - Number(a.overlap) || (a.forward + a.perpendicular * (a.overlap ? .05 : 3)) - (b.forward + b.perpendicular * (b.overlap ? .05 : 3)));
      return candidates[0]?.node || active;
    }
    function adjust(node, amount) {
      if (node?.hasAttribute('data-menu-adjust')) {
        node.dispatchEvent(new root.CustomEvent('menu-adjust', {bubbles:true, detail:{amount}}));
        return true;
      }
      if (node?.tagName === 'SELECT') {
        const options = Array.from(node.options).filter(option => !option.disabled && !option.hidden);
        const index = options.findIndex(option => option.selected);
        const option = options[Math.max(0, Math.min(options.length - 1, index + amount))];
        if (option && node.value !== option.value) {
          node.value = option.value;
          node.dispatchEvent(new Event('input', {bubbles:true}));
          node.dispatchEvent(new Event('change', {bubbles:true}));
        }
        return true;
      }
      if (node?.type === 'range') {
        amount > 0 ? node.stepUp() : node.stepDown();
        node.dispatchEvent(new Event('input', {bubbles:true}));
        node.dispatchEvent(new Event('change', {bubbles:true}));
        return true;
      }
      return false;
    }
    function back(container, source, device) {
      if (onBack?.(container, source, device)) return;
      if (container.tagName === 'DIALOG') {
        const event = new Event('cancel', {cancelable:true});
        if (container.dispatchEvent(event)) container.close();
      }
    }
    function action(value, nextSource, nextDevice = -1) {
      source = nextSource; device = nextDevice;
      doc.documentElement.dataset.navigation = source;
      onDevice?.(source, device);
      if (value === 'menu' && !allowMenu()) return;
      const container = scope();
      if (!container) { if (value === 'menu') onMenu?.(); return; }
      const nodes = ensure(container), active = doc.activeElement;
      remembered.set(container, active);
      if (onAction?.({action:value, source, device, container})) return;
      if (value === 'back' || value === 'menu') { back(container, source, device); return; }
      if (value === 'confirm') {
        if (active?.hasAttribute('data-menu-device') && Number(active.dataset.menuDevice) !== device) return;
        if (active?.hasAttribute('data-menu-adjust')) return;
        // Native select popups do not receive Gamepad API input. Cycle without opening one.
        if (active?.tagName === 'SELECT') adjust(active, 1);
        else active?.click();
        return;
      }
      if (!nodes.length) return;
      if (['left','right'].includes(value) && adjust(active, value === 'left' ? -1 : 1)) return;
      const target = active?.getAttribute(`data-menu-${value}`);
      const directed = target && nodes.find(node => node.dataset.focusKey === target);
      focus(directed || neighbor(active, nodes, value));
      showHints(container);
    }
    function keydown(event) {
      if (event.altKey || event.ctrlKey || event.metaKey) return;
      source='keyboard';device=-1;doc.documentElement.dataset.navigation=source;onDevice?.(source,device);
      if(!scope())return;
      const keys = {ArrowUp:'up', ArrowDown:'down', ArrowLeft:'left', ArrowRight:'right', Enter:'confirm', Escape:'back'};
      const value = keys[event.key];
      if (!value) return;
      if (event.target.matches('textarea, input:not([type="radio"]):not([type="checkbox"]):not([type="range"])') && value !== 'back') return;
      event.preventDefault();
      event.stopImmediatePropagation();
      doc.documentElement.dataset.navigation = 'keyboard';
      if (!event.repeat || !['confirm','back'].includes(value)) action(value, 'keyboard');
    }
    function pointer() { source = 'keyboard'; device = -1; delete doc.documentElement.dataset.navigation; onDevice?.(source, device); showHints(scope()); }
    function remember(event) {
      const container = scope();
      if (container===lastScope&&container?.contains(event.target)) { remembered.set(container, event.target); showHints(container); }
    }
    function tick(now) {
      let pads = [];
      try { pads = root.navigator.getGamepads?.() || []; } catch { /* Gamepad access is optional. */ }
      const available=Array.from(pads).filter(pad=>pad?.connected!==false&&pad?.mapping==='standard');
      const discovered=available.find(pad=>!detectedPads.has(pad.index));
      detectedPads=new Set(available.map(pad=>pad.index));
      if(discovered) {source='gamepad';device=discovered.index;doc.documentElement.dataset.navigation=source;onDevice?.(source,device);showHints(scope());}
      else if(source==='gamepad'&&!detectedPads.has(device)){source='keyboard';device=-1;doc.documentElement.dataset.navigation=source;onDevice?.(source,device);showHints(scope());}
      if (!doc.hidden && doc.hasFocus()) {
        const container = scope();
        if (container !== lastScope || (container && (!container.contains(doc.activeElement) || !visible(doc.activeElement)))) ensure(container);
        const actions = read(pads, now, true);
        for (const entry of actions) {
          if (scope() !== container) break;
          action(entry.action, 'gamepad', entry.device);
        }
      } else { read(pads, now, true); read.cancel(); }
      frame = root.requestAnimationFrame(tick);
    }
    doc.addEventListener('keydown', keydown, true);
    doc.addEventListener('pointerdown', pointer, true);
    doc.addEventListener('focusin', remember, true);
    frame = root.requestAnimationFrame(tick);
    return {destroy() { root.cancelAnimationFrame(frame); hints.remove(); doc.removeEventListener('keydown', keydown, true); doc.removeEventListener('pointerdown', pointer, true); doc.removeEventListener('focusin', remember, true); }};
  }

  root.GnomMenuNavigation = {create, createPadReader};
  if (typeof module !== 'undefined') module.exports = root.GnomMenuNavigation;
})(typeof window !== 'undefined' ? window : globalThis);
