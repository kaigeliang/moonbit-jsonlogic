#!/usr/bin/env node
// Execute the pinned, unmodified upstream implementation as the oracle.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const logic = require('../third_party/json-logic-js/logic.js');
const official = JSON.parse(fs.readFileSync(path.join(root, 'third_party/json-logic-js/tests.json'))).filter(Array.isArray);
const edges = JSON.parse(fs.readFileSync(path.join(root, 'tests/edge_cases.json')));
const cases = official.map(([rule, data, expected], i) => {
  const value = logic.apply(rule, data);
  assert.deepStrictEqual(value, expected, `upstream fixture ${i}`);
  return {id: `official/${String(i).padStart(3, '0')}`, value};
});
for (const {id, rule, data} of edges) {
  const value = logic.apply(rule, data);
  assert.notEqual(value, undefined, `${id}: non-JSON reference result`);
  cases.push({id, value});
}
cases.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
process.stdout.write(JSON.stringify({casekit: 1, suite: 'jsonlogic-2.0.5', cases}) + '\n');
