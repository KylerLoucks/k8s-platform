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

type ServiceState = "live" | "offline";

type WsEvent = {
  type?: string;
  job_id?: string;
  item_id?: number;
  name?: string;
  status?: string;
  [k: string]: unknown;
};

type JourneyPhase = "idle" | "processing" | "completed" | "failed";

type JobJourney = {
  id: string;
  name: string;
  phase: JourneyPhase;
  startedAt: number;
  finishedAt?: number;
  itemId?: number;
};

function statusClass(s: string): string {
  const x = s.toLowerCase();
  if (x === "pending") return "status-pill status-pending";
  if (x === "processing") return "status-pill status-processing";
  if (x === "completed") return "status-pill status-completed";
  if (x === "failed") return "status-pill status-failed";
  return "status-pill";
}

function formatElapsed(ms: number): string {
  const secs = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

export function App() {
  const API_OFFLINE_GRACE_MS = 15000;
  const WORKER_OFFLINE_GRACE_MS = 10 * 60_000;
  const [jobName, setJobName] = useState("demo-item");
  const [jobsJson, setJobsJson] = useState("—");
  const [jobRows, setJobRows] = useState<JobRow[] | null>(null);
  const [lastApi, setLastApi] = useState("—");
  const [apiErr, setApiErr] = useState<string | null>(null);
  const [feed, setFeed] = useState<FeedEntry[]>([]);
  const [wsLive, setWsLive] = useState(false);
  const [wsDetail, setWsDetail] = useState<string>("Connecting…");
  const [debugOut, setDebugOut] = useState("—");
  const [apiLive, setApiLive] = useState<ServiceState>("offline");
  const [workerLive, setWorkerLive] = useState<ServiceState>("offline");
  const [isScheduling, setIsScheduling] = useState(false);
  const [hasScheduled, setHasScheduled] = useState(false);
  const [jobJourney, setJobJourney] = useState<JobJourney | null>(null);
  const [nowMs, setNowMs] = useState(Date.now());
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectAttempt = useRef(0);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const scheduledAtRef = useRef<Record<string, number>>({});
  const lastApiOkAtRef = useRef<number | null>(null);
  const lastWorkerSeenAtRef = useRef<number | null>(null);
  const feedScrollRef = useRef<HTMLDivElement | null>(null);

  const markApiLiveNow = useCallback(() => {
    lastApiOkAtRef.current = Date.now();
    setApiLive("live");
  }, []);

  const markWorkerLiveNow = useCallback(() => {
    lastWorkerSeenAtRef.current = Date.now();
    setWorkerLive("live");
  }, []);

  const appendFeed = useCallback((text: string, highlight: boolean) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    const t = new Date().toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    setFeed((prev) => [...prev.slice(-80), { id, t, text, highlight }]);
  }, []);

  const refreshJobs = useCallback(async () => {
    setApiErr(null);
    try {
      const { ok, text } = await apiFetch("/api/jobs");
      if (ok) markApiLiveNow();
      setJobsJson(ok ? text : `Error: ${text}`);
      if (ok) {
        try {
          const data = JSON.parse(text) as { jobs?: JobRow[] };
          const rows = Array.isArray(data.jobs) ? data.jobs : [];
          setJobRows(rows);
          const processing = rows.find((j) => j.status.toLowerCase() === "processing");
          if (processing?.id) {
            setJobJourney((prev) => {
              if (prev?.id === processing.id && prev.phase === "processing") return prev;
              const startedAt = Number.isFinite(Date.parse(processing.created_at)) ? Date.parse(processing.created_at) : Date.now();
              return {
                id: processing.id,
                name: processing.name,
                phase: "processing",
                startedAt,
              };
            });
          } else {
            setJobJourney((prev) => (prev?.phase === "processing" ? null : prev));
          }
          const hasActiveOrRecentWorkerJob = rows.some((j) => {
            if (j.status === "processing") return true;
            const done = j.completed_at ? Date.parse(j.completed_at) : NaN;
            return Number.isFinite(done) && Date.now() - done < 3 * 60_000;
          });
          if (hasActiveOrRecentWorkerJob) {
            markWorkerLiveNow();
          }
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
  }, [markApiLiveNow, markWorkerLiveNow]);

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
          const o = JSON.parse(line) as WsEvent;
          if (o.type === "job.processing") {
            const id = o.job_id ?? "";
            const since = id && scheduledAtRef.current[id] ? Date.now() - scheduledAtRef.current[id] : null;
            const wait = since !== null ? ` · queue wait ${(since / 1000).toFixed(1)}s` : "";
            display = `Worker picked up: "${o.name}" (${o.job_id?.slice(0, 8)}...)${wait}`;
            void refreshJobs();
            markWorkerLiveNow();
            if (id) {
              setJobJourney({
                id,
                name: o.name ?? "job",
                phase: "processing",
                startedAt: scheduledAtRef.current[id] ?? Date.now(),
              });
            }
          } else if (o.type === "job.completed") {
            const id = o.job_id ?? "";
            const since = id && scheduledAtRef.current[id] ? Date.now() - scheduledAtRef.current[id] : null;
            const total = since !== null ? ` · end-to-end ${(since / 1000).toFixed(1)}s` : "";
            display = `Job finished: "${o.name}" -> item #${o.item_id} (${o.job_id?.slice(0, 8)}...)${total}`;
            highlight = true;
            if (id) delete scheduledAtRef.current[id];
            void refreshJobs();
            markWorkerLiveNow();
            setJobJourney((prev) => {
              if (!prev) return prev;
              if (!id || prev.id === id || prev.name === o.name) {
                return { ...prev, phase: "completed", finishedAt: Date.now(), itemId: o.item_id };
              }
              return prev;
            });
          } else if (o.type === "job.failed") {
            const id = o.job_id ?? "";
            const since = id && scheduledAtRef.current[id] ? Date.now() - scheduledAtRef.current[id] : null;
            const total = since !== null ? ` after ${(since / 1000).toFixed(1)}s` : "";
            display = `Job failed: "${o.name}" (${o.job_id?.slice(0, 8)}...)${total}`;
            highlight = true;
            if (id) delete scheduledAtRef.current[id];
            markWorkerLiveNow();
            void refreshJobs();
            setJobJourney((prev) => {
              if (!prev) return prev;
              if (!id || prev.id === id || prev.name === o.name) {
                return { ...prev, phase: "failed", finishedAt: Date.now() };
              }
              return prev;
            });
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
    setIsScheduling(true);
    try {
      const requestedName = jobName.trim() || "demo-item";
      appendFeed(`Dispatching "${requestedName}" to API...`, false);
      const { ok, text } = await apiFetch("/api/jobs", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: requestedName }),
      });
      if (ok) markApiLiveNow();
      let body = text;
      try {
        body = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        /* plain */
      }
      setLastApi(`HTTP ${ok ? "OK" : "ERR"}\n\n${body}`);
      if (!ok) {
        setApiErr("Schedule failed");
        appendFeed(`API rejected "${requestedName}"`, true);
      } else {
        setHasScheduled(true);
        try {
          const parsed = JSON.parse(text) as { job_id?: string; id?: string; job?: { id?: string }; name?: string };
          const jobId = parsed.job_id ?? parsed.id ?? parsed.job?.id;
          if (jobId) {
            scheduledAtRef.current[jobId] = Date.now();
            appendFeed(`Job accepted: "${parsed.name ?? requestedName}" (${jobId.slice(0, 8)}...)`, false);
          } else {
            appendFeed(`Job accepted: "${requestedName}"`, false);
          }
        } catch {
          appendFeed(`Job accepted: "${requestedName}"`, false);
        }
      }
      void refreshJobs();
    } catch (e) {
      setApiErr(e instanceof Error ? e.message : String(e));
    } finally {
      setIsScheduling(false);
    }
  };

  useEffect(() => {
    const id = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    // Keep API liveness fresh even when no jobs are being scheduled.
    const ping = async () => {
      try {
        const { ok } = await apiFetch("/healthz");
        if (ok) {
          markApiLiveNow();
        }
      } catch {
        /* ignore; interval evaluator will flip to offline after grace window */
      }
    };

    void ping();
    const id = setInterval(() => {
      void ping();
    }, 5000);

    return () => clearInterval(id);
  }, [markApiLiveNow]);

  useEffect(() => {
    const id = setInterval(() => {
      const now = Date.now();
      const apiSeen = lastApiOkAtRef.current;
      const workerSeen = lastWorkerSeenAtRef.current;
      const apiIsLive = apiSeen !== null && now - apiSeen <= API_OFFLINE_GRACE_MS;
      const workerIsLive = workerSeen !== null && now - workerSeen <= WORKER_OFFLINE_GRACE_MS;
      setApiLive(apiIsLive ? "live" : "offline");
      setWorkerLive(workerIsLive ? "live" : "offline");
    }, 1000);
    return () => clearInterval(id);
  }, [API_OFFLINE_GRACE_MS, WORKER_OFFLINE_GRACE_MS]);

  useEffect(() => {
    // Keep newest events visible as they arrive.
    feedScrollRef.current?.scrollTo({ top: feedScrollRef.current.scrollHeight, behavior: "smooth" });
  }, [feed]);

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
          <span className={apiLive === "live" ? "badge badge-live" : "badge badge-off"}>{apiLive === "live" ? "LIVE API" : "OFFLINE API"}</span>
          <span className={wsLive ? "badge badge-live" : "badge badge-off"}>{wsLive ? "LIVE WS" : "OFFLINE WS"}</span>
          <span className={workerLive === "live" ? "badge badge-live" : "badge badge-off"}>
            {workerLive === "live" ? "LIVE WORKER" : "OFFLINE WORKER"}
          </span>
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
          <div className="quick-guide">
            <span className="quick-guide-label">How to use this page</span>
            <ol className="quick-guide-list">
              <li>Enter a job name and click <strong>Schedule job</strong> (or press Enter).</li>
              <li>Watch <strong>Current worker job</strong> for live progress.</li>
              <li>Verify completion in <strong>Jobs</strong> and the <strong>Realtime feed</strong>.</li>
            </ol>
          </div>
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
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !isScheduling) {
                      void scheduleJob();
                    }
                  }}
                  placeholder="Job name"
                  aria-label="Job name"
                />
                <button type="button" className="btn btn-primary btn-schedule" onClick={() => void scheduleJob()} disabled={isScheduling}>
                  {isScheduling ? (
                    <>
                      <span className="spinner" aria-hidden="true" />
                      Scheduling...
                    </>
                  ) : (
                    "Schedule job"
                  )}
                </button>
                <button type="button" className="btn btn-ghost" onClick={() => void refreshJobs()}>
                  Refresh jobs
                </button>
              </div>
              <p className="helper-copy">Tip: use distinctive names like <code className="mono">invoice-123</code> so events are easy to scan.</p>
              <div className="journey-card">
                <div className="journey-head">
                  <h3>Current worker job</h3>
                  <span className="journey-meta mono">
                    {jobJourney ? `${jobJourney.name} · ${formatElapsed((jobJourney.finishedAt ?? nowMs) - jobJourney.startedAt)}` : "Waiting for processing job"}
                  </span>
                </div>
                <div className="journey-steps">
                  <div
                    className={`journey-step${jobJourney && ["processing", "completed", "failed"].includes(jobJourney.phase) ? " active" : ""}${jobJourney?.phase === "processing" ? " pulse" : ""}`}
                  >
                    Processing
                  </div>
                  <div className={`journey-step${jobJourney?.phase === "completed" ? " active ok" : ""}`}>Completed</div>
                  <div className={`journey-step${jobJourney?.phase === "failed" ? " active err" : ""}`}>Failed</div>
                </div>
                {jobJourney?.phase === "completed" ? (
                  <p className="status-msg journey-note ok">Completed{jobJourney.itemId ? ` -> item #${jobJourney.itemId}` : ""}</p>
                ) : null}
                {jobJourney?.phase === "failed" ? <p className="status-msg journey-note err">Job failed. Check API/worker logs.</p> : null}
              </div>
              <h3>Jobs</h3>
              {!hasScheduled && (!jobRows || jobRows.length === 0) ? (
                <div className="empty-hint">No jobs yet. Schedule your first job to see the full API -&gt; Worker -&gt; WS journey.</div>
              ) : null}
              {jobRows && jobRows.length > 0 ? (
                <div className="job-table-wrap">
                  <table className="job-table">
                    <thead>
                      <tr>
                        <th>ID</th>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Item</th>
                      </tr>
                    </thead>
                    <tbody>
                      {jobRows.map((j) => (
                        <tr key={j.id}>
                          <td className="mono">{j.id ? j.id.slice(0, 8) : "—"}</td>
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
              <div className="feed-scroll" ref={feedScrollRef}>
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
