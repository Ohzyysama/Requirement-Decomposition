"""
对单个 SR 文件跑一次完整的拆分并保存结果。

用法:
  PYTHONPATH=. python scripts/run_single_sr.py \
      --sr-file ../SaltPlayerHarmonyEval-eval-requirement-testset/eval/requirements/SR/SR-01-playback.md \
      --token "你的token" \
      --label "optimized"
"""
import argparse
import asyncio
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional

# Windows GBK -> UTF-8
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import httpx


API_BASE = "http://127.0.0.1:8000/api/v1"
TIMEOUT = 900  # 15 分钟


def parse_sr_file(filepath: Path) -> Dict[str, str]:
    text = filepath.read_text(encoding="utf-8")
    result: Dict[str, str] = {}
    m = re.match(r"#\s*(SR-\d+)\s*(.*)", text)
    if m:
        result["sr_id"] = m.group(1).strip()
        result["title"] = m.group(2).strip()
    for match in re.finditer(r"\[\s*([^\]]+)\s*\]\s*\|\s*(.+)", text):
        key = match.group(1).strip()
        value = match.group(2).strip()
        result[key] = value
    return result


def count_metrics(function_list: list) -> dict:
    if not function_list:
        return {"node_count": 0, "max_depth": 0, "leaf_count": 0}

    by_id = {}
    for r in function_list:
        if isinstance(r, dict):
            nid = str(r.get("id", "")).strip()
            if nid:
                by_id[nid] = r

    # 计算深度
    memo = {}
    def depth(nid, visited):
        if nid in memo:
            return memo[nid]
        if nid in visited:
            return 0
        visited.add(nid)
        row = by_id.get(nid, {})
        pid = str(row.get("parent_id", "")).strip()
        if not pid or pid not in by_id:
            memo[nid] = 1
            return 1
        d = 1 + depth(pid, visited.copy())
        memo[nid] = d
        return d

    max_d = max(depth(nid, set()) for nid in by_id) if by_id else 0

    # 叶子数
    all_ids = set(by_id.keys())
    parent_ids = {str(by_id[nid].get("parent_id", "")).strip() for nid in by_id}
    leaf_ids = all_ids - parent_ids
    if not leaf_ids:
        leaf_ids = all_ids

    return {
        "node_count": len(function_list),
        "max_depth": max_d,
        "leaf_count": len(leaf_ids),
        "nodes": [
            {"id": str(r.get("id", "")), "title": str(r.get("title", "")),
             "parent_id": str(r.get("parent_id", "")), "desc": str(r.get("desc", ""))[:80]}
            for r in function_list if isinstance(r, dict)
        ]
    }


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sr-file", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--label", default="run")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    sr_file = Path(args.sr_file)
    if not sr_file.exists():
        print(f"❌ 文件不存在: {sr_file}")
        sys.exit(1)

    data = parse_sr_file(sr_file)
    sr_id = data.get("sr_id", sr_file.stem)
    title = data.get("需求标题", data.get("title", sr_id))
    requirement = data.get("需求描述", "")

    if not requirement:
        print(f"❌ 未找到 [需求描述] 字段")
        sys.exit(1)

    print(f"📋 {sr_id} — {title}")
    print(f"   需求长度: {len(requirement)} 字符")
    print(f"   标签: {args.label}")
    print()

    headers = {"Authorization": f"Bearer {args.token}"}

    async with httpx.AsyncClient(
        headers=headers,
        timeout=httpx.Timeout(TIMEOUT, connect=30.0),
        follow_redirects=True,
    ) as client:
        # 1. 创建对话
        resp = await client.post(
            f"{API_BASE}/conversations",
            json={
                "title": f"[评测-{args.label}] {sr_id} {title}",
                "description": f"{args.label} 版本评测",
                "original_requirement": requirement,
            },
        )
        resp.raise_for_status()
        conv_id = resp.json()["id"]
        print(f"   对话ID: {conv_id}")

        # 2. 启动协调器
        resp = await client.post(
            f"{API_BASE}/coordinator/start",
            json={
                "conversation_id": conv_id,
                "config": {
                    "consistency_pass_threshold": 0.7,
                    "consistency_inner_max_retries": 1,
                    "continue_pipeline_after_consistency_exhausted": False,
                    "enable_feasibility_refinement": True,
                    "max_feasibility_refinement_depth": 1,
                },
            },
        )
        resp.raise_for_status()
        print(f"   任务已启动: {resp.json().get('message', '')}")

        # 3. 轮询等待
        start = time.time()
        while time.time() - start < TIMEOUT:
            resp = await client.get(f"{API_BASE}/conversations/{conv_id}")
            conv = resp.json()
            status = conv.get("status", "")

            elapsed = int(time.time() - start)
            if status in ("completed", "done"):
                print(f"   ✅ 完成! 耗时: {elapsed}s")

                # 获取最终结果
                result_resp = await client.get(
                    f"{API_BASE}/coordinator/tasks/{conv_id}/result"
                )
                final = result_resp.json() if result_resp.status_code == 200 else {}
                fl = final.get("function_list") or []

                # 如果没有 function_list，从 metadata 中找
                if not fl:
                    meta = conv.get("conversation_metadata") or {}
                    fr = meta.get("final_result") or {}
                    fl = fr.get("function_list") or []

                metrics = count_metrics(fl if isinstance(fl, list) else [])

                # 评估信息
                eval_info = {}
                eps = final.get("evaluation_episodes") or []
                if eps:
                    last_ep = eps[-1]
                    bundle = last_ep.get("bundle") or {}
                    ev = bundle.get("evaluation") or {}
                    eval_info = {
                        "consistency_score": ev.get("consistency_score"),
                        "feasibility_score": ev.get("feasibility_score"),
                        "overall_score": ev.get("overall_score"),
                        "recommendation": ev.get("recommendation"),
                    }

                result = {
                    "sr_id": sr_id,
                    "title": title,
                    "label": args.label,
                    "conversation_id": conv_id,
                    "elapsed_seconds": elapsed,
                    "metrics": metrics,
                    "evaluation": eval_info,
                    "function_list": fl if isinstance(fl, list) else [],
                }

                out_path = args.out or f"eval_result_{args.label}_{sr_id}.json"
                Path(out_path).write_text(
                    json.dumps(result, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
                print(f"   📁 结果: {out_path}")
                print(f"   节点数: {metrics['node_count']}")
                print(f"   最大深度: {metrics['max_depth']}")
                print(f"   叶子数: {metrics['leaf_count']}")
                if eval_info:
                    print(f"   一致性: {eval_info.get('consistency_score')}")
                    print(f"   可实现性: {eval_info.get('feasibility_score')}")
                    print(f"   综合: {eval_info.get('overall_score')}")
                return

            if status in ("failed", "error"):
                print(f"   ❌ 失败: status={status}")
                return

            # 进度
            dots = "." * ((elapsed // 5) % 4 + 1)
            print(f"\r   等待中{dots}   {elapsed}s", end="", flush=True)
            await asyncio.sleep(5)

        print(f"\n   ⏰ 超时")


if __name__ == "__main__":
    asyncio.run(main())
