import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const alerts = vm.createContext({});
vm.runInContext(readFileSync(new URL('../Alerts.js', import.meta.url), 'utf8'), alerts);
const agent = state => ({ pane_id: 'p1', terminal_id: 't1', agent_status: state });
const events = (before, after) => Array.from(alerts.events(before, after));

test('disabling alerts clears popups, preserves unread counts, and blocks new alerts', () => {
  const source = readFileSync(new URL('../HerdrHud.qml', import.meta.url), 'utf8');
  const context = vm.createContext({
    alertsEnabled: true, alertQueue: [agent('done')], activeAlert: agent('done'),
    alertHovered: true, opened: false, overlayVisible: true, unread: { p1: true },
    saves: 0, saveState() { context.saves++; },
  });
  for (const name of ['toggleAlerts', 'clearAlerts', 'queueAlert', 'showNextAlert']) {
    const start = source.indexOf(`  function ${name}(`);
    const end = source.indexOf('\n  }', start) + 4;
    vm.runInContext(source.slice(start, end), context);
  }
  context.toggleAlerts();
  assert.equal(context.alertsEnabled, false);
  assert.equal(context.saves, 1);
  assert.match(source, /onAlertsEnabledChanged: if \(!alertsEnabled\) clearAlerts\(\)/);
  context.clearAlerts();
  assert.equal(context.activeAlert, null);
  assert.equal(context.alertHovered, false);
  context.queueAlert(agent('done'));
  context.showNextAlert();
  assert.equal(context.alertQueue.length, 0);
  assert.equal(context.activeAlert, null);
  assert.equal(context.unread.p1, true);
  context.toggleAlerts();
  assert.equal(context.alertsEnabled, true);
  assert.equal(context.saves, 2);
  assert.match(source, /typeof parsed.alertsEnabled === "boolean"/);
  assert.match(source, /alertsEnabled: alertsEnabled/);
});

test('alerts on completion and new input requests', () => {
  for (const status of ['idle', 'done', 'blocked']) assert.equal(events([agent('working')], [agent(status)]).length, 1);
  assert.equal(events([agent('idle')], [agent('blocked')]).length, 1);
});

test('queued input requests are discarded when the agent no longer needs input', () => {
  const source = readFileSync(new URL('../HerdrHud.qml', import.meta.url), 'utf8');
  const context = vm.createContext({
    alertsEnabled: true, opened: false, overlayVisible: true,
    activeAlert: null, alertQueue: [agent('blocked')],
    agentForPane: () => agent('idle'),
  });
  const start = source.indexOf('  function showNextAlert(');
  const end = source.indexOf('\n  }', start) + 4;
  vm.runInContext(source.slice(start, end), context);
  context.showNextAlert();
  assert.equal(context.activeAlert, null);
  assert.equal(context.alertQueue.length, 0);
  assert.match(source, /running: !!root.activeAlert && !root.activeAlertNeedsInput && !root.alertHovered/);
});
test('no startup, repeated idle/blocked, working, or replacement alerts', () => {
  assert.equal(events([], [agent('done')]).length, 0);
  for (const status of ['idle', 'done', 'blocked']) assert.equal(events([agent(status)], [agent(status)]).length, 0);
  assert.equal(events([agent('idle')], [agent('working')]).length, 0);
  assert.equal(events([agent('working')], [{ ...agent('done'), terminal_id: 'replacement' }]).length, 0);
});
