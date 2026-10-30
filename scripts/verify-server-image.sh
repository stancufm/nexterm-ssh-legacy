#!/bin/sh
# Run only against a locally built candidate; creates no host port or data mount.
set -eu
image=${1:?Usage: scripts/verify-server-image.sh IMAGE}
command -v docker >/dev/null 2>&1 || { echo 'Docker is required' >&2; exit 1; }
name="nexterm-node-smoke-$$"
cleanup() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then docker logs "$name" >&2 || true; fi
    docker rm -f "$name" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Test-only key and account, in a disposable container without production data.
docker run -d --name "$name" \
    -e ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
    "$image" >/dev/null
check() {
    docker exec -i "$name" node - "$1" <<'JS'
const assert = require('node:assert/strict');
const { setTimeout: delay } = require('node:timers/promises');
const base = 'http://127.0.0.1:6989';
const mode = process.argv[2];
async function request(path, body, token) {
    const response = await fetch(base + path, {
        method: body ? 'POST' : 'GET',
        headers: { ...(body ? {'Content-Type': 'application/json'} : {}),
            ...(token ? {Authorization: `Bearer ${token}`} : {}) },
        ...(body ? {body: JSON.stringify(body)} : {}),
        signal: AbortSignal.timeout(5000),
    });
    return {status: response.status, body: await response.json()};
}
(async () => {
    assert.equal(process.version, 'v26.13.0');
    let ready = false;
    for (let i = 0; i < 60; i++) {
        try {
            const response = await request('/api/service/version');
            if (response.status === 200 && typeof response.body.version === 'string') { ready = true; break; }
        } catch {}
        await delay(1000);
    }
    assert(ready, 'Server did not become ready');
    assert.equal((await fetch(base + '/')).status, 200, 'Frontend must be served');
    const credentials = {username: 'nodesmoke', password: 'DisposableSmokePassword42!'};
    if (mode === 'setup') {
        assert.equal((await request('/api/service/is-fts')).body, true);
        const registration = await request('/api/accounts/register', {
            ...credentials, firstName: 'Node', lastName: 'Smoke',
        });
        assert.equal(registration.status, 200);
        assert.equal(registration.body.code, undefined);
    }
    assert.equal((await request('/api/service/is-fts')).body, false);
    const rejected = await request('/api/auth/login', {...credentials, password: 'incorrect'});
    assert.equal(rejected.body.code, 201);
    assert.equal(rejected.body.token, undefined);
    const login = await request('/api/auth/login', credentials);
    assert.equal(login.status, 200);
    assert.match(login.body.token, /^[a-f0-9]{96}$/i);
    const me = await request('/api/accounts/me', undefined, login.body.token);
    assert.equal(me.status, 200);
    assert.equal(me.body.username, credentials.username);
    assert.equal(me.body.isAdmin, true);
    assert.equal((await request('/api/accounts/me', undefined, 'invalid')).status, 401);
    await request('/api/auth/logout', {token: login.body.token});
    assert.equal((await request('/api/accounts/me', undefined, login.body.token)).status, 401);
    console.log(`PASS ${mode}: startup, frontend, SQLite, bcrypt, login, authorization, logout`);
})().catch(error => {console.error(error); process.exitCode = 1;});
JS
}
check setup
docker restart "$name" >/dev/null
check restart
