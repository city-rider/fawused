import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { HealthModule } from './health/health.module';
import { AuthModule } from './auth/auth.module';
import { ListingsModule } from './listings/listings.module';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), HealthModule, AuthModule, ListingsModule],
})
export class AppModule {}
