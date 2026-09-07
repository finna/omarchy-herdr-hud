import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const roster = vm.createContext({});
vm.runInContext(readFileSync(new URL('../Roster.js', import.meta.url), 'utf8'), roster);
const agents = [
  { pane_id: 'read', agent_status: 'idle' },
  { pane_id: 'busy', agent_status: 'working' },
  { pane_id: 'unread', agent_status: 'done' },
  { pane_id: 'blocked', agent_status: 'blocked' },
  { pane_id: 'idle', agent_status: 'idle' },
];
const order = unread => Array.from(roster.sorted(agents, unread), a => a.pane_id);

test('attention first, then working, then read; stable within groups', () => {
  assert.deepEqual(order({ unread: true, busy: true }), ['unread', 'blocked', 'busy', 'read', 'idle']);
  assert.equal(agents[0].pane_id, 'read');
});

test('reading a reply moves it down; blocked agents still need attention', () => {
  assert.deepEqual(order({}), ['blocked', 'busy', 'read', 'unread', 'idle']);
});
