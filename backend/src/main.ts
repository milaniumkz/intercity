import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { join } from 'path';
import { AppModule } from './app.module';
import { AdminService } from './admin/admin.service';

async function bootstrap() {
    const app = await NestFactory.create<NestExpressApplication>(AppModule);
    const adminService = app.get(AdminService, { strict: false });
    const corsOriginsRaw = (process.env.CORS_ORIGINS || '').trim();
    const corsOrigins = corsOriginsRaw
        ? corsOriginsRaw.split(',').map((item) => item.trim()).filter(Boolean)
        : ['*'];
    const allowAllOrigins = corsOrigins.length === 1 && corsOrigins[0] === '*';

    const originalConsoleError = console.error.bind(console);
    console.error = (...args: any[]) => {
        try {
            adminService?.recordError({
                at: new Date().toISOString(),
                source: 'console',
                message: args.map((item) => String(item)).join(' ').slice(0, 2000),
            });
        } catch (_) {
            // Keep console behavior intact even if logging fails.
        }
        originalConsoleError(...args);
    };

    app.use((req: any, res: any, next: () => void) => {
        const started = Date.now();
        res.on('finish', () => {
            const rawPath = typeof req.originalUrl === 'string' ? req.originalUrl : req.url;
            const path = (rawPath || '').split('?')[0] || '/';
            adminService?.recordHttpRequest({
                at: new Date().toISOString(),
                method: req.method || 'GET',
                path,
                statusCode: res.statusCode || 0,
                durationMs: Date.now() - started,
                ip: req.ip,
                userAgent: req.headers?.['user-agent'],
            });
        });
        next();
    });

    app.enableCors({
        origin: allowAllOrigins ? true : corsOrigins,
        methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
        credentials: !allowAllOrigins,
    });

    app.useGlobalPipes(new ValidationPipe({
        whitelist: true,
        transform: true,
    }));

    app.useStaticAssets(process.env.UPLOAD_DIR || join(process.cwd(), 'uploads'), {
        prefix: '/uploads/',
    });

    app.setGlobalPrefix('api');

    const config = new DocumentBuilder()
        .setTitle('INTERCITY API')
        .setDescription('INTERCITY Ride Sharing API')
        .setVersion('1.0')
        .addBearerAuth()
        .build();
    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup('api/docs', app, document);

    const port = process.env.PORT || 3000;
    await app.listen(port);
    console.log(`INTERCITY API running on port ${port}`);
}
bootstrap();
