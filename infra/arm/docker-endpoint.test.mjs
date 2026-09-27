import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertLocalDockerEndpoint } from './docker-endpoint.mjs';

const local = { Endpoints: { docker: { Host: 'unix:///var/run/docker.sock' } } };
const remote = { Endpoints: { docker: { Host: 'ssh://user@remote-arm' } } };

test('the selected default context must use a local Unix socket', () => {
  assert.equal(assertLocalDockerEndpoint(local, {}), 'unix:///var/run/docker.sock');
  assert.throws(() => assertLocalDockerEndpoint(remote, {}), /local Docker Unix socket/);
});

test('DOCKER_HOST overrides the default context when no explicit context is set', () => {
  assert.equal(assertLocalDockerEndpoint(remote, { DOCKER_HOST: 'unix:///run/user/1000/docker.sock' }), 'unix:///run/user/1000/docker.sock');
  assert.throws(() => assertLocalDockerEndpoint(local, { DOCKER_HOST: 'tcp://remote-arm:2376' }), /local Docker Unix socket/);
});

test('an explicit remote DOCKER_CONTEXT cannot be hidden by a local DOCKER_HOST', () => {
  assert.throws(() => assertLocalDockerEndpoint(remote, {
    DOCKER_CONTEXT: 'remote-arm', DOCKER_HOST: 'unix:///var/run/docker.sock',
  }), /local Docker Unix socket/);
});

test('an explicit local DOCKER_CONTEXT ignores a stale remote DOCKER_HOST', () => {
  assert.equal(assertLocalDockerEndpoint(local, {
    DOCKER_CONTEXT: 'local-arm', DOCKER_HOST: 'tcp://remote-arm:2376',
  }), 'unix:///var/run/docker.sock');
});

test('a missing selected context endpoint fails closed even with a local DOCKER_HOST', () => {
  assert.throws(() => assertLocalDockerEndpoint({}, {
    DOCKER_CONTEXT: 'remote-arm', DOCKER_HOST: 'unix:///var/run/docker.sock',
  }), /local Docker Unix socket/);
});
