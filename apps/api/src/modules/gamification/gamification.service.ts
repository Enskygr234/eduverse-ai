import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { applyActivity, lessonXp, levelForXp, localDateString, visibleStreak } from './rules';

type Tx = Prisma.TransactionClient;

const toDate = (isoDate: string) => new Date(`${isoDate}T00:00:00Z`);
const toIso = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : null);

@Injectable()
export class GamificationService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Must run inside the lesson-completion transaction. XP is computed here from
   * server-side grading only; the unique (user, source, attempt) key makes it idempotent.
   */
  async awardLessonXp(
    tx: Tx,
    input: { userId: string; attemptId: string; xpReward: number; correct: number; total: number; firstCompletion: boolean; now: Date },
  ) {
    const profile = await tx.profile.findUniqueOrThrow({ where: { userId: input.userId } });
    const today = localDateString(input.now, profile.timezone);
    const amount = lessonXp(input.xpReward, input.correct, input.total, input.firstCompletion);

    await tx.xpTransaction.create({
      data: {
        userId: input.userId,
        amount,
        source: input.firstCompletion ? 'LESSON_COMPLETION' : 'LESSON_PRACTICE',
        sourceId: input.attemptId,
        localDate: toDate(today),
      },
    });
    const updated = await tx.profile.update({
      where: { userId: input.userId },
      data: { totalXp: { increment: amount } },
    });

    const streakRow = await tx.streak.upsert({ where: { userId: input.userId }, create: { userId: input.userId }, update: {} });
    const next = applyActivity(
      { currentCount: streakRow.currentCount, longestCount: streakRow.longestCount, lastActiveDate: toIso(streakRow.lastActiveDate) },
      today,
    );
    await tx.streak.update({
      where: { userId: input.userId },
      data: {
        currentCount: next.currentCount,
        longestCount: next.longestCount,
        lastActiveDate: next.lastActiveDate ? toDate(next.lastActiveDate) : null,
      },
    });

    return {
      xpAwarded: amount,
      totalXp: updated.totalXp,
      level: levelForXp(updated.totalXp),
      streak: next.currentCount,
    };
  }

  async summary(userId: string, now = new Date()) {
    const profile = await this.prisma.profile.findUniqueOrThrow({ where: { userId } });
    const today = localDateString(now, profile.timezone);
    const [streakRow, todayAgg] = await Promise.all([
      this.prisma.streak.findUnique({ where: { userId } }),
      this.prisma.xpTransaction.aggregate({ where: { userId, localDate: toDate(today) }, _sum: { amount: true } }),
    ]);
    const state = {
      currentCount: streakRow?.currentCount ?? 0,
      longestCount: streakRow?.longestCount ?? 0,
      lastActiveDate: toIso(streakRow?.lastActiveDate ?? null),
    };
    return {
      totalXp: profile.totalXp,
      level: levelForXp(profile.totalXp),
      todayXp: todayAgg._sum.amount ?? 0,
      dailyGoalXp: profile.dailyGoalXp,
      streak: { current: visibleStreak(state, today), longest: state.longestCount, activeToday: state.lastActiveDate === today },
    };
  }
}
