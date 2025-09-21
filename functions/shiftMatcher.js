const admin = require('firebase-admin');
const ShiftAdminAPI = require('./shiftadmin');
const MedResParser = require('./medres');

class ShiftMatcher {
    constructor() {
        this.db = admin.firestore();
        this.shiftAdmin = new ShiftAdminAPI();
        this.medRes = new MedResParser();
        this.MAX_RESIDENTS_PER_ATTENDING = 4;
        this.MIN_OVERLAP_MINUTES = 15;
        this.RESIDENT_WEIGHT = 0.7;
        this.ATTENDING_WEIGHT = 0.3;
    }
    async runMatching(startDate, endDate, dryRun = false) {
        console.log(`Running shift matching from ${startDate} to ${endDate} (dryRun: ${dryRun})`);
        const start = Date.now();
        try {
            const [attendingShifts, residentShifts] = await Promise.all([
                this.shiftAdmin.getScheduledShifts(startDate, endDate),
                this.medRes.getResidentShifts(startDate, endDate)
            ]);
            console.log(`Found ${attendingShifts.length} attending shifts and ${residentShifts.length} resident shifts`);
            const matches = this.matchShifts(attendingShifts, residentShifts);
            console.log(`Generated ${matches.length} matches`);
            if (!dryRun) await this.saveMatches(matches);
            await this.logMatchingRun(startDate, endDate, attendingShifts.length, residentShifts.length, matches.length, dryRun);
            return { success: true, attendingShiftsCount: attendingShifts.length, residentShiftsCount: residentShifts.length, matchesCount: matches.length, matches: dryRun ? matches : [], dryRun, elapsedMs: Date.now() - start };
        } catch (e) {
            console.error('Shift matching failed:', e);
            throw e;
        }
    }
    matchShifts(attendingShifts, residentShifts) {
        const matches = [];
        const residentAssignments = new Map();
        for (const attending of attendingShifts) {
            const potentials = [];
            for (const resident of residentShifts) {
                const overlap = this.calculateOverlap(attending, resident);
                if (overlap.minutes >= this.MIN_OVERLAP_MINUTES) {
                    const score = this.calculateMatchScore(attending, resident, overlap);
                    potentials.push({ resident, score, overlap });
                }
            }
            potentials.sort((a, b) => b.score - a.score);
            let assigned = 0;
            for (const p of potentials) {
                if (assigned >= this.MAX_RESIDENTS_PER_ATTENDING) break;
                const rk = `${p.resident.id}_${attending.start_time.toISOString()}`;
                if (!residentAssignments.has(rk)) {
                    matches.push({ attending, resident: p.resident, confidence: p.score, overlap_hours: p.overlap.hours, match_id: this.generateMatchId(attending, p.resident) });
                    residentAssignments.set(rk, true);
                    assigned++;
                }
            }
        }
        return matches;
    }
    calculateOverlap(attending, resident) {
        const start = new Date(Math.max(attending.start_time, resident.start_time));
        const end = new Date(Math.min(attending.end_time, resident.end_time));
        if (start >= end) return { minutes: 0, hours: 0 };
        const diffMs = end - start; const minutes = Math.floor(diffMs / 60000); return { minutes, hours: minutes / 60, start, end };
    }
    calculateMatchScore(attending, resident, overlap) {
        const attendingDuration = (attending.end_time - attending.start_time) / 3600000;
        const residentDuration = (resident.end_time - resident.start_time) / 3600000;
        const attendingCoverage = (overlap.hours / attendingDuration) * 100;
        const residentCoverage = (overlap.hours / residentDuration) * 100;
        return Math.round(residentCoverage * this.RESIDENT_WEIGHT + attendingCoverage * this.ATTENDING_WEIGHT);
    }
    generateMatchId(attending, resident) { return `${attending.start_time.toISOString().split('T')[0]}_${attending.id}_${resident.id}`; }
    async saveMatches(matches) {
        const batch = this.db.batch();
        const userCache = new Map();
        const usersSnap = await this.db.collection('users').get();
        usersSnap.forEach(doc => { const d = doc.data(); userCache.set((d.display_name || '').toUpperCase().trim(), { id: doc.id, ...d }); });
        for (const match of matches) {
            const attendingUser = userCache.get(match.attending.physician_name);
            const residentUser = userCache.get(match.resident.resident_name);
            const scheduleRef = this.db.collection('schedules').doc(match.match_id);
            batch.set(scheduleRef, {
                attendee: attendingUser ? this.db.collection('users').doc(attendingUser.id) : null,
                attendee_ref: attendingUser ? `/users/${attendingUser.id}` : null,
                resident: residentUser ? this.db.collection('users').doc(residentUser.id) : null,
                resident_ref: residentUser ? `/users/${residentUser.id}` : null,
                scheduled_date: admin.firestore.Timestamp.fromDate(match.attending.start_time),
                shift_timings: { start_time: admin.firestore.Timestamp.fromDate(match.attending.start_time), end_time: admin.firestore.Timestamp.fromDate(match.attending.end_time) },
                auto_matched: true,
                match_confidence: match.confidence,
                overlap_hours: match.overlap_hours,
                evaluation_data: {
                    attendee_evaluation: {
                        status: {
                            status: 'evaluate',
                            last_updated: admin.firestore.FieldValue.serverTimestamp()
                        },
                        scores: {},
                        feedback: '',
                        completed_at: null
                    },
                    resident_evaluation: {
                        status: {
                            status: 'evaluate',
                            last_updated: admin.firestore.FieldValue.serverTimestamp()
                        },
                        scores: {},
                        feedback: '',
                        completed_at: null
                    }
                },
                startNotificationSentToPhysician: false,
                startNotificationSentToResident: false,
                endNotificationSentToPhysician: false,
                endNotificationSentToResident: false,
                endNotificationFollowupSentToPhysician: false,
                endNotificationFollowupSentToResident: false,
                resident_evaluation_completed: false,
                attending_evaluation_completed: false,
                assigned_topic: { category_name: 'Emergency Medicine', is_category: false, topic_title: 'General Emergency Medicine' },
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
                schema_version: 1,
                test: false
            });
        }
        await batch.commit();
        console.log(`Saved ${matches.length} matched schedules to Firestore`);
    }
    async logMatchingRun(startDate, endDate, attCount, resCount, matchCount, dryRun) {
        await this.db.collection('shift_matching_logs').add({
            run_id: `run_${Date.now()}`,
            run_timestamp: admin.firestore.FieldValue.serverTimestamp(),
            date_range: { start_date: startDate, end_date: endDate },
            attending_shifts_count: attCount,
            resident_shifts_count: resCount,
            matches_count: matchCount,
            dry_run: dryRun,
            triggered_by: 'manual',
            errors: []
        });
    }
}
module.exports = ShiftMatcher;
