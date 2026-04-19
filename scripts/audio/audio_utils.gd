class_name AudioUtils
extends RefCounted
## 音频工具函数集。提供程序化生成提示音等共享方法。

const SAMPLE_RATE := 22050

# Kimi Code，2026-04-19

## 生成单声道 16-bit 正弦波提示音。
## freq_a: 主频率(Hz)；duration: 时长(秒)；amplitude: 振幅(0~1)；
## freq_b: 可选第二频率，>0 时与主频率混合。
static func make_tone(freq_a: float, duration: float, amplitude: float, freq_b: float = 0.0) -> AudioStreamWAV:
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := 1.0 - (float(i) / float(sample_count))
		var sample := sin(TAU * freq_a * t)
		if freq_b > 0.0:
			sample = (sample + sin(TAU * freq_b * t)) * 0.5
		var value := int(clampf(sample * amplitude * envelope, -1.0, 1.0) * 32767.0)
		data[i * 2] = value & 0xff
		data[i * 2 + 1] = (value >> 8) & 0xff

	var wav := AudioStreamWAV.new()
	wav.data = data
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	return wav
