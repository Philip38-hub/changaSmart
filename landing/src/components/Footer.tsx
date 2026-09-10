import { Github, Download, Users } from 'lucide-react';
import { LINKS } from '@/constants';

export function Footer() {
  const year = new Date().getFullYear();

  return (
    <footer className="bg-white border-t border-gray-100">
      <div className="max-w-6xl mx-auto px-5 sm:px-6 py-10">
        <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-6">
          {/* Left: brand + disclaimer */}
          <div className="max-w-sm">
            <div className="flex items-center gap-2">
              <span className="w-7 h-7 rounded-lg bg-brand-primary flex items-center justify-center text-white font-bold text-xs">
                C
              </span>
              <span className="font-bold text-brand-ink">ChangaSmart</span>
            </div>
            <p className="mt-3 text-xs text-brand-muted leading-relaxed">
              Hackathon prototype. Not an M-PESA banking or payment service.
            </p>
          </div>

          {/* Right: links */}
          <div className="flex flex-wrap gap-x-6 gap-y-2">
            <a
              href={LINKS.github}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 text-sm text-brand-muted hover:text-brand-primary transition-colors"
            >
              <Github className="w-4 h-4" />
              GitHub Repo
            </a>
            <a
              href={LINKS.releases}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 text-sm text-brand-muted hover:text-brand-primary transition-colors"
            >
              <Download className="w-4 h-4" />
              GitHub Releases
            </a>
            <a
              href="#team"
              className="flex items-center gap-1.5 text-sm text-brand-muted hover:text-brand-primary transition-colors"
            >
              <Users className="w-4 h-4" />
              Team
            </a>
          </div>
        </div>

        <div className="mt-8 pt-6 border-t border-gray-50">
          <p className="text-xs text-brand-muted">
            © {year} ChangaSmart. Hackathon prototype — not a real payment service.
          </p>
        </div>
      </div>
    </footer>
  );
}
