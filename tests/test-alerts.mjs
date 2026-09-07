import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const alerts = vm.createContext({});
vm.runInContext(readFileSync(new URL('../Alerts.js', import.meta.url), 'utf8'), alerts);
const agent = state => ({ pane_id: 'p1', terminal_id: 't1', agent_status: state });
const events = (before, after) => Array.from(alerts.events(before, after));

test('alerts on completion and new input requests', () => {
  for (const status of ['idle', 'done', 'blocked']) assert.equal(events([agent('working')], [agent(status)]).length, 1);
  assert.equal(events([agent('idle')], [agent('blocked')]).length, 1);
});
test('no startup, repeated idle/blocked, working, or replacement alerts', () => {
  assert.equal(events([], [agent('done')]).length, 0);
  for (const status of ['idle', 'done', 'blocked']) assert.equal(events([agent(status)], [agent(status)]).length, 0);
  assert.equal(events([agent('idle')], [agent('working')]).length, 0);
  assert.equal(events([agent('working')], [{ ...agent('done'), terminal_id: 'replacement' }]).length, 0);
});
