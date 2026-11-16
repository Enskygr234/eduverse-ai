import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export interface LessonNode {
  id: string;
  slug: string;
  title: string;
  xpReward: number;
  completed: boolean;
  locked: boolean;
}

@Injectable()
export class CoursesService {
  constructor(private readonly prisma: PrismaService) {}

  listCategories() {
    return this.prisma.category.findMany({
      orderBy: { sortOrder: 'asc' },
      select: { id: true, slug: true, name: true, icon: true, color: true },
    });
  }

  async listCourses(userId: string, categorySlug?: string) {
    const courses = await this.prisma.course.findMany({
      where: { status: 'PUBLISHED', ...(categorySlug ? { category: { slug: categorySlug } } : {}) },
      orderBy: [{ category: { sortOrder: 'asc' } }, { title: 'asc' }],
      include: {
        category: { select: { slug: true, name: true, color: true, icon: true } },
        units: { include: { lessons: { where: { status: 'PUBLISHED' }, select: { id: true } } } },
      },
    });
    const done = await this.completedLessonIds(userId);
    return courses.map((c) => {
      const lessonIds = c.units.flatMap((u) => u.lessons.map((l) => l.id));
      return {
        id: c.id,
        slug: c.slug,
        title: c.title,
        description: c.description,
        level: c.level,
        category: c.category,
        lessonCount: lessonIds.length,
        completedLessons: lessonIds.filter((id) => done.has(id)).length,
      };
    });
  }

  async getCourse(userId: string, slug: string) {
    const course = await this.prisma.course.findFirst({
      where: { slug, status: 'PUBLISHED' },
      include: {
        category: { select: { slug: true, name: true, color: true, icon: true } },
        units: {
          orderBy: { sortOrder: 'asc' },
          include: {
            lessons: {
              where: { status: 'PUBLISHED' },
              orderBy: { sortOrder: 'asc' },
              select: { id: true, slug: true, title: true, xpReward: true },
            },
          },
        },
      },
    });
    if (!course) throw new NotFoundException('Course not found');

    const done = await this.completedLessonIds(userId);
    let previousCompleted = true;
    const units = course.units.map((u) => ({
      id: u.id,
      title: u.title,
      lessons: u.lessons.map((l): LessonNode => {
        const completed = done.has(l.id);
        const node = { ...l, completed, locked: !previousCompleted };
        previousCompleted = completed;
        return node;
      }),
    }));
    const all = units.flatMap((u) => u.lessons);
    return {
      id: course.id,
      slug: course.slug,
      title: course.title,
      description: course.description,
      level: course.level,
      category: course.category,
      lessonCount: all.length,
      completedLessons: all.filter((l) => l.completed).length,
      units,
    };
  }

  /** A lesson is playable if it is the first of its course or the one before it is completed. */
  async assertLessonUnlocked(userId: string, lessonId: string): Promise<void> {
    const lesson = await this.prisma.lesson.findFirst({
      where: { id: lessonId, status: 'PUBLISHED', unit: { course: { status: 'PUBLISHED' } } },
      select: { unit: { select: { course: { select: { slug: true } } } } },
    });
    if (!lesson) throw new NotFoundException('Lesson not found');
    const course = await this.getCourse(userId, lesson.unit.course.slug);
    const node = course.units.flatMap((u) => u.lessons).find((l) => l.id === lessonId);
    if (!node) throw new NotFoundException('Lesson not found');
    if (node.locked) throw new NotFoundException('Lesson is locked');
  }

  private async completedLessonIds(userId: string): Promise<Set<string>> {
    const rows = await this.prisma.lessonProgress.findMany({ where: { userId }, select: { lessonId: true } });
    return new Set(rows.map((r) => r.lessonId));
  }
}
