import {AbilityConstant, UIAbility, Want} from '@kit.AbilityKit';
import {hilog} from '@kit.PerformanceAnalysisKit';
import {window} from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class FakeUIAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  }

  onDestroy(): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
  }
}
