const admin = require('firebase-admin');
const functions = require('firebase-functions');

// Simple in-memory rate limiter (token buckets per user+callName)
// Note: Per-instance only. For multi-instance consistency we also write violation docs.
const RATE_LIMITS = { perSecond: 10, perMinute: 60 };
const buckets = new Map(); // key => { secondWindowStart, secondCount, minuteWindowStart, minuteCount }

function checkRateLimit(uid, callName) {
    const now = Date.now();
    const key = `${uid}:${callName}`;
    const b = buckets.get(key) || { secondWindowStart: now, secondCount: 0, minuteWindowStart: now, minuteCount: 0 };

    // Reset windows
    if (now - b.secondWindowStart >= 1000) { b.secondWindowStart = now; b.secondCount = 0; }
    if (now - b.minuteWindowStart >= 60000) { b.minuteWindowStart = now; b.minuteCount = 0; }

    b.secondCount += 1;
    b.minuteCount += 1;
    buckets.set(key, b);

    const overSecond = b.secondCount > RATE_LIMITS.perSecond;
    const overMinute = b.minuteCount > RATE_LIMITS.perMinute;
    if (overSecond || overMinute) {
        return { allowed: false, reason: overSecond ? 'per-second' : 'per-minute', counts: { second: b.secondCount, minute: b.minuteCount } };
    }
    return { allowed: true };
}

async function logViolation(db, uid, callName, reason, counts) {
    try {
        await db.collection('rate_limit_violations').add({
            uid,
            call: callName,
            reason,
            counts,
            ts: admin.firestore.FieldValue.serverTimestamp()
        });
    } catch (e) {
        console.warn('[rate-limit] failed to log violation', e.message);
    }
}

// Input validation schemas (lightweight, no external deps)
function validate(callName, vars) {
    switch (callName) {
        case 'runShiftMatching': {
            if (vars.startDate && !/^\d{4}-\d{2}-\d{2}$/.test(vars.startDate)) throw new Error('startDate must be YYYY-MM-DD');
            if (vars.endDate && !/^\d{4}-\d{2}-\d{2}$/.test(vars.endDate)) throw new Error('endDate must be YYYY-MM-DD');
            if (vars.dryRun != null && typeof vars.dryRun !== 'boolean') throw new Error('dryRun must be boolean');
            return;
        }
        case 'getMatchedSchedules': {
            if (vars.startDate && !/^\d{4}-\d{2}-\d{2}$/.test(vars.startDate)) throw new Error('startDate must be YYYY-MM-DD');
            if (vars.endDate && !/^\d{4}-\d{2}-\d{2}$/.test(vars.endDate)) throw new Error('endDate must be YYYY-MM-DD');
            if (vars.residentId && typeof vars.residentId !== 'string') throw new Error('residentId must be string');
            if (vars.attendingId && typeof vars.attendingId !== 'string') throw new Error('attendingId must be string');
            return;
        }
        case 'createEvaluation': {
            if (!vars.scheduleId || typeof vars.scheduleId !== 'string') throw new Error('scheduleId required');
            if (vars.overallRating != null && (typeof vars.overallRating !== 'number' || vars.overallRating < 1 || vars.overallRating > 5)) throw new Error('overallRating 1-5');
            return;
        }
        case 'getEvaluationComparison': {
            if (!vars.scheduleId || typeof vars.scheduleId !== 'string') throw new Error('scheduleId required');
            return;
        }
        default:
            throw new Error(`Unknown API call: ${callName}`);
    }
}

/** Wrap a callable handler with auth, rate limit, validation, logging */
function withApiGuards(handler) {
    return functions.https.onCall(async (data, context) => {
        const start = Date.now();
        const db = admin.firestore();
        const callName = data?.callName;
        const variables = data?.variables || {};
        if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
        if (!callName) throw new functions.https.HttpsError('invalid-argument', 'callName required');

        // Rate limiting
        const rl = checkRateLimit(context.auth.uid, callName);
        if (!rl.allowed) {
            await logViolation(db, context.auth.uid, callName, rl.reason, rl.counts);
            throw new functions.https.HttpsError('resource-exhausted', `Rate limit exceeded (${rl.reason})`);
        }

        // Validation
        try { validate(callName, variables); }
        catch (e) { throw new functions.https.HttpsError('invalid-argument', e.message); }

        try {
            const result = await handler({ data: { callName, variables }, context, db });
            const durationMs = Date.now() - start;
            console.log(JSON.stringify({ level: 'info', type: 'api_call', callName, uid: context.auth.uid, durationMs, ok: true }));
            return result;
        } catch (e) {
            const durationMs = Date.now() - start;
            console.error(JSON.stringify({ level: 'error', type: 'api_call', callName, uid: context.auth.uid, durationMs, error: e.message }));
            if (e instanceof functions.https.HttpsError) throw e;
            throw new functions.https.HttpsError('internal', e.message || 'Internal error');
        }
    });
}

module.exports = { withApiGuards };
