#!/bin/sh
set -eu
image=${1:?image required}
net="nexterm-stage-$$"
a="${net}-app"
s="${net}-ssh"
cleanup() { rc=$?; trap - EXIT; if [ "$rc" -ne 0 ]; then docker logs "$a" 2>&1 | tail -80 || true; docker logs "$s" 2>&1 | tail -30 || true; fi; docker rm -f "$a" "$s" >/dev/null 2>&1 || true; docker network rm "$net" >/dev/null 2>&1 || true; exit "$rc"; }
trap cleanup EXIT
docker network create "$net" >/dev/null
docker run -d --name "$s" --network "$net" --network-alias legacy-target alpine:3.22 sh -ec '
  apk add --no-cache openssh >/dev/null
  adduser -D testuser
  echo testuser:StagingOnlyPassword42 | chpasswd
  ssh-keygen -A >/dev/null
  mkdir -p /run/sshd
  printf "Port 2222\nHostKey /etc/ssh/ssh_host_rsa_key\nKexAlgorithms diffie-hellman-group14-sha1\nHostKeyAlgorithms ssh-rsa\nPasswordAuthentication yes\nAllowUsers testuser\n" > /tmp/sshd_config
  exec /usr/sbin/sshd -D -e -f /tmp/sshd_config
' >/dev/null
docker run -d --name "$a" --network "$net" -e ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef "$image" >/dev/null
sleep 12
docker exec -i "$a" node - <<'JS'
const assert = require('node:assert/strict');
const {setTimeout: delay} = require('node:timers/promises');
const base = 'http://127.0.0.1:6989';
async function req(path, method='GET', body, token) {
 const r = await fetch(base+path, {method,headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(40000)});
 const t=await r.text(); let data; try{data=JSON.parse(t)}catch{data=t}; if(!r.ok) throw Error(`${path}: ${r.status} ${t.slice(0,300)}`); return data;
}
(async()=>{
 let ready=false;for(let i=0;i<90;i++){try{await req('/api/service/version');ready=true;break}catch{await delay(1000)}}assert(ready,'server unavailable');
 const account={username:'stagetest',password:'StagingOnlyPassword42!'};
 await req('/api/accounts/register','POST',{...account,firstName:'Stage',lastName:'Test'});
 const {token}=await req('/api/auth/login','POST',account);assert(token,'missing token');
 let engines=[]; for(let i=0;i<60;i++){engines=await req('/api/engines','GET',undefined,token);if(engines.some(e=>e.isLocal&&e.connected))break;await delay(1000)}
 const engine=engines.find(e=>e.isLocal&&e.connected);assert(engine,'local engine is not connected');assert.equal(engine.version,'1.2.2-nsg.17');console.log('PASS staging controller connected to engine',engine.version);
 const ident=await req('/api/identities','PUT',{name:'test',username:'testuser',type:'password',password:'StagingOnlyPassword42'},token);assert(ident.id,'missing identity id');
 async function addEntry(enabled){let r=await req('/api/entries','PUT',{name:enabled?'legacy-on':'legacy-off',type:'server',identities:[ident.id],config:{protocol:'ssh',ip:'legacy-target',port:2222,enableLegacyCrypto:enabled}},token);assert(r.id,'missing entry id');return r.id;}
 await delay(10000);
 const off=await addEntry(false);const denied=await req(`/api/connections/${off}/exec?identityId=${ident.id}`,'POST',{command:'printf STAGING_SUCCESS'},token);console.log('Legacy test target with opt-in disabled: success='+Boolean(denied.success));
 const on=await addEntry(true);const result=await req(`/api/connections/${on}/exec?identityId=${ident.id}`,'POST',{command:'printf STAGING_SUCCESS'},token);assert(result.success,JSON.stringify(result));assert.equal(result.stdout,'STAGING_SUCCESS');console.log('PASS legacy SSH command succeeded with opt-in');
})().catch(e=>{console.error(e);process.exit(1)});
JS
