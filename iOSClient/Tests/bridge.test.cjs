// Exercise the actual iOS bridge and the copied Android entry flow without real credentials.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = join(__dirname, '..');
const bridge = readFileSync(join(root, 'Resources/bridge.js'), 'utf8');
const entry = readFileSync(join(root, 'Resources/game-start.js'), 'utf8');

function fixture({ role = '7', main = true, select = false } = {}) {
  let now = 0;
  const messages = [], timers = new Map();
  let serial = 0;
  const context = vm.createContext({
    setInterval(fn, delay) { timers.set(++serial, { fn, delay }); return serial; },
    clearInterval(id) { timers.delete(id); }, setTimeout() {}, clearTimeout() {},
    Date: { now: () => now },
    document: { querySelector: () => null, getElementById: () => null },
    webkit: { messageHandlers: { iosSlot: { postMessage: message => messages.push(message) } } },
    EntityManager: { ins: () => ({ getMainRole: () => main ? {} : null }) },
    RoleMgr: { ins: () => ({ lastRoleID: role, sendEnterGame: id => { context.sentRole = id; } }) },
    ViewManager: { ins: () => ({ getView: () => select ? {} : null }) }
  });
  context.window = context;
  vm.runInContext(bridge.replace('__IOS_SESSION_TOKEN__', JSON.stringify('session-test')), context);
  vm.runInContext(entry.replace('__CDK_SERVER__', JSON.stringify('9688'))
    .replace('__CDK_ROLE__', JSON.stringify(role)), context);
  return { context, messages, tick(delay, time) {
    now = time ?? now;
    for (const timer of [...timers.values()]) if (timer.delay === delay) timer.fn();
  }, timers };
}

const entered = fixture();
entered.tick(800);
assert.equal(entered.messages[0].method, 'entered');
assert.equal(entered.messages[0].token, 'session-test');
assert.equal([...entered.timers.values()].filter(t => t.delay === 800).length, 0);
entered.context.CdkBridge.restartGame();
assert.equal(entered.messages.at(-1).method, 'restartGame');
entered.context.__iosHelperInjected = true;
entered.context.__hangjiModules = { status: () => ({ status: 'current' }) };
entered.tick(5000);
assert.equal(entered.messages.at(-1).detail, 'current');
const messageCount = entered.messages.length;
entered.tick(5000);
assert.equal(entered.messages.length, messageCount, 'unchanged status should not flood native bridge');

const noRole = fixture({ role: '', main: false, select: true });
noRole.tick(800);
assert.equal(noRole.messages[0].method, 'needRole');

const chooseRole = fixture({ role: '8', main: false, select: true });
chooseRole.tick(800);
assert.equal(chooseRole.context.sentRole, '8');

const timeout = fixture({ main: false });
timeout.tick(800, 181000);
assert.equal(timeout.messages[0].method, 'fail');

const six = Array.from({ length: 6 }, () => fixture());
six.forEach(f => f.tick(800));
assert(six.every(f => f.messages.length === 1 && f.messages[0].method === 'entered'));
assert(six.every(f => f.context.__cdkStartLoop === false));
console.log('PASS: entry, role selection, timeout, restart bridge, module health, six independent JS contexts');
