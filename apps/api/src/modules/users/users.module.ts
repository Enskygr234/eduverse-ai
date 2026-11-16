import { Module } from '@nestjs/common';
import { CoursesModule } from '../courses/courses.module';
import { GamificationModule } from '../gamification/gamification.module';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [CoursesModule, GamificationModule],
  controllers: [UsersController],
  providers: [UsersService],
})
export class UsersModule {}
