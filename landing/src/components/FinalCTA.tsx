import { Download } from 'lucide-react';
import { LINKS } from '@/constants';
import { Reveal } from '@/components/Reveal';

export function FinalCTA() {
  return (
    <section className="py-16 sm:py-24">
      <div className="max-w-6xl mx-auto px-5 sm:px-6">
        <Reveal>
          <div className="relative rounded-2xl overflow-hidden bg-brand-primary px-6 py-12 sm:px-12 sm:py-16 text-center shadow-lift">
            {/* decorative shapes */}
            <div className="absolute top-0 right-0 w-64 h-64 rounded-full bg-white/5 -translate-y-1/3 translate-x-1/4" />
            <div className="absolute bottom-0 left-0 w-48 h-48 rounded-full bg-white/5 translate-y-1/3 -translate-x-1/4" />

            <div className="relative">
              <h2 className="text-3xl sm:text-4xl font-bold text-white tracking-tight">
                Try the MVP on your own phone
              </h2>
              <p className="mt-4 text-base text-white/80 max-w-xl mx-auto">
                Download the APK from GitHub and test it — no setup required,
                it’s already connected to the live backend.
              </p>
              <a
                href={LINKS.releases}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-8 inline-flex items-center gap-2 px-8 h-12 rounded-xl bg-white text-brand-primary font-semibold hover:bg-brand-bg transition-colors shadow-card"
              >
                <Download className="w-5 h-5" />
                Download APK
              </a>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
