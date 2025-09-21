const axios = require('axios');

class ShiftAdminAPI {
    constructor() {
        this.baseUrl = process.env.SHIFTADMIN_BASE_URL;
        this.validationKey = process.env.SHIFTADMIN_API_KEY;
    }
    async getScheduledShifts(startDate, endDate) {
        const url = `${this.baseUrl}?validationKey=${this.validationKey}&type=json&sd=${startDate}&ed=${endDate}`;
        try {
            const response = await axios.get(url, { timeout: 30000 });
            if (response.data.status === 'success') {
                const shifts = response.data.data.scheduledShifts || [];
                const pittShifts = shifts.filter(shift => shift.location && shift.location.includes('PITT'));
                return pittShifts.map(shift => ({
                    id: shift.shift_id,
                    physician_name: this.normalizeNam(shift.physician_name),
                    location: shift.location,
                    start_time: new Date(shift.start_datetime),
                    end_time: new Date(shift.end_datetime),
                    shift_type: shift.shift_type,
                    raw_data: shift
                }));
            }
            throw new Error(`ShiftAdmin API error: ${response.data.message}`);
        } catch (err) {
            console.error('ShiftAdmin API fetch failed:', err.message);
            throw err;
        }
    }
    normalizeNam(name) { return name.toUpperCase().trim().replace(/\s+/g, ' '); }
}

module.exports = ShiftAdminAPI;
