import {
  CheckCircle2,
  Brain,
  BellRing,
  Zap,
  Layers,
  MessageCircle,
} from 'lucide-react';
import { Reveal } from '@/components/Reveal';

const features = [
  {
    icon: CheckCircle2,
    title: 'Deterministic name matching',
    desc: 'Near-exact matches and duplicate M-PESA codes resolved instantly — no AI guesswork on money.',
  },
  {
    icon: Brain,
    title: 'AI-assisted review for ambiguous cases',
    desc: 'A Bedrock-backed agent reasons about genuinely unclear \u201Cpaid on behalf of\u201D cases, always leaving the final call to a human.',
  },
  {
    icon: BellRing,
    title: 'Real-time contribution alerts',
    desc: 'Get notified the moment a matching M-PESA SMS arrives, even when the app is closed.',
  },
  {
    icon: Zap,
    title: 'Smart auto-import',
    desc: 'A message that matches on name, amount, and group all at once imports itself automatically, with one-tap undo.',
  },
  {
    icon: Layers,
    title: 'Harambee sessions',
    desc: 'Run one-off fundraising drives alongside an ongoing Main Contribution, each with its own target and progress.',
  },
  {
    icon: MessageCircle,
    title: 'WhatsApp-ready updates',
    desc: 'Generate a clean \u201Cwho\u2019s paid\u201D summary to paste into the group — no manual retyping.',
  },
];

export function Features() {
  return (
    <section className="py-16 sm:py-24 bg-white">
      <div className="max-w-6xl mx-auto px-5 sm:px-6">
        <Reveal>
          <p className="text-sm font-semibold text-brand-primary uppercase tracking-wider">
            Features
          </p>
          <h2 className="mt-2 text-3xl sm:text-4xl font-bold text-brand-ink tracking-tight">
            Built for the way chamas actually work.
          </h2>
        </Reveal>

        <div className="mt-12 grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((f, i) => (
            <Reveal key={f.title} delay={(i % 3) * 80}>
              <div className="h-full p-6 rounded-xl2 bg-brand-bg border border-gray-100 hover:shadow-card hover:border-brand-primary/20 transition-all duration-300">
                <div className="w-11 h-11 rounded-xl bg-brand-primaryLight flex items-center justify-center">
                  <f.icon className="w-5 h-5 text-brand-primary" strokeWidth={1.75} />
                </div>
                <h3 className="mt-4 font-semibold text-brand-ink">{f.title}</h3>
                <p className="mt-2 text-sm text-brand-muted leading-relaxed">
                  {f.desc}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
