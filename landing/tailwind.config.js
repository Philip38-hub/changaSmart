/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          primary: '#1B7A4B',
          primaryDark: '#155A37',
          primaryLight: '#E8F3EC',
          confirmed: '#1E8E5A',
          amber: '#B5680A',
          orange: '#D9740B',
          danger: '#B3261E',
          bg: '#F7F8F6',
          bgCard: '#FFFFFF',
          ink: '#1A2E22',
          muted: '#5A6B5F',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      borderRadius: {
        xl2: '16px',
      },
      boxShadow: {
        soft: '0 2px 8px rgba(27, 122, 75, 0.06)',
        card: '0 4px 24px rgba(27, 122, 75, 0.08)',
        lift: '0 8px 32px rgba(27, 122, 75, 0.12)',
      },
      keyframes: {
        'fade-up': {
          '0%': { opacity: '0', transform: 'translateY(24px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        shimmer: {
          '0%': { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        'pulse-dot': {
          '0%, 100%': { opacity: '1', transform: 'scale(1)' },
          '50%': { opacity: '0.5', transform: 'scale(0.85)' },
        },
      },
      animation: {
        'fade-up': 'fade-up 0.6s ease-out forwards',
        shimmer: 'shimmer 1.5s linear infinite',
        'pulse-dot': 'pulse-dot 1.5s ease-in-out infinite',
      },
    },
  },
  plugins: [],
};
