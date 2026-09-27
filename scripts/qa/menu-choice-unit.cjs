'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// A deliberately small DOM fixture: no renderer, browser, server or physical pad.
class FixtureEvent {
  constructor(type, options = {}) { this.type = type; Object.assign(this, options); }
  preventDefault() { this.defaultPrevented = true; }
  stopImmediatePropagation() { this.stopped = true; }
}
class FixtureNode {
  constructor(tag, doc, rect = {left:0, right:200, top:0, bottom:40}) {
    this.tagName = tag.toUpperCase(); this.doc = doc; this.children = []; this.dataset = {};
    this.attributes = new Map(); this.listeners = new Map(); this.rect = rect;
    this.tabIndex = ['BUTTON', 'SELECT', 'INPUT', 'SUMMARY', 'A'].includes(this.tagName) ? 0 : -1;
    this.textContent = ''; this.clicks = 0;
  }
  setAttribute(name, value) { this.attributes.set(name, String(value)); if (name === 'tabindex') this.tabIndex = Number(value); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  hasAttribute(name) { return this.attributes.has(name); }
  append(...nodes) { for (const node of nodes) { node.remove(); node.parentElement = this; this.children.push(node); } }
  replaceChildren(...nodes) { for (const node of [...this.children]) node.remove(); this.append(...nodes); }
  remove() { if (this.parentElement) this.parentElement.children = this.parentElement.children.filter(node => node !== this); this.parentElement = null; }
  contains(node) { return node === this || this.children.some(child => child.contains(node)); }
  querySelectorAll() {
    const descendants = this.children.flatMap(child => [child, ...child.querySelectorAll()]);
    return descendants.filter(node => ['BUTTON','SELECT','INPUT','SUMMARY','A'].includes(node.tagName) || node.getAttribute('tabindex') === '0');
  }
  matches(selector) {
    if (selector === ':disabled') return Boolean(this.disabled);
    return this.tagName === 'TEXTAREA' || (this.tagName === 'INPUT' && !['radio','checkbox','range'].includes(this.type));
  }
  closest() { return this.hidden || this.inert ? this : this.parentElement?.closest() || null; }
  getClientRects() { return [this.rect]; }
  getBoundingClientRect() { return this.rect; }
  focus() { this.doc.activeElement = this; this.doc.dispatchEvent(new FixtureEvent('focusin', {target:this})); }
  scrollIntoView() {}
  click() { this.clicks++; this.dispatchEvent(new FixtureEvent('click', {bubbles:true})); }
  addEventListener(type, callback) { const list = this.listeners.get(type) || []; list.push(callback); this.listeners.set(type, list); }
  removeEventListener(type, callback) { this.listeners.set(type, (this.listeners.get(type) || []).filter(entry => entry !== callback)); }
  dispatchEvent(event) {
    event.target ||= this;
    for (const callback of this.listeners.get(event.type) || []) { callback(event); if (event.stopped) break; }
    if (event.bubbles && !event.stopped) this.parentElement?.dispatchEvent(event);
    return !event.defaultPrevented;
  }
}
const document = new FixtureNode('document');
document.doc = document;
document.documentElement = new FixtureNode('html', document);
document.createElement = tag => new FixtureNode(tag, document);
document.createTextNode = text => Object.assign(new FixtureNode('#text', document), {textContent:text});
document.hasFocus = () => true;
let nextFrame, pads = [], now = 0;
const context = vm.createContext({
  document, Event:FixtureEvent, CustomEvent:FixtureEvent,
  navigator:{getGamepads:() => pads}, getComputedStyle:() => ({visibility:'visible', display:'block'}),
  requestAnimationFrame:callback => { nextFrame = callback; return 1; }, cancelAnimationFrame:() => { nextFrame = null; }
});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../web/menu-navigation.js'), 'utf8'), context);
const setup = new FixtureNode('dialog', document); setup.id = 'local-setup';
const choices = [0, 60].map(top => {
  const node = new FixtureNode('div', document, {left:40, right:240, top, bottom:top + 40});
  node.setAttribute('tabindex', '0'); node.setAttribute('role', 'spinbutton'); node.setAttribute('data-menu-adjust', '');
  node.setAttribute('aria-valuemin', '1'); node.setAttribute('aria-valuemax', '2'); node.setAttribute('aria-valuenow', '1');
  for (const left of [0, 260]) {
    const pointer = new FixtureNode('button', document, {left, right:left + 30, top, bottom:top + 40});
    pointer.setAttribute('tabindex', '-1'); node.append(pointer);
  }
  node.addEventListener('menu-adjust', event => {
    const value = Math.max(1, Math.min(2, Number(node.getAttribute('aria-valuenow')) + event.detail.amount));
    node.setAttribute('aria-valuenow', value);
  });
  setup.append(node); return node;
});
choices[0].setAttribute('data-menu-default', '');
const action = new FixtureNode('button', document, {left:40, right:240, top:120, bottom:160}); setup.append(action);
const ignored = new FixtureNode('button', document, {left:40, right:240, top:170, bottom:190}); ignored.tabIndex = -1; setup.append(ignored);
const disabled = new FixtureNode('button', document, {left:40, right:240, top:180, bottom:200}); disabled.disabled = true; setup.append(disabled);
const hidden = new FixtureNode('button', document, {left:40, right:240, top:200, bottom:240}); hidden.hidden = true; setup.append(hidden);
const nativeSelect = new FixtureNode('select', document, {left:40, right:240, top:260, bottom:300});
nativeSelect.options = [{value:'a', selected:true}, {value:'b', selected:false}]; nativeSelect.value = 'a'; setup.append(nativeSelect);
let current = setup, adjustments = [], back;
setup.addEventListener('menu-adjust', event => adjustments.push(event.detail.amount));
const navigation = context.GnomMenuNavigation.create({scope:() => current, onBack:(_, source, device) => { back = {source, device}; return true; }});
let checks = 0;
const check = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const tick = () => nextFrame(now += 20);
const key = name => {
  const event = new FixtureEvent('keydown', {key:name, target:document.activeElement});
  document.dispatchEvent(event); check(event.defaultPrevented, true, `${name} is consumed`);
};
const text = node => node.textContent + node.children.map(text).join('');
const hints = () => text(setup.children.find(node => node.className === 'menu-hints'));
const pad = buttons => ({index:4, connected:true, mapping:'standard', axes:[0,0], buttons:Array.from({length:16}, (_, i) => ({pressed:buttons.includes(i)}))});
tick();
check(document.activeElement, choices[0], 'first stepper receives default focus');
check(hints(), '← →ИзменитьEscНазад', 'stepper hints offer adjustment, not confirmation');
key('ArrowRight'); check(choices[0].getAttribute('aria-valuenow'), '2', 'right dispatches an increment');
key('ArrowRight'); check(choices[0].getAttribute('aria-valuenow'), '2', 'control keeps its upper boundary');
check(document.activeElement, choices[0], 'right at boundary does not leave the control');
key('ArrowLeft'); key('ArrowLeft');
check(choices[0].getAttribute('aria-valuenow'), '1', 'control keeps its lower boundary');
check(adjustments, [1,1,-1,-1], 'adjustments bubble with signed amounts');
key('Enter'); check(choices[0].clicks, 0, 'Enter must not cycle a stepper');
key('ArrowDown'); check(document.activeElement, choices[1], 'down moves between control rows');
key('ArrowUp'); check(document.activeElement, choices[0], 'up moves between control rows');
key('ArrowDown'); key('ArrowDown'); check(document.activeElement, action, 'pointer-only buttons are not additional stops');
check(hints(), 'EnterВыбратьEscНазад', 'action hint returns on buttons');
key('Enter'); check(action.clicks, 1, 'button confirmation remains active');
key('ArrowDown'); check(document.activeElement, nativeSelect, 'negative-tabindex, disabled and hidden controls are skipped');
key('ArrowRight'); check(nativeSelect.value, 'b', 'existing native select adjustment remains supported');
choices[0].focus(); check(hints(), '← →ИзменитьEscНазад', 'pointer focus updates hints immediately');
pads = [pad([0])]; tick();
check(hints(), '← →ИзменитьBНазад', 'pad discovery changes the back hint');
pads = [pad([])]; tick(); check(choices[0].clicks, 0, 'connecting with A held cannot confirm');
pads = [pad([15])]; tick(); check(choices[0].getAttribute('aria-valuenow'), '2', 'D-pad right adjusts the same control');
pads = [pad([])]; tick(); pads = [pad([0])]; tick(); pads = [pad([])]; tick();
check(choices[0].clicks, 0, 'released A cannot click or cycle a stepper');
action.focus(); pads = [pad([0])]; tick(); check(action.clicks, 1, 'A does not confirm until release');
pads = [pad([])]; tick(); check(action.clicks, 2, 'A release confirms an action');
const next = new FixtureNode('dialog', document), nextAction = new FixtureNode('button', document); next.append(nextAction);
pads = [pad([0])]; tick(); current = next; tick(); pads = [pad([])]; tick();
check(nextAction.clicks, 0, 'held confirmation cannot leak into another scope');
current = null; tick(); pads = [pad([15])]; tick();
check(document.activeElement, nextAction, 'racing without a menu does not move focus');
current = setup; pads = [pad([])]; tick();
check(document.activeElement, action, 'returning to a scope restores its prior action');
pads = [pad([1])]; tick(); pads = [pad([])]; tick();
check(back, {source:'gamepad', device:4}, 'back preserves sparse controller identity');
key('Escape'); check(back, {source:'keyboard', device:-1}, 'keyboard back remains available');
choices[0].dataset.focusKey = 'first-choice'; action.dataset.focusKey = 'start-action';
choices[0].setAttribute('data-menu-down', 'start-action');
action.setAttribute('data-menu-up', 'first-choice');
choices[0].focus(); key('ArrowDown');
check(document.activeElement, action, 'explicit same-scope direction overrides spatial proximity');
key('ArrowUp'); check(document.activeElement, choices[0], 'reverse explicit direction restores the intended control');
hidden.dataset.focusKey = 'hidden-action'; disabled.dataset.focusKey = 'disabled-action';
ignored.dataset.focusKey = 'pointer-only-action'; nextAction.dataset.focusKey = 'other-scope-action';
for (const target of ['missing-action', 'hidden-action', 'disabled-action', 'pointer-only-action', 'other-scope-action']) {
  choices[0].setAttribute('data-menu-down', target); choices[0].focus(); key('ArrowDown');
  check(document.activeElement, choices[1], `${target} falls back to an available spatial neighbor`);
}
navigation.destroy(); check(nextFrame, null, 'destroy stops the animation loop');
console.log(`menu choice unit: ${checks}/${checks} passed (no browser)`);
