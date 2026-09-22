class_name ApiConfig
## 全部对外 API 的密钥 / URL / 模型集中在这里。
## 任何接外网的脚本（LLMClient、VolcengineTTSClient 等）都从本类读默认值。
##
## 改 key / 换模型 / 切端点 → 只改这一个文件。
## 想覆盖默认值（比如测试场景里临时换 key），运行时直接给客户端实例的字段赋值即可。


# ────────────── LLM（OpenAI Chat Completions 兼容）──────────────

## API 根地址，不带尾斜杠。chat completions 端点会拼成 base_url + "/chat/completions"。
const LLM_BASE_URL: String = ""

## 形如 "sk-..."。空字符串则 LLMClient 拒绝请求。
const LLM_API_KEY: String = ""

## 模型名。按 base_url 服务方约定。
const LLM_MODEL: String = ""

## 默认请求超时秒数。0 表示不超时。
const LLM_TIMEOUT_SEC: float = 30.0


# ────────────── 火山引擎 TTS（豆包语音合成 2.0 双向流式）──────────────

## WebSocket 入口。生产环境一般不用改。
const TTS_WS_URL: String = "wss://openspeech.bytedance.com/api/v3/tts/bidirection"

## 资源 ID。和模型代际绑定（seed-tts-2.0 / 1.0），不要混搭。
const TTS_RESOURCE_ID: String = "seed-tts-2.0"

## 火山控制台拿到的 API Key。空字符串则 VolcengineTTSClient 跳过合成
## 并允许 ChatterScheduler 走系统 TTS 兜底。
const TTS_API_KEY: String = ""

## 模型名。空字符串走音色默认；常用："seed-tts-2.0-expressive"
const TTS_MODEL: String = "seed-tts-2.0-expressive"

## 用户 ID，仅服务端日志用，本地随便填。
const TTS_USER_UID: String = "wcx-game-user"

## 音频参数（mp3 24kHz 128kbps 通用够用）。
const TTS_AUDIO_FORMAT: String = "mp3"
const TTS_SAMPLE_RATE: int = 24000
const TTS_BIT_RATE: int = 128000


# ────────────── 工具方法 ──────────────

## 当前 LLM 配置是否完整可用。
static func has_llm() -> bool:
	return not LLM_API_KEY.is_empty() and not LLM_BASE_URL.is_empty()


## 当前火山 TTS 配置是否完整可用。失败时调用方应回落到系统 TTS 或静默。
static func has_volcengine_tts() -> bool:
	return not TTS_API_KEY.is_empty()
