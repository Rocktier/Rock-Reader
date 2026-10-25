/**
 * 服务卡片 Extension（B1，2026-10-25 党哥批准）
 *
 * 官方三件套之一：卡片生命周期（加卡片/刷新/销毁/状态查询）。
 * 数据全部走 CardData（本地库 + 快照），本类只做「什么时候读、推给谁」。
 *
 * 尺寸 2×2 / 2×4 都在一个 form_config 里声明，布局分发在 WidgetCard 页
 * （binding data 的 dimension 键，值 '2*2' / '2*4'）。
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Configuration, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { cardFormData, CardFormData, dimLabel, loadCardSnapshot, pushCardUpdate, readCardData } from '../data/CardData';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 从 want.parameters 里取尺寸（系统给的是 FormDimension 枚举值；容错字符串形态） */
function dimOfParams(params: Record<string, Object> | undefined): string {
  if (params === undefined) {
    return '2*2';
  }
  const raw: Object | undefined = params[formInfo.FormParam.DIMENSION_KEY];
  if (typeof raw === 'number') {
    return dimLabel(raw);
  }
  if (typeof raw === 'string' && raw.indexOf('*') >= 0) {
    return raw;
  }
  return '2*2';
}

export default class EntryFormAbility extends FormExtensionAbility {
  /**
   * 加卡片（**同步**签名）：先用 preferences 快照首绘，再异步查库推一次准的。
   *
   * 为什么不是等查库完再返回：onAddForm 同步等不了 await，桌面上加卡片
   * 会白屏一下；快照是上一次阅读留下的，内容差不了几秒。
   */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const d = loadCardSnapshot(this.context);
    const data: CardFormData = cardFormData(d, dimOfParams(want.parameters));
    hilog.info(DOMAIN, TAG, 'onAddForm dim=%{public}s', data.dimension);
    // 异步刷新：拿 formId（系统放在 want.parameters 的 IDENTITY_KEY 里）
    const rawId: Object | undefined = want.parameters === undefined
      ? undefined
      : want.parameters[formInfo.FormParam.IDENTITY_KEY];
    const formId: string = typeof rawId === 'string' ? rawId : (typeof rawId === 'number' ? String(rawId) : '');
    if (formId.length > 0) {
      this.refresh(formId, data.dimension);
    }
    return formBindingData.createFormBindingData(data);
  }

  /** 系统请求刷新 / 卡片改尺寸：查库后推新数据 */
  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.refresh(formId, dimOfParams(wantParams));
  }

  /** 查库 + 推送；失败只记日志（卡片刷新失败不该影响任何人） */
  private async refresh(formId: string, dimension: string): Promise<void> {
    try {
      const d = await readCardData(this.context);
      const data: CardFormData = cardFormData(d, dimension);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'refresh failed: %{public}s', JSON.stringify(e));
    }
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm %{public}s', formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    // 可见性变化不推数据（下次阅读落库自然会推）；留日志便于排查
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility %{public}s', JSON.stringify(newStatus));
  }

  /** 'message' 动作事件；本卡片只用 'router'（点卡片拉起应用），留空实现 */
  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent %{public}s %{public}s', formId, message);
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  /** 复用 pushCardUpdate：配置变化（深浅色/语言）时顺带刷一次卡片 */
  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate');
    pushCardUpdate(this.context);
  }
}
