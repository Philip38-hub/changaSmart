import { useEffect, useRef, useState } from 'react';
import {
  API_BASE,
  POLL_INTERVAL_MS,
  type ProjectSummary,
  type CollectionSummary,
  type CollectionReport,
  type RankedProject,
} from '@/constants';
import { formatKSh, formatAgo } from '@/utils/format';
import { Reveal } from '@/components/Reveal';

type FetchState = 'loading' | 'ready' | 'hidden';

export function LiveProjects() {
  const [state, setState] = useState<FetchState>('loading');
  const [projects, setProjects] = useState<RankedProject[]>([]);
  const [lastUpdate, setLastUpdate] = useState<number | null>(null);
  const [now, setNow] = useState(Date.now());
  const positionsRef = useRef<Map<string, number>>(new Map());
  const containerRef = useRef<HTMLDivElement>(null);
  // Mirrors `state` synchronously for the effect's closure below (which has
  // an empty dependency array, so a plain read of `state` there would stay
  // frozen at its initial value forever) -- without this, a transient
  // network hiccup on any poll AFTER the first successful one would
  // incorrectly hide a section that's already showing good data, instead
  // of just skipping that one refresh.
  const stateRef = useRef<FetchState>('loading');
  const setStateBoth = (next: FetchState) => {
    stateRef.current = next;
    setState(next);
  };

  // Poll data
  useEffect(() => {
    let cancelled = false;

    async function fetchAll() {
      try {
        const projRes = await fetch(`${API_BASE}/projects`);
        if (!projRes.ok) throw new Error('projects fetch failed');
        const allProjects: ProjectSummary[] = await projRes.json();
        const active = allProjects.filter((p) => p.status === 'ACTIVE');
        if (active.length === 0) {
          if (!cancelled) setStateBoth('hidden');
          return;
        }

        const ranked: RankedProject[] = [];

        for (const proj of active) {
          const colRes = await fetch(
            `${API_BASE}/projects/${proj.id}/collections`
          );
          if (!colRes.ok) continue;
          const collections: CollectionSummary[] = await colRes.json();

          let raised = 0;
          let collectionTargetSum: number | null = 0;

          for (const col of collections) {
            const reportRes = await fetch(
              `${API_BASE}/collections/${col.id}/report`
            );
            if (!reportRes.ok) continue;
            const report: CollectionReport = await reportRes.json();
            raised += report.total_received ?? 0;

            if (col.target_amount != null) {
              collectionTargetSum =
                (collectionTargetSum ?? 0) + col.target_amount;
            } else {
              collectionTargetSum = null;
            }
          }

          const target =
            proj.target_amount != null
              ? proj.target_amount
              : collectionTargetSum;

          ranked.push({
            id: proj.id,
            name: proj.name,
            raised,
            target,
          });
        }

        if (cancelled) return;
        if (ranked.length === 0) {
          setStateBoth('hidden');
          return;
        }

        ranked.sort((a, b) => b.raised - a.raised);
        const top5 = ranked.slice(0, 5);

        // Record old positions for FLIP
        const oldPos = new Map(positionsRef.current);
        const newPos = new Map<string, number>();
        top5.forEach((p, i) => newPos.set(p.id, i));
        positionsRef.current = newPos;

        setProjects(top5);
        setStateBoth('ready');
        setLastUpdate(Date.now());

        // FLIP: compute delta and apply transition
        requestAnimationFrame(() => {
          if (cancelled || !containerRef.current) return;
          const items = containerRef.current.querySelectorAll<HTMLElement>(
            '[data-proj-id]'
          );
          items.forEach((item) => {
            const id = item.dataset.projId!;
            const oldIdx = oldPos.get(id);
            const newIdx = newPos.get(id);
            if (oldIdx == null || newIdx == null || oldIdx === newIdx) return;
            const rowHeight = item.offsetHeight + 12;
            const delta = (oldIdx - newIdx) * rowHeight;
            item.style.transform = `translateY(${delta}px)`;
            item.style.transition = 'none';
            requestAnimationFrame(() => {
              item.style.transition = '';
              item.style.transform = '';
            });
          });
        });
      } catch {
        if (!cancelled && stateRef.current !== 'ready') {
          setStateBoth('hidden');
        }
      }
    }

    fetchAll();
    const interval = setInterval(fetchAll, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  // Tick "updated Xs ago"
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  if (state === 'hidden') return null;

  const secondsAgo =
    lastUpdate != null ? Math.floor((now - lastUpdate) / 1000) : 0;

  return (
    <section className="py-16 sm:py-20">
      <div className="max-w-4xl mx-auto px-5 sm:px-6">
        <Reveal>
          <div className="flex items-center justify-between flex-wrap gap-3 mb-6">
            <div className="flex items-center gap-3">
              <h2 className="text-2xl sm:text-3xl font-bold text-brand-ink tracking-tight">
                Live: Top Performing Projects
              </h2>
              <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-brand-primaryLight">
                <span className="w-2 h-2 rounded-full bg-brand-confirmed animate-pulse-dot" />
                <span className="text-xs font-semibold text-brand-confirmed">
                  Live
                </span>
              </span>
            </div>
            {state === 'ready' && (
              <span className="text-xs text-brand-muted">
                Updated {formatAgo(secondsAgo)}
              </span>
            )}
          </div>
        </Reveal>

        {state === 'loading' && <SkeletonRows />}

        {state === 'ready' && (
          <div ref={containerRef} className="flip-list">
            {projects.map((proj, idx) => {
              const hasTarget = proj.target != null && proj.target > 0;
              const pct = hasTarget
                ? Math.min(100, Math.round((proj.raised / proj.target!) * 100))
                : null;
              return (
                <div
                  key={proj.id}
                  data-proj-id={proj.id}
                  className="flip-item bg-white rounded-xl2 p-4 sm:p-5 shadow-card border border-gray-50 flex items-center gap-4"
                >
                  <span className="flex-shrink-0 w-8 h-8 rounded-full bg-brand-primary text-white text-sm font-bold flex items-center justify-center">
                    {idx + 1}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-brand-ink truncate">
                      {proj.name}
                    </p>
                    {hasTarget && (
                      <div className="mt-2 flex items-center gap-3">
                        <div className="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden max-w-xs">
                          <div
                            className="h-full bg-brand-primary rounded-full transition-all duration-700 ease-out"
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                        <span className="text-xs font-medium text-brand-muted flex-shrink-0">
                          {pct}%
                        </span>
                      </div>
                    )}
                  </div>
                  <span className="font-bold text-brand-ink text-sm sm:text-base whitespace-nowrap">
                    {formatKSh(proj.raised)}
                  </span>
                </div>
              );
            })}
          </div>
        )}

        <Reveal delay={200}>
          <p className="mt-4 text-xs text-brand-muted text-center">
            Live data from the deployed ChangaSmart backend — refreshes every
            30 seconds
          </p>
        </Reveal>
      </div>
    </section>
  );
}

function SkeletonRows() {
  return (
    <div className="space-y-3">
      {Array.from({ length: 5 }).map((_, i) => (
        <div
          key={i}
          className="bg-white rounded-xl2 p-4 sm:p-5 shadow-card border border-gray-50 flex items-center gap-4"
        >
          <div className="w-8 h-8 rounded-full skeleton-shimmer flex-shrink-0" />
          <div className="flex-1 space-y-2">
            <div className="h-4 w-40 rounded skeleton-shimmer" />
            <div className="h-1.5 w-32 rounded-full skeleton-shimmer" />
          </div>
          <div className="h-5 w-24 rounded skeleton-shimmer" />
        </div>
      ))}
    </div>
  );
}
