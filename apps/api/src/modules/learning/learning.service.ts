import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditService } from '../../common/audit/audit.service';
import { CoursesService } from '../courses/courses.service';
import { GamificationService } from '../gamification/gamification.service';
import { grade, InvalidAnswerError } from './grader';

@Injectable()
export class LearningService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly courses: CoursesService,
    private readonly gamification: GamificationService,
    private readonly audit: AuditService,
  ) {}

  /** Lesson content for playing. Answer keys are never included. */
  async getLesson(userId: string, lessonId: string) {
    await this.courses.assertLessonUnlocked(userId, lessonId);
    const lesson = await this.prisma.lesson.findUniqueOrThrow({
      where: { id: lessonId },
      include: {
        questions: {
          where: { status: 'PUBLISHED' },
          orderBy: { sortOrder: 'asc' },
          select: { id: true, type: true, prompt: true, payload: true },
        },
        unit: { select: { course: { select: { slug: true, title: true } } } },
      },
    });
    return {
      id: lesson.id,
      slug: lesson.slug,
      title: lesson.title,
      explanation: lesson.explanation,
      examples: lesson.examples,
      xpReward: lesson.xpReward,
      course: lesson.unit.course,
      questions: lesson.questions,
    };
  }

  async startAttempt(userId: string, lessonId: string) {
    await this.courses.assertLessonUnlocked(userId, lessonId);
    const total = await this.prisma.question.count({ where: { lessonId, status: 'PUBLISHED' } });
    if (total === 0) throw new BadRequestException('Lesson has no questions');
    const attempt = await this.prisma.lessonAttempt.create({ data: { userId, lessonId, totalCount: total } });
    return { attemptId: attempt.id, totalQuestions: total };
  }

  async submitAnswer(userId: string, attemptId: string, questionId: string, response: Record<string, unknown>) {
    const attempt = await this.ownedAttempt(userId, attemptId);
    if (attempt.status !== 'IN_PROGRESS') throw new ConflictException('Attempt is already finished');

    const question = await this.prisma.question.findFirst({
      where: { id: questionId, lessonId: attempt.lessonId, status: 'PUBLISHED' },
    });
    if (!question) throw new NotFoundException('Question not found in this lesson');

    let result;
    try {
      result = grade(question.type, question.payload, question.answerKey, response);
    } catch (err) {
      if (err instanceof InvalidAnswerError) throw new BadRequestException(err.message);
      throw err;
    }

    try {
      await this.prisma.questionAnswer.create({
        data: { attemptId, questionId, response: response as Prisma.InputJsonValue, isCorrect: result.correct },
      });
    } catch (err) {
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new ConflictException('Question already answered in this attempt');
      }
      throw err;
    }
    return { correct: result.correct, correctAnswer: result.correctAnswer, explanation: question.explanation };
  }

  /**
   * Finishes an attempt and awards XP in one transaction. Safe against double submits:
   * the status flip is conditional and the XP row is unique per attempt.
   */
  async completeAttempt(userId: string, attemptId: string) {
    const attempt = await this.ownedAttempt(userId, attemptId);
    if (attempt.status === 'COMPLETED') throw new ConflictException('Attempt is already completed');

    const result = await this.prisma.$transaction(async (tx) => {
      const claimed = await tx.lessonAttempt.updateMany({
        where: { id: attemptId, userId, status: 'IN_PROGRESS' },
        data: { status: 'COMPLETED', completedAt: new Date() },
      });
      if (claimed.count === 0) throw new ConflictException('Attempt is already completed');

      const [answers, questionCount, lesson] = await Promise.all([
        tx.questionAnswer.findMany({ where: { attemptId }, select: { isCorrect: true } }),
        tx.question.count({ where: { lessonId: attempt.lessonId, status: 'PUBLISHED' } }),
        tx.lesson.findUniqueOrThrow({
          where: { id: attempt.lessonId },
          select: { id: true, xpReward: true, unit: { select: { courseId: true } } },
        }),
      ]);
      if (answers.length < questionCount) {
        throw new BadRequestException(`All questions must be answered (${answers.length}/${questionCount})`);
      }
      const correct = answers.filter((a) => a.isCorrect).length;
      const accuracy = Math.round((correct / questionCount) * 100);

      const existing = await tx.lessonProgress.findUnique({
        where: { userId_lessonId: { userId, lessonId: lesson.id } },
      });
      const now = new Date();
      if (existing) {
        await tx.lessonProgress.update({
          where: { userId_lessonId: { userId, lessonId: lesson.id } },
          data: {
            timesCompleted: { increment: 1 },
            bestAccuracy: Math.max(existing.bestAccuracy, accuracy),
            lastCompletedAt: now,
          },
        });
      } else {
        await tx.lessonProgress.create({
          data: { userId, lessonId: lesson.id, timesCompleted: 1, bestAccuracy: accuracy },
        });
      }

      const reward = await this.gamification.awardLessonXp(tx, {
        userId,
        attemptId,
        xpReward: lesson.xpReward,
        correct,
        total: questionCount,
        firstCompletion: !existing,
        now,
      });

      await tx.lessonAttempt.update({
        where: { id: attemptId },
        data: { correctCount: correct, totalCount: questionCount, xpAwarded: reward.xpAwarded },
      });
      await this.touchEnrollment(tx, userId, lesson.unit.courseId, now);
      await this.audit.log('lesson.completed', {
        userId,
        tx,
        metadata: { attemptId, lessonId: lesson.id, correct, total: questionCount, xp: reward.xpAwarded },
      });

      return { correctCount: correct, totalCount: questionCount, accuracy, firstCompletion: !existing, ...reward };
    });
    return result;
  }

  private async touchEnrollment(tx: Prisma.TransactionClient, userId: string, courseId: string, now: Date) {
    const [lessonIds, doneCount] = await Promise.all([
      tx.lesson.findMany({ where: { status: 'PUBLISHED', unit: { courseId } }, select: { id: true } }),
      tx.lessonProgress.count({ where: { userId, lesson: { status: 'PUBLISHED', unit: { courseId } } } }),
    ]);
    const completedAt = lessonIds.length > 0 && doneCount >= lessonIds.length ? now : null;
    await tx.courseEnrollment.upsert({
      where: { userId_courseId: { userId, courseId } },
      create: { userId, courseId, lastActivityAt: now, completedAt },
      update: { lastActivityAt: now, ...(completedAt ? { completedAt } : {}) },
    });
  }

  private async ownedAttempt(userId: string, attemptId: string) {
    const attempt = await this.prisma.lessonAttempt.findUnique({ where: { id: attemptId } });
    // Same error for "missing" and "someone else's" so ids cannot be probed.
    if (!attempt || attempt.userId !== userId) throw new NotFoundException('Attempt not found');
    return attempt;
  }
}
