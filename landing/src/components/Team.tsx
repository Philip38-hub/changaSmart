import { User, Linkedin, Github } from 'lucide-react';
import { Reveal } from '@/components/Reveal';

// PLACEHOLDER: The three team member cards below (name, photo, bio, social links)
// are placeholders meant to be replaced with real team info before final submission.

const members = [
  { role: 'Project Manager', color: 'bg-brand-primary' },
  { role: 'Developer', color: 'bg-brand-orange' },
  { role: 'UI/UX Designer', color: 'bg-brand-amber' },
];

export function Team() {
  return (
    <section id="team" className="py-16 sm:py-24">
      <div className="max-w-5xl mx-auto px-5 sm:px-6">
        <Reveal>
          <p className="text-sm font-semibold text-brand-primary uppercase tracking-wider">
            Team
          </p>
          <h2 className="mt-2 text-3xl sm:text-4xl font-bold text-brand-ink tracking-tight">
            Meet the team
          </h2>
        </Reveal>

        <div className="mt-12 grid sm:grid-cols-3 gap-6">
          {members.map((m, i) => (
            <Reveal key={m.role} delay={i * 100}>
              {/* PLACEHOLDER CARD — replace name, photo, bio, and links */}
              <div className="p-6 rounded-xl2 bg-white border border-gray-100 shadow-soft text-center">
                <div className="w-20 h-20 rounded-full bg-gray-100 mx-auto flex items-center justify-center">
                  <User className="w-10 h-10 text-gray-400" strokeWidth={1.5} />
                </div>
                <p className="mt-4 font-semibold text-brand-ink">[Name]</p>
                <span
                  className={`inline-block mt-2 px-3 py-1 rounded-full text-xs font-semibold text-white ${m.color}`}
                >
                  {m.role}
                </span>
                <p className="mt-3 text-sm text-brand-muted">Bio coming soon.</p>
                <div className="mt-4 flex items-center justify-center gap-3">
                  <a
                    href="#"
                    className="w-8 h-8 rounded-lg bg-gray-50 flex items-center justify-center text-brand-muted hover:bg-brand-primaryLight hover:text-brand-primary transition-colors"
                    aria-label="LinkedIn"
                  >
                    <Linkedin className="w-4 h-4" />
                  </a>
                  <a
                    href="#"
                    className="w-8 h-8 rounded-lg bg-gray-50 flex items-center justify-center text-brand-muted hover:bg-brand-primaryLight hover:text-brand-primary transition-colors"
                    aria-label="GitHub"
                  >
                    <Github className="w-4 h-4" />
                  </a>
                </div>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
