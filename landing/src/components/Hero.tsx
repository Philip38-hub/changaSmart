import { Download, Github, Check } from 'lucide-react';
import { LINKS } from '@/constants';
import { Reveal } from '@/components/Reveal';

export function Hero() {
  return (
    <section
      id="top"
      className="relative pt-28 pb-16 sm:pt-36 sm:pb-24 overflow-hidden"
    >
      {/* soft background blobs */}
      <div className="absolute top-20 -left-20 w-72 h-72 rounded-full bg-brand-primary/5 blur-3xl pointer-events-none" />
      <div className="absolute top-40 -right-10 w-80 h-80 rounded-full bg-brand-orange/5 blur-3xl pointer-events-none" />

      <div className="max-w-6xl mx-auto px-5 sm:px-6 grid lg:grid-cols-2 gap-12 lg:gap-16 items-center">
        {/* Left: copy */}
        <div>
          <Reveal>
            <h1 className="text-4xl sm:text-5xl font-extrabold text-brand-ink leading-[1.1] tracking-tight">
              Stop cross-checking M-PESA messages by hand.
            </h1>
          </Reveal>

          <Reveal delay={160}>
            <p className="mt-5 text-base sm:text-lg text-brand-muted leading-relaxed max-w-xl">
              ChangaSmart reconciles harambee and chama contributions
              automatically — matching names, catching duplicates, and
              flagging anything ambiguous for a human to confirm. Never an
              M-PESA banking service; it reconciles structured data
              extracted from SMS.
            </p>
          </Reveal>

          <Reveal delay={240}>
            <div className="mt-8 flex flex-col sm:flex-row gap-3">
              <a
                href={LINKS.releases}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center justify-center gap-2 px-6 h-12 rounded-xl bg-brand-primary text-white font-semibold hover:bg-brand-primaryDark transition-colors shadow-card"
              >
                <Download className="w-5 h-5" />
                Download the APK
              </a>
              <a
                href={LINKS.github}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center justify-center gap-2 px-6 h-12 rounded-xl bg-white text-brand-ink font-semibold border border-gray-200 hover:border-brand-primary hover:text-brand-primary transition-colors"
              >
                <Github className="w-5 h-5" />
                View on GitHub
              </a>
            </div>
          </Reveal>
        </div>

        {/* Right: phone mockup */}
        <Reveal delay={200} className="flex justify-center lg:justify-end">
          <PhoneMockup />
        </Reveal>
      </div>
    </section>
  );
}

function PhoneMockup() {
  return (
    <div className="relative">
      {/* glow behind phone */}
      <div className="absolute inset-0 bg-brand-primary/8 blur-2xl rounded-[40px]" />

      <div className="relative w-[260px] sm:w-[300px] bg-brand-ink rounded-[36px] p-3 shadow-lift">
        {/* notch */}
        <div className="absolute top-3 left-1/2 -translate-x-1/2 w-24 h-6 bg-brand-ink rounded-b-2xl z-10" />

        {/* screen */}
        <div className="bg-brand-bg rounded-[28px] overflow-hidden h-[520px] flex flex-col">
          {/* status bar */}
          <div className="h-8 flex items-center justify-between px-5 pt-2 text-[10px] text-brand-muted font-medium">
            <span>9:41</span>
            <span>ChangaSmart</span>
            <span>100%</span>
          </div>

          {/* app header */}
          <div className="px-4 py-3 bg-brand-primary text-white">
            <p className="text-[10px] uppercase tracking-wider opacity-80">
              Mary's Medical Fund
            </p>
            <p className="text-sm font-bold mt-0.5">Main Contribution</p>
          </div>

          {/* transaction card */}
          <div className="flex-1 px-4 py-4 space-y-3">
            <div className="bg-white rounded-2xl p-3.5 shadow-soft border border-gray-100">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-semibold text-brand-confirmed bg-brand-primaryLight px-2 py-0.5 rounded-full">
                  ✓ Confirmed
                </span>
                <span className="text-[9px] text-brand-muted">2 min ago</span>
              </div>
              <p className="text-lg font-bold text-brand-ink mt-2">
                KSh 3,000
              </p>
              <p className="text-xs text-brand-muted mt-0.5">
                from Jane M Wanjiku
              </p>
              <div className="mt-2 pt-2 border-t border-gray-50 flex items-center gap-1.5">
                <Check className="w-3 h-3 text-brand-confirmed" />
                <span className="text-[10px] text-brand-confirmed font-medium">
                  Matched: Jane Wanjiku
                </span>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-3.5 shadow-soft border border-gray-100">
              <div className="flex items-center justify-between">
                <span className="text-[10px] font-semibold text-brand-amber bg-amber-50 px-2 py-0.5 rounded-full">
                  ⚠ Review
                </span>
                <span className="text-[9px] text-brand-muted">5 min ago</span>
              </div>
              <p className="text-lg font-bold text-brand-ink mt-2">
                KSh 5,000
              </p>
              <p className="text-xs text-brand-muted mt-0.5">
                from Anne Otieno
              </p>
              <div className="mt-2 pt-2 border-t border-gray-50">
                <span className="text-[10px] text-brand-amber font-medium">
                  Paid on behalf of Jane Wanjiku?
                </span>
              </div>
            </div>

            {/* progress */}
            <div className="bg-white rounded-2xl p-3.5 shadow-soft border border-gray-100">
              <div className="flex items-center justify-between text-[10px]">
                <span className="text-brand-muted">Raised</span>
                <span className="font-bold text-brand-ink">
                  KSh 47,000 / 100,000
                </span>
              </div>
              <div className="mt-2 h-2 bg-gray-100 rounded-full overflow-hidden">
                <div
                  className="h-full bg-brand-primary rounded-full"
                  style={{ width: '47%' }}
                />
              </div>
            </div>
          </div>

          {/* bottom tab bar */}
          <div className="h-12 bg-white border-t border-gray-100 flex items-center justify-around text-[9px] text-brand-muted">
            <span className="text-brand-primary font-semibold">Home</span>
            <span>Projects</span>
            <span>Reports</span>
            <span>Settings</span>
          </div>
        </div>
      </div>

      {/* placeholder label */}
      <p className="mt-3 text-center text-[10px] text-brand-muted italic">
        Placeholder screenshot — swap with real app screenshot
      </p>
    </div>
  );
}
