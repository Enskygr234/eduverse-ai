import { Transform } from 'class-transformer';
import type { CourseLevel } from '@prisma/client';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

export const DAILY_GOALS = [10, 20, 30, 50] as const;
export const LEARNING_GOALS = ['career', 'school', 'travel', 'hobby', 'brain_training'] as const;
export const LEVELS: CourseLevel[] = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED'];

export class OnboardingDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @Matches(/^[a-z0-9-]{1,80}$/, { each: true })
  interests: string[];

  @IsIn(LEARNING_GOALS)
  learningGoal: (typeof LEARNING_GOALS)[number];

  @IsIn(LEVELS)
  level: CourseLevel;

  @IsIn(DAILY_GOALS)
  dailyGoalXp: number;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  timezone?: string;
}

export class UpdateProfileDto {
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MinLength(2)
  @MaxLength(40)
  displayName?: string;

  @IsOptional()
  @IsIn(DAILY_GOALS)
  dailyGoalXp?: number;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  timezone?: string;
}
