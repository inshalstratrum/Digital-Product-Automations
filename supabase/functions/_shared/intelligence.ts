export type IdeaMetrics = {
  demand: number;
  competition: number;
  feasibility: number;
  founder_fit: number;
  evidence_quality: number;
};

export type IdeaScore = { score: number; breakdown: Record<string, number>; method: string };
export type FeedbackClassification = {
  issue_type: string;
  severity: "low" | "medium" | "high" | "critical";
  sentiment: number;
  tags: string[];
  method: string;
};

function bounded(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.min(100, parsed));
}

export function deterministicIdeaScore(input: Partial<IdeaMetrics>): IdeaScore {
  const demand = bounded(input.demand);
  const competitionOpportunity = 100 - bounded(input.competition);
  const feasibility = bounded(input.feasibility);
  const founderFit = bounded(input.founder_fit);
  const evidenceQuality = bounded(input.evidence_quality);
  const score = demand * 0.30 + competitionOpportunity * 0.25 + feasibility * 0.20 + founderFit * 0.15 + evidenceQuality * 0.10;
  return {
    score: Math.round(score * 100) / 100,
    breakdown: { demand, competition_opportunity: competitionOpportunity, feasibility, founder_fit: founderFit, evidence_quality: evidenceQuality },
    method: "weighted_evidence_v1",
  };
}

export function deterministicFeedbackClassification(note: string, rating?: number | null): FeedbackClassification {
  const text = note.toLowerCase();
  const critical = /(charged twice|data leak|security|fraud|malware|cannot access.*paid|legal threat)/.test(text);
  const bug = /(broken|error|doesn.t work|not working|missing file|corrupt|can.t open|cannot open)/.test(text);
  const refund = /(refund|money back|cancel)/.test(text);
  const request = /(please add|feature|would like|could you include|suggest)/.test(text);
  const issue_type = critical ? "risk" : refund ? "refund" : bug ? "product_issue" : request ? "feature_request" : "general";
  const severity = critical ? "critical" : rating === 1 || refund ? "high" : rating === 2 || bug ? "medium" : "low";
  const sentiment = rating ? Math.max(-1, Math.min(1, (rating - 3) / 2)) : /(love|great|excellent|helpful)/.test(text) ? 0.7 : bug || refund ? -0.7 : 0;
  const tags = [issue_type, ...(rating ? [`rating_${rating}`] : [])];
  return { issue_type, severity, sentiment, tags, method: "keyword_rules_v1" };
}
