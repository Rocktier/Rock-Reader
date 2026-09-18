import BackupExtensionAbility from "@ohos:application.BackupExtensionAbility";
import type { BundleVersion } from "@ohos:application.BackupExtensionAbility";
import hilog from "@ohos:hilog";
const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';
export default class EntryBackupAbility extends BackupExtensionAbility {
    async onBackup(): Promise<void> {
        hilog.info(DOMAIN, TAG, 'onBackup');
    }
    async onRestore(bundleVersion: BundleVersion): Promise<void> {
        hilog.info(DOMAIN, TAG, 'onRestore: %{public}s', JSON.stringify(bundleVersion));
    }
}
