const admin = require('firebase-admin');

const db = admin.firestore();

function validateRating(n, field) {
    if (typeof n !== 'number' || n < 1 || n > 5) {
        throw new Error(`Invalid rating for ${field}`);
    }
    return n;
}

function normalizeCompetencies(raw) {
    const required = [
        'medical_knowledge',
        'patient_care',
        'communication',
        'professionalism',
        'systems_based_practice',
        'practice_based_learning'
    ];
    const out = {};
    for (const key of required) {
        out[key] = validateRating(raw?.[key] ?? 3, key);
    }
    return out;
}

async function createEvaluation({ scheduleId, evaluatorId, evaluatorType, evaluatedUserId, overallRating, competencyRatings, strengths, areasForImprovement, additionalComments }) {
    const scheduleRef = db.collection('schedules').doc(scheduleId);
    const scheduleSnap = await scheduleRef.get();
    if (!scheduleSnap.exists) throw new Error('Schedule not found');
    const schedule = scheduleSnap.data();

    if (evaluatorType === 'resident' && schedule.resident_ref !== `/users/${evaluatorId}`) {
        throw new Error('Resident not part of schedule');
    }
    if (evaluatorType === 'attending' && schedule.attendee_ref !== `/users/${evaluatorId}`) {
        throw new Error('Attending not part of schedule');
    }

    const competencies = normalizeCompetencies(competencyRatings);
    validateRating(overallRating, 'overall_rating');

    const evalDoc = {
        evaluation_id: `eval_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        schedule_id: scheduleId,
        shift_id: schedule.shift_id || scheduleId,
        evaluator_id: evaluatorId,
        evaluator_type: evaluatorType,
        evaluated_user_id: evaluatedUserId,
        overall_rating: overallRating,
        competency_ratings: competencies,
        strengths: strengths || '',
        areas_for_improvement: areasForImprovement || '',
        additional_comments: additionalComments || '',
        submitted_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        is_final: true
    };

    const batch = db.batch();
    const evalRef = db.collection('evaluations').doc();
    batch.set(evalRef, evalDoc);
    const completionField = evaluatorType === 'resident' ? 'resident_evaluation_completed' : 'attending_evaluation_completed';
    const evalKey = evaluatorType === 'resident' ? 'resident_evaluation' : 'attendee_evaluation';
    const now = admin.firestore.FieldValue.serverTimestamp();
    const scheduleUpdates = {
        [completionField]: true,
        updated_at: now,
        [`evaluation_data.${evalKey}.status.status`]: 'done',
        [`evaluation_data.${evalKey}.status.last_updated`]: now,
        [`evaluation_data.${evalKey}.completed_at`]: now,
        [`evaluation_data.${evalKey}.feedback`]: evaluatorType === 'resident' ? strengths || '' : additionalComments || ''
    };
    if (competencies) {
        scheduleUpdates[`evaluation_data.${evalKey}.scores`] = competencies;
    }
    batch.update(scheduleRef, scheduleUpdates);
    await batch.commit();
    return { id: evalRef.id, ...evalDoc };
}

async function getEvaluationComparison(scheduleId) {
    const evalsSnap = await db.collection('evaluations').where('schedule_id', '==', scheduleId).get();
    const residentEval = evalsSnap.docs.map(d => d.data()).find(e => e.evaluator_type === 'resident');
    const attendingEval = evalsSnap.docs.map(d => d.data()).find(e => e.evaluator_type === 'attending');
    if (!residentEval && !attendingEval) return { scheduleId, residentEval: null, attendingEval: null, deltas: null };
    const deltas = {};
    if (residentEval && attendingEval) {
        const keys = Object.keys(residentEval.competency_ratings || {});
        for (const k of keys) {
            deltas[k] = (attendingEval.competency_ratings?.[k] ?? 0) - (residentEval.competency_ratings?.[k] ?? 0);
        }
        deltas.overall = (attendingEval.overall_rating ?? 0) - (residentEval.overall_rating ?? 0);
    }
    return { scheduleId, residentEval: residentEval || null, attendingEval: attendingEval || null, deltas };
}

module.exports = { createEvaluation, getEvaluationComparison };
