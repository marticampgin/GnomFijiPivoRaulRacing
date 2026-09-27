(function (root) {
  'use strict';

  // Edges and repeats are per device, so a held button cannot confirm a new screen.
  function createPadReader() {
    const previous = new Map();
    return function read(pads, now, detailed = false) {
      const actions = [];
      const connected = new Set();
      for (const pad of pads || []) {
        if (!pad || pad.connected === false || pad.mapping !== 'standard') continue;
        connected.add(pad.index);
        const emit = action => actions.push(detailed ? {action, device:pad.index} : action);
        const pressed = index => Boolean(pad.buttons[index]?.pressed);
        const x = Number(pad.axes[0]) || 0, y = Number(pad.axes[1]) || 0;
        const direction = pressed(12) ? 'up' : pressed(13) ? 'down' : pressed(14) ? 'left' : pressed(15) ? 'right'
          : Math.max(Math.abs(x), Math.abs(y)) < 0.55 ? null
          : Math.abs(x) > Math.abs(y) ? x < 0 ? 'left' : 'right' : y < 0 ? 'up' : 'down';
        const current = {confirm:pressed(0), back:pressed(1), menu:pressed(9), direction};
        const old = previous.get(pad.index);
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
    };
  }

  function create({scope, onMenu, onBack, allowMenu = () => true} = {}) {
    const doc = root.document, read = createPadReader();
    let frame = 0, lastScope = null;
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
    function choices(container) { return Array.from(container.querySelectorAll(selector)).filter(visible); }
    function focus(node) {
      node?.focus({preventScroll:true});
      node?.scrollIntoView({block:'nearest', inline:'nearest'});
    }
    function ensure(container) {
      if (!container) { lastScope = null; return []; }
      const nodes = choices(container);
      if (container !== lastScope || !nodes.includes(doc.activeElement)) focus(nodes.find(node => node.hasAttribute('data-menu-default')) || nodes[0]);
      lastScope = container;
      return nodes;
    }
    function adjust(node, amount) {
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
    function back(container) {
      if (onBack?.(container)) return;
      if (container.tagName === 'DIALOG') {
        const event = new Event('cancel', {cancelable:true});
        if (container.dispatchEvent(event)) container.close();
      }
    }
    function action(value, source, device = -1) {
      if (value === 'menu' && !allowMenu()) return;
      const container = scope();
      if (!container) { if (value === 'menu') onMenu?.(); return; }
      const nodes = ensure(container), active = doc.activeElement;
      if (source === 'gamepad') doc.documentElement.dataset.navigation = 'gamepad';
      if (value === 'back' || value === 'menu') { back(container); return; }
      if (value === 'confirm') {
        if (active?.hasAttribute('data-menu-device') && Number(active.dataset.menuDevice) !== device) return;
        // Native select popups do not receive Gamepad API input. Cycle without opening one.
        if (active?.tagName === 'SELECT') adjust(active, 1);
        else active?.click();
        return;
      }
      if (!nodes.length) return;
      if (['left','right'].includes(value) && adjust(active, value === 'left' ? -1 : 1)) return;
      const offset = ['up','left'].includes(value) ? -1 : 1;
      focus(nodes[(nodes.indexOf(active) + offset + nodes.length) % nodes.length]);
    }
    function keydown(event) {
      if (!scope() || event.altKey || event.ctrlKey || event.metaKey) return;
      const keys = {ArrowUp:'up', ArrowDown:'down', ArrowLeft:'left', ArrowRight:'right', Enter:'confirm', Escape:'back'};
      const value = keys[event.key];
      if (!value) return;
      if (event.target.matches('textarea, input:not([type="radio"]):not([type="checkbox"]):not([type="range"])') && value !== 'back') return;
      event.preventDefault();
      event.stopImmediatePropagation();
      doc.documentElement.dataset.navigation = 'keyboard';
      if (!event.repeat || !['confirm','back'].includes(value)) action(value, 'keyboard');
    }
    function pointer() { delete doc.documentElement.dataset.navigation; }
    function tick(now) {
      let pads = [];
      try { pads = root.navigator.getGamepads?.() || []; } catch { /* Gamepad access is optional. */ }
      const actions = read(pads, now, true);
      if (!doc.hidden && doc.hasFocus()) {
        const container = scope();
        if (container !== lastScope || (container && !visible(doc.activeElement))) ensure(container);
        if (actions.length) action(actions[0].action, 'gamepad', actions[0].device);
      }
      frame = root.requestAnimationFrame(tick);
    }
    doc.addEventListener('keydown', keydown, true);
    doc.addEventListener('pointerdown', pointer, true);
    frame = root.requestAnimationFrame(tick);
    return {destroy() { root.cancelAnimationFrame(frame); doc.removeEventListener('keydown', keydown, true); doc.removeEventListener('pointerdown', pointer, true); }};
  }

  root.GnomMenuNavigation = {create, createPadReader};
  if (typeof module !== 'undefined') module.exports = root.GnomMenuNavigation;
})(typeof window !== 'undefined' ? window : globalThis);
