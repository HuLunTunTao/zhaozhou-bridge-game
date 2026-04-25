# godot-cloud-tts

> 本项目是基于公开接口文档实现的第三方非官方 Godot 调用库，
> 用于方便开发者快捷在 Godot 游戏中接入豆包语音合成 2.0 相关功能

> 本项目不隶属于字节跳动、火山引擎或豆包，也未获得其官方背书。
> 使用者需要自行开通相关服务、获取 API Key，并遵守火山引擎相关服务条款。

支持火山官方三个端点：

| 端点 | 用途 | SSML | 延迟 |
|---|---|---|---|
| `wss://.../tts/bidirection` | LLM token streaming → TTS（边喂文字边出音频） | ❌ | ~1s 首音 |
| `wss://.../tts/unidirectional/stream` | 一次塞文本，PCM/MP3 流式吐回 | ✅ | ~1s 首音 |
| `https://.../tts/unidirectional` | 一次塞文本，等所有 chunk 拼成完整 mp3 字节 | ✅ | ~3-5s |

SDK 零项目依赖：复制 `addons/godot_volcengine_tts/` 到任何 Godot 4 项目即可使用。

## 5 分钟接入

1. 复制本插件目录到 `addons/godot_volcengine_tts/`
2. 在 `项目设置 → 插件` 启用 "Godot Volcengine TTS"
3. 代码里调用：

```gdscript
extends Node

func _ready() -> void:
	var voice := VolcengineStreamingVoicePlayer.new()
	voice.audio_bus = &"Master"
	add_child(voice)

	# 三个 client 各自需要 api_key（key 来源由你决定）
	for c in [voice.bidi_client, voice.uni_client, voice.http_client]:
		c.api_key = "your-volcengine-api-key"
		c.resource_id = "seed-tts-2.0"
		c.default_model = "seed-tts-2.0-expressive"

	await voice.speak("你好，世界。", "zh_male_dayi_uranus_bigtts")
```

## 三种用法

### 用法 A · 单句流式播放（最常用）

```gdscript
var voice := VolcengineStreamingVoicePlayer.new()
add_child(voice)
voice.uni_client.api_key = "..."

# 简单调用，opts 全默认
await voice.speak("依老朽看，这桥要成。", "zh_male_dayi_uranus_bigtts")

# 带情绪 / 语速参数
await voice.speak("你别过来！", "zh_male_dayi_uranus_bigtts", {
	"emotion": "scared",
	"emotion_scale": 5,
	"speech_rate": 20,
})

# 带 SSML
await voice.speak("", "zh_female_xiaohe_uranus_bigtts", {
	"ssml": "<speak>测试<break time=\"500ms\"/>停顿</speak>",
})
```

`speak()` 走单向流式 WS，输出强制 PCM（自动喂入 `AudioStreamGenerator`）。
返回 true / false 表示成功；同时 emit `speak_finished` 信号。

### 用法 B · 真双向（LLM token streaming）

```gdscript
voice.bidi_client.api_key = "..."

await voice.start_streaming("zh_male_dayi_uranus_bigtts")

# 假装 LLM 逐 token 吐字
for chunk in ["依老朽看，", "这桥要成。", "须得脚下踩稳。"]:
	voice.feed_text(chunk)
	await get_tree().create_timer(0.3).timeout

voice.finish_streaming()
await voice.speak_finished
```

特点：
- session 内多次 feed_text 共享 prosody（语调连贯）
- **不**支持 SSML（火山协议限制）
- 首音延迟最低（~1s）

### 用法 C · 拿原始字节（缓存 / 预生成）

```gdscript
voice.http_client.api_key = "..."

var mp3 := await voice.fetch_audio("欢迎光临", "zh_male_dayi_uranus_bigtts", {
	"format": "mp3",
})
FileAccess.open("user://welcome.mp3", FileAccess.WRITE).store_buffer(mp3)
```

走 HTTP Chunked，返回完整 mp3 字节。适合：
- 预合成固定台词（cutscene、UI 提示音）
- 持久化缓存（避免重复消耗 token）
- 不要 streaming player 的简单场景

## 上下文支持

### 服务端原生（仅 TTS 2.0）

| opts 键 | 说明 | 示例 |
|---|---|---|
| `context_texts` | 自然语言 hint（list[String]，仅第一项有效）| `["你能用骄傲的语气说话吗？"]` |
| `section_id` | 上一段会话的 session_id，让模型基于上下文延续 | `"bf5b5771-31cd-..."`（最长 30 轮 / 10 分钟） |

### 客户端自动续接

```gdscript
voice.auto_context_chain = true   # 开启
await voice.speak("依老朽看", voice_id)        # 这次返回 session_id 1
await voice.speak("这桥要成", voice_id)        # 自动用 session_id 1 作为 section_id
await voice.speak("须得脚下踩稳", voice_id)    # 自动用 session_id 2 作为 section_id

voice.reset_context_chain()                     # 显式断链（角色换了/场景换了）
await voice.speak("新场景的台词", voice_id)    # 重新开始
```

## opts 完整参考

`opts` 是扁平 Dictionary，SDK 自动归位到火山 protobuf 嵌套结构。

### 常用键（Tier 2）

| 键 | 类型 | 范围 / 取值 | 默认 | 适用 |
|---|---|---|---|---|
| `format` | String | `"mp3"` / `"pcm"` / `"wav"` / `"ogg_opus"` | `"mp3"` | 全部 |
| `sample_rate` | int | 8000 / 16000 / 22050 / 24000 / 32000 / 44100 / 48000 | 24000 | 全部 |
| `bit_rate` | int | 16k-160k | – | 仅 mp3 |
| `emotion` | String | `"happy"` / `"sad"` / `"angry"` / `"scared"` / ... | – | 多情感音色 |
| `emotion_scale` | int | 1-5 | 4 | 多情感音色 |
| `speech_rate` | int | -50 ~ 100（100=2x 速）| 0 | 全部 |
| `loudness_rate` | int | -50 ~ 100（100=2x 音量）| 0 | 非 mix 音色 |
| `model` | String | `"seed-tts-2.0-expressive"` / `"seed-tts-2.0-standard"` | – | – |
| `ssml` | String | 完整 `<speak>...</speak>` | – | uni / http |
| `context_texts` | Array[String] | 自然语言 hint | – | TTS 2.0 |
| `section_id` | String | 上一段 session_id | – | TTS 2.0 |
| `silence_duration` | int | 句尾静音 ms（0-30000） | 0 | – |
| `disable_markdown_filter` | bool | 关闭 markdown 过滤 | false | – |
| `explicit_language` | String | `"zh-cn"` / `"en"` / `"ja"` / ... | – | – |
| `enable_subtitle` | bool | 返回字幕事件 | false | TTS 2.0 / ICL 2.0 |

完整字段定义见 [`tts_options.gd`](tts_options.gd)。

### 逃生口（Tier 3）

```gdscript
opts = {
	"emotion": "happy",
	# 火山新加的字段，SDK 不认识，原样塞进 audio_params
	"audio_params_extra": { "future_unknown_field": "value" },
	# 注入 additions（会被 stringify 进 jsonstring）
	"additions_extra": { "with_frontend_text": true },
	# 终极覆盖：完全自定义 req_params（绕过所有合并）
	"raw_req_params": { ... },
}
```

## API 概览

```
VolcengineStreamingVoicePlayer extends Node       # 高层壳
├── 用法 A：speak(text, voice, opts) → bool       # 单向 WS，PCM 流式播放
│   signal speak_finished
├── 用法 B：start_streaming(voice, opts)          # 双向 WS
│         feed_text(chunk) / finish_streaming()
├── 用法 C：fetch_audio(text, voice, opts) → PackedByteArray   # HTTP，全字节
├── auto_context_chain / reset_context_chain()
├── is_speaking() / current_session_id()
└── 暴露的 client：bidi_client / uni_client / http_client（用于配 api_key）

VolcengineTTSBidirectionalClient extends Node     # 端点 1（低层）
├── start_session(voice, opts) → bool
├── feed_text(chunk) / finish_session()
├── signal audio_chunk_received(chunk)
├── signal session_finished(session_id) / session_failed(reason)
└── @export api_key / base_url / path / resource_id / user_uid / default_model

VolcengineTTSUnidirectionalClient extends Node    # 端点 2（低层）
└── synthesize_streaming(text, voice, on_chunk: Callable, opts, out_session_id) → bool

VolcengineTTSHttpClient extends Node              # 端点 3（低层）
└── synthesize(text, voice, opts, out_session_id) → PackedByteArray

TtsOptions (静态工具)
├── build_req_params(voice, opts) → Dictionary
├── warn_if_ssml_unsupported(voice, endpoint_kind)
└── get_audio_format(opts) / get_sample_rate(opts)
```

## 协议踩坑笔记

1. **PCM 优于 MP3 用于流式**：火山文档明确「在流式场景下传入 wav 会多次返回 wav header，建议使用 pcm」。SDK 内 `speak()` 强制 PCM；要 mp3 用 `fetch_audio()`。
2. **`bit_rate` 仅对 MP3 生效**：传 pcm 时 `bit_rate` 会被忽略；wav 比特率 = 采样率 × 位深 × 声道。
3. **超时是"无活动"超时**：每收到一个 WS 包就重置 deadline（默认 20s 无任何包到达才算超时）。长文本（>20s 音频）不会被误杀。
4. **SSML 路径**：
   - 仅 `unidirectional` / `http` 端点支持
   - 双向流式协议层就不允许，硬塞会被拒
   - `saturn_` 前缀 / `_saturn_bigtts` 后缀的 ICL 2.0 复刻音色不支持 SSML
   - 单次 SSML 含标签 ≤ 150 字
5. **`context_texts` / `section_id` 仅 TTS 2.0**：1.0 / ICL 1.0 音色传了不报错但无效。
6. **base_url 切换**：所有 client 的 `base_url` 默认 `openspeech.bytedance.com`。要切镜像或兼容站点，赋值即可：
   ```gdscript
   client.base_url = "your-mirror.example.com"
   client.path = "/api/v3/tts/bidirection"   # 一般不变
   ```
7. **资源 ID 与计费绑定**：`resource_id` 决定模型代际和计费方式：
   - `seed-tts-2.0` → 2.0 字符版
   - `seed-tts-1.0` / `seed-tts-1.0-concurr` → 1.0 字符版 / 并发版
   - `seed-icl-2.0` / `seed-icl-1.0` → 声音复刻
8. **空文本 vs SSML**：用 SSML 时 `text` 字段火山要求空字符串；SDK 已自动处理。
9. **HTTP 响应是行式 JSON**：每行一个 `{code, message, data: base64}`，data 字段需 base64 解码后 append 到字节流。SDK 内 `_process_line` 已实现。

## 限制

- 暂不支持 SSE 端点（`/api/v3/tts/unidirectional/sse`）。HTTP Chunked 已覆盖等效场景。
- 暂不支持时间戳事件（`enable_timestamp` / `enable_subtitle`）的字幕回调——服务端会发字幕帧，SDK 当前丢弃。后续按需补 `subtitle_received` 信号。
- 不内置音色清单：`voice` 是字符串参数，由调用方维护。火山会持续新增音色，SDK 不假装懂哪些 voice_type 存在。
- 不内置系统 TTS 兜底：失败处理由调用方决定（`session_failed` 信号 / 返回 false）。

## 许可证

MIT。详见 `LICENSE`。

## 免责声明

> 本项目是第三方非官方 Godot TTS 调用库，不隶属于字节跳动、火山引擎或豆包，
> 也未获得其官方背书或赞助。
> 
> 项目中提及的商标、产品名、服务名归其各自权利人所有。
> 
> 使用者需要自行开通相关服务、获取 API 凭证，并自行遵守火山引擎相关服务条款、计费规则、调用限制和内容合规要求。

## 参考文档

本项目基于火山引擎公开接口文档实现，主要参考：

- 火山引擎语音合成接口文档：  
  https://www.volcengine.com/docs/6561/1598757
  https://www.volcengine.com/docs/6561/1719100
  https://www.volcengine.com/docs/6561/1329505

- 火山引擎 SDK 合规 / 隐私相关文档：  
  https://www.volcengine.com/docs/6561/116711

- 火山引擎服务条款：  
  https://www.volcengine.com/docs/6256/64903