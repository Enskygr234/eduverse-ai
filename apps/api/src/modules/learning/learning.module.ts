import { Module } from '@nestjs/common';
import { CoursesModule } from '../courses/courses.module';
import { GamificationModule } from '../gamification/gamification.module';
import { LearningController } from './learning.controller';
import { LearningService } from './learning.service';

@Module({
  imports: [CoursesModule, GamificationModule],
  controllers: [LearningController],
  providers: [LearningService],
})
export class LearningModule {}
