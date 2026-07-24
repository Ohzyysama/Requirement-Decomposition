"""
读两次 run_sr_eval.py 的 eval_results.json，自动生成对比数据 JSON。

用法:
  PYTHONPATH=. python scripts/compute_comparison.py \
      --before eval_results_before.json \
      --after eval_results_after.json \
      --out ../frontend_release/frontend/public/comparison_data.json
"""
import argparse
import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Any


def load_json(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def count_leaf_nodes(function_list: List[dict]) -> int:
    """扁平行 function_list 中的叶子节点数（没有其他节点以它为 parent_id）。"""
    if not function_list:
        return 0
    ids = {str(r.get("id", "")).strip() for r in function_list if isinstance(r, dict)}
    parent_ids = {str(r.get("parent_id", "")).strip() for r in function_list if isinstance(r, dict)}
    leaf_ids = ids - parent_ids
    # 没有 parent_id 的也可能算叶子
    if not leaf_ids:
        return len(function_list)
    return len(leaf_ids)


def count_tree_depth(function_list: List[dict]) -> float:
    """计算扁平行 function_list 的最大深度。"""
    if not function_list:
        return 0

    by_id: Dict[str, dict] = {}
    for r in function_list:
        if isinstance(r, dict):
            nid = str(r.get("id", "")).strip()
            if nid:
                by_id[nid] = r

    memo: Dict[str, int] = {}

    def depth(nid: str, visited: set) -> int:
        if nid in memo:
            return memo[nid]
        if nid in visited:
            return 0  # 环
        visited.add(nid)
        row = by_id.get(nid, {})
        pid = str(row.get("parent_id", "")).strip()
        if not pid or pid not in by_id:
            memo[nid] = 1
            return 1
        d = 1 + depth(pid, visited.copy())
        memo[nid] = d
        return d

    if not by_id:
        return 0
    max_d = max(depth(nid, set()) for nid in by_id)
    return float(max_d)


def compute_stats(results: List[dict]) -> dict:
    """从一个 eval_results.json 的 results 列表中提取统计。"""
    sr_stats = []
    for r in results:
        fl = r.get("function_list") or []
        node_count = len(fl)
        tree_depth = count_tree_depth(fl)
        leaf_count = count_leaf_nodes(fl)
        sr_stats.append({
            "sr_id": r.get("sr_id", "?"),
            "node_count": node_count,
            "tree_depth": tree_depth,
            "leaf_count": leaf_count,
            "error": r.get("error"),
        })

    valid = [s for s in sr_stats if not s.get("error")]
    if not valid:
        return {
            "error": "no_valid_results",
            "sr_count": len(results),
            "stats": sr_stats,
        }

    n = len(valid)
    avg_node = sum(s["node_count"] for s in valid) / n
    avg_depth = sum(s["tree_depth"] for s in valid) / n
    avg_leaf = sum(s["leaf_count"] for s in valid) / n

    return {
        "sr_count": len(results),
        "valid_sr_count": n,
        "avg_node_count": round(avg_node, 1),
        "avg_tree_depth": round(avg_depth, 1),
        "avg_leaf_count": round(avg_leaf, 1),
        "per_sr": sr_stats,
    }


def merge_comparison(before_stats: dict, after_stats: dict) -> dict:
    """合并两次统计为前端需要的 comparisonData。"""
    b = before_stats
    a = after_stats

    bn = b.get("avg_node_count", 0)
    an = a.get("avg_node_count", 0)
    bd = b.get("avg_tree_depth", 0)
    ad = a.get("avg_tree_depth", 0)
    bl = b.get("avg_leaf_count", 0)
    al = a.get("avg_leaf_count", 0)

    # 如果 avg_node_count 差异不大，用 leaf_count 估算过度拆分
    overly_before = max(0, round(bl - b.get("sr_count", 15) * 3))  # 假设每个 SR 期望 ~3 个叶子
    overly_after = max(0, round(al - a.get("sr_count", 15) * 3))

    return {
        "generated": True,
        "srCount": max(b.get("sr_count", 15), a.get("sr_count", 15)),
        "before": {
            "avgNodeCount": bn,
            "avgTreeDepth": bd,
            "overlySplitNodes": overly_before,
            "leafCount": bl,
            "validSrCount": b.get("valid_sr_count", 0),
        },
        "after": {
            "avgNodeCount": an,
            "avgTreeDepth": ad,
            "overlySplitNodes": overly_after,
            "leafCount": al,
            "validSrCount": a.get("valid_sr_count", 0),
        },
        "perSr": {
            "before": b.get("per_sr", []),
            "after": a.get("per_sr", []),
        },
    }


def main():
    parser = argparse.ArgumentParser(description="生成优化前后对比 JSON")
    parser.add_argument("--before", required=True, help="优化前的 eval_results.json")
    parser.add_argument("--after", required=True, help="优化后的 eval_results.json")
    parser.add_argument("--out", default="comparison_data.json", help="输出路径")
    args = parser.parse_args()

    before_raw = load_json(args.before)
    after_raw = load_json(args.after)

    before_results = before_raw.get("results", [])
    after_results = after_raw.get("results", [])

    if not before_results or not after_results:
        print("❌ 缺少 results 字段，请确认输入是正确的 eval_results.json")
        sys.exit(1)

    before_stats = compute_stats(before_results)
    after_stats = compute_stats(after_results)
    merged = merge_comparison(before_stats, after_stats)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"✅ 对比数据已生成: {out_path}")
    print(f"   优化前: {before_stats['avg_node_count']} 节点, 深度 {before_stats['avg_tree_depth']}")
    print(f"   优化后: {after_stats['avg_node_count']} 节点, 深度 {after_stats['avg_tree_depth']}")
    delta_n = after_stats['avg_node_count'] - before_stats['avg_node_count']
    pct = abs(delta_n) / max(before_stats['avg_node_count'], 1) * 100
    print(f"   节点变化: {'+' if delta_n > 0 else ''}{delta_n:.0f} ({'↑' if delta_n > 0 else '↓'}{pct:.0f}%)")


if __name__ == "__main__":
    main()
