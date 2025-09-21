const ical = require('node-ical');
const axios = require('axios');

class MedResParser {
    constructor() {
        this.juniorIcsUrl = process.env.MEDRES_JUNIOR_ICS_URL;
        this.seniorIcsUrl = process.env.MEDRES_SENIOR_ICS_URL;
        this.excludedShifts = ['QA/PS', 'EMS', 'IM', 'NEURO', 'PEDS', 'OB', 'SURG'];
    }
    async getResidentShifts(startDate, endDate) {
        const [junior, senior] = await Promise.all([
            this.parseICSFile(this.juniorIcsUrl, 'junior', startDate, endDate),
            this.parseICSFile(this.seniorIcsUrl, 'senior', startDate, endDate)
        ]);
        return [...junior, ...senior];
    }
    async parseICSFile(url, level, startDate, endDate) {
        if (!url) return [];
        try {
            const resp = await axios.get(url, { timeout: 20000 });
            const events = ical.sync.parseICS(resp.data);
            const shifts = [];
            const start = new Date(startDate);
            const end = new Date(endDate);
            for (const k in events) {
                if (!Object.prototype.hasOwnProperty.call(events, k)) continue;
                const ev = events[k];
                if (ev.type !== 'VEVENT') continue;
                const evStart = new Date(ev.start);
                const evEnd = new Date(ev.end);
                if (evStart >= start && evEnd <= end) {
                    const summary = (ev.summary || '').toUpperCase();
                    const isED = !this.excludedShifts.some(ex => summary.includes(ex));
                    if (isED) {
                        shifts.push({
                            id: `${level}_${ev.uid}`,
                            resident_name: this.extractResidentName(summary),
                            resident_level: level,
                            location: ev.location || 'ED',
                            start_time: evStart,
                            end_time: evEnd,
                            shift_type: this.extractShiftType(summary),
                            raw_summary: ev.summary
                        });
                    }
                }
            }
            return shifts;
        } catch (e) {
            console.error(`Failed to parse ${level} ICS file:`, e.message);
            return [];
        }
    }
    extractResidentName(summary) { const m = summary.match(/^([^-]+)/); return m ? m[1].trim().toUpperCase() : summary.toUpperCase(); }
    extractShiftType(summary) { const m = summary.match(/-\s*(.+)$/); return m ? m[1].trim() : 'ED'; }
}
module.exports = MedResParser;
