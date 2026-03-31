import { useCallback, useEffect, useRef, useState } from "react";

function apiBase(): string {
  return (typeof window !== "undefined" && window.__API_BASE__?.trim()) || "";
}

function wsBase(): string {
  return (typeof window !== "undefined" && window.__WS_BASE__?.trim()) || "";
}

/** Full WebSocket URL for the notifications room (config, or localhost:8001 in dev). */
function notificationsWsUrl(): string {
  const configured = wsBase();
  if (configured) {
    return `${configured.replace(/\/$/, "")}/ws?room=notifications`;
  }
  if (typeof window !== "undefined") {
    const { protocol, hostname } = window.location;
    const wsProto = protocol === "https:" ? "wss:" : "ws:";
    if (hostname === "localhost" || hostname === "127.0.0.1") {
      return `${wsProto}//${hostname}:8001/ws?room=notifications`;
    }
    // In-cluster ingress path routing: same host, WS service on /ws
    return `${wsProto}//${window.location.host}/ws?room=notifications`;
  }
  return "";
}

async function apiFetch(path: string, init?: RequestInit): Promise<{ ok: boolean; text: string }> {
  const base = apiBase();
  const url = base ? `${base.replace(/\/$/, "")}${path}` : path;
  const res = await fetch(url, { ...init, cache: "no-store" });
  const text = await res.text();
  return { ok: res.ok, text };
}

type FeedEntry = { id: string; t: string; text: string; highlight: boolean };

type JobRow = {
  id: string;
  name: string;
  status: string;
  item_id: number | null;
  created_at: string;
  completed_at: string | null;
};

function statusClass(s: string): string {
  const x = s.toLowerCase();
  if (x === "pending") return "status-pill status-pending";
  if (x === "processing") return "status-pill status-processing";
  if (x === "completed") return "status-pill status-completed";
  if (x === "failed") return "status-pill status-failed";
  return "status-pill";
}

export function App() {
  const [jobName, setJobName] = useState("demo-item");
  const [jobsJson, setJobsJson] = useState("—");
  const [jobRows, setJobRows] = useState<JobRow[] | null>(null);
  const [lastApi, setLastApi] = useState("—");
  const [apiErr, setApiErr] = useState<string | null>(null);
  const [feed, setFeed] = useState<FeedEntry[]>([]);
  const [wsLive, setWsLive] = useState(false);
  const [wsDetail, setWsDetail] = useState<string>("Connecting…");
  const [debugOut, setDebugOut] = useState("—");
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttempt = useRef(0);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const appendFeed = useCallback((text: string, highlight: boolean) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    const t = new Date().toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    setFeed((prev) => [...prev.slice(-80), { id, t, text, highlight }]);
  }, []);

  const refreshJobs = useCallback(async () => {
    setApiErr(null);
    try {
      const { ok, text } = await apiFetch("/api/jobs");
      setJobsJson(ok ? text : `Error: ${text}`);
      if (ok) {
        try {
          const data = JSON.parse(text) as { jobs?: JobRow[] };
          setJobRows(Array.isArray(data.jobs) ? data.jobs : []);
        } catch {
          setJobRows(null);
        }
      } else {
        setJobRows(null);
      }
    } catch (e) {
      setJobsJson(e instanceof Error ? e.message : String(e));
      setJobRows(null);
    }
  }, []);

  useEffect(() => {
    void refreshJobs();
  }, [refreshJobs]);

  useEffect(() => {
    let cancelled = false;

    const clearTimer = () => {
      if (reconnectTimer.current) {
        clearTimeout(reconnectTimer.current);
        reconnectTimer.current = null;
      }
    };

    const connect = () => {
      if (cancelled) return;
      clearTimer();
      const url = notificationsWsUrl();
      if (!url) {
        setWsLive(false);
        setWsDetail("Set __WS_BASE__ (Helm) or open via localhost for :8001 fallback.");
        return;
      }

      wsRef.current?.close();
      setWsDetail(reconnectAttempt.current > 0 ? `Reconnecting (${reconnectAttempt.current})…` : "Connecting…");
      setWsLive(false);

      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.addEventListener("open", () => {
        if (cancelled) return;
        reconnectAttempt.current = 0;
        setWsLive(true);
        setWsDetail(`Subscribed · ${url.replace(/\?.*$/, "")}`);
        appendFeed("Connected to notifications room.", false);
      });

      ws.addEventListener("message", (ev) => {
        if (cancelled) return;
        const line = ev.data as string;
        let display = line;
        let highlight = false;
        try {
          const o = JSON.parse(line) as { type?: string; job_id?: string; item_id?: number; name?: string };
          if (o.type === "job.processing") {
            display = `Job processing: “${o.name}” (${o.job_id?.slice(0, 8)}…)`;
            void refreshJobs();
          } else if (o.type === "job.completed") {
            display = `Job finished: “${o.name}” → item #${o.item_id} (${o.job_id?.slice(0, 8)}…)`;
            highlight = true;
            void refreshJobs();
          }
        } catch {
          /* raw */
        }
        appendFeed(display, highlight);
      });

      ws.addEventListener("error", () => {
        if (!cancelled) setWsDetail("Connection error");
      });

      ws.addEventListener("close", () => {
        if (cancelled) return;
        setWsLive(false);
        wsRef.current = null;
        const delay = Math.min(1000 * 2 ** reconnectAttempt.current, 30000);
        reconnectAttempt.current += 1;
        setWsDetail(`Disconnected · retry in ${Math.round(delay / 1000)}s`);
        reconnectTimer.current = setTimeout(connect, delay);
      });
    };

    connect();

    return () => {
      cancelled = true;
      clearTimer();
      wsRef.current?.close();
      wsRef.current = null;
    };
  }, [appendFeed, refreshJobs]);

  const scheduleJob = async () => {
    setApiErr(null);
    try {
      const { ok, text } = await apiFetch("/api/jobs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: jobName.trim() || "demo-item" }),
      });
      let body = text;
      try {
        body = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        /* plain */
      }
      setLastApi(`HTTP ${ok ? "OK" : "ERR"}\n\n${body}`);
      if (!ok) setApiErr("Schedule failed");
      void refreshJobs();
    } catch (e) {
      setApiErr(e instanceof Error ? e.message : String(e));
    }
  };

  const runDebug = async (path: string) => {
    try {
      const { ok, text } = await apiFetch(path);
      let body = text;
      try {
        body = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        /* plain */
      }
      setDebugOut(`${ok ? "OK" : "ERR"}\n\n${body}`);
    } catch (e) {
      setDebugOut(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <div className="app">
      <header className="topbar">
        <div className="topbar-brand">
          <strong>Platform demo</strong>
          <span>Schedule work through the API, let the worker finish it, watch everyone get notified over WebSockets + Redis pub/sub.</span>
        </div>
        <div className="topbar-meta">
          <span className={wsLive ? "badge badge-live" : "badge badge-off"}>{wsLive ? "Live" : "Offline"}</span>
          <span className="pill-mini mono" title={apiBase() || "relative / Vite proxy"}>
            API {apiBase() || "·/·"}
          </span>
          <span className="pill-mini mono" title={notificationsWsUrl() || "—"}>
            WS {wsBase() || "·8001·"}
          </span>
        </div>
      </header>

      <main className="layout-main">
        <div className="flow-strip">
          <div className="flow-step">
            <span className="flow-step-num">1</span>
            <span>
              <code className="mono">POST /api/jobs</code> → Redis queue
            </span>
          </div>
          <span className="flow-arrow">→</span>
          <div className="flow-step">
            <span className="flow-step-num">2</span>
            <span>Worker → Postgres</span>
          </div>
          <span className="flow-arrow">→</span>
          <div className="flow-step">
            <span className="flow-step-num">3</span>
            <span>
              <code className="mono">PUBLISH</code> → WS replicas → you
            </span>
          </div>
        </div>

        <div className="grid cols-2">
          <section className="card">
            <div className="card-head">
              <h2>Schedule a job</h2>
              <p>
                Creates a <code className="mono">pending</code> row and pushes <code className="mono">jobs:queue</code> on Redis.
              </p>
            </div>
            <div className="card-body">
              <div className="toolbar">
                <input
                  className="input-field"
                  value={jobName}
                  onChange={(e) => setJobName(e.target.value)}
                  placeholder="Job name"
                  aria-label="Job name"
                />
                <button type="button" className="btn btn-primary" onClick={() => void scheduleJob()}>
                  Schedule job
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => void refreshJobs()}>
                  Refresh list
                </button>
              </div>
              <h3>Jobs</h3>
              {jobRows && jobRows.length > 0 ? (
                <div className="job-table-wrap">
                  <table className="job-table">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Item</th>
                      </tr>
                    </thead>
                    <tbody>
                      {jobRows.map((j) => (
                        <tr key={j.id}>
                          <td>{j.name}</td>
                          <td>
                            <span className={statusClass(j.status)}>{j.status}</span>
                          </td>
                          <td className="mono">{j.item_id ?? "—"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <pre className="pre-block">{jobsJson}</pre>
              )}
              <h3 style={{ marginTop: "1rem" }}>Last response</h3>
              <pre className="pre-block">{lastApi}</pre>
              {apiErr ? <div className="status-msg err">{apiErr}</div> : null}
            </div>
          </section>

          <section className="card">
            <div className="card-head">
              <h2>Realtime feed</h2>
              <p>
                Auto-connected to <code className="mono">/ws?room=notifications</code>. Events fan out from every WS pod via{" "}
                <code className="mono">jobs:events</code>.
              </p>
            </div>
            <div className="card-body">
              <p className="status-msg" style={{ marginTop: 0 }}>
                {wsDetail}
              </p>
              <h3 style={{ marginTop: "1rem" }}>Event log</h3>
              <div className="feed-scroll">
                {feed.length === 0 ? (
                  <div className="feed-empty">Waiting for events… schedule a job or watch for reconnect messages.</div>
                ) : (
                  feed.map((e) => (
                    <div key={e.id} className={`feed-entry${e.highlight ? " highlight" : ""}`}>
                      <time>{e.t}</time>
                      <span className="msg">{e.text}</span>
                    </div>
                  ))
                )}
              </div>
            </div>
          </section>

          <section className="card debug-card" style={{ gridColumn: "1 / -1" }}>
            <div className="card-head">
              <h2>API debug</h2>
              <p>Quick health checks for demos and interviews.</p>
            </div>
            <div className="card-body">
              <div className="toolbar">
                <button type="button" className="btn btn-ghost" onClick={() => void runDebug("/healthz")}>
                  /healthz
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => void runDebug("/readyz")}>
                  /readyz
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => void runDebug("/api/info")}>
                  /api/info
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => void runDebug("/api/items")}>
                  /api/items
                </button>
              </div>
              <pre className="pre-block">{debugOut}</pre>
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}
