const functions = require('firebase-functions');
const admin = require('firebase-admin');
const ShiftMatcher = require('./shiftMatcher');
const { createEvaluation, getEvaluationComparison } = require('./evaluations');
const { withApiGuards } = require('./middleware');

if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();
const messaging = admin.messaging();

exports.api = withApiGuards(async ({ data, context, db }) => {
    const { callName, variables } = data;
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!userDoc.exists) throw new functions.https.HttpsError('not-found', 'User not found');
    const userData = userDoc.data();
    switch (callName) {
        case 'runShiftMatching': {
            if (!userData.is_admin && userData.role !== 'physician') throw new functions.https.HttpsError('permission-denied', 'Insufficient permissions');
            const matcher = new ShiftMatcher();
            const today = new Date().toISOString().split('T')[0];
            const thirtyDaysLater = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
            const startDate = variables.startDate || today;
            const endDate = variables.endDate || thirtyDaysLater;
            const dryRun = variables.dryRun || false;
            return await matcher.runMatching(startDate, endDate, dryRun);
        }
        case 'getMatchedSchedules': {
            const { startDate: start, endDate: end, residentId, attendingId } = variables;
            let query = db.collection('schedules').where('auto_matched', '==', true).orderBy('scheduled_date');
            if (start) query = query.where('scheduled_date', '>=', new Date(start));
            if (end) query = query.where('scheduled_date', '<=', new Date(end));
            if (residentId) query = query.where('resident_ref', '==', `/users/${residentId}`);
            else if (attendingId) query = query.where('attendee_ref', '==', `/users/${attendingId}`);
            const snap = await query.get();
            return { success: true, count: snap.size, schedules: snap.docs.map(d => ({ id: d.id, ...d.data() })) };
        }
        case 'createEvaluation': {
            const { scheduleId, overallRating, competencyRatings, strengths, areasForImprovement, additionalComments } = variables;
            if (!scheduleId) throw new functions.https.HttpsError('invalid-argument', 'scheduleId required');
            const evaluatorType = userData.role === 'resident' ? 'resident' : 'attending';
            const evaluatedUserId = evaluatorType === 'resident' ? context.auth.uid : variables.evaluatedUserId || null;
            try {
                const result = await createEvaluation({
                    scheduleId,
                    evaluatorId: context.auth.uid,
                    evaluatorType,
                    evaluatedUserId,
                    overallRating,
                    competencyRatings,
                    strengths,
                    areasForImprovement,
                    additionalComments
                });
                return { success: true, evaluation: result };
            } catch (e) {
                throw new functions.https.HttpsError('invalid-argument', e.message);
            }
        }
        case 'getEvaluationComparison': {
            const { scheduleId } = variables;
            if (!scheduleId) throw new functions.https.HttpsError('invalid-argument', 'scheduleId required');
            const comp = await getEvaluationComparison(scheduleId);
            return { success: true, comparison: comp };
        }
        default:
            throw new functions.https.HttpsError('invalid-argument', `Unknown API call: ${callName}`);
    }
});

exports.dailyShiftMatching = functions.pubsub.schedule('0 2 * * *').timeZone('America/New_York').onRun(async () => {
    const matcher = new ShiftMatcher();
    const today = new Date().toISOString().split('T')[0];
    const thirtyDaysLater = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
    try { return await matcher.runMatching(today, thirtyDaysLater, false); } catch (e) { console.error(e); throw e; }
});

exports.sendShiftStartNotifications = functions.pubsub.schedule('every 1 minutes').onRun(async () => {
    const now = new Date(); const five = new Date(now.getTime() + 5 * 60000); const six = new Date(now.getTime() + 6 * 60000);
    const upcoming = await db.collection('schedules').where('shift_timings.start_time', '>=', five).where('shift_timings.start_time', '<', six).get();
    const notifications = []; const updates = [];
    for (const doc of upcoming.docs) {
        const shift = doc.data();
        if (!shift.startNotificationSentToPhysician && shift.attendee_ref) {
            const pDoc = await db.doc(shift.attendee_ref).get();
            if (pDoc.exists && pDoc.data().fcm_token) { notifications.push({ notification: { title: 'Shift Starting Soon', body: 'Your shift starts in 5 minutes' }, token: pDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'startNotificationSentToPhysician', value: true }); }
        }
        if (!shift.startNotificationSentToResident && shift.resident_ref) {
            const rDoc = await db.doc(shift.resident_ref).get();
            if (rDoc.exists && rDoc.data().fcm_token) { notifications.push({ notification: { title: 'Shift Starting Soon', body: 'Your shift starts in 5 minutes' }, token: rDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'startNotificationSentToResident', value: true }); }
        }
    }
    if (notifications.length) await messaging.sendAll(notifications);
    const batch = db.batch(); updates.forEach(u => batch.update(db.collection('schedules').doc(u.id), { [u.field]: u.value })); await batch.commit();
    return null;
});

exports.sendShiftEndNotifications = functions.pubsub.schedule('every 1 minutes').onRun(async () => {
    const now = new Date(); const oneAgo = new Date(now.getTime() - 60000);
    const ended = await db.collection('schedules').where('shift_timings.end_time', '>=', oneAgo).where('shift_timings.end_time', '<=', now).get();
    const notifications = []; const updates = [];
    for (const doc of ended.docs) {
        const shift = doc.data();
        if (!shift.endNotificationSentToPhysician && shift.attendee_ref) {
            const pDoc = await db.doc(shift.attendee_ref).get();
            if (pDoc.exists && pDoc.data().fcm_token) { notifications.push({ notification: { title: 'Complete Your Evaluation', body: "Please evaluate your resident from today's shift" }, data: { type: 'evaluation_reminder', schedule_id: doc.id }, token: pDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'endNotificationSentToPhysician', value: true }); }
        }
        if (!shift.endNotificationSentToResident && shift.resident_ref) {
            const rDoc = await db.doc(shift.resident_ref).get();
            if (rDoc.exists && rDoc.data().fcm_token) { notifications.push({ notification: { title: 'Complete Your Self-Evaluation', body: "Please complete your self-evaluation for today's shift" }, data: { type: 'evaluation_reminder', schedule_id: doc.id }, token: rDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'endNotificationSentToResident', value: true }); }
        }
    }
    if (notifications.length) await messaging.sendAll(notifications);
    const batch = db.batch(); updates.forEach(u => batch.update(db.collection('schedules').doc(u.id), { [u.field]: u.value })); await batch.commit();
    return null;
});

exports.sendEvaluationFollowupNotifications = functions.pubsub.schedule('every 5 minutes').onRun(async () => {
    const now = new Date(); const sixHoursAgo = new Date(now.getTime() - 6 * 60 * 60 * 1000); const sixHoursFiveAgo = new Date(now.getTime() - (6 * 60 + 5) * 60 * 1000);
    const overdue = await db.collection('schedules').where('shift_timings.end_time', '>=', sixHoursFiveAgo).where('shift_timings.end_time', '<=', sixHoursAgo).get();
    const notifications = []; const updates = [];
    for (const doc of overdue.docs) {
        const shift = doc.data();
        if (!shift.attending_evaluation_completed && !shift.endNotificationFollowupSentToPhysician && shift.attendee_ref) {
            const pDoc = await db.doc(shift.attendee_ref).get();
            if (pDoc.exists && pDoc.data().fcm_token) { notifications.push({ notification: { title: 'Evaluation Reminder - Final', body: 'You have an incomplete evaluation from today\'s shift' }, data: { type: 'evaluation_final_reminder', schedule_id: doc.id }, token: pDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'endNotificationFollowupSentToPhysician', value: true }); }
        }
        if (!shift.resident_evaluation_completed && !shift.endNotificationFollowupSentToResident && shift.resident_ref) {
            const rDoc = await db.doc(shift.resident_ref).get();
            if (rDoc.exists && rDoc.data().fcm_token) { notifications.push({ notification: { title: 'Self-Evaluation Reminder - Final', body: 'Please complete your self-evaluation from today\'s shift' }, data: { type: 'evaluation_final_reminder', schedule_id: doc.id }, token: rDoc.data().fcm_token }); updates.push({ id: doc.id, field: 'endNotificationFollowupSentToResident', value: true }); }
        }
    }
    if (notifications.length) await messaging.sendAll(notifications);
    const batch = db.batch(); updates.forEach(u => batch.update(db.collection('schedules').doc(u.id), { [u.field]: u.value })); await batch.commit();
    return null;
});
