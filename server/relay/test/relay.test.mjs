// Essai du relais contre `npx wrangler dev` (ou une URL déployée) : node test/relay.test.mjs [ws://127.0.0.1:8787]
// Node 22 fournit WebSocket en global.
const BASE = process.argv[2] || "ws://127.0.0.1:8787";
const code = "T" + Math.random().toString(36).slice(2, 5).toUpperCase().replace(/[^A-Z]/g, "Q").padEnd(3, "Q");

function open(path) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(BASE + path);
    ws.binaryType = "arraybuffer";
    const inbox = [];
    const waiters = [];
    ws.onmessage = (ev) => {
      inbox.push(ev.data);
      while (waiters.length) waiters.shift()();
    };
    ws.next = async (ms = 3000) => {
      const t0 = Date.now();
      while (inbox.length === 0) {
        if (Date.now() - t0 > ms) throw new Error("rien reçu sur " + path);
        await new Promise((r) => { waiters.push(r); setTimeout(r, 50); });
      }
      return inbox.shift();
    };
    ws.closed = new Promise((r) => (ws.onclose = (ev) => r(ev.code)));
    ws.onopen = () => resolve(ws);
    ws.onerror = (e) => reject(e);
  });
}

function ok(cond, msg) {
  if (!cond) {
    console.error("ÉCHEC : " + msg);
    process.exit(1);
  }
  console.log("ok  " + msg);
}

const host = await open(`/room/${code}?role=host`);
let m = JSON.parse(await host.next());
ok(m.t === "hello" && m.role === "host" && m.code === code && m.peer === false, "l'hôte crée la salle " + code);

const nobody = await open(`/room/ZZZZ?role=guest`);
m = JSON.parse(await nobody.next());
ok(m.t === "err" && m.why === "no_room", "rejoindre une salle inexistante est refusé");

const dup = await open(`/room/${code}?role=host`);
m = JSON.parse(await dup.next());
ok(m.t === "err" && m.why === "occupied", "un deuxième hôte sur le même code est refusé");

const guest = await open(`/room/${code.toLowerCase()}?role=guest`);
m = JSON.parse(await guest.next());
ok(m.t === "hello" && m.role === "guest" && m.peer === true, "l'invité rejoint (code en minuscules accepté)");
m = JSON.parse(await host.next());
ok(m.t === "peer" && m.on === true, "l'hôte est prévenu de l'arrivée de l'invité");

const third = await open(`/room/${code}?role=guest`);
m = JSON.parse(await third.next());
ok(m.t === "err" && m.why === "full", "un troisième joueur est refusé");

host.send(new Uint8Array([1, 2, 3, 250]));
let b = new Uint8Array(await guest.next());
ok(b.length === 4 && b[3] === 250, "binaire relayé hôte -> invité");
guest.send(new Uint8Array(1500).fill(7));
b = new Uint8Array(await host.next());
ok(b.length === 1500 && b[1499] === 7, "binaire relayé invité -> hôte (1500 octets)");

host.send("ping");
ok((await host.next()) === "pong", "ping -> pong");

// débit : 200 messages de 600 octets
const t0 = Date.now();
for (let i = 0; i < 200; i++) host.send(new Uint8Array(600).fill(i & 255));
for (let i = 0; i < 200; i++) await guest.next();
ok(true, `200 messages relayés en ${Date.now() - t0} ms`);

guest.close();
m = JSON.parse(await host.next());
ok(m.t === "peer" && m.on === false, "l'hôte est prévenu du départ de l'invité");

const guest2 = await open(`/room/${code}?role=guest`);
m = JSON.parse(await guest2.next());
ok(m.t === "hello", "un invité peut revenir dans la salle");
await host.next(); // peer on
host.close();
m = JSON.parse(await guest2.next());
ok(m.t === "peer" && m.on === false, "l'invité est prévenu du départ de l'hôte");
const cc = await guest2.closed;
ok(cc === 4000, "la salle ferme quand l'hôte part (code " + cc + ")");

const again = await open(`/room/${code}?role=host`);
m = JSON.parse(await again.next());
ok(m.t === "hello", "la salle vide est libérée : le code est réutilisable");
again.close();
console.log("TOUS LES ESSAIS PASSENT");
process.exit(0);
