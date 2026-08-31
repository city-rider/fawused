import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api/v1');
  app.enableCors({ origin: true, credentials: true });
  const port = Number(process.env.API_PORT ?? 4000);
  await app.listen(port, '0.0.0.0');
  console.log(`FAWUsed API listening on http://localhost:${port}/api/v1`);
}
bootstrap();
