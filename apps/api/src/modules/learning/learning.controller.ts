import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { LearningService } from './learning.service';
import { SubmitAnswerDto } from './dto/learning.dto';

@Controller()
export class LearningController {
  constructor(private readonly learning: LearningService) {}

  @Get('lessons/:id')
  lesson(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.learning.getLesson(user.id, id);
  }

  @Post('lessons/:id/attempts')
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  start(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.learning.startAttempt(user.id, id);
  }

  @Post('attempts/:id/answers')
  @HttpCode(200)
  answer(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SubmitAnswerDto) {
    return this.learning.submitAnswer(user.id, id, dto.questionId, dto.response);
  }

  @Post('attempts/:id/complete')
  @HttpCode(200)
  complete(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.learning.completeAttempt(user.id, id);
  }
}
