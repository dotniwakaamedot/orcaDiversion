const {readFileSync} = require('node:fs');
const assert = require('node:assert/strict');
const {test} = require('node:test');

const yaml = readFileSync('adapters/github/close-integrated-sub-issue.yml', 'utf8').replace(/\r\n/g, '\n');
const marker = '          script: |\n';
assert.ok(yaml.includes(marker));
const script = yaml.split(marker)[1].split('\n').map(line => line.replace(/^            /, '')).join('\n');
const run = new (Object.getPrototypeOf(async function(){}).constructor)('context', 'github', 'core', script);

async function scenario({branch = 'integration/issue-12', body = 'Sub-issue: #34', parent = 12, parentRepo = 'https://api.github.com/repos/acme/repo', state = 'open', pullRequest = false} = {}) {
  const updates = [];
  const context = {repo: {owner: 'acme', repo: 'repo'}, payload: {pull_request: {base: {ref: branch}, body, number: 56}}};
  const github = {rest: {issues: {
    get: async () => ({data: {state, ...(pullRequest ? {pull_request: {}} : {})}}),
    update: async value => updates.push(value),
  }}, request: async () => ({data: {number: parent, repository_url: parentRepo}})};
  await run(context, github, {info() {}});
  return updates;
}

test('closes only the identified sub-issue after matching its parent', async () => {
  const updates = await scenario();
  assert.equal(updates.length, 1);
  assert.equal(updates[0].issue_number, 34);
  assert.equal(updates[0].state_reason, 'completed');
});
test('rejects ambiguous or unsafe issue references', async () => {
  for (const value of [
    {branch: 'integration/issue-12-extra'}, {body: ''},
    {body: 'Sub-issue: #34\nSub-issue: #35'}, {body: 'Sub-issue: #12'},
    {parent: 13}, {parentRepo: 'https://api.github.com/repos/other/repo'}, {pullRequest: true},
  ]) await assert.rejects(scenario(value));
});
test('does not update an already closed issue', async () => {
  assert.deepEqual(await scenario({state: 'closed'}), []);
});
test('workflow triggers only for merged integration PRs', () => {
  assert.match(yaml, /types: \[closed\]/);
  assert.match(yaml, /branches:\s*\n\s*- 'integration\/issue-\*'/);
  assert.match(yaml, /if: github\.event\.pull_request\.merged == true/);
});
