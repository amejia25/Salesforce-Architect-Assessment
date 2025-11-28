import { LightningElement, api, wire, track } from 'lwc';
import getQuarterlyContractHours
    from '@salesforce/apex/PBJStaffingService.getQuarterlyContractHours';

export default class PbjContractHoursChart extends LightningElement {
    @api recordId;

    @track chartData = [];
    @track isLoading = true;
    @track error;
    @track showEmpty = false;

    // convenience getter for template
    get hasData() {
        return this.chartData && this.chartData.length > 0;
    }

    @wire(getQuarterlyContractHours, { accountId: '$recordId' })
    wiredHours({ error, data }) {
        this.isLoading = false;

        if (error) {
            this.error = error;
            this.chartData = [];
            this.showEmpty = false;
            console.error('PBJ LWC error', error);
            return;
        }

        if (!data || data.length === 0) {
            this.chartData = [];
            this.showEmpty = true;
            this.error = undefined;
            return;
        }

        this.error = undefined;
        this.showEmpty = false;

        // compute max for height percentages
        let maxTotal = 0;
        const processed = data.map(d => {
            const total =
                (d.cnaHours || 0) +
                (d.lpnHours || 0) +
                (d.rnHours  || 0);

            if (total > maxTotal) {
                maxTotal = total;
            }

            return {
                quarter: d.quarter,
                cnaHours: d.cnaHours || 0,
                lpnHours: d.lpnHours || 0,
                rnHours:  d.rnHours  || 0,
                totalHours: total,
                // Label we’ll show above the bar
                totalLabel: Math.round(total)  // or total.toFixed(1)
            };
        });

        // avoid divide-by-zero
        if (maxTotal <= 0) {
            this.chartData = [];
            this.showEmpty = true;
            return;
        }

        // add style strings for stacked bar segments
        this.chartData = processed.map(row => {
            const total = row.totalHours;

            const cnaPct = (row.cnaHours / maxTotal) * 100;
            const lpnPct = (row.lpnHours / maxTotal) * 100;
            const rnPct  = (row.rnHours  / maxTotal) * 100;

            return {
                ...row,
                cnaStyle: `height: ${cnaPct}%;`,
                lpnStyle: `height: ${lpnPct}%;`,
                rnStyle:  `height: ${rnPct}%;`
            };
        });
    }
}
