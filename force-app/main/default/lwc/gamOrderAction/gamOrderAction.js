import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getGamOrderStatus from '@salesforce/apex/GAMOrderButtonController.getGamOrderStatus';
import pushOrderToGam from '@salesforce/apex/GAMOrderButtonController.pushOrderToGam';
import deleteOrderFromGam from '@salesforce/apex/GAMOrderButtonController.deleteOrderFromGam';

export default class GamOrderAction extends LightningElement {
    @api recordId;

    status = { isPushed: false, gamOrderId: null };
    isLoading = true;
    isProcessing = false;
    showConfirmModal = false;
    pendingAction = null;
    wiredStatusResult;

    @wire(getGamOrderStatus, { orderId: '$recordId' })
    wiredStatus(result) {
        this.wiredStatusResult = result;
        if (result.data) {
            this.status = result.data;
            this.isLoading = false;
        } else if (result.error) {
            this.isLoading = false;
            this.showToast('Error', this.extractErrorMessage(result.error), 'error');
        }
    }

    get confirmTitle() {
        return this.pendingAction === 'push'
            ? 'Push Order to Google Ad Manager'
            : 'Delete Order from Google Ad Manager';
    }

    get confirmMessage() {
        return this.pendingAction === 'push'
            ? 'This will create a real, live Order in Google Ad Manager. Are you sure you want to continue?'
            : 'This will permanently delete the real Google Ad Manager Order. This cannot be undone. Are you sure you want to continue?';
    }

    handlePushClick() {
        this.pendingAction = 'push';
        this.showConfirmModal = true;
    }

    handleDeleteClick() {
        this.pendingAction = 'delete';
        this.showConfirmModal = true;
    }

    handleCancel() {
        this.showConfirmModal = false;
        this.pendingAction = null;
    }

    async handleConfirm() {
        if (this.isProcessing) {
            return;
        }
        this.showConfirmModal = false;
        this.isProcessing = true;

        try {
            if (this.pendingAction === 'push') {
                const result = await pushOrderToGam({ orderId: this.recordId });
                if (result && result.success === true) {
                    this.showToast(
                        'Success',
                        'Pushed to Google Ad Manager as Order ' + result.gamOrderId +
                            ' with ' + result.lineItemsPushed + ' line item(s).',
                        'success'
                    );
                } else {
                    this.showToast('Push Failed', (result && result.explanation) || 'Unknown error - check console for raw result.', 'error');
                }
            } else if (this.pendingAction === 'delete') {
                const result = await deleteOrderFromGam({ orderId: this.recordId });
                if (result && result.success === true) {
                    this.showToast('Success', result.explanation, 'success');
                } else {
                    this.showToast('Delete Failed', (result && result.explanation) || 'Unknown error - check console for raw result.', 'error');
                }
            }
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.pendingAction = null;
            this.isProcessing = false;
            await refreshApex(this.wiredStatusResult);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: 'sticky' }));
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }
}
