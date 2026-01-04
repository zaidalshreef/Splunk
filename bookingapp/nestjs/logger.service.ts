/**
 * BookingApp APM Logger Service
 * 
 * Structured JSON logging with:
 * - Request ID / Correlation ID / Trace ID
 * - Performance metrics (duration, memory)
 * - Error tracking with stack traces
 * - Context propagation
 * 
 * Compatible with: Splunk, Datadog, Sentry
 */

import { Injectable, LoggerService, Scope } from '@nestjs/common';
import { randomUUID } from 'crypto';

export interface LogContext {
    requestId?: string;
    traceId?: string;
    correlationId?: string;
    spanId?: string;
    userId?: string;
    sessionId?: string;
    method?: string;
    url?: string;
    statusCode?: number;
    duration?: number;
    userAgent?: string;
    ip?: string;
    [key: string]: any;
}

export interface LogEntry {
    timestamp: string;
    level: string;
    message: string;
    context?: string;
    service: string;
    version: string;
    environment: string;
    host: string;
    pid: number;
    requestId?: string;
    traceId?: string;
    correlationId?: string;
    spanId?: string;
    userId?: string;
    method?: string;
    url?: string;
    statusCode?: number;
    duration?: number;
    error?: {
        name: string;
        message: string;
        stack?: string;
        code?: string;
    };
    metadata?: Record<string, any>;
    memory?: {
        heapUsed: number;
        heapTotal: number;
        external: number;
        rss: number;
    };
}

@Injectable({ scope: Scope.TRANSIENT })
export class APMLoggerService implements LoggerService {
    private context: string = 'Application';
    private requestContext: LogContext = {};

    private readonly serviceName = process.env.SERVICE_NAME || 'bookingapp-api';
    private readonly serviceVersion = process.env.SERVICE_VERSION || '1.0.0';
    private readonly environment = process.env.ENVIRONMENT || process.env.NODE_ENV || 'development';
    private readonly hostname = process.env.HOSTNAME || 'unknown';

    setContext(context: string) {
        this.context = context;
        return this;
    }

    setRequestContext(ctx: LogContext) {
        this.requestContext = { ...this.requestContext, ...ctx };
        return this;
    }

    generateTraceId(): string {
        return randomUUID().replace(/-/g, '');
    }

    generateSpanId(): string {
        return randomUUID().replace(/-/g, '').substring(0, 16);
    }

    private formatLog(level: string, message: string, context?: string, meta?: any): LogEntry {
        const memUsage = process.memoryUsage();

        const entry: LogEntry = {
            timestamp: new Date().toISOString(),
            level: level.toLowerCase(),
            message,
            context: context || this.context,
            service: this.serviceName,
            version: this.serviceVersion,
            environment: this.environment,
            host: this.hostname,
            pid: process.pid,
            ...this.requestContext,
            memory: {
                heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024),
                heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024),
                external: Math.round(memUsage.external / 1024 / 1024),
                rss: Math.round(memUsage.rss / 1024 / 1024),
            },
        };

        if (meta) {
            if (meta instanceof Error) {
                entry.error = {
                    name: meta.name,
                    message: meta.message,
                    stack: meta.stack,
                    code: (meta as any).code,
                };
            } else if (typeof meta === 'object') {
                entry.metadata = meta;
            }
        }

        return entry;
    }

    private output(entry: LogEntry) {
        const json = JSON.stringify(entry);

        if (entry.level === 'error' || entry.level === 'fatal') {
            process.stderr.write(json + '\n');
        } else {
            process.stdout.write(json + '\n');
        }
    }

    log(message: string, context?: string, meta?: any) {
        this.output(this.formatLog('info', message, context, meta));
    }

    error(message: string, trace?: string, context?: string) {
        const entry = this.formatLog('error', message, context);
        if (trace) {
            entry.error = {
                name: 'Error',
                message: message,
                stack: trace,
            };
        }
        this.output(entry);
    }

    warn(message: string, context?: string, meta?: any) {
        this.output(this.formatLog('warn', message, context, meta));
    }

    debug(message: string, context?: string, meta?: any) {
        if (this.environment !== 'production') {
            this.output(this.formatLog('debug', message, context, meta));
        }
    }

    verbose(message: string, context?: string, meta?: any) {
        if (this.environment !== 'production') {
            this.output(this.formatLog('trace', message, context, meta));
        }
    }

    fatal(message: string, context?: string, meta?: any) {
        this.output(this.formatLog('fatal', message, context, meta));
    }

    // APM-specific methods

    logRequest(method: string, url: string, statusCode: number, duration: number, meta?: any) {
        const entry = this.formatLog('info', `${method} ${url} ${statusCode} ${duration}ms`, 'HTTP');
        entry.method = method;
        entry.url = url;
        entry.statusCode = statusCode;
        entry.duration = duration;
        if (meta) entry.metadata = meta;
        this.output(entry);
    }

    logDatabaseQuery(query: string, duration: number, success: boolean, meta?: any) {
        const level = success ? 'debug' : 'error';
        const entry = this.formatLog(level, `DB Query: ${duration}ms`, 'Database');
        entry.duration = duration;
        entry.metadata = { query: query.substring(0, 500), ...meta };
        this.output(entry);
    }

    logCacheOperation(operation: string, key: string, hit: boolean, duration: number) {
        const entry = this.formatLog('debug', `Cache ${operation}: ${hit ? 'HIT' : 'MISS'}`, 'Cache');
        entry.duration = duration;
        entry.metadata = { operation, key, hit };
        this.output(entry);
    }

    logExternalCall(service: string, method: string, url: string, statusCode: number, duration: number) {
        const level = statusCode >= 400 ? 'error' : 'info';
        const entry = this.formatLog(level, `External ${service}: ${method} ${statusCode} ${duration}ms`, 'External');
        entry.duration = duration;
        entry.statusCode = statusCode;
        entry.metadata = { service, method, url };
        this.output(entry);
    }

    logMetric(name: string, value: number, tags?: Record<string, string>) {
        const entry = this.formatLog('info', `Metric: ${name}=${value}`, 'Metrics');
        entry.metadata = { metric_name: name, metric_value: value, tags };
        this.output(entry);
    }
}

/**
 * Request context middleware factory
 */
export function createRequestContext(req: any): LogContext {
    const traceId = req.headers['x-trace-id'] || randomUUID().replace(/-/g, '');
    const correlationId = req.headers['x-correlation-id'] || traceId;
    const requestId = req.headers['x-request-id'] || randomUUID();

    return {
        requestId,
        traceId,
        correlationId,
        spanId: randomUUID().replace(/-/g, '').substring(0, 16),
        method: req.method,
        url: req.originalUrl || req.url,
        userAgent: req.headers['user-agent'],
        ip: req.headers['x-forwarded-for'] || req.ip || req.connection?.remoteAddress,
        userId: req.user?.id,
        sessionId: req.session?.id,
    };
}

