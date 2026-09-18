import window from "@ohos:window";
import ConfigurationConstant from "@ohos:app.ability.ConfigurationConstant";
import hilog from "@ohos:hilog";
import { THEME_LIGHT } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import type { ThemeName } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';
/** 只应在主题**发生变化**时调用（避免无谓的配置变更） */
export function applyThemeToSystem(ctx: Context, theme: ThemeName): void {
    const light: boolean = theme === THEME_LIGHT;
    const contentColor: string = light ? '#000000' : '#FFFFFF';
    try {
        ctx.getApplicationContext().setColorMode(light
            ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
            : ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
    catch (e) {
        hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(e));
    }
    window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowSystemBarProperties({
            statusBarContentColor: contentColor,
            navigationBarContentColor: contentColor
        }).catch((e: Error) => {
            hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', e.message);
        });
    }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}s', e.message);
    });
}
