# Analiza Node.js și Docker — 30 octombrie 2026

Repository: stancufm/nexterm-ssh-legacy, ramura nsg/legacy-crypto.
Commit analizat: 63bc1ce89f4781872194f88e2badf806e11337cd.
Patch local propus; nu a fost publicat sau aplicat unui deployment.

## Ce s-a verificat efectiv

| Componentă originală | Rezultat verificat | Limită |
|---|---|---|
| `node:26-alpine`, toate etapele builder | Registrul Docker a returnat indexul `sha256:c6ad9e9c1d80f6eb607c26b4b0a132ff7a2344fad1c78ea3baa2a7d4c8de6d94`; configurația linux/amd64 declară `NODE_VERSION=26.13.0` | Nu stabilește versiunea folosită într-un build anterior cu cache sau alt digest |
| Runtime `alpine:3.22` + `apk add nodejs` | APKINDEX live v3.22/main/x86_64 oferă `nodejs=22.23.4-r0` | Nu am executat APK și nu am inspectat o imagine deja construită; alte arhitecturi/build-uri istorice trebuie inspectate separat |
| Baza propusă `node:26.13.0-alpine3.24` | Tagul explicit are același digest ca `26-alpine` la momentul verificării | Build-ul containerului rămâne de executat |

Așadar, pentru o reconstrucție curentă linux/amd64, sursele indică Node 26.13.0 la build și 22.23.4 la runtime. Nu există dovada unei erori ABI într-un container existent. Versiunile efectiv executate se confirmă cu comenzile de mai jos și cu logurile serverului, care deja afișează `process.version`.

## ABI și module native

`yarn.lock` fixează bcrypt 6.0.0 și sqlite3 6.0.1. Ambele folosesc Node-API, nu exclusiv ABI-ul V8 specific fiecărei versiuni majore. Bcrypt folosește node-addon-api/node-gyp-build și distribuie prebuild-uri musl; sqlite3 declară Node-API v3/v6 și suport linuxmusl x64/arm64. Diferența 26/22 nu demonstrează automat incompatibilitate.

Rămân riscuri la alegerea prebuild-ului, arhitectură, musl, libstdc++, alte biblioteci dinamice și compilarea fallback prin node-gyp. Instrumentele esbuild sunt și ele specifice platformei, dar sunt folosite la build. Lockfile-ul serverului nu conține în prezent sharp; ștergerile existente pentru sharp au fost păstrate pentru a evita extinderea scopului.

Patch-ul folosește aceeași bază imuabilă pentru toate etapele, pe arhitectura țintă. Runtime-ul moștenește bibliotecile Node din imaginea oficială; nu copiem doar executabilul Node între distribuții. Testul RUN din imaginea finală încarcă modulele copiate, verifică hash/compare bcrypt și execută SQL în memorie. O problemă de încărcare sau execuție oprește build-ul.

## Securitate și reproductibilitate

Node 26.13.0 este LTS și include modificările din release-ul de securitate 26.12.1 din 21 octombrie; anunțul 26.13.0 precizează că restul diferențelor sunt metadata LTS. Node 22.23.4 este de asemenea un release de securitate: configurația originală nu demonstrează singură că runtime-ul curent este vulnerabil. Containerele construite anterior trebuie inventariate și reconstruite.

Fixarea versiunii și digestului asigură baza și Node reproductibile, iar `--frozen-lockfile` împiedică rezolvarea liberă a dependențelor serverului. Yarn este fixat la 1.22.22, esbuild la versiunea 0.28.1 deja prezentă în lockfile. Retry-urile eșuate se termină acum cu exit 1.

Acesta NU este un build complet identic bit cu bit: pachetele APK pentru compilatoare/flatc, dependențele tranzitive ale uneltelor globale, descărcările prebuild și metadata/timestamp-urile pot varia. Pentru acest nivel ar fi necesare snapshot-uri/mirror-uri și verificarea tuturor inputurilor. Digestul trebuie actualizat intenționat pentru patch-uri de securitate; pinning-ul nu înlocuiește actualizările și scanarea imaginii.

SQLite folosit de addon poate fi inclus în addon și diferă de SQLite integrat în Node sau de pachetul Alpine. Actualizarea Node nu garantează remedierea vulnerabilităților addon-ului sau ale întregului arbore npm. Scanarea CVE/SBOM nu a fost executată în acest mediu.

## Verificări automate

Într-un checkout al commitului analizat cu patch-ul aplicat și Docker funcțional:

```sh
docker build --pull --no-cache --progress=plain -f Dockerfile.server -t nexterm-server:node26-check .
sh scripts/verify-server-image.sh nexterm-server:node26-check
docker run --rm nexterm-server:node26-check node -p 'JSON.stringify({node:process.version,abi:process.versions.modules,napi:process.versions.napi,arch:process.arch,openssl:process.versions.openssl})'
docker run --rm nexterm-server:node26-check ntctl --help
```

Scriptul creează exclusiv un container temporar, fără porturi publicate și fără volume de producție. Verifică frontend-ul, inițializarea bazei și migrațiile prin startup, înregistrarea unui cont temporar, refuzul parolei greșite, login, accesul protejat, refuzul tokenului invalid și logout. După restart, repetă login-ul pentru a verifica persistența SQLite. Șterge containerul la final. Nu execută teste SSH și nu verifică furnizori externi de identitate.

Pentru inventarierea unui container existent, fără modificare:

```sh
docker exec CONTAINER node -p 'JSON.stringify({node:process.version,abi:process.versions.modules,napi:process.versions.napi,arch:process.arch,openssl:process.versions.openssl})'
docker exec CONTAINER sh -c 'cat /etc/alpine-release; apk info -v nodejs || true'
docker exec CONTAINER node -e 'require("bcrypt"); require("sqlite3"); console.log("native modules loaded")'
```

`apk info nodejs` poate lipsi în imaginea propusă: Node provine din imaginea oficială, nu dintr-un pachet APK. Pentru build multi-platform executați build-ul și scriptul pe fiecare arhitectură folosită, de exemplu linux/amd64 și linux/arm64. Nu copiați node_modules de pe host sau între arhitecturi.

## SSH legacy și autentificare: validare de integrare înainte de deployment

Nu s-au modificat engine-ul, libssh2, lista algoritmilor, `enableLegacyCrypto`, transmiterea `legacyCrypto=true`, conturile, hash-urile, MFA, LDAP, OIDC sau passkeys. `docker-start.sh`, comanda CMD și comportamentul entrypoint-ului sunt păstrate.

Totuși, `Dockerfile.engine` folosește Alpine 3.22, iar Dockerfile-ul agregat copiază binare și biblioteci din acel engine în baza serverului. Trecerea runtime-ului serverului la Alpine 3.24 cere un test al imaginii agregate, nu doar al serverului. Nu există în acest mediu dovadă că această integrare este validată. Nu extindem patch-ul la engine fără rezultate concrete.

În staging, cu o copie restaurabilă a datelor și aceeași cheie de criptare ca sursa datelor:

1. Construiți imaginea engine din același commit și imaginea agregată folosind `SERVER_IMAGE=nexterm-server:node26-check` și engine-ul candidat. Folosiți taguri/digesturi exacte pentru ambele, nu latest.
2. Porniți imaginea agregată cu configurația de staging existentă. Verificați încărcarea engine-ului și bibliotecilor, înregistrarea control-plane și absența erorilor `Error loading shared library`, `NODE_MODULE_VERSION`, simboluri lipsă sau crash-uri.
3. Testați SSH modern cu parolă și cheie; apoi un echipament legacy cunoscut cu opțiunea legacy activată. Executați o comandă, un task remote și un transfer SFTP. Verificați că opțiunea dezactivată nu activează suplimentar algoritmi legacy.
4. Testați contul local existent și parola greșită, TOTP corect/greșit dacă este configurat, logout și expirarea/revocarea sesiunii. Testați LDAP/OIDC/passkey/API keys dacă sunt utilizate. Confirmați decriptarea identităților SSH existente.
5. Reporniți containerul, verificați datele și reconectarea engine-ului. Scanați imaginea finală cu instrumentul CVE/SBOM existent, inclusiv bibliotecile engine-ului copiate.
6. Păstrați digestul imaginii precedente și backup-ul datelor pentru rollback. Nu testați candidații direct pe datele active ale producției.

## Rezultatele verificărilor în acest mediu

Trecute: `git diff --check`, sintaxa shell a tuturor RUN-urilor, sintaxa JavaScript a verificărilor inline și a scriptului, sintaxa shell a scriptului, teste simulate pentru ambele bucle de retry (succes în încercările 1/2/3 și eșec final), verificarea registrului și APKINDEX.

Neexecutate: build Docker, testele native reale, startup, teste HTTP/autentificare/restart, ntctl, engine/SSH și scanarea CVE. Nu există Docker, Podman sau socket Docker disponibil. Scriptul a fost invocat și a refuzat corect execuția cu `Docker is required`. Patch-ul este pregătit pentru review și validare Docker, nu certificat pentru producție.

## Surse primare

- https://github.com/stancufm/nexterm-ssh-legacy/tree/63bc1ce89f4781872194f88e2badf806e11337cd
- https://registry-1.docker.io/v2/library/node/manifests/26.13.0-alpine3.24
- https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/APKINDEX.tar.gz
- https://nodejs.org/en/blog/release/v26.13.0
- https://nodejs.org/en/blog/vulnerability/october-2026-security-releases
- https://github.com/kelektiv/node.bcrypt.js/blob/v6.0.0/package.json
- https://github.com/TryGhost/node-sqlite3/blob/v6.0.1/package.json
- https://nodejs.org/api/n-api.html#node-api
