const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

function load(file, stubs, exportSuffix = '') {
  const mod = { exports: {} };
  const source = fs.readFileSync(path.join(__dirname, '..', file), 'utf8');
  vm.runInNewContext(source + exportSuffix, {
    module: mod, exports: mod.exports, require: (id) => {
      if (Object.hasOwn(stubs, id)) return stubs[id];
      return {};
    }, setInterval: () => {}, setTimeout, clearTimeout, console, Date, Promise,
  }, { filename: file });
  return mod.exports;
}

test('status checks route by configured engine and isolate failures with bounded concurrency', async () => {
  const calls = []; let active = 0, max = 0;
  const cp = { hasEngine: () => true, portCheck: async (targets, timeout, engine) => {
    calls.push({targets, timeout, engine}); active++; max = Math.max(max, active);
    await new Promise(resolve => setTimeout(resolve, 5)); active--;
    if (engine === 3) throw new Error('engine disconnected');
    return {entries:[{id: targets[0].id, online: engine !== 2}]};
  }};
  const { checkServerStatusBatch } = load('server/hooks/status/portHook.js', {'../../lib/controlPlane/ControlPlaneServer': cp});
  const entries = Array.from({length: 22}, (_, i) => ({id:i+1, config:{ip:'test',port:22,engineId:i === 0 ? 3 : i % 2 ? 2 : 1}}));
  entries.push({id:99,config:{}});
  const result = await checkServerStatusBatch(entries, 30000);
  assert.equal(calls.length, 22); assert.equal(max, 10);
  assert.ok(calls.every(c => c.targets.length === 1 && c.timeout === 25000));
  assert.equal(calls[0].engine, 3);
  assert.equal(result.find(x => x.id === 2).status, 'offline');
  assert.equal(result.find(x => x.id === 3).status, 'online');
  assert.equal(result.find(x => x.id === 99).status, 'offline');
  assert.equal(result.some(x => x.id === 1), false);
});

test('SSH monitoring uses configured engine for the batch', async () => {
  let args;
  const cp = {hasEngine: () => true, execCommandBatch: async (...a) => {args=a;return {success:true,results:[]}}};
  const service = load('server/utils/monitoringService.js', {
    '../lib/controlPlane/ControlPlaneServer':cp,
    '../lib/ConnectionService':{buildSSHParams:()=>({}),resolveJumpHosts:async()=>[]},
    './logger':{error:()=>{}},
    sequelize:{Op:{lt:Symbol('lt')}},
  }, '\nmodule.exports.collectServerData = collectServerData;');
  await service.collectServerData({config:{ip:'192.0.2.1',port:22,engineId:3}}, {}, {});
  assert.equal(args[5], 3);
});
