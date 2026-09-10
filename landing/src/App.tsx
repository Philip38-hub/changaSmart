import { Navbar } from '@/components/Navbar';
import { Hero } from '@/components/Hero';
import { LiveProjects } from '@/components/LiveProjects';
import { Problem } from '@/components/Problem';
import { HowItWorks } from '@/components/HowItWorks';
import { Features } from '@/components/Features';
import { TechStack } from '@/components/TechStack';
import { Team } from '@/components/Team';
import { FinalCTA } from '@/components/FinalCTA';
import { Footer } from '@/components/Footer';

function App() {
  return (
    <div className="min-h-screen bg-brand-bg">
      <Navbar />
      <main>
        <Hero />
        <LiveProjects />
        <Problem />
        <HowItWorks />
        <Features />
        <TechStack />
        <Team />
        <FinalCTA />
      </main>
      <Footer />
    </div>
  );
}

export default App;
