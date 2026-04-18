extends SceneTree
## LLMClient 命令行验证脚本（headless）。
##
## 运行：
##   export OPENAI_API_KEY="sk-..."
##   export OPENAI_BASE_URL="https://api.deepseek.com/v1"   # 可选
##   export OPENAI_MODEL="deepseek-chat"                     # 可选
##   godot --headless --path /home/ffcrazy/proj/game --script res://scripts/llm/llm_client_test.gd
##
## 退出码：0 = 成功，1 = 失败或未配置 key。

# 用 preload 而非 class_name 直接引用：--script 启动模式下全局 class 注册表尚未生效。
const LLMClientScript = preload("res://scripts/llm/llm_client.gd")


func _init() -> void:
	_run()


func _run() -> void:
	# env 变量为空时不覆盖 client 默认值（允许在 llm_client.gd 里直接硬编码做本地测试）
	var api_key := OS.get_environment("OPENAI_API_KEY")
	var base_url := OS.get_environment("OPENAI_BASE_URL")
	var model := OS.get_environment("OPENAI_MODEL")

	var client = LLMClientScript.new()
	if not api_key.is_empty():
		client.api_key = api_key
	if not base_url.is_empty():
		client.base_url = base_url
	if not model.is_empty():
		client.model = model
	root.add_child(client)
	# 等子节点 _ready 跑完
	await process_frame

	print("[llm_test] base_url=%s  model=%s" % [client.base_url, client.model])
	print("[llm_test] 发送请求中...")

	var resp: Dictionary = await client.chat_completion([
		{"role": "user", "content": "用一句话介绍赵州桥。"}
	], {"max_tokens": 200, "temperature": 0.7})

	if resp.ok:
		print("[llm_test] OK")
		print("---")
		print(resp.text)
		print("---")
		quit(0)
	else:
		print("[llm_test] FAIL  code=%d" % resp.code)
		print("[llm_test] error=%s" % resp.error)
		quit(1)
