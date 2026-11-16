import 'reflect-metadata';
import type { IncomingMessage, ServerResponse } from 'http';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApp } from './bootstrap';

type RequestListener = (req: IncomingMessage, res: ServerResponse) => void;

// One Nest app per warm serverless instance; cold starts build it once.
let server: Promise<RequestListener> | undefined;

async function createServer(): Promise<RequestListener> {
  const app = await NestFactory.create(AppModule, { logger: ['error', 'warn', 'log'] });
  configureApp(app);
  await app.init();
  return app.getHttpAdapter().getInstance() as RequestListener;
}

/** Vercel Node.js function entry point (see apps/api/api/index.js). */
export async function handler(req: IncomingMessage, res: ServerResponse): Promise<void> {
  server ??= createServer().catch((err) => {
    server = undefined; // retry on the next request instead of caching a failure
    throw err;
  });
  const listener = await server;
  listener(req, res);
}
