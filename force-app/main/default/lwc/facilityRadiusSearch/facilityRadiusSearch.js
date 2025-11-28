import { LightningElement, api, track } from 'lwc';
import findNearbyFacilities
    from '@salesforce/apex/AccountProximityService.findNearbyFacilities';

export default class FacilityRadiusSearch extends LightningElement {
    @api recordId;

    @track radius = 50;
    @track results = [];
    @track isLoading = false;
    @track error;
    @track showEmpty = false;

    columns = [
        { label: 'Name', fieldName: 'name', type: 'text' },
        { label: 'City', fieldName: 'city', type: 'text' },
        { label: 'State', fieldName: 'state', type: 'text', initialWidth: 80 },
        {
            label: 'Distance (mi)',
            fieldName: 'distanceMiles',
            type: 'number',
            typeAttributes: {
                maximumFractionDigits: 1,
                minimumFractionDigits: 1
            },
            initialWidth: 130
        }
    ];

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get errorMessage() {
        if (!this.error) {
            return '';
        }
        if (this.error.body && this.error.body.message) {
            return this.error.body.message;
        }
        return JSON.stringify(this.error);
    }

    handleRadiusChange(event) {
        const val = event.target.value;
        this.radius = val ? Number(val) : 0;
    }

    handleSearch() {
        if (!this.recordId) {
            return;
        }

        this.isLoading = true;
        this.error = undefined;
        this.showEmpty = false;
        this.results = [];

        findNearbyFacilities({
            accountId: this.recordId,
            radiusMiles: this.radius
        })
            .then(data => {
                if (data && data.length > 0) {
                    this.results = data;
                    this.showEmpty = false;
                } else {
                    this.results = [];
                    this.showEmpty = true;
                }
            })
            .catch(err => {
                this.error = err;
                this.results = [];
                this.showEmpty = false;
                // eslint-disable-next-line no-console
                console.error('Error fetching nearby facilities', err);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}