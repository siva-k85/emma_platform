// Simple ad-hoc test (requires env vars & service account if run outside emulator)
const admin = require('firebase-admin');
const ShiftMatcher = require('./shiftMatcher');

if (!admin.apps.length) {
    admin.initializeApp();
}

(async () => {
    const matcher = new ShiftMatcher();
    const startDate = process.argv[2] || new Date().toISOString().split('T')[0];
    const endDate = process.argv[3] || startDate;
    console.log(`Dry run shift matching ${startDate} -> ${endDate}`);
    try {
        const res = await matcher.runMatching(startDate, endDate, true);
        console.log(JSON.stringify(res, null, 2));
        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
})();
