// Relais du mode duo de Passeurs.
// Le Worker route /room/ABCD vers le Durable Object de la salle ABCD. La salle accepte un hôte et un invité,
// et relaie tel quel chaque message binaire de l'un vers l'autre. Le serveur ne comprend rien au jeu.
//
// Protocole (WebSocket) :
//   GET /room/ABCD?role=host   crée la salle (refusée si un hôte l'occupe déjà)
//   GET /room/ABCD?role=guest  rejoint la salle (refusée si elle n'existe pas ou est pleine)
//   messages texte du serveur (JSON) : {"t":"hello","role","code","peer"} {"t":"peer","on"} {"t":"err","why"}
//   message texte "ping" du client : le serveur répond "pong" sans se réveiller (auto-réponse)
//   messages binaires : relayés à l'autre joueur
import { DurableObject } from "cloudflare:workers";

const IDLE_MS = 90_000; // une connexion muette plus longtemps est fermée
const ALARM_MS = 30_000; // ménage périodique tant que la salle a des connexions

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === "/health") {
      return new Response("passeurs-relay ok\n", { headers: { "content-type": "text/plain; charset=utf-8" } });
    }
    const m = url.pathname.match(/^\/room\/([A-Za-z]{4})\/?$/);
    if (!m) return new Response("introuvable\n", { status: 404 });
    if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
      return new Response("WebSocket attendu\n", { status: 426 });
    }
    const code = m[1].toUpperCase();
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    const fwd = new URL(request.url);
    fwd.searchParams.set("code", code);
    return stub.fetch(new Request(fwd.toString(), request));
  },
};

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    // ping applicatif : répondu par le runtime sans réveiller l'objet (pas facturé en durée)
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request) {
    const url = new URL(request.url);
    const role = url.searchParams.get("role") === "host" ? "host" : "guest";
    const code = url.searchParams.get("code") || "????";
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const hosts = this.ctx.getWebSockets("host");
    const guests = this.ctx.getWebSockets("guest");
    let why = "";
    if (role === "host" && hosts.length > 0) why = "occupied";
    if (role === "guest" && hosts.length === 0) why = "no_room";
    if (role === "guest" && guests.length > 0) why = "full";
    if (why !== "") {
      // refus : on accepte quand même pour dire pourquoi, puis on ferme
      this.ctx.acceptWebSocket(server, ["reject"]);
      server.send(JSON.stringify({ t: "err", why }));
      server.close(4001, why);
      return new Response(null, { status: 101, webSocket: client });
    }
    this.ctx.acceptWebSocket(server, [role]);
    server.serializeAttachment({ role, last: Date.now() });
    const other = role === "host" ? guests : hosts;
    server.send(JSON.stringify({ t: "hello", role, code, peer: other.length > 0 }));
    for (const o of other) this._send(o, JSON.stringify({ t: "peer", on: true }));
    await this.ctx.storage.setAlarm(Date.now() + ALARM_MS);
    return new Response(null, { status: 101, webSocket: client });
  }

  _send(ws, msg) {
    try {
      ws.send(msg);
    } catch (_) {
      // connexion déjà fermée : le ménage s'en charge
    }
  }

  _role(ws) {
    const tags = this.ctx.getTags(ws);
    return tags.includes("host") ? "host" : tags.includes("guest") ? "guest" : "reject";
  }

  async webSocketMessage(ws, message) {
    const role = this._role(ws);
    if (role === "reject") return;
    if (typeof message === "string") {
      if (message === "ping") this._send(ws, "pong");
      return;
    }
    const target = role === "host" ? "guest" : "host";
    for (const o of this.ctx.getWebSockets(target)) this._send(o, message);
    // horodatage d'activité, mis à jour au plus toutes les 10 s (écriture peu coûteuse mais inutile à 20 Hz)
    const att = ws.deserializeAttachment() || {};
    const now = Date.now();
    if (!att.last || now - att.last > 10_000) ws.serializeAttachment({ ...att, last: now });
  }

  async webSocketClose(ws, code, reason) {
    await this._gone(ws, code, reason);
  }

  async webSocketError(ws) {
    await this._gone(ws, 1011, "error");
  }

  async _gone(ws, code, reason) {
    const role = this._role(ws);
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code, String(reason || "").slice(0, 100));
    } catch (_) {}
    if (role === "host") {
      // l'hôte part : la salle ferme, l'invité est prévenu
      for (const o of this.ctx.getWebSockets("guest")) {
        this._send(o, JSON.stringify({ t: "peer", on: false }));
        try { o.close(4000, "host_left"); } catch (_) {}
      }
    } else if (role === "guest") {
      for (const o of this.ctx.getWebSockets("host")) this._send(o, JSON.stringify({ t: "peer", on: false }));
    }
    await this._cleanup();
  }

  // Salle vide : plus d'alarme, plus de stockage. L'objet sort de la mémoire de lui-même.
  async _cleanup() {
    const live = this.ctx.getWebSockets().filter((w) => this._role(w) !== "reject" && w.readyState === WebSocket.OPEN);
    if (live.length === 0) {
      await this.ctx.storage.deleteAlarm();
      await this.ctx.storage.deleteAll();
    }
  }

  // Ménage : ferme les connexions muettes depuis IDLE_MS (ni message, ni ping), puis replanifie.
  async alarm() {
    const now = Date.now();
    for (const ws of this.ctx.getWebSockets()) {
      if (this._role(ws) === "reject") {
        try { ws.close(4001, "reject"); } catch (_) {}
        continue;
      }
      const att = ws.deserializeAttachment() || {};
      const ping = this.ctx.getWebSocketAutoResponseTimestamp(ws);
      const last = Math.max(att.last || 0, ping ? ping.getTime() : 0);
      if (now - last > IDLE_MS) await this._gone(ws, 4002, "idle");
    }
    const live = this.ctx.getWebSockets().filter((w) => this._role(w) !== "reject");
    if (live.length > 0) await this.ctx.storage.setAlarm(now + ALARM_MS);
    else await this._cleanup();
  }
}
