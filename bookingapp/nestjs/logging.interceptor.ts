/**
 * BookingApp HTTP Logging Interceptor
 * 
 * Captures all HTTP requests with:
 * - Request/Response timing
 * - Correlation ID propagation
 * - Error tracking
 * - Performance metrics
 */

import {
    Injectable,
    NestInterceptor,
    ExecutionContext,
    CallHandler,
    HttpException,
    HttpStatus,
} from '@nestjs/common';
import { Observable, throwError } from 'rxjs';
import { tap, catchError } from 'rxjs/operators';
import { APMLoggerService, createRequestContext } from './logger.service';
import { randomUUID } from 'crypto';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
    constructor(private readonly logger: APMLoggerService) {
        this.logger.setContext('HTTP');
    }

    intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
        const ctx = context.switchToHttp();
        const request = ctx.getRequest();
        const response = ctx.getResponse();
        const startTime = Date.now();

        // Generate trace context
        const traceId = request.headers['x-trace-id'] || randomUUID().replace(/-/g, '');
        const correlationId = request.headers['x-correlation-id'] || traceId;
        const requestId = request.headers['x-request-id'] || randomUUID();
        const spanId = randomUUID().replace(/-/g, '').substring(0, 16);

        // Attach to request for downstream use
        request.traceId = traceId;
        request.correlationId = correlationId;
        request.requestId = requestId;
        request.spanId = spanId;

        // Set response headers for tracing
        response.setHeader('X-Request-ID', requestId);
        response.setHeader('X-Trace-ID', traceId);
        response.setHeader('X-Correlation-ID', correlationId);

        // Set request context for logger
        this.logger.setRequestContext(createRequestContext(request));

        // Log incoming request
        this.logger.log(`--> ${request.method} ${request.originalUrl}`, 'HTTP', {
            headers: this.sanitizeHeaders(request.headers),
            query: request.query,
            body: this.sanitizeBody(request.body),
        });

        return next.handle().pipe(
            tap((data) => {
                const duration = Date.now() - startTime;
                const statusCode = response.statusCode;

                // Log successful response
                this.logger.logRequest(
                    request.method,
                    request.originalUrl,
                    statusCode,
                    duration,
                    {
                        responseSize: JSON.stringify(data)?.length || 0,
                        userAgent: request.headers['user-agent'],
                    }
                );

                // Log slow requests
                if (duration > 1000) {
                    this.logger.warn(`Slow request: ${request.method} ${request.originalUrl} took ${duration}ms`, 'Performance');
                }
            }),
            catchError((error) => {
                const duration = Date.now() - startTime;
                const statusCode = error instanceof HttpException
                    ? error.getStatus()
                    : HttpStatus.INTERNAL_SERVER_ERROR;

                // Log error response
                this.logger.error(
                    `<-- ${request.method} ${request.originalUrl} ${statusCode} ${duration}ms - ${error.message}`,
                    error.stack,
                    'HTTP'
                );

                // Add trace context to error for Sentry/Datadog
                if (error instanceof Error) {
                    (error as any).traceId = traceId;
                    (error as any).correlationId = correlationId;
                    (error as any).requestId = requestId;
                }

                return throwError(() => error);
            })
        );
    }

    private sanitizeHeaders(headers: Record<string, any>): Record<string, any> {
        const sensitiveHeaders = ['authorization', 'cookie', 'x-api-key', 'api-key'];
        const sanitized = { ...headers };

        for (const key of sensitiveHeaders) {
            if (sanitized[key]) {
                sanitized[key] = '[REDACTED]';
            }
        }

        return sanitized;
    }

    private sanitizeBody(body: any): any {
        if (!body || typeof body !== 'object') return body;

        const sensitiveFields = ['password', 'token', 'secret', 'apiKey', 'creditCard', 'cvv'];
        const sanitized = { ...body };

        for (const field of sensitiveFields) {
            if (sanitized[field]) {
                sanitized[field] = '[REDACTED]';
            }
        }

        return sanitized;
    }
}

/**
 * Database Query Logging Decorator
 */
export function LogQuery(target: any, propertyKey: string, descriptor: PropertyDescriptor) {
    const originalMethod = descriptor.value;

    descriptor.value = async function (...args: any[]) {
        const logger = new APMLoggerService();
        logger.setContext('Database');

        const startTime = Date.now();
        const queryString = args[0]?.toString().substring(0, 200) || 'Unknown query';

        try {
            const result = await originalMethod.apply(this, args);
            const duration = Date.now() - startTime;
            logger.logDatabaseQuery(queryString, duration, true);
            return result;
        } catch (error) {
            const duration = Date.now() - startTime;
            logger.logDatabaseQuery(queryString, duration, false, { error: (error as Error).message });
            throw error;
        }
    };

    return descriptor;
}

/**
 * Cache Operation Logging Decorator
 */
export function LogCache(operation: 'get' | 'set' | 'del') {
    return function (target: any, propertyKey: string, descriptor: PropertyDescriptor) {
        const originalMethod = descriptor.value;

        descriptor.value = async function (...args: any[]) {
            const logger = new APMLoggerService();
            logger.setContext('Cache');

            const startTime = Date.now();
            const key = args[0]?.toString() || 'unknown';

            try {
                const result = await originalMethod.apply(this, args);
                const duration = Date.now() - startTime;
                const hit = operation === 'get' ? result !== null && result !== undefined : true;
                logger.logCacheOperation(operation, key, hit, duration);
                return result;
            } catch (error) {
                const duration = Date.now() - startTime;
                logger.logCacheOperation(operation, key, false, duration);
                throw error;
            }
        };

        return descriptor;
    };
}

