/**
 * TTS 引擎封装（**IO 层**，依赖 @kit.CoreSpeechKit）
 *
 * 设计依据：findings §15（朗读功能技术调研）。三层结构的最上层：
 *   SpeakQueue.ets（纯逻辑，单测）→ **本文件**（IO 封装）→ Reader.ets（UI）
 *
 * API 真源：本机 HarmonyOS SDK 自带的官方声明
 *   <DevEco>/sdk/default/hms/ets/api/@hms.ai.textToSpeech.d.ts（2026-10-17 读全文，非博客）。
 *   ⚠️ 曾经以为 OpenHarmony SDK 没有 CoreSpeechKit、自备了一份 d.ts —— 错，
 *   官方声明一直在 sdk/default 的 hms 目录下（hms 目录是 HarmonyOS SDK 组件，
 *   与 ets 目录的 OpenHarmony 组件并列）。自备声明已删，一切以官方为准。
 *
 * 官方 API 的关键事实（读声明全文确认，官网文档都没写全）：
 *   1. createEngine params.online：**1 = 离线模式（supported）**，0 = 在线模式
 *      （当前 not supported）。离线合成 = 不联网，契合项目定位。
 *   2. params.person：**13 = 凌小珊女声（推荐，离线可用）**；21 = 凌飞哲男声（需下载）；
 *      8 = Laura 美音女（需下载）。0 是 13 的兼容别名。
 *   3. SpeakListener.onComplete 的 response.type：**0 = 合成完成，1 = 播放完成**。
 *      推进队列必须判 type === 1，否则音频没播完就切下一段（重大坑，官方声明才看得到）。
 *   4. speak 的 extraParams 是 Record<string, Object>（官方口径）；speed 键控速。
 *   5. createEngine 错误码：401 参数错 / 1002300002 语言不支持 /
 *      1002300003 音色不支持 / 1002300005 建引擎失败。
 *   6. extraParams['isBackStage'] = true 可开后合播放（期二 AVSession 的替代路径）。
 *
 * 关键约束（三次实测，结论翻转过，以最新为准）：
 *   1. **模拟器有 TTS 能力**（2026-10-18 jscrash 日志实锤）：createEngine 成功
 *      （version 61.29.11.202，连 com.huawei.hmsapp.hiai TtsAbility，code 0）。
 *      此前"无库/无工具/hidumper 无 SA"的判断有盲区 —— TTS 是 hiai 应用内的
 *      ExtensionAbility + AI_TEXT 原生模块，本就不在 hidumper 的 SA 列表里。
 *      语音整链路（建引擎→speak→翻页续读→暂停/停止）均已在模拟器实测通过。
 *   2. **成功回调的 err 是 undefined 不是 null**（同次实锤）：createEngine 成功后
 *      原生侧 callback(undefined, engine)，判定必须同时防 null 和 undefined。
 *   3. **章级朗读**（2026-10-18 修订）：段从页级 500 字改章级 8000 字
 *      （findings §16.9：小段接缝 = 停顿莫名/连读/翻页中断三大听感问题的总根因）。
 *      代价是段内无官方断点 → 位置跟踪（时间估算 + 段播完校准 + 句界回退续读），
 *      见 estimatedOffset / resumeNow / SpeakQueue.seekTo。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SpeakQueue, SpeakState, updateCharsPerSec } from './SpeakQueue';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReaderTts';

/** 系统能力名（仅日志标注用；探测走 createEngine 错误码，不依赖它） */
const TTS_SYSCAP: string = 'SystemCapability.AI.TextToSpeech';

/** 离线模式（官方：1 = offline，supported；0 = online，当前不支持） */
const TTS_ONLINE_MODE: number = 1;
/** 凌小珊女声（官方推荐值；离线可用，无需下载音色模型） */
const TTS_PERSON: number = 13;
/** 语速默认值（常速） */
const DEFAULT_SPEED: number = 1.0;
/**
 * 语速估算初值（ chars/sec，中文女声常速约 4~6 字/秒）。
 * 仅第一段用；第二段起用段播完的实际时长校准（updateCharsPerSec EMA）。
 */
const DEFAULT_CPS: number = 4.5;

/** 音色不支持错误码（如凌飞哲未下载）：设备 TTS 能力没问题，不污染 supported 缓存 */
const TTS_ERR_VOICE_UNSUPPORTED: number = 1002300003;

/**
 * UI 回调容器。
 * ⚠️ 用 class 不用 interface + 对象字面量：ArkTS 对**全可选字段**的接口做字面量赋值时
 * 类型推导失效（arkts-no-untyped-obj-literals，2026-10-17 实测：同文件里官方
 * SpeakListener 有 4 个必填字段，方法语法字面量就过；全可选的 TtsCallbacks 必报）。
 * class 实例走 new，不碰字面量规则；字段默认 null，调用处判空。
 */
export class TtsCallbacks {
  /** 某段开始播报（index/total 段号；charOffset = 该段在章内起始偏移，UI 算百分比） */
  onSegmentStart: ((index: number, total: number, charOffset: number) => void) | null = null;
  /** 某段播完 */
  onSegmentDone: ((index: number, total: number) => void) | null = null;
  /** 全部段播完 */
  onAllDone: (() => void) | null = null;
  /** 出错（UI 弹 hint；调用方应同时准备降级） */
  onError: ((message: string) => void) | null = null;
}

export class TtsEngine {
  private static instance: TtsEngine | null = null;

  /** 单例：Reader 页进出不重建引擎（createEngine 有开销，且同时只应有一个播报） */
  static shared(): TtsEngine {
    if (TtsEngine.instance === null) {
      TtsEngine.instance = new TtsEngine();
    }
    return TtsEngine.instance;
  }

  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private queue: SpeakQueue = new SpeakQueue();
  /** null = 未探测；true/false = 探测结论（缓存，不重复 createEngine） */
  private supported: boolean | null = null;
  /** 是否曾成功建过引擎（跨音色切换保持）：
   *  建成功过再失败 = 音色级问题（不动 supported 缓存，入口不闪）；
   *  从没成功过就失败 = 设备级/瞬态（supported=false，下次进 Reader 重探测）。 */
  private everSupported: boolean = false;
  private speed: number = DEFAULT_SPEED;
  /** 当前音色 person（建引擎时定死；setPerson 热切换 = 停旧引擎重建） */
  private person: number = TTS_PERSON;
  private callbacks: TtsCallbacks = new TtsCallbacks();
  /** requestId 序号（同一实例内 requestId 只能有一次，官方文档明确要求） */
  private reqSeq: number = 0;
  /** 当前有效 speak 的 requestId（过期回调凭它丢弃：seek 换段/暂停后的压哨事件） */
  private activeReqId: string = '';
  /** 当前段 onStart 时刻（位置估算的时间基点） */
  private segStartMs: number = 0;
  /** 暂停时冻结的章内偏移（-1 = 无冻结值）；续读从这句界回退点开读 */
  private pausedOffset: number = -1;
  /** 语速估算（chars/sec，EMA 校准，见 updateCharsPerSec） */
  private cps: number = DEFAULT_CPS;

  private constructor() {
  }

  setCallbacks(cbs: TtsCallbacks): void {
    this.callbacks = cbs;
  }

  /** 已探测过且结论为"不支持"时为 false；未探测为 false（UI 先当不支持处理） */
  isSupported(): boolean {
    return this.supported === true;
  }

  /**
   * 能力探测（UI 显隐入口的唯一依据）。异步：回调参数即结论。
   * 探测成功会**留下引擎**（begin 复用，不 shutdown）—— 真机上 createEngine
   * 有开销，没必要 probe 完就毁；Reader 页退出时统一 shutdown。
   * 幂等：已探测过直接同步回调结论。
   */
  probe(cb: (supported: boolean) => void): void {
    if (this.supported !== null) {
      cb(this.supported);
      return;
    }
    this.ensureEngine((ok: boolean, _reason: string) => {
      cb(ok);
    });
  }

  setSpeed(v: number): void {
    // 夹取防呆：官方没给 CoreSpeechKit 的 speed 范围（老 ML TTS 是 0.2~1.8），
    // 超出夹到边界，好过把非法值透传给系统导致 speak 直接报错
    if (v < 0.2) {
      this.speed = 0.2;
    } else if (v > 2.0) {
      this.speed = 2.0;
    } else {
      this.speed = v;
    }
  }

  /**
   * 切换音色（设置面板试听入口）。音色在建引擎时定死（params.person），
   * 只能停旧引擎重建：stop + shutdown + engine=null。
   * supported（设备级能力缓存）**不动** —— 换音色不等于换设备，入口不该闪；
   * 新音色建不起来（如凌飞哲未下载 → 1002300003）走 ensureEngine 的 err 回调
   * → callbacks.onError，由 Reader 层提示并回退选中态。
   * 幂等：同值直接返回，不碰引擎。
   */
  setPerson(v: number): void {
    if (this.person === v) {
      return;
    }
    this.person = v;
    if (this.engine !== null) {
      this.stop();
      try {
        this.engine.shutdown();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'person switch shutdown failed: %{public}s', JSON.stringify(e));
      }
      this.engine = null;
    }
  }

  getSpeed(): number {
    return this.speed;
  }

  get state(): SpeakState {
    return this.queue.state;
  }

  get cursorIndex(): number {
    return this.queue.cursorIndex;
  }

  get total(): number {
    return this.queue.total;
  }

  /**
   * 载入文本（切段）。返回段数；0 = 空文本/纯空白（调用方提示"无可读内容"）。
   * 载入即复位播放态（防止新旧文本混读）。
   */
  loadText(text: string): number {
    this.queue.stop();
    return this.queue.load(text);
  }

  /** 载入**整章**并切段（章级朗读入口：默认 8000/段，绝大多数章节一段读完） */
  loadChapter(text: string): number {
    this.queue.stop();
    return this.queue.loadChapter(text);
  }

  /**
   * 章内当前播放位置（字符偏移）。-1 = 不在播（idle/stopped/未建引擎）。
   * speaking = 段起点 + 已播秒数 × 估算语速（段播完时用实际时长校准）；
   * paused = 暂停时冻结值。
   * Reader 的 1s 定时器凭它做**页同步**（眼睛跟着耳朵走）。
   */
  estimatedOffset(): number {
    if (this.engine === null || this.queue.cursorIndex < 0) {
      return -1;
    }
    if (this.queue.state === 'paused') {
      return this.pausedOffset;
    }
    if (this.queue.state !== 'speaking') {
      return -1;
    }
    const base: number = this.queue.segmentOffset(this.queue.cursorIndex);
    const segLen: number = this.queue.currentLength();
    if (base < 0 || segLen < 0) {
      return -1;
    }
    const played: number = (Date.now() - this.segStartMs) / 1000 * this.cps;
    return base + Math.max(0, Math.min(played, segLen));
  }

  /**
   * 开始朗读。**可能是异步的**：引擎首次创建（createEngine 是回调式）时，
   * 本方法返回 false 但后台会建引擎，建好自动续跑 beginNow。
   *   - 返回 true = 已发起第一段；
   *   - 返回 false = 三种情况：能力不支持（最终态，onError 会到）/
   *     空文本（最终态）/ 引擎创建中（瞬态，随后 onSegmentStart 或 onError 到）。
   * UI 约定：false 时显示「正在准备朗读…」占位；onSegmentStart 到即开读；
   * onError 到即降级提示。这样异步路径与同步路径对用户是一致的。
   */
  begin(): boolean {
    if (this.supported === false) {
      return false;
    }
    if (this.engine !== null) {
      return this.beginNow();
    }
    this.ensureEngine((ok: boolean, reason: string) => {
      if (ok) {
        this.beginNow();
      } else {
        this.callbacks.onError?.(reason.length > 0 ? reason : '当前设备不支持朗读');
      }
    });
    return false;
  }

  /** 引擎已就绪的同步开读路径 */
  private beginNow(): boolean {
    const first: string | null = this.queue.begin();
    if (first === null) {
      return false;
    }
    this.speakCurrent(first);
    return true;
  }

  /**
   * 从章内偏移 offset 处开读（章级朗读的真正入口：用户点朗读时从**当前页**
   * 开始，不是章首）。异步语义同 begin：引擎未建则后台建好自动续跑。
   */
  startFrom(offset: number): boolean {
    if (this.supported === false) {
      return false;
    }
    if (this.engine !== null) {
      return this.startFromNow(offset);
    }
    const off: number = offset;
    this.ensureEngine((ok: boolean, reason: string) => {
      if (ok) {
        this.startFromNow(off);
      } else {
        this.callbacks.onError?.(reason.length > 0 ? reason : '当前设备不支持朗读');
      }
    });
    return false;
  }

  private startFromNow(offset: number): boolean {
    const tail: string | null = this.queue.seekTo(offset);
    if (tail === null) {
      return false;
    }
    this.queue.markSpeaking();
    this.speakCurrent(tail);
    return true;
  }

  pause(): void {
    if (this.engine !== null && this.queue.state === 'speaking') {
      // 冻结当前位置（估算值）—— 续读从这里按句界回退开播。
      // 必须在 engine.stop() **之前**取：stop 后段内时间基点就失去意义了。
      this.pausedOffset = this.estimatedOffset();
      this.engine.stop();
    }
    this.queue.pause();
  }

  resume(): boolean {
    if (this.supported === false) {
      return false;
    }
    if (this.engine !== null) {
      return this.resumeNow();
    }
    this.ensureEngine((ok: boolean, reason: string) => {
      if (ok) {
        this.resumeNow();
      } else {
        this.callbacks.onError?.(reason.length > 0 ? reason : '当前设备不支持朗读');
      }
    });
    return false;
  }

  /**
   * 续读（章级语义）：从暂停时的冻结偏移开播，按句界回退切当前段
   * （CoreSpeechKit 无段内断点，回退到上一个句号是唯一诚实的近似；
   *  重听量通常只有一句话，见 SpeakQueue.resumeCutIndex）。
   */
  private resumeNow(): boolean {
    if (this.pausedOffset >= 0) {
      const tail: string | null = this.queue.seekTo(this.pausedOffset);
      this.pausedOffset = -1;
      if (tail === null) {
        return false;
      }
      this.queue.markSpeaking();
      this.speakCurrent(tail);
      return true;
    }
    // 防御路径：从没定位过就暂停（理论不出现）→ 旧语义整段重读
    const cur: string | null = this.queue.resume();
    if (cur === null) {
      return false;
    }
    this.speakCurrent(cur);
    return true;
  }

  /**
   * 跳转到章内偏移 offset（用户手动翻页：耳朵跟眼睛走）。
   * paused 时只做文本手术 + 后移恢复点，不开读（点「继续」才读）；
   * 其余状态手术后立即开播。
   */
  seekTo(offset: number): void {
    if (this.engine === null || this.queue.total === 0) {
      return;
    }
    const wasPaused: boolean = this.queue.state === 'paused';
    const tail: string | null = this.queue.seekTo(offset);
    if (tail === null) {
      return;
    }
    if (wasPaused) {
      // 恢复点 = 新段起点（seekTo 已把段切在句界上）
      this.pausedOffset = this.queue.segmentOffset(this.queue.cursorIndex);
      return;
    }
    this.queue.markSpeaking();
    this.engine.stop();
    this.speakCurrent(tail);
  }

  /** 停止（UI「停止」；队列复位，再 begin 从第一段来） */
  stop(): void {
    if (this.engine !== null) {
      this.engine.stop();
    }
    this.queue.stop();
  }

  /** 页面销毁必须调（引擎持有音频资源；不释放=进程内泄漏+下次 begin 行为未定义） */
  shutdown(): void {
    this.stop();
    this.activeReqId = ''; // 之后的迟到回调全部按过期丢弃
    if (this.engine !== null) {
      try {
        this.engine.shutdown();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'shutdown failed: %{public}s', JSON.stringify(e));
      }
      this.engine = null;
    }
    this.supported = null; // 下次进入 Reader 重新探测（设备能力不会变，但便宜且干净）
  }

  // ----------------------------------------------------------------
  // 内部
  // ----------------------------------------------------------------

  /**
   * 创建/获取引擎。成功回调 ok=true；失败 ok=false + reason（中文，给 UI 提示）。
   * 幂等：engine 已在则直接 cb(true)；探测过不支持则直接 cb(false)（不再碰系统）。
   */
  private ensureEngine(cb: (ok: boolean, reason: string) => void): void {
    if (this.engine !== null) {
      cb(true, '');
      return;
    }
    // 官方：online=1 离线模式（唯一受支持的）；person 由 setPerson 配置（默认 13 凌小珊）
    const params: textToSpeech.CreateEngineParams = {
      language: 'zh-CN',
      person: this.person,
      online: TTS_ONLINE_MODE
    };
    try {
      textToSpeech.createEngine(params, (err: BusinessError | null | undefined, eng?: textToSpeech.TextToSpeechEngine) => {
        // ⚠️ 成功回调的 err 是 **undefined，不是 null**（2026-10-18 模拟器 jscrash 实锤）：
        //   createEngine 建引擎成功后原生侧 callback(undefined, engine)，
        //   旧代码 `err !== null` 防不住 undefined，误入错误分支读 err.code → TypeError 崩进程。
        //   判定顺序：先看有没有错误对象，再看有没有引擎实例。
        if (err !== undefined && err !== null) {
          // 音色级失败两种：错误码 1002300003（官方音色不支持），
          // 或 everSupported（曾建成功过 —— 切音色后的失败必是音色问题，
          // 实测凌飞哲未下载报的是 1002300005 + HyVoiceSynthesizer 资源错）。
          const voiceIssue: boolean = err.code === TTS_ERR_VOICE_UNSUPPORTED || this.everSupported;
          // 音色问题（如凌飞哲未下载）≠ 设备问题：supported 缓存不动，
          // 否则设置里试听失败会把朗读入口搞闪隐（切换回来还得重新探测）
          if (!voiceIssue) {
            this.supported = false;
          }
          this.engine = null;
          hilog.warn(DOMAIN, TAG, 'createEngine failed: %{public}d:%{public}s voiceIssue=%{public}s',
            err.code, err.message, String(voiceIssue));
          cb(false, TtsEngine.errText(err, voiceIssue));
          return;
        }
        if (eng === undefined) {
          this.supported = false;
          this.engine = null;
          hilog.warn(DOMAIN, TAG, 'createEngine failed: engine undefined (syscap=%{public}s)', TTS_SYSCAP);
          cb(false, '引擎创建失败');
          return;
        }
        eng.setListener(this.buildListener());
        this.engine = eng;
        this.supported = true;
        this.everSupported = true;
        hilog.info(DOMAIN, TAG, 'createEngine OK');
        cb(true, '');
      });
    } catch (e) {
      // createEngine 同步 throw（能力缺失时部分版本走这条路而非 err 回调）
      this.supported = false;
      hilog.error(DOMAIN, TAG, 'createEngine threw: %{public}s', JSON.stringify(e));
      cb(false, '朗读引擎创建异常');
    }
  }

  /** 建引擎错误码 → 中文提示（系统 message 是中英混排，给党哥看的不如给准话） */
  private static errText(err: BusinessError, voiceIssue: boolean): string {
    if (voiceIssue) {
      return '该音色暂不可用（需下载音色包）';
    }
    if (err.code === TTS_ERR_VOICE_UNSUPPORTED) {
      return '该音色暂不可用（需下载音色包）';
    }
    if (err.code === 1002300005) {
      return '引擎创建失败，请稍后重试';
    }
    if (err.code === 1002300002) {
      return '语言不支持';
    }
    if (err.code === 401) {
      return '朗读参数错误';
    }
    return `朗读启动失败（${err.code}）`;
  }

  /** speak 监听：把系统回调翻译成队列推进 + UI 回调 */
  private buildListener(): textToSpeech.SpeakListener {
    const self: TtsEngine = this;
    // ArkTS 铁律：对象字面量必须先落到接口变量再 return（裸 return {...} 报 10605038）。
    // 字段用**方法语法**（箭头函数属性值会踩 arkts-no-untyped-obj-literals 的推导坑，见 NOOP_CALLBACKS 注释）
    const listener: textToSpeech.SpeakListener = {
      onStart(requestId: string, _response: textToSpeech.StartResponse): void {
        // 过期事件守卫（requestId 版）：seekTo 换段/暂停后的压哨 onStart 一律丢弃。
        // 比状态判断更硬 —— stop 是异步的，旧 speak 的回调可能晚于新 speak 到达。
        if (requestId !== self.activeReqId) {
          hilog.info(DOMAIN, TAG, 'onStart stale, dropped: id=%{public}s', requestId);
          return;
        }
        self.segStartMs = Date.now();
        hilog.info(DOMAIN, TAG, 'onStart: id=%{public}s seg=%{public}d/%{public}d',
          requestId, self.queue.cursorIndex + 1, self.queue.total);
        self.callbacks.onSegmentStart?.(self.queue.cursorIndex, self.queue.total,
          self.queue.segmentOffset(self.queue.cursorIndex));
      },
      onComplete(requestId: string, response: textToSpeech.CompleteResponse): void {
        // type 0 = 合成完成（音频还没播完！），type 1 = 播放完成。
        // 只有播放完成才推进队列 —— 否则会切成"合成一段播一半就跳下一段"
        if (response.type !== 1) {
          return;
        }
        if (requestId !== self.activeReqId) {
          hilog.info(DOMAIN, TAG, 'onComplete stale, dropped: id=%{public}s', requestId);
          return;
        }
        // 过期事件守卫（状态版）：用户暂停/停止后段尾 onComplete 压哨到达。
        // 此时队列已非 speaking → 死信，丢弃：不推进（否则把暂停态冲掉），
        // 更不触发 onAllDone（否则无故翻页）。
        if (self.queue.state !== 'speaking') {
          hilog.info(DOMAIN, TAG, 'onComplete stale (state=%{public}s), dropped: id=%{public}s',
            self.queue.state, requestId);
          return;
        }
        hilog.info(DOMAIN, TAG, 'onComplete: id=%{public}s seg=%{public}d/%{public}d',
          requestId, self.queue.cursorIndex + 1, self.queue.total);
        // 段播完：用实际播放时长校准语速估算（位置同步/续读准不准全靠它）。
        // 必须在 advance() **之前**取当前段长度。
        const doneChars: number = self.queue.currentLength();
        const secs: number = (Date.now() - self.segStartMs) / 1000;
        self.cps = updateCharsPerSec(self.cps, doneChars, secs);
        const done: number = self.queue.cursorIndex;
        const total: number = self.queue.total;
        self.callbacks.onSegmentDone?.(done, total);
        const next: string | null = self.queue.advance();
        if (next === null) {
          self.callbacks.onAllDone?.();
          return;
        }
        self.speakCurrent(next);
      },
      onStop(_requestId: string, _response: textToSpeech.StopResponse): void {
        // 引擎侧停止（用户主动 stop/pause 也会走到这）；队列状态由 stop()/pause() 管，
        // 这里不碰状态机 —— 否则"播完自动 stopped"会被 onStop 误清
      },
      onError(requestId: string, errorCode: number, errorMessage: string): void {
        if (requestId !== self.activeReqId) {
          // 旧 speak 的残错误（seek 换段后被 stop 的那个）—— 不上抛，免幽灵提示
          hilog.info(DOMAIN, TAG, 'onError stale, dropped: id=%{public}s code=%{public}d',
            requestId, errorCode);
          return;
        }
        hilog.error(DOMAIN, TAG, 'speak onError: id=%{public}s code=%{public}d msg=%{public}s',
          requestId, errorCode, errorMessage);
        self.callbacks.onError?.(errorMessage);
      }
    };
    return listener;
  }

  /** speak 当前段（内部：调用前必须已 ensureReady + 队列已 begin/seek/resume） */
  private speakCurrent(text: string): void {
    const eng: textToSpeech.TextToSpeechEngine | null = this.engine;
    if (eng === null) {
      return;
    }
    this.reqSeq++;
    // 语速接入（2026-10-22 评审 P0-3 断头路清零）：
    //   一期注释说"extraParams 三条路全堵"——堵的真因是**无类型注解的字面量**
    //   （arkts-no-untyped-obj-literals 只拒裸字面量；官方 workaround 恰恰就是
    //   带注解的 Record 字面量：`let r: Record<string, Object> = {'k': 123}` 是
    //   ArkTS 文档原例）。带注解写法编译通过，语速终于生效。
    //   speed 为浮点（0.5~2.0，setSpeed 已夹取）；键名用官方口径 'speed'。
    //   ⚠️ CoreSpeechKit 的 speed 是 **per-speak 参数**：改速对正在播的段不生效，
    //   下一段起生效（UI 文案如实标注）。
    const extra: Record<string, Object> = { 'speed': this.speed };
    const params: textToSpeech.SpeakParams = { requestId: 'rr-' + Date.now() + '-' + this.reqSeq };
    params.extraParams = extra;
    this.activeReqId = params.requestId;
    try {
      eng.speak(text, params);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'speak threw: %{public}s', JSON.stringify(e));
      this.callbacks.onError?.('朗读启动失败');
    }
  }
}
