'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/control-settings.js'), 'utf8'), context);
const {defaultProfile, normalize} = context.GnomControlSettings;
const plain = value => JSON.parse(JSON.stringify(value));
let checks = 0;
function check(condition, message) { assert.ok(condition, message); checks += 1; }
assert.deepEqual(plain(defaultProfile()), {keyboard:'both', gamepad:'standard', deadzone:0.2, steering:1}); checks += 1;
check(defaultProfile() !== defaultProfile(), 'defaults must be independent objects');
for (const keyboard of ['both', 'wasd', 'arrows']) {
  for (const gamepad of ['standard', 'alternate']) {
    for (const deadzone of [0.05, 0.2, 0.35]) {
      for (const steering of [0.5, 1, 1.5]) {
        const value = {keyboard, gamepad, deadzone, steering};
        assert.deepEqual(plain(normalize(value)), value); checks += 1;
      }
    }
  }
}
for (const value of [null, undefined, [], 0, true, 'profile', {}, {...defaultProfile(), extra:1}]) {
  check(normalize(value) === null, 'reject non-profile or unexpected keys');
}
for (const key of ['keyboard', 'gamepad', 'deadzone', 'steering']) {
  const missing = {...defaultProfile()}; delete missing[key];
  check(normalize(missing) === null, `reject missing ${key}`);
}
for (const [key, values] of Object.entries({keyboard:['other', null, true, 1], gamepad:['other', null, true, 1], deadzone:[0.049,0.351,NaN,Infinity,-Infinity,'0.2',true,null], steering:[0.499,1.501,NaN,Infinity,-Infinity,'1',true,null]})) {
  for (const value of values) check(normalize({...defaultProfile(), [key]:value}) === null, `reject invalid ${key}`);
}
const inherited = Object.create(defaultProfile());
check(normalize(inherited) === null, 'reject inherited fields');
const source = defaultProfile(), copy = normalize(source);
copy.steering = 1.5;
check(source.steering === 1, 'normalization copies its source');
console.log(`control settings: ${checks}/${checks} passed`);
