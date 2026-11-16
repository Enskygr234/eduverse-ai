import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CoursesService } from '../courses/courses.service';
import { GamificationService } from '../gamification/gamification.service';
import { OnboardingDto, UpdateProfileDto } from './dto/users.dto';

const LEVEL_RANK = { BEGINNER: 0, INTERMEDIATE: 1, ADVANCED: 2 } as const;

function assertTimezone(tz: string | undefined): void {
  if (!tz) return;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
  } catch {
    throw new BadRequestException('Unknown time zone');
  }
}

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly courses: CoursesService,
    private readonly gamification: GamificationService,
  ) {}

  async me(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { profile: true, roles: { include: { role: true } } },
    });
    const p = user.profile!;
    return {
      id: user.id,
      email: user.email,
      emailVerified: user.emailVerifiedAt !== null,
      roles: user.roles.map((r) => r.role.key),
      profile: {
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        locale: p.locale,
        timezone: p.timezone,
        dailyGoalXp: p.dailyGoalXp,
        learningGoal: p.learningGoal,
        level: p.selfAssessedLevel,
        interests: p.interests,
        onboardingCompleted: p.onboardingCompleted,
        totalXp: p.totalXp,
      },
    };
  }

  async updateProfile(userId: string, dto: UpdateProfileDto) {
    assertTimezone(dto.timezone);
    await this.prisma.profile.update({ where: { userId }, data: dto });
    return this.me(userId);
  }

  /** Saves onboarding answers and builds a rule-based learning plan (AI plans come in Phase 4). */
  async completeOnboarding(userId: string, dto: OnboardingDto) {
    assertTimezone(dto.timezone);
    const known = await this.prisma.category.findMany({ where: { slug: { in: dto.interests } }, select: { slug: true } });
    if (known.length === 0) throw new BadRequestException('Choose at least one existing category');
    const interests = known.map((c) => c.slug);

    const candidates = await this.prisma.course.findMany({
      where: { status: 'PUBLISHED', category: { slug: { in: interests } } },
      select: { slug: true, level: true },
    });
    const userRank = LEVEL_RANK[dto.level];
    const recommended = candidates
      .sort((a, b) => Math.abs(LEVEL_RANK[a.level] - userRank) - Math.abs(LEVEL_RANK[b.level] - userRank))
      .slice(0, 5)
      .map((c) => c.slug);

    const plan = await this.prisma.$transaction(async (tx) => {
      await tx.profile.update({
        where: { userId },
        data: {
          interests,
          learningGoal: dto.learningGoal,
          selfAssessedLevel: dto.level,
          dailyGoalXp: dto.dailyGoalXp,
          onboardingCompleted: true,
          ...(dto.timezone ? { timezone: dto.timezone } : {}),
        },
      });
      await tx.learningPlan.updateMany({ where: { userId, isActive: true }, data: { isActive: false } });
      return tx.learningPlan.create({
        data: { userId, goal: dto.learningGoal, dailyGoalXp: dto.dailyGoalXp, recommendedCourses: recommended },
      });
    });
    return { planId: plan.id, recommendedCourses: recommended, dailyGoalXp: plan.dailyGoalXp };
  }

  async dashboard(userId: string) {
    const [me, stats, plan, lastEnrollment, courses] = await Promise.all([
      this.me(userId),
      this.gamification.summary(userId),
      this.prisma.learningPlan.findFirst({ where: { userId, isActive: true }, orderBy: { createdAt: 'desc' } }),
      this.prisma.courseEnrollment.findFirst({
        where: { userId, completedAt: null },
        orderBy: { lastActivityAt: 'desc' },
        include: { course: { select: { slug: true } } },
      }),
      this.courses.listCourses(userId),
    ]);

    let continueLearning = null;
    const continueSlug = lastEnrollment?.course.slug ?? plan?.recommendedCourses[0];
    if (continueSlug) {
      try {
        const course = await this.courses.getCourse(userId, continueSlug);
        const next = course.units.flatMap((u) => u.lessons).find((l) => !l.completed && !l.locked);
        if (next) {
          continueLearning = {
            course: { slug: course.slug, title: course.title, completedLessons: course.completedLessons, lessonCount: course.lessonCount },
            nextLesson: { id: next.id, title: next.title, xpReward: next.xpReward },
          };
        }
      } catch {
        continueLearning = null; // course was unpublished
      }
    }

    const recommendedSlugs = new Set(plan?.recommendedCourses ?? []);
    const recommended = courses
      .filter((c) => recommendedSlugs.has(c.slug) && c.completedLessons < c.lessonCount)
      .concat(courses.filter((c) => !recommendedSlugs.has(c.slug) && c.completedLessons < c.lessonCount))
      .slice(0, 4);

    return { displayName: me.profile.displayName, ...stats, continueLearning, recommended };
  }
}
