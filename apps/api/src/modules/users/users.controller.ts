import { Body, Controller, Get, Patch, Put } from '@nestjs/common';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { OnboardingDto, UpdateProfileDto } from './dto/users.dto';
import { UsersService } from './users.service';

@Controller('me')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  me(@CurrentUser() user: AuthUser) {
    return this.users.me(user.id);
  }

  @Patch('profile')
  updateProfile(@CurrentUser() user: AuthUser, @Body() dto: UpdateProfileDto) {
    return this.users.updateProfile(user.id, dto);
  }

  @Put('onboarding')
  onboarding(@CurrentUser() user: AuthUser, @Body() dto: OnboardingDto) {
    return this.users.completeOnboarding(user.id, dto);
  }

  @Get('dashboard')
  dashboard(@CurrentUser() user: AuthUser) {
    return this.users.dashboard(user.id);
  }
}
