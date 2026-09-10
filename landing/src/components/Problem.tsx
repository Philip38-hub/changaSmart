import { UserX, Users, MessageSquare } from 'lucide-react';
import { Reveal } from '@/components/Reveal';

const problems = [
  {
    icon: UserX,
    title: 'Names don\u2019t match',
    desc: '\u201CJANE M WANJIKU\u201D on M-PESA vs \u201CJane Wanjiku\u201D on the list. Every contribution needs a manual guess.',
  },
  {
    icon: Users,
    title: 'Someone pays on someone else\u2019s behalf',
    desc: 'Anne pays Jane\u2019s pledge. Money gets miscredited or missed entirely without careful tracking.',
  },
  {
    icon: MessageSquare,
    title: 'Manual WhatsApp updates',
    desc: 'The harambee secretary retypes the same \u201Cwho\u2019s paid\u201D summary over and over for the group.',
  },
];

export function Problem() {
  return (
    <section className="py-16 sm:py-24 bg-white">
      <div className="max-w-6xl mx-auto px-5 sm:px-6">
        <Reveal>
          <p className="text-sm font-semibold text-brand-primary uppercase tracking-wider">
            The Problem
          </p>
          <h2 className="mt-2 text-3xl sm:text-4xl font-bold text-brand-ink tracking-tight">
            Running a harambee is manual, error-prone work.
          </h2>
        </Reveal>

        <div className="mt-12 grid md:grid-cols-3 gap-6">
          {problems.map((p, i) => (
            <Reveal key={p.title} delay={i * 100}>
              <div className="h-full p-6 rounded-xl2 bg-brand-bg border border-gray-100 hover:shadow-card transition-shadow">
                <div className="w-11 h-11 rounded-xl bg-brand-primaryLight flex items-center justify-center">
                  <p.icon className="w-5 h-5 text-brand-primary" strokeWidth={1.75} />
                </div>
                <h3 className="mt-4 font-semibold text-brand-ink">{p.title}</h3>
                <p className="mt-2 text-sm text-brand-muted leading-relaxed">
                  {p.desc}
                </p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
