import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import convertServiceAccountKey from '@salesforce/apex/GAMKeyConversionController.convertServiceAccountKey';
import startProvisioning from '@salesforce/apex/GAMOnboardingProvisioningService.startProvisioning';
import checkProvisioningStatus from '@salesforce/apex/GAMOnboardingProvisioningService.checkStatus';
import assignPermissionSet from '@salesforce/apex/GAMOnboardingProvisioningService.assignPermissionSet';
import discoverNetwork from '@salesforce/apex/GAMOnboardingProvisioningService.discoverNetwork';

const POLL_INTERVAL_MS = 3000;
const MAX_POLL_ATTEMPTS = 40; // ~2 minutes

/*
 * Security note: `serviceAccountJsonText` and the resulting JKS bytes
 * live only in this component instance's memory for the duration of
 * the session. Nothing here writes them to localStorage,
 * sessionStorage, or any persistent browser storage. Once the user
 * navigates away or refreshes, everything is gone - by design, this
 * is a one-time-use onboarding flow, not something meant to be
 * revisited or recovered later.
 */
export default class GamOnboardingWizard extends LightningElement {

    serviceAccountJsonText = '';
    isConverting = false;

    step = 'paste'; // 'paste' | 'error' | 'result' | 'provisioning' | 'done'
    errorMessage = '';

    jksBase64 = '';
    keystorePassword = '';
    alias = '';
    issuer = '';

    isProvisioning = false;
    provisioningStatusMessage = '';
    networkCode = '';
    networkDisplayName = '';

    get showPasteStep() {
        return this.step === 'paste';
    }

    get showErrorStep() {
        return this.step === 'error';
    }

    get showResultStep() {
        return this.step === 'result';
    }

    get showProvisioningStep() {
        return this.step === 'provisioning';
    }

    get showDoneStep() {
        return this.step === 'done';
    }

    get importFromKeystoreUrl() {
        return '/lightning/setup/CertificateAndKeysManagement/home';
    }

    handleJsonChange(event) {
        this.serviceAccountJsonText = event.target.value;
    }

    async handleConvert() {

        if (!this.serviceAccountJsonText || !this.serviceAccountJsonText.trim()) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing key',
                    message: 'Please paste your service account JSON key first.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isConverting = true;

        try {
            const result = await convertServiceAccountKey({
                serviceAccountJsonText: this.serviceAccountJsonText
            });

            // Clear the pasted key out of this component's memory
            // immediately after sending it - we never need it again
            // once the conversion service has responded.
            this.serviceAccountJsonText = '';

            if (!result.success) {
                this.errorMessage = result.errorMessage;
                this.step = 'error';
                return;
            }

            this.jksBase64 = result.jksBase64;
            this.keystorePassword = result.keystorePassword;
            this.alias = result.alias;
            this.issuer = result.issuer;

            this.triggerJksDownload();

            this.step = 'result';

        } catch (err) {
            this.errorMessage = (err && err.body && err.body.message)
                ? err.body.message
                : 'Unexpected error while converting your key. Please try again.';
            this.step = 'error';

        } finally {
            this.isConverting = false;
        }
    }

    triggerJksDownload() {
        const byteCharacters = atob(this.jksBase64);
        const byteNumbers = new Array(byteCharacters.length);

        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }

        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: 'application/octet-stream' });

        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `${this.alias || 'gam_service_account_key'}.jks`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);
    }

    handleDownloadAgain() {
        this.triggerJksDownload();
    }

    handleCopyPassword() {
        navigator.clipboard.writeText(this.keystorePassword).then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Copied',
                    message: 'Keystore password copied to clipboard.',
                    variant: 'success'
                })
            );
        });
    }

    async handleContinueAfterImport() {
        this.step = 'provisioning';
        this.isProvisioning = true;
        this.errorMessage = '';

        try {
            this.provisioningStatusMessage = 'Setting up your GAM connection in Salesforce...';
            const startResult = await startProvisioning({ clientEmail: this.issuer });

            if (!startResult.success) {
                throw new Error(startResult.errorMessage || 'Failed to start provisioning.');
            }

            await this.pollUntilDeployed(startResult.deployId);

            this.provisioningStatusMessage = 'Granting access...';
            const assignResult = await assignPermissionSet();
            if (!assignResult.success) {
                throw new Error(assignResult.errorMessage || 'Failed to grant access to the new connection.');
            }

            this.provisioningStatusMessage = 'Detecting your Google Ad Manager network...';
            const discoverResult = await discoverNetwork();
            if (!discoverResult.success) {
                throw new Error(
                    discoverResult.errorMessage ||
                    'Could not detect your GAM network. Make sure your service account has been added as a user in your GAM Admin panel.'
                );
            }

            this.networkCode = discoverResult.networkCode;
            this.networkDisplayName = discoverResult.networkDisplayName;
            this.step = 'done';

        } catch (err) {
            this.errorMessage = (err && err.body && err.body.message)
                ? err.body.message
                : (err && err.message) ? err.message : 'Unexpected error while finishing setup. Please try again.';
            this.step = 'error';

        } finally {
            this.isProvisioning = false;
        }
    }

    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    async pollUntilDeployed(deployId) {
        for (let attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
            const statusResult = await checkProvisioningStatus({ deployId });

            if (statusResult.status === 'Succeeded') {
                return;
            }
            if (statusResult.status === 'Failed') {
                throw new Error(statusResult.errorMessage || 'Setup failed while applying the configuration.');
            }

            await this.sleep(POLL_INTERVAL_MS);
        }

        throw new Error('Setup is taking longer than expected. Please try again in a few minutes.');
    }

    handleReset() {
        this.serviceAccountJsonText = '';
        this.jksBase64 = '';
        this.keystorePassword = '';
        this.alias = '';
        this.issuer = '';
        this.errorMessage = '';
        this.provisioningStatusMessage = '';
        this.networkCode = '';
        this.networkDisplayName = '';
        this.step = 'paste';
    }
}
