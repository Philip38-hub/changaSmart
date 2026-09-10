import { FolderPlus, MessageSquareText, BrainCircuit, FileText } from 'lucide-react';
import { Reveal } from '@/components/Reveal';

const steps = [
  {
    icon: FolderPlus,
    title: 'Create a project',
    desc: 'Set up a project and add the list of expected contributors.',
  },
  {
    icon: MessageSquareText,
    title: 'Import M-PESA messages',
    desc: 'Manually, or automatically via the real-time alert listener.',
  },
  {
    icon: BrainCircuit,
    title: 'ChangaSmart matches',
    desc: 'Names and amounts are matched deterministically; genuinely ambiguous cases are flagged for you — never guessed.',
  },
  {
    icon: FileText,
    title: 'Get your report',
    desc: 'An instant report and a copy-paste-ready WhatsApp update.',
  },
];

export function HowItWorks() {
  return (
    <section className="py-16 sm:py-24">
      <div className="max-w-6xl mx-auto px-5 sm:px-6">
        <Reveal>
          <p className="text-sm font-semibold text-brand-primary uppercase tracking-wider">
            How It Works
          </p>
          <h2 className="mt-2 text-3xl sm:text-4xl font-bold text-brand-ink tracking-tight">
            From pledge list to reconciled report in four steps.
          </h2>
        </Reveal>

        <div className="mt-12 grid sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {steps.map((s, i) => (
            <Reveal key={s.title} delay={i * 100}>
              <div className="relative h-full p-6 rounded-xl2 bg-white border border-gray-100 shadow-soft">
                {/* step number */}
                <span className="absolute -top-3 -left-3 w-8 h-8 rounded-full bg-brand-primary text-white text-sm font-bold flex items-center justify-center shadow-soft">
                  {i + 1}
                </span>
                <div className="w-11 h-11 rounded-xl bg-brand-primaryLight flex items-center justify-center mt-2">
                  <s.icon className="w-5 h-5 text-brand-primary" strokeWidth={1.75} />
                </div>
                <h3 className="mt-4 font-semibold text-brand-ink">{s.title}</h3>
                <p className="mt-2 text-sm text-brand-muted leading-relaxed">
                  {s.desc}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
