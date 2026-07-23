"""
对 SaltPlayerHarmonyEval 测试集的 15 个 SR 做批量需求拆分评测。

用法:
  1. 确保后端已启动 (uvicorn app.main:app)
  2. 先注册用户并获取 token
  3. 运行: PYTHONPATH=. python scripts/run_sr_eval.py --token <your_token>

依赖: pip install httpx
"""
import argparse
import asyncio
import json
import os
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

import httpx

# ─── 配置 ──────────────────────────────────────────────
API_BASE = os.getenv("EVAL_API_BASE", "http://127.0.0.1:8000/api/v1")
SR_DIR = Path(__file__).resolve().parent.parent.parent / \
    "SaltPlayerHarmonyEval-eval-requirement-testset" / "eval" / "requirements" / "SR"
JUDGMENT_FILE = Path(__file__).resolve().parent.parent.parent / \
    "SaltPlayerHarmonyEval-eval-requirement-testset" / "eval" / "requirements" / \
    "decomposition-judgment-points.md"
TIMEOUT = 600  # 每个 SR 最长等待 10 分钟


# ─── 解析 SR 文件 ──────────────────────────────────────

def parse_sr_file(filepath: Path) -> Dict[str, str]:
    """从 SR markdown 文件中提取结构化需求字段。"""
    text = filepath.read_text(encoding="utf-8")
    result: Dict[str, str] = {}

    # 提取 SR-ID 和标题
    m = re.match(r"#\s*(SR-\d+)\s*(.*)", text)
    if m:
        result["sr_id"] = m.group(1).strip()
        result["title"] = m.group(2).strip()

    # 提取表格式字段 [字段名] | 值
    for match in re.finditer(r"\[\s*([^\]]+)\s*\]\s*\|\s*(.+)", text):
        key = match.group(1).strip()
        value = match.group(2).strip()
        result[key] = value

    return result


def parse_judgment_points(filepath: Path) -> List[Dict[str, str]]:
    """解析判定点文件，返回 77 个标准答案条目。"""
    text = filepath.read_text(encoding="utf-8")
    points: List[Dict[str, str]] = []

    in_table = False
    for line in text.split("\n"):
        line = line.strip()
        # 检测表格开始（判定点清单表头）
        if line.startswith("| # | SR"):
            in_table = True
            continue
        if in_table and line.startswith("|-"):
            continue
        if in_table and line.startswith("|") and re.match(r"\|\s*\d+\s*\|", line):
            parts = [p.strip() for p in line.split("|")]
            parts = [p for p in parts if p]  # 去掉首尾空
            if len(parts) >= 5:
                points.append({
                    "index": parts[0],
                    "sr_id": parts[1],
                    "sr_title": parts[2],
                    "ar_id": parts[3],
                    "ar_title": parts[4],
                })
        elif in_table and not line.startswith("|"):
            # 表格结束
            if len(points) >= 77:
                break
            in_table = False

    return points


# ─── API 客户端 ────────────────────────────────────────

class EvalClient:
    def __init__(self, token: str, base_url: str = API_BASE):
        self.token = token
        self.base_url = base_url
        self.client = httpx.AsyncClient(
            headers={"Authorization": f"Bearer {token}"},
            timeout=httpx.Timeout(TIMEOUT, connect=30.0),
        )

    async def close(self):
        await self.client.aclose()

    async def create_conversation(self, title: str, requirement: str) -> str:
        """创建对话，返回 conversation_id。"""
        resp = await self.client.post(
            f"{self.base_url}/conversations",
            json={
                "title": title,
                "description": f"评测: {title}",
                "original_requirement": requirement,
            },
        )
        resp.raise_for_status()
        data = resp.json()
        return data["id"]

    async def start_task(self, conversation_id: str):
        """启动协调器任务。"""
        resp = await self.client.post(
            f"{self.base_url}/coordinator/start",
            json={
                "conversation_id": conversation_id,
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
        return resp.json()

    async def wait_for_result(self, conversation_id: str) -> Optional[dict]:
        """轮询等待任务完成。"""
        start = time.time()
        while time.time() - start < TIMEOUT:
            resp = await self.client.get(
                f"{self.base_url}/conversations/{conversation_id}"
            )
            resp.raise_for_status()
            conv = resp.json()
            status = conv.get("status", "")

            if status in ("completed", "done"):
                # 获取最终结果
                result_resp = await self.client.get(
                    f"{self.base_url}/coordinator/tasks/{conversation_id}/result"
                )
                if result_resp.status_code == 200:
                    return result_resp.json()
                # 降级：从 conversation_metadata 读取
                meta = conv.get("conversation_metadata") or {}
                return meta.get("final_result")

            if status in ("failed", "error"):
                print(f"   ❌ 任务失败: {conv.get('quality_flags', {})}")
                return None

            await asyncio.sleep(5)

        print(f"   ⏰ 超时（{TIMEOUT}s）")
        return None


# ─── 评分 ──────────────────────────────────────────────

@dataclass
class EvalResult:
    sr_id: str = ""
    sr_title: str = ""
    conversation_id: str = ""
    function_list: List[dict] = field(default_factory=list)
    error: Optional[str] = None

    @property
    def ar_count(self) -> int:
        return len(self.function_list)


def compute_scores(
    results: List[EvalResult],
    judgment_points: List[Dict[str, str]],
) -> dict:
    """
    计算拆分召回率 / 准确率 / F1。
    这里使用一个简化的语义对齐：title 模糊匹配。
    完整评测需要人工或 LLM 辅助做语义对齐。
    """
    # 按 SR 分组标准答案
    gt_by_sr: Dict[str, List[Dict[str, str]]] = {}
    for jp in judgment_points:
        sr = jp["sr_id"]
        gt_by_sr.setdefault(sr, []).append(jp)

    total_hits = 0
    total_system_ars = 0
    total_gt_ars = sum(len(v) for v in gt_by_sr.values())
    sr_details: List[dict] = []

    for result in results:
        gt_ars = gt_by_sr.get(result.sr_id, [])
        system_ar_titles = [
            (node.get("title") or node.get("desc") or "")
            for node in result.function_list
            if isinstance(node, dict)
        ]
        total_system_ars += len(system_ar_titles)

        # 简化命中判定：标题关键词匹配
        hits = 0
        for gt in gt_ars:
            gt_title = gt["ar_title"].lower()
            for sys_title in system_ar_titles:
                # 取交集词 ≥ 2 即认为命中（简化，正式评测建议用 LLM 语义对齐）
                gt_words = set(re.findall(r"[\w一-鿿]+", gt_title))
                sys_words = set(re.findall(r"[\w一-鿿]+", sys_title.lower()))
                common = gt_words & sys_words
                if len(common) >= 2:
                    hits += 1
                    break

        total_hits += hits
        sr_details.append({
            "sr_id": result.sr_id,
            "gt_count": len(gt_ars),
            "system_ar_count": len(system_ar_titles),
            "hits": hits,
        })

    recall = total_hits / total_gt_ars if total_gt_ars else 0
    precision = total_hits / total_system_ars if total_system_ars else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0

    return {
        "total_hits": total_hits,
        "total_gt_ars": total_gt_ars,
        "total_system_ars": total_system_ars,
        "recall": round(recall, 4),
        "precision": round(precision, 4),
        "f1": round(f1, 4),
        "sr_details": sr_details,
    }


# ─── 主流程 ─────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="SR 需求拆分评测")
    parser.add_argument("--token", required=True, help="Bearer token")
    parser.add_argument("--sr", type=str, default=None,
                       help="单独跑某个 SR（如 SR-01），不传则全跑")
    parser.add_argument("--dry-run", action="store_true",
                       help="仅解析 SR 文件，不调用 API")
    args = parser.parse_args()

    # 解析 SR 文件
    sr_files = sorted(SR_DIR.glob("SR-*.md"))
    if not sr_files:
        print(f"❌ 未找到 SR 文件，路径: {SR_DIR}")
        sys.exit(1)

    sr_data_list = [(f, parse_sr_file(f)) for f in sr_files]
    if args.sr:
        sr_data_list = [(f, d) for f, d in sr_data_list if d.get("sr_id") == args.sr]
        if not sr_data_list:
            print(f"❌ 未找到 {args.sr}")
            sys.exit(1)

    # 解析标准答案
    judgment_points = parse_judgment_points(JUDGMENT_FILE) if JUDGMENT_FILE.exists() else []
    print(f"📋 预测 SR: {len(sr_data_list)} 个")
    print(f"📋 Ground Truth: {len(judgment_points)} 个 ARs")
    print()

    if args.dry_run:
        for fp, data in sr_data_list:
            req = data.get("需求描述", "")[:120]
            print(f"  {data.get('sr_id')}: {data.get('title')}")
            print(f"    需求: {req}...\n")
        return

    # 逐个 SR 跑评测
    client = EvalClient(args.token)
    results: List[EvalResult] = []

    try:
        for i, (fp, data) in enumerate(sr_data_list, 1):
            sr_id = data.get("sr_id", fp.stem)
            title = data.get("需求标题", data.get("title", sr_id))
            requirement = data.get("需求描述", "")

            if not requirement:
                print(f"⚠️  [{i}/{len(sr_data_list)}] {sr_id}: 无需求描述，跳过")
                continue

            print(f"🔄 [{i}/{len(sr_data_list)}] {sr_id} — {title}")
            print(f"   需求长度: {len(requirement)} 字符")

            # 创建对话
            conv_id = await client.create_conversation(
                title=f"[评测] {sr_id} {title}",
                requirement=requirement,
            )
            print(f"   对话ID: {conv_id}")

            # 启动任务
            await client.start_task(conv_id)
            print(f"   任务已启动，等待完成...")

            # 等待结果
            final_result = await client.wait_for_result(conv_id)

            er = EvalResult(
                sr_id=sr_id,
                sr_title=title,
                conversation_id=conv_id,
            )

            if final_result:
                # 提取 function_list
                fl = final_result.get("function_list") or []
                if not fl:
                    # 尝试从 evaluation_episodes 提取
                    eps = final_result.get("evaluation_episodes") or []
                    if eps:
                        for ep in eps:
                            bundle = ep.get("bundle") or {}
                            eval_data = bundle.get("evaluation") or {}
                            # 尝试多种路径
                            fl = (eval_data.get("function_list") or
                                  final_result.get("function_list") or [])
                            if fl:
                                break

                if isinstance(fl, list):
                    er.function_list = fl
                print(f"   ✅ 完成，产出 {len(fl)} 个功能节点")
            else:
                er.error = "timeout_or_failed"
                print(f"   ❌ 失败/超时")

            results.append(er)
            print()

    finally:
        await client.close()

    # ─── 评分 ──────────────────────────────────────────
    if results and judgment_points:
        scores = compute_scores(results, judgment_points)
        print("=" * 60)
        print("📊 评测结果")
        print("=" * 60)
        print(f"  SR 数:     {len(results)}")
        print(f"  标准 AR 数: {scores['total_gt_ars']}")
        print(f"  系统产出 AR: {scores['total_system_ars']}")
        print(f"  命中:       {scores['total_hits']}")
        print(f"  Recall:     {scores['recall']:.2%}")
        print(f"  Precision:  {scores['precision']:.2%}")
        print(f"  F1:         {scores['f1']:.2%}")
        print()
        print("  SR 明细:")
        for d in scores["sr_details"]:
            status = "✅" if d["hits"] == d["gt_count"] else "⚠️"
            print(f"    {status} {d['sr_id']}: {d['hits']}/{d['gt_count']} hits "
                  f"(系统产出 {d['system_ar_count']} 个)")

    # 保存结果到文件
    out_path = Path(__file__).resolve().parent.parent / "eval_results.json"
    out_path.write_text(
        json.dumps({
            "results": [
                {
                    "sr_id": r.sr_id,
                    "sr_title": r.sr_title,
                    "conversation_id": r.conversation_id,
                    "function_list": r.function_list,
                    "error": r.error,
                }
                for r in results
            ],
            "scores": scores,
        }, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\n📁 结果已保存到: {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
