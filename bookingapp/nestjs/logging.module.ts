/**
 * BookingApp Logging Module
 * 
 * Provides:
 * - APM Logger Service
 * - HTTP Logging Interceptor
 * - Database Query Logging
 * - Cache Operation Logging
 */

import { Module, Global, DynamicModule } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { APMLoggerService } from './logger.service';
import { LoggingInterceptor } from './logging.interceptor';

export interface LoggingModuleOptions {
    serviceName?: string;
    enableRequestLogging?: boolean;
    enableDatabaseLogging?: boolean;
    enableCacheLogging?: boolean;
}

@Global()
@Module({})
export class LoggingModule {
    static forRoot(options: LoggingModuleOptions = {}): DynamicModule {
        const providers: any[] = [
            APMLoggerService,
            {
                provide: 'LOGGING_OPTIONS',
                useValue: options,
            },
        ];

        if (options.enableRequestLogging !== false) {
            providers.push({
                provide: APP_INTERCEPTOR,
                useClass: LoggingInterceptor,
            });
        }

        return {
            module: LoggingModule,
            providers,
            exports: [APMLoggerService, 'LOGGING_OPTIONS'],
        };
    }
}

/**
 * Usage in main.ts:
 * 
 * import { NestFactory } from '@nestjs/core';
 * import { APMLoggerService } from './logging/logger.service';
 * 
 * async function bootstrap() {
 *   const app = await NestFactory.create(AppModule, {
 *     bufferLogs: true,
 *   });
 *   
 *   const logger = app.get(APMLoggerService);
 *   app.useLogger(logger);
 *   
 *   await app.listen(5000);
 * }
 * 
 * Usage in AppModule:
 * 
 * @Module({
 *   imports: [
 *     LoggingModule.forRoot({
 *       serviceName: 'bookingapp-api',
 *       enableRequestLogging: true,
 *       enableDatabaseLogging: true,
 *       enableCacheLogging: true,
 *     }),
 *   ],
 * })
 * export class AppModule {}
 */

