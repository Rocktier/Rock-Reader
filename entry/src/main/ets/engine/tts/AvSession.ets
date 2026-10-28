/**
 * TTS 媒体会话（AVSession）封装 —— 让朗读能锁屏控、通知栏控、耳机键控。
 *
 * 为什么现在做：2026-10-28 之前，阅读页的策略是「回后台立即停读」
 * （见 Reader.ets 的 onPageHide），理由是没有 AVSession。
 * 有了它，后台/锁屏可以继续播，系统媒体中心也会出现朗读卡片。
 *
 * 三条硬约束（都踩过坑，别改）：
 *  1. **失败必须降级、不能连累朗读**：AVSession 创不起来（模拟器 / 低端机 /
 *     别的应用占了会话）时，朗读本身要照常能用 —— 所有调用都包 try/catch，
 *     失败只记日志，不抛。
 *  2. **不需要 -keep**：ASR 那边要 -keep 是因为「系统 SDK 按方法名反射回调
 *     我们的类实现」；这里注册的是**闭包**（session.on('play', cb)），
 *     混淆改不了它 ⇒ 别加无意义的 -keep。
 *  3. **不要用 BackgroundPlayMode**：那个枚举是 API 24 才有的，
 *     本工程 compileSdkVersion = 20 ⇒ 用它直接编译不过。
 *     API 20 的后台音频靠 module.json5 的 `backgroundModes: ["audio"]`。
 *
 * 纯逻辑（播放状态 → 系统状态码的映射）留在本文件底部，可单测。
 */
import { avSession } from '@kit.AVSessionKit';
import { Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeSpeed, SpeakPhase } from './AvSessionState';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReaderAvSession';

/** 会话 tag（系统内唯一标识本应用的朗读会话） */
const SESSION_TAG: string = 'RockReaderTTS';

/** 点通知栏回到应用时拉起的 ability */
const BUNDLE_NAME: string = 'com.rocktier.rockreader';
const ABILITY_NAME: string = 'EntryAbility';

/** 支持的倍速档（与 TTS 语速范围 0.5~2.0 对齐） */
export const AV_SPEEDS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/** 系统媒体控制回调（由阅读页注入） */
export class AvSessionCallbacks {
  /** 锁屏/通知栏点了「播放」 */
  onPlay: () => void = () => {};
  /** 点了「暂停」 */
  onPause: () => void = () => {};
  /** 点了「停止」 */
  onStop: () => void = () => {};
  /** 改了倍速 */
  onSpeed: (speed: number) => void = () => {};
}

/** 朗读在应用内的状态 → 系统播放状态码的映射（纯 SDK 翻译层，不含判断） */
function sdkStateOf(phase: SpeakPhase): avSession.PlaybackState {
  if (phase === SpeakPhase.PLAYING) {
    return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
  }
  if (phase === SpeakPhase.PAUSED) {
    return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
  }
  return avSession.PlaybackState.PLAYBACK_STATE_STOP;
}

export class AvSessionService {
  private session: avSession.AVSession | null = null;
  private cbs: AvSessionCallbacks = new AvSessionCallbacks();
  private ready: boolean = false;

  /** 会话是否可用（模拟器上通常 false） */
  isReady(): boolean {
    return this.ready;
  }

  /** 注入系统控制回调 */
  setCallbacks(cbs: AvSessionCallbacks): void {
    this.cbs = cbs;
  }

  /**
   * 创建会话。返回是否成功 —— 失败不抛，朗读照常用（约束 1）。
   */
  async start(context: Context): Promise<boolean> {
    if (this.ready) {
      return true;
    }
    try {
      const session: avSession.AVSession =
        await avSession.createAVSession(context, SESSION_TAG, 'audio');
      session.on('play', (): void => {
        this.cbs.onPlay();
      });
      session.on('pause', (): void => {
        this.cbs.onPause();
      });
      session.on('stop', (): void => {
        this.cbs.onStop();
      });
      session.on('setSpeed', (speed: number): void => {
        this.cbs.onSpeed(normalizeSpeed(speed));
      });
      await this.setLaunchAbility(session);
      await session.setSupportedPlaySpeeds(AV_SPEEDS);
      await session.activate();
      this.session = session;
      this.ready = true;
      hilog.info(DOMAIN, TAG, 'av session started');
      return true;
    } catch (e) {
      this.ready = false;
      this.session = null;
      hilog.warn(DOMAIN, TAG, 'av session unavailable: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 通知栏点击后拉起应用（失败不影响其余功能） */
  private async setLaunchAbility(session: avSession.AVSession): Promise<void> {
    try {
      const want: Want = { bundleName: BUNDLE_NAME, abilityName: ABILITY_NAME };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 1
      };
      const agent: WantAgent = await wantAgent.getWantAgent(info);
      await session.setLaunchAbility(agent);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setLaunchAbility failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 同步播放状态到系统 */
  async publish(phase: SpeakPhase, bookTitle: string, chapterTitle: string): Promise<void> {
    if (!this.ready || this.session === null) {
      return;
    }
    try {
      if (phase === SpeakPhase.IDLE) {
        const stopped: avSession.AVPlaybackState = {
          state: avSession.PlaybackState.PLAYBACK_STATE_STOP
        };
        await this.session.setAVPlaybackState(stopped);
        return;
      }
      const meta: avSession.AVMetadata = {
        assetId: `${BUNDLE_NAME}.tts`,
        title: bookTitle.length > 0 ? bookTitle : '朗读中',
        artist: chapterTitle.length > 0 ? chapterTitle : ''
      };
      await this.session.setAVMetadata(meta);
      const playing: avSession.AVPlaybackState = {
        state: sdkStateOf(phase),
        speed: 1.0
      };
      await this.session.setAVPlaybackState(playing);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'publish failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 释放会话（退出阅读页时调） */
  async stop(): Promise<void> {
    const session: avSession.AVSession | null = this.session;
    this.session = null;
    this.ready = false;
    if (session === null) {
      return;
    }
    try {
      await session.deactivate();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'deactivate failed: %{public}s', JSON.stringify(e));
    }
  }
}
