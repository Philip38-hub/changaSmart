import { Reveal } from '@/components/Reveal';

const stack = [
  'Flutter',
  'FastAPI',
  'AWS Lambda',
  'Amazon Bedrock',
  'API Gateway',
];

export function TechStack() {
  return (
    <section className="py-12 sm:py-16">
      <div className="max-w-4xl mx-auto px-5 sm:px-6">
        <Reveal>
          <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
            {stack.map((tech) => (
              <span
                key={tech}
                className="px-4 py-2 rounded-xl bg-white border border-gray-100 text-sm font-medium text-brand-muted shadow-soft"
              >
                {tech}
              </span>
            ))}
          </div>
          <p className="mt-5 text-center text-sm text-brand-muted">
            Built for the hackathon on a serverless AWS stack.
          </p>
        </Reveal>
      </div>
    </section>
  );
}
