"""
将依赖边的 trigger（常为英文 snake_case）转为界面可读的中文短语。

已含中日韩字符时原样返回，避免重复加工。
"""
from __future__ import annotations

import copy
import re
from typing import Any, Dict, List

_CJK_RE = re.compile(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")

# 常见完整短语（小写键）
_FULL: Dict[str, str] = {
    "favorite_toggled": "收藏状态切换",
    "comment_fetched": "评论数据已获取",
    "card_clicked": "卡片点击",
    "detail_loaded": "详情加载完成",
    "filter_params_changed": "筛选参数变更",
    "export_requested": "导出请求",
    "registration_completed": "注册完成",
    "info_collected": "信息已收集",
    "login_attempted": "登录尝试",
    "credentials_validated": "凭证已校验",
    "view_courses_requested": "查看课程请求",
    "data_retrieved": "数据已获取",
    "purchase_initiated": "发起购买",
    "payment_method_selected": "支付方式已选",
    "video_playback_requested": "请求播放视频",
    "video_loaded": "视频加载完成",
    "assignment_submission_initiated": "发起作业提交",
    "file_uploaded": "文件已上传",
    "view_assignments_requested": "查看作业列表",
    "scoring_initiated": "发起评分",
    "score_inputted": "分数已录入",
    "业务流程执行中": "业务流程执行中",
}

# 片段翻译，用于未知组合词的兜底拼装
_TOKEN: Dict[str, str] = {
    "user": "用户",
    "click": "点击",
    "clicked": "点击",
    "card": "卡片",
    "favorite": "收藏",
    "toggled": "切换",
    "toggle": "切换",
    "comment": "评论",
    "comments": "评论",
    "fetched": "获取",
    "fetch": "获取",
    "loaded": "加载完成",
    "load": "加载",
    "detail": "详情",
    "page": "页",
    "filter": "筛选",
    "params": "参数",
    "changed": "变更",
    "change": "变更",
    "export": "导出",
    "requested": "请求",
    "request": "请求",
    "submit": "提交",
    "submitted": "已提交",
    "initiated": "发起",
    "completed": "完成",
    "valid": "有效",
    "validated": "已校验",
    "invalid": "无效",
    "login": "登录",
    "logout": "登出",
    "register": "注册",
    "registration": "注册",
    "payment": "支付",
    "video": "视频",
    "audio": "音频",
    "file": "文件",
    "upload": "上传",
    "uploaded": "已上传",
    "download": "下载",
    "select": "选择",
    "selected": "已选",
    "search": "搜索",
    "scroll": "滚动",
    "input": "输入",
    "output": "输出",
    "error": "错误",
    "success": "成功",
    "fail": "失败",
    "failed": "失败",
    "start": "开始",
    "started": "已开始",
    "end": "结束",
    "cancel": "取消",
    "confirm": "确认",
    "save": "保存",
    "delete": "删除",
    "update": "更新",
    "create": "创建",
    "sync": "同步",
    "refresh": "刷新",
    "retry": "重试",
    "timeout": "超时",
    "pending": "等待中",
    "flow": "流程",
    "context": "上下文",
    "step": "步骤",
    "event": "事件",
    "action": "操作",
    "list": "列表",
    "item": "项",
    "data": "数据",
    "state": "状态",
    "status": "状态",
}


def dependency_trigger_to_zh(trigger: str) -> str:
    if not isinstance(trigger, str):
        return "业务流程执行中"
    s = trigger.strip()
    if not s:
        return "业务流程执行中"
    if _CJK_RE.search(s):
        return s
    key = s.lower().replace(" ", "_").replace("-", "_")
    if key in _FULL:
        return _FULL[key]
    if key in _FULL.values():
        return s

    parts = [p for p in key.split("_") if p]
    if not parts:
        return s

    mapped = [_TOKEN.get(p) for p in parts]
    if all(mapped):
        return "".join(mapped)

    out: list[str] = []
    for p in parts:
        out.append(_TOKEN.get(p, p))
    joined = "".join(out)
    if _CJK_RE.search(joined):
        return joined
    return f"「{joined}」（{key}）"


def localize_dependency_triggers(deps: Any) -> Any:
    """深拷贝依赖列表，并将每条边的 trigger 规范为中文展示。"""
    if deps is None:
        return None
    if not isinstance(deps, list):
        return deps
    out: List[Any] = []
    for dep in deps:
        if not isinstance(dep, dict):
            out.append(dep)
            continue
        d = copy.deepcopy(dep)
        d["trigger"] = dependency_trigger_to_zh(str(d.get("trigger") or ""))
        out.append(d)
    return out
