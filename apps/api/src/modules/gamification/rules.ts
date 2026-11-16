/** Pure gamification rules. No I/O here so they can be unit-tested exhaustively. */

/** XP needed to go from level n to n+1 grows linearly: 50, 100, 150, ... */
export function levelForXp(totalXp: number): { level: number; currentLevelXp: number; nextLevelXp: number } {
  let level = 1;
  let remaining = Math.max(0, Math.floor(totalXp));
  let needed = 50;
  while (remaining >= needed) {
    remaining -= needed;
    level += 1;
    needed = level * 50;
  }
  return { level, currentLevelXp: remaining, nextLevelXp: needed };
}

/** Calendar date (YYYY-MM-DD) of an instant in the user's time zone. Falls back to UTC on bad zones. */
export function localDateString(instant: Date, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(instant);
  } catch {
    return instant.toISOString().slice(0, 10);
  }
}

function dayNumber(isoDate: string): number {
  return Math.floor(Date.parse(`${isoDate}T00:00:00Z`) / 86_400_000);
}

export interface StreakState {
  currentCount: number;
  longestCount: number;
  lastActiveDate: string | null;
}

/** Applies one day of activity. Same day: unchanged. Next day: +1. Gap: restart at 1. */
export function applyActivity(state: StreakState, today: string): StreakState {
  if (state.lastActiveDate === today) return state;
  let current = 1;
  if (state.lastActiveDate && dayNumber(today) - dayNumber(state.lastActiveDate) === 1) {
    current = state.currentCount + 1;
  } else if (state.lastActiveDate && dayNumber(today) < dayNumber(state.lastActiveDate)) {
    return state; // clock skew: never move a streak backwards
  }
  return { currentCount: current, longestCount: Math.max(state.longestCount, current), lastActiveDate: today };
}

/** Streak to display: it is broken if the last activity was before yesterday. */
export function visibleStreak(state: StreakState, today: string): number {
  if (!state.lastActiveDate) return 0;
  return dayNumber(today) - dayNumber(state.lastActiveDate) <= 1 ? state.currentCount : 0;
}

/**
 * XP for a completed lesson. First completion earns the full reward scaled by accuracy
 * (minimum half). Repeats are practice and earn a third, so farming one lesson is not worth it.
 */
export function lessonXp(xpReward: number, correct: number, total: number, firstCompletion: boolean): number {
  if (total <= 0) return 0;
  const accuracy = correct / total;
  const scaled = Math.round(xpReward * Math.max(0.5, accuracy));
  return firstCompletion ? scaled : Math.max(1, Math.round(scaled / 3));
}
