export const LINKS = {
  github: 'https://github.com/Philip38-hub/changaSmart',
  releases: 'https://github.com/Philip38-hub/changaSmart/releases/latest',
} as const;

export const API_BASE =
  'https://5l95fhljcc.execute-api.us-east-1.amazonaws.com/dev';

export const POLL_INTERVAL_MS = 30_000;

export type ProjectSummary = {
  id: string;
  name: string;
  target_amount: number | null;
  status: string;
  created_at: string;
};

export type CollectionSummary = {
  id: string;
  name: string;
  target_amount: number | null;
  status: string;
};

export type CollectionReport = {
  total_received: number;
  target_amount: number | null;
  remaining_amount: number | null;
};

export type RankedProject = {
  id: string;
  name: string;
  raised: number;
  target: number | null;
};
