import { applyActivity, lessonXp, levelForXp, localDateString, visibleStreak } from './rules';

describe('levelForXp', () => {
  it('starts at level 1', () => {
    expect(levelForXp(0)).toEqual({ level: 1, currentLevelXp: 0, nextLevelXp: 50 });
  });
  it('levels up at 50 and 150', () => {
    expect(levelForXp(49).level).toBe(1);
    expect(levelForXp(50)).toEqual({ level: 2, currentLevelXp: 0, nextLevelXp: 100 });
    expect(levelForXp(150)).toEqual({ level: 3, currentLevelXp: 0, nextLevelXp: 150 });
  });
  it('ignores negative input', () => {
    expect(levelForXp(-10).level).toBe(1);
  });
});

describe('localDateString', () => {
  it('uses the user time zone', () => {
    const instant = new Date('2026-11-15T22:30:00Z');
    expect(localDateString(instant, 'Europe/Istanbul')).toBe('2026-11-16');
    expect(localDateString(instant, 'UTC')).toBe('2026-11-15');
  });
  it('falls back to UTC for an invalid zone', () => {
    expect(localDateString(new Date('2026-01-02T03:00:00Z'), 'Not/AZone')).toBe('2026-01-02');
  });
});

describe('streaks', () => {
  const empty = { currentCount: 0, longestCount: 0, lastActiveDate: null };

  it('starts at 1', () => {
    expect(applyActivity(empty, '2026-11-16')).toEqual({ currentCount: 1, longestCount: 1, lastActiveDate: '2026-11-16' });
  });
  it('does not double count the same day', () => {
    const s = applyActivity(empty, '2026-11-16');
    expect(applyActivity(s, '2026-11-16')).toBe(s);
  });
  it('increments on consecutive days, including month boundaries', () => {
    let s = applyActivity(empty, '2026-10-30');
    s = applyActivity(s, '2026-10-31');
    s = applyActivity(s, '2026-11-01');
    expect(s.currentCount).toBe(3);
    expect(s.longestCount).toBe(3);
  });
  it('resets after a gap but keeps the record', () => {
    let s = applyActivity(empty, '2026-11-01');
    s = applyActivity(s, '2026-11-02');
    s = applyActivity(s, '2026-11-05');
    expect(s).toEqual({ currentCount: 1, longestCount: 2, lastActiveDate: '2026-11-05' });
  });
  it('never moves backwards on clock skew', () => {
    const s = applyActivity(empty, '2026-11-10');
    expect(applyActivity(s, '2026-11-09')).toBe(s);
  });
  it('shows 0 once a day was missed', () => {
    const s = applyActivity(empty, '2026-11-10');
    expect(visibleStreak(s, '2026-11-11')).toBe(1);
    expect(visibleStreak(s, '2026-11-12')).toBe(0);
  });
});

describe('lessonXp', () => {
  it('gives full reward for a perfect first completion', () => {
    expect(lessonXp(10, 4, 4, true)).toBe(10);
  });
  it('scales with accuracy but never below half', () => {
    expect(lessonXp(10, 3, 4, true)).toBe(8);
    expect(lessonXp(10, 0, 4, true)).toBe(5);
  });
  it('gives a third for practice repeats', () => {
    expect(lessonXp(15, 4, 4, false)).toBe(5);
    expect(lessonXp(1, 0, 4, false)).toBe(1);
  });
  it('gives nothing for an empty lesson', () => {
    expect(lessonXp(10, 0, 0, true)).toBe(0);
  });
});
