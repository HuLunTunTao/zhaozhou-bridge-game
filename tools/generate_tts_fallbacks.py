#!/usr/bin/env python3
"""为 LLM fallback 文本预合成火山 TTS MP3。

工作流：
    1. 在 Godot 编辑器里维护 npc_personas.fallback_lines + voice_mapping.gd
    2. 跑 `godot --headless --path . --script res://tools/dump_fallback_manifest.gd`
       生成 data/tts_fallback_manifest.json
    3. 跑这个 Python 脚本 `--bake` 调火山 HTTP TTS API 烤 mp3
    4. 跑 `--check` 校验 manifest 与本地 mp3 一致

环境：
    需 .env 提供 VOLC_TTS_API_KEY（也可在 shell 里 export）
    可选 VOLC_TTS_RESOURCE_ID（默认 seed-tts-2.0）/ VOLC_TTS_USER_UID（默认 fallback-baker）

用法：
    python tools/generate_tts_fallbacks.py --bake               # 烤所有缺失的
    python tools/generate_tts_fallbacks.py --bake --force       # 重烤覆盖
    python tools/generate_tts_fallbacks.py --bake --only hero_li_chun,bridge_old_master
    python tools/generate_tts_fallbacks.py --check              # 仅校验文件存在性

依赖：requests（pip install requests）
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import ssl
import sys
import time
import uuid
from typing import Iterator, Sequence

ENDPOINT = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
DEFAULT_MANIFEST = "data/tts_fallback_manifest.json"
THROTTLE_SEC = 0.3   # 每条请求间节流，避免火山限流
TIMEOUT_SEC = 30     # 单次 HTTP 总超时


def synthesize(api_key: str, resource_id: str, user_uid: str,
               voice: str, text: str, context_texts: Sequence[str] | None = None) -> bytes:
    """调火山 unidirectional HTTP TTS 端点，返回完整 MP3 字节。"""
    headers = {
        "Content-Type": "application/json",
        "X-Api-Key": api_key,
        "X-Api-Resource-Id": resource_id,
        "X-Api-Connect-Id": str(uuid.uuid4()),
        "X-Api-Request-Id": str(uuid.uuid4()),
    }
    req_params = {
        "text": text,
        "speaker": voice,
        "audio_params": {"format": "mp3"},
    }
    if context_texts:
        req_params["additions"] = json.dumps(
            {"context_texts": list(context_texts)},
            ensure_ascii=False,
        )
    body = {
        "user": {"uid": user_uid},
        "req_params": req_params,
    }
    try:
        return _synthesize_with_requests(headers, body)
    except ModuleNotFoundError:
        return _synthesize_with_urllib(headers, body)


def _collect_audio_from_lines(lines: Iterator[str]) -> bytes:
    audio = bytearray()
    for raw in lines:
        if not raw:
            continue
        try:
            d = json.loads(raw)
        except json.JSONDecodeError:
            continue   # 火山偶尔混入 keep-alive 空行
        code = d.get("code", -1)
        if code == 20000000:
            break        # 正常结束信号
        if code != 0:
            msg = d.get("message", "?")
            raise RuntimeError(f"火山返回 code={code} msg={msg}")
        data = d.get("data")
        if isinstance(data, str) and data:
            audio.extend(base64.b64decode(data))
    return bytes(audio)


def _synthesize_with_requests(headers: dict, body: dict) -> bytes:
    import requests   # 延迟导入：仅 bake 模式需要
    with requests.post(ENDPOINT, json=body, headers=headers,
                       stream=True, timeout=TIMEOUT_SEC) as resp:
        resp.raise_for_status()
        return _collect_audio_from_lines(resp.iter_lines(decode_unicode=True))


def _synthesize_with_urllib(headers: dict, body: dict) -> bytes:
    import urllib.error
    import urllib.request
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    context = None
    if os.environ.get("VOLC_TTS_INSECURE_SSL", "").strip() in {"1", "true", "TRUE", "yes", "YES"}:
        context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC, context=context) as resp:
            lines = (line.decode("utf-8").strip() for line in resp)
            return _collect_audio_from_lines(lines)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {detail[:200]}") from e


def normalize_context_texts(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()]


def cmd_bake(args, manifest: dict, repo_root: pathlib.Path) -> int:
    api_key = os.environ.get("VOLC_TTS_API_KEY", "").strip()
    if not api_key:
        print("ERROR: 环境变量 VOLC_TTS_API_KEY 未设置", file=sys.stderr)
        return 2
    resource_id = os.environ.get("VOLC_TTS_RESOURCE_ID",
                                 manifest.get("default_resource_id", "seed-tts-2.0"))
    user_uid = os.environ.get("VOLC_TTS_USER_UID", "fallback-baker")
    only = set(s.strip() for s in (args.only or "").split(",") if s.strip())

    items = manifest.get("items", [])
    n_ok = n_skip = n_fail = 0
    for it in items:
        unit_id = it.get("unit_id", "")
        if only and unit_id not in only:
            continue
        out_rel = it.get("output", "")
        if not out_rel:
            continue
        out = repo_root / out_rel
        if out.exists() and not args.force:
            n_skip += 1
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        slug = it.get("slug", "?")
        text = it.get("tts_text") or it.get("text", "")
        voice = it.get("voice", "")
        context_texts = normalize_context_texts(it.get("context_texts"))
        if not text or not voice:
            print(f"[SKIP] {unit_id}/{slug} 缺 text/voice", file=sys.stderr)
            n_fail += 1
            continue

        for attempt in range(args.retry + 1):
            try:
                audio = synthesize(api_key, resource_id, user_uid, voice, text, context_texts)
                if not audio:
                    raise RuntimeError("空音频")
                out.write_bytes(audio)
                size_kb = len(audio) / 1024
                ctx_flag = "[CTX]" if context_texts else "     "
                print(f"[OK]{ctx_flag} {unit_id}/{slug}  {size_kb:.1f}KB  '{text[:18]}...'")
                n_ok += 1
                break
            except Exception as e:
                wait = 1.5 * (attempt + 1)
                print(f"[WARN] {unit_id}/{slug} attempt {attempt+1}: {e}; wait {wait:.1f}s",
                      file=sys.stderr)
                time.sleep(wait)
        else:
            n_fail += 1
        time.sleep(THROTTLE_SEC)

    total = len(items) if not only else sum(1 for it in items if it.get("unit_id") in only)
    print()
    print(f"完成: ok={n_ok} skip={n_skip} fail={n_fail} (total filtered={total})")
    return 0 if n_fail == 0 else 1


def cmd_check(args, manifest: dict, repo_root: pathlib.Path) -> int:
    """校验 manifest 里每个 item 的 output mp3 文件是否存在。"""
    items = manifest.get("items", [])
    missing = []
    for it in items:
        out_rel = it.get("output", "")
        if not out_rel:
            continue
        out = repo_root / out_rel
        if not out.exists():
            missing.append((it.get("unit_id", "?"), it.get("slug", "?"), out_rel))
    if not missing:
        print(f"[CHECK] 全部 {len(items)} 条 item 的 mp3 文件都存在 ✓")
        return 0
    print(f"[CHECK] 缺失 {len(missing)} / {len(items)} 条：", file=sys.stderr)
    for unit_id, slug, path in missing[:30]:
        print(f"  - {unit_id}/{slug}  {path}", file=sys.stderr)
    if len(missing) > 30:
        print(f"  ... 以及另外 {len(missing) - 30} 条", file=sys.stderr)
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    p_bake = sub.add_parser("bake", help="调火山 API 批量合成 mp3")
    p_bake.add_argument("--manifest", default=DEFAULT_MANIFEST)
    p_bake.add_argument("--force", action="store_true", help="覆盖已存在 mp3")
    p_bake.add_argument("--only", default="", help="逗号分隔 unit_id 白名单")
    p_bake.add_argument("--retry", type=int, default=2, help="单条失败重试次数")

    p_check = sub.add_parser("check", help="校验 manifest 与本地 mp3 一致")
    p_check.add_argument("--manifest", default=DEFAULT_MANIFEST)

    # 兼容老用法（python tool.py --bake）作 default cmd
    ap.add_argument("--bake", action="store_const", const="bake", dest="_legacy_cmd")
    ap.add_argument("--check", action="store_const", const="check", dest="_legacy_cmd")
    ap.add_argument("--manifest", default=DEFAULT_MANIFEST, help=argparse.SUPPRESS)
    ap.add_argument("--force", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--only", default="", help=argparse.SUPPRESS)
    ap.add_argument("--retry", type=int, default=2, help=argparse.SUPPRESS)

    args = ap.parse_args()
    cmd = args.cmd or args._legacy_cmd
    if not cmd:
        ap.print_help()
        return 0

    repo_root = pathlib.Path(__file__).resolve().parent.parent
    manifest_path = repo_root / args.manifest
    if not manifest_path.exists():
        print(f"ERROR: 找不到 manifest {manifest_path}", file=sys.stderr)
        print("先跑：godot --headless --path . --script res://tools/dump_fallback_manifest.gd",
              file=sys.stderr)
        return 2
    manifest = json.loads(manifest_path.read_text("utf-8"))

    if cmd == "bake":
        return cmd_bake(args, manifest, repo_root)
    if cmd == "check":
        return cmd_check(args, manifest, repo_root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
