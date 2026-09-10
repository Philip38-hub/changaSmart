import { useEffect, useState } from 'react';
import { Github, Download } from 'lucide-react';
import { LINKS } from '@/constants';

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header
      className={`fixed top-0 inset-x-0 z-50 transition-all duration-300 ${
        scrolled
          ? 'bg-white/90 backdrop-blur-md shadow-soft'
          : 'bg-transparent'
      }`}
    >
      <nav className="max-w-6xl mx-auto px-5 sm:px-6 h-16 flex items-center justify-between">
        <a href="#top" className="flex items-center gap-2 group">
          <span className="w-8 h-8 rounded-xl bg-brand-primary flex items-center justify-center text-white font-bold text-sm shadow-soft transition-transform group-hover:scale-105">
            C
          </span>
          <span className="font-bold text-lg text-brand-ink tracking-tight">
            ChangaSmart
          </span>
        </a>

        <div className="flex items-center gap-2 sm:gap-3">
          <a
            href={LINKS.github}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-3 sm:px-4 h-9 rounded-xl text-sm font-medium text-brand-ink hover:bg-brand-primaryLight transition-colors"
          >
            <Github className="w-4 h-4" />
            <span className="hidden sm:inline">GitHub</span>
          </a>
          <a
            href={LINKS.releases}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 px-4 sm:px-5 h-9 rounded-xl text-sm font-semibold text-white bg-brand-primary hover:bg-brand-primaryDark transition-colors shadow-soft"
          >
            <Download className="w-4 h-4" />
            <span>Download APK</span>
          </a>
        </div>
      </nav>
    </header>
  );
}
