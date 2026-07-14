#!/usr/bin/env python3
"""
模块二（M2）评估流水线独立测试脚本

运行方式：
    python scripts/run_m2_evaluation.py

功能：
1. 加载示例功能列表和依赖关系（符合M2模块实际输入格式）
2. 运行一致性评估（规则引擎+LLM混合模式）
3. 运行可实现性评估（集成FPA功能点分析）
4. 生成综合评估报告（包含FPA分析和决策支持）
5. 输出详细的评估结果和建议
"""

import asyncio
import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Any

from sqlalchemy import true, null, false

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 将项目根目录添加到Python路径
import sys

project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from app.services.coordinator.agent_invoker import AgentInvoker
from app.services.coordinator.context import CoordinatorContext
from app.core.enums import TaskMode
from app.core.config import settings

# 示例功能列表数据
SAMPLE_FUNCTION_LIST = [
    {
        "id": "F-1",
        "desc": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。",
        "path": "在线课程平台",
        "title": "在线课程平台",
        "node_type": "DOMAIN",
        "parent_id": null,
        "constraints": [],
        "granularity": "EPIC",
        "acceptance_hint": []
    },
    {
        "id": "F-1.1",
        "desc": "支持学生注册登录",
        "path": "在线课程平台 > 用户管理",
        "title": "用户管理",
        "node_type": "WORKFLOW",
        "parent_id": "F-1",
        "constraints": [],
        "granularity": "FEATURE",
        "acceptance_hint": []
    },
    {
        "id": "F-1.1.1",
        "desc": "允许新用户注册账户",
        "path": "在线课程平台 > 用户管理 > 用户注册",
        "title": "用户注册",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.1",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-2",
        "desc": "收集用户的姓名、邮箱、密码等信息",
        "path": "收集用户信息",
        "title": "收集用户信息",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "用户信息表单验证通过"
        ]
    },
    {
        "id": "F-3",
        "desc": "向用户注册邮箱发送确认邮件",
        "path": "发送确认邮件",
        "title": "发送确认邮件",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "确认邮件发送成功"
        ]
    },
    {
        "id": "F-1.1.2",
        "desc": "允许已注册用户登录账户",
        "path": "在线课程平台 > 用户管理 > 用户登录",
        "title": "用户登录",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.1",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-4",
        "desc": "验证用户提供的用户名和密码",
        "path": "验证用户凭据",
        "title": "验证用户凭据",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "用户凭据验证通过"
        ]
    },
    {
        "id": "F-5",
        "desc": "生成并返回会话令牌给客户端",
        "path": "生成会话令牌",
        "title": "生成会话令牌",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "会话令牌生成并返回"
        ]
    },
    {
        "id": "F-1.2",
        "desc": "支持学生浏览课程列表、购买课程",
        "path": "在线课程平台 > 课程管理",
        "title": "课程管理",
        "node_type": "WORKFLOW",
        "parent_id": "F-1",
        "constraints": [],
        "granularity": "FEATURE",
        "acceptance_hint": []
    },
    {
        "id": "F-1.2.1",
        "desc": "允许学生浏览所有可用课程",
        "path": "在线课程平台 > 课程管理 > 浏览课程列表",
        "title": "浏览课程列表",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.2",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-6",
        "desc": "从数据库中获取课程信息",
        "path": "获取课程数据",
        "title": "获取课程数据",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "课程数据成功获取"
        ]
    },
    {
        "id": "F-7",
        "desc": "在前端页面渲染课程列表",
        "path": "渲染课程列表",
        "title": "渲染课程列表",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "课程列表渲染完成"
        ]
    },
    {
        "id": "F-1.2.2",
        "desc": "允许学生购买课程",
        "path": "在线课程平台 > 课程管理 > 购买课程",
        "title": "购买课程",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.2",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-8",
        "desc": "允许用户选择支付方式",
        "path": "选择支付方式",
        "title": "选择支付方式",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "支付方式选择成功"
        ]
    },
    {
        "id": "F-9",
        "desc": "处理用户的支付请求",
        "path": "处理支付请求",
        "title": "处理支付请求",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "支付请求处理成功"
        ]
    },
    {
        "id": "F-1.3",
        "desc": "支持学生观看视频、提交作业",
        "path": "在线课程平台 > 学习管理",
        "title": "学习管理",
        "node_type": "WORKFLOW",
        "parent_id": "F-1",
        "constraints": [],
        "granularity": "FEATURE",
        "acceptance_hint": []
    },
    {
        "id": "F-1.3.1",
        "desc": "允许学生观看课程视频",
        "path": "在线课程平台 > 学习管理 > 观看视频",
        "title": "观看视频",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.3",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-10",
        "desc": "从服务器加载视频资源",
        "path": "加载视频资源",
        "title": "加载视频资源",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "视频资源加载成功"
        ]
    },
    {
        "id": "F-11",
        "desc": "允许用户控制视频播放",
        "path": "控制视频播放",
        "title": "控制视频播放",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "视频播放控制正常"
        ]
    },
    {
        "id": "F-1.3.2",
        "desc": "允许学生提交作业",
        "path": "在线课程平台 > 学习管理 > 提交作业",
        "title": "提交作业",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.3",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-12",
        "desc": "允许用户上传作业文件",
        "path": "上传作业文件",
        "title": "上传作业文件",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "作业文件上传成功"
        ]
    },
    {
        "id": "F-13",
        "desc": "记录作业提交的时间戳",
        "path": "记录提交时间",
        "title": "记录提交时间",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "提交时间记录成功"
        ]
    },
    {
        "id": "F-1.4",
        "desc": "支持老师评分",
        "path": "在线课程平台 > 评分管理",
        "title": "评分管理",
        "node_type": "WORKFLOW",
        "parent_id": "F-1",
        "constraints": [],
        "granularity": "FEATURE",
        "acceptance_hint": []
    },
    {
        "id": "F-1.4.1",
        "desc": "允许老师查看学生提交的作业",
        "path": "在线课程平台 > 评分管理 > 查看提交作业",
        "title": "查看提交作业",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.4",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-14",
        "desc": "从数据库中获取作业数据",
        "path": "获取作业数据",
        "title": "获取作业数据",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "作业数据成功获取"
        ]
    },
    {
        "id": "F-15",
        "desc": "在前端页面渲染作业列表",
        "path": "渲染作业列表",
        "title": "渲染作业列表",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "作业列表渲染完成"
        ]
    },
    {
        "id": "F-1.4.2",
        "desc": "允许老师为作业评分",
        "path": "在线课程平台 > 评分管理 > 评分作业",
        "title": "评分作业",
        "node_type": "CAPABILITY",
        "parent_id": "F-1.4",
        "constraints": [],
        "granularity": "STORY",
        "acceptance_hint": []
    },
    {
        "id": "F-16",
        "desc": "允许老师输入作业评分",
        "path": "输入评分",
        "title": "输入评分",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "评分输入成功"
        ]
    },
    {
        "id": "F-17",
        "desc": "记录评分的时间戳",
        "path": "记录评分时间",
        "title": "记录评分时间",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "评分时间记录成功"
        ]
    },
    {
        "id": "F-1.5",
        "desc": "处理系统中的异常情况",
        "path": "在线课程平台 > 异常处理",
        "title": "异常处理",
        "node_type": "EXCEPTION",
        "parent_id": "F-1",
        "constraints": [],
        "granularity": "FEATURE",
        "acceptance_hint": []
    },
    {
        "id": "F-18",
        "desc": "处理用户认证过程中可能出现的异常",
        "path": "处理用户认证异常",
        "title": "处理用户认证异常",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "异常情况被正确处理"
        ]
    },
    {
        "id": "F-19",
        "desc": "处理支付过程中可能出现的异常",
        "path": "处理支付异常",
        "title": "处理支付异常",
        "node_type": "TASK",
        "parent_id": null,
        "constraints": [],
        "granularity": "TASK",
        "acceptance_hint": [
            "异常情况被正确处理"
        ]
    }
]

# 示例依赖关系数据
SAMPLE_DEPENDENCIES = [
    {
        "to": "F-2",
        "from": "F-1.1.1",
        "dep_id": "D-001",
        "trigger": "registration_completed",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "用户注册信息传递",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "用户注册时收集用户信息",
        "resources_required": []
    },
    {
        "to": "F-3",
        "from": "F-2",
        "dep_id": "D-002",
        "trigger": "info_collected",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "收集用户信息后发送确认邮件",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "用户信息收集完成后触发邮件发送",
        "resources_required": []
    },
    {
        "to": "F-4",
        "from": "F-1.1.2",
        "dep_id": "D-003",
        "trigger": "login_attempted",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "用户登录凭据传递",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "用户登录时验证凭据",
        "resources_required": []
    },
    {
        "to": "F-5",
        "from": "F-4",
        "dep_id": "D-004",
        "trigger": "credentials_validated",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "验证通过后生成会话令牌",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "用户凭据验证通过后生成令牌",
        "resources_required": []
    },
    {
        "to": "F-6",
        "from": "F-1.2.1",
        "dep_id": "D-005",
        "trigger": "view_courses_requested",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "获取课程数据",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "浏览课程列表前获取数据",
        "resources_required": []
    },
    {
        "to": "F-7",
        "from": "F-6",
        "dep_id": "D-006",
        "trigger": "data_retrieved",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "渲染课程列表",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "获取课程数据后渲染列表",
        "resources_required": []
    },
    {
        "to": "F-8",
        "from": "F-1.2.2",
        "dep_id": "D-007",
        "trigger": "purchase_initiated",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "选择支付方式",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "购买课程前选择支付方式",
        "resources_required": []
    },
    {
        "to": "F-9",
        "from": "F-8",
        "dep_id": "D-008",
        "trigger": "payment_method_selected",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "处理支付请求",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "选择支付方式后处理请求",
        "resources_required": []
    },
    {
        "to": "F-10",
        "from": "F-1.3.1",
        "dep_id": "D-009",
        "trigger": "video_playback_requested",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "加载视频资源",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "观看视频前加载资源",
        "resources_required": []
    },
    {
        "to": "F-11",
        "from": "F-10",
        "dep_id": "D-010",
        "trigger": "video_loaded",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "控制视频播放",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "加载视频资源后控制播放",
        "resources_required": []
    },
    {
        "to": "F-12",
        "from": "F-1.3.2",
        "dep_id": "D-011",
        "trigger": "assignment_submission_initiated",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "上传作业文件",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "提交作业前上传文件",
        "resources_required": []
    },
    {
        "to": "F-13",
        "from": "F-12",
        "dep_id": "D-012",
        "trigger": "file_uploaded",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "记录提交时间",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "上传文件后记录时间",
        "resources_required": []
    },
    {
        "to": "F-14",
        "from": "F-1.4.1",
        "dep_id": "D-013",
        "trigger": "view_assignments_requested",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "获取作业数据",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "查看作业前获取数据",
        "resources_required": []
    },
    {
        "to": "F-15",
        "from": "F-14",
        "dep_id": "D-014",
        "trigger": "data_retrieved",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "渲染作业列表",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "获取作业数据后渲染列表",
        "resources_required": []
    },
    {
        "to": "F-16",
        "from": "F-1.4.2",
        "dep_id": "D-015",
        "trigger": "scoring_initiated",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "输入评分",
        "dependency_type": "DATA",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "评分作业前输入评分",
        "resources_required": []
    },
    {
        "to": "F-17",
        "from": "F-16",
        "dep_id": "D-016",
        "trigger": "score_inputted",
        "provides": [
            {
                "field": "step_output",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "requires": [
            {
                "field": "flow_context",
                "source": "SYSTEM",
                "required": true,
                "data_type": "object"
            }
        ],
        "severity": "MEDIUM",
        "description": "记录评分时间",
        "dependency_type": "EXEC_ORDER",
        "degradation_mode": "PROMPT",
        "degradation_note": "按PROMPT策略处理依赖缺失场景",
        "direction_explain": "输入评分后记录时间",
        "resources_required": []
    }
]

# 示例规范化器结果
SAMPLE_NORMALIZER_RESULT = {
    "goal": {
        "actors": [
            "学生",
            "老师"
        ],
        "primary_goal": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。",
        "success_criteria": [
            "学生可以注册并登录平台",
            "学生可以浏览课程列表",
            "学生可以购买课程",
            "学生可以观看视频",
            "学生可以提交作业",
            "老师可以对学生作业进行评分"
        ]
    },
    "scope": {
        "in": [
            "学生注册登录",
            "浏览课程列表",
            "购买课程",
            "观看视频",
            "作业提交",
            "老师评分"
        ],
        "out": [
            "未在需求中明确排除的能力（待产品确认）"
        ]
    },
    "assumptions": [
        {
            "impact": "MEDIUM",
            "statement": "未写明的业务细节按行业常见默认实现，后续迭代可再收敛",
            "confidence": "MEDIUM"
        }
    ],
    "constraints": [
        {
            "type": "OTHER",
            "value": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。",
            "mandatory": true,
            "confidence": "HIGH"
        }
    ],
    "preconditions": [
        {
            "key": "user_authenticated",
            "value": "true",
            "description": "用户已完成登录鉴权后方可访问个人订单数据"
        }
    ],
    "open_questions": [
        {
            "reason": "需要确认平台的访问设备范围。",
            "question": "平台是否需要支持移动设备访问？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        },
        {
            "reason": "需要确认课程内容的主要形式。",
            "question": "课程内容是以视频形式为主吗？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        },
        {
            "reason": "需要确认作业提交的文件格式要求。",
            "question": "作业提交是否需要支持多种文件格式？",
            "suggested_answer_options": [
                "待产品确认后再细化（迭代补充）",
                "按最小可用/行业默认先实现"
            ]
        },
        {
            "reason": "需要确认评分标准的制定者。",
            "question": "评分标准由谁制定？",
            "suggested_answer_options": [
                "老师",
                "平台管理员",
                "其他"
            ]
        },
        {
            "reason": "需要确认是否需要集成支付功能。",
            "question": "是否需要集成支付功能？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        },
        {
            "reason": "需要确认是否需要支持课程搜索功能。",
            "question": "是否需要支持课程搜索功能？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        },
        {
            "reason": "需要确认是否需要支持课程评论功能。",
            "question": "是否需要支持课程评论功能？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        },
        {
            "reason": "需要确认是否需要支持课程进度跟踪功能。",
            "question": "是否需要支持课程进度跟踪功能？",
            "suggested_answer_options": [
                "是",
                "否"
            ]
        }
    ],
    "constraints_copy": [
        {
            "type": "OTHER",
            "value": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能。",
            "mandatory": true,
            "confidence": "HIGH"
        }
    ],
    "structured_exports": [],
    "glossary_candidates": [],
    "performance_metrics": [],
    "external_dependencies": [],
    "normalized_requirement": "实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频******（省略用作测试）。"
}


async def run_m2_evaluation():
    """运行模块二评估"""

    logger.info("=== 开始模块二评估测试 ===")

    # 验证LLM配置
    if not settings.LLM_API_KEY:
        logger.error("LLM API密钥未配置，请在.env文件中设置LLM_API_KEY")
    else:
        logger.info(f"使用LLM模型: {settings.LLM_MODEL}")
        logger.info(f"LLM服务地址: {settings.LLM_BASE_URL}")

    # 创建评估上下文
    context = CoordinatorContext(
        conversation_id=f"m2_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
        requirement_text="实现一个在线课程平台，支持学生注册登录、浏览课程列表、购买课程、观看视频，并提供作业提交和老师评分功能",
        mode=TaskMode.AUTO,
        config={
            "model": settings.LLM_MODEL if settings.LLM_API_KEY else "gpt-4o-mini",
            "api_key": settings.LLM_API_KEY or "sk-dummy-key",
            "base_url": settings.LLM_BASE_URL or "https://api.openai.com/v1",
            "temperature": settings.LLM_TEMPERATURE or 0.1,
            "max_tokens": settings.LLM_MAX_TOKENS or 2000,
            "enable_module2": True,
            "enable_feasibility_refinement": False,
        }
    )

    # 添加M1模块的产物作为M2评估输入（符合实际项目结构）
    context.add_artifact("function_list", SAMPLE_FUNCTION_LIST, agent="test")
    context.add_artifact("dependencies", SAMPLE_DEPENDENCIES, agent="test")
    context.add_artifact("normalized_requirement", SAMPLE_NORMALIZER_RESULT, agent="test")

    # 创建智能体调用器
    invoker = AgentInvoker()

    try:
        # 运行模块二评估流水线
        logger.info("运行模块二评估流水线...")
        start_time = datetime.now()

        c_out = await invoker.invoke_m2_consistency_only(context)
        tail = await invoker.invoke_m2_feasibility_integrator_only(context)
        results = {
            "consistency_evaluator": invoker._to_serializable(c_out),
            "feasibility_evaluator": invoker._to_serializable(
                tail.get("feasibility_evaluator")
            ),
            "evaluation_integrator": invoker._to_serializable(
                tail.get("evaluation_integrator")
            ),
        }

        end_time = datetime.now()
        processing_time = (end_time - start_time).total_seconds()

        logger.info(f"模块二评估完成，处理时间: {processing_time:.2f}秒")

        # 输出评估结果
        await _print_evaluation_results(results)

        # 保存结果到文件
        await _save_results_to_file(results, context)

        return results

    except Exception as e:
        logger.error(f"模块二评估失败: {str(e)}", exc_info=True)
        raise


async def _print_evaluation_results(results: dict):
    """打印评估结果"""

    print("\n" + "=" * 80)
    print("模块二评估结果报告")
    print("=" * 80)


    print(f"原始结果: {results}")

    print("\n" + "=" * 80)


async def _save_results_to_file(results: dict, context: CoordinatorContext):
    """保存结果到文件"""

    # 创建结果目录
    results_dir = Path("evaluation_results")
    results_dir.mkdir(exist_ok=True)

    # 生成文件名
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"m2_evaluation_{context.conversation_id}_{timestamp}.json"
    filepath = results_dir / filename

    # # 将BaseAgentOutput对象转换为可序列化的字典
    # def _to_serializable(obj: Any) -> Any:
    #     """递归将对象转为可JSON序列化的格式"""
    #     if hasattr(obj, "model_dump"):
    #         return obj.model_dump()
    #     if hasattr(obj, "__dict__"):
    #         return {k: _to_serializable(v) for k, v in obj.__dict__.items()}
    #     if isinstance(obj, dict):
    #         return {k: _to_serializable(v) for k, v in obj.items()}
    #     if isinstance(obj, list):
    #         return [_to_serializable(v) for v in obj]
    #     if callable(obj):
    #         return f"<function {obj.__name__ if hasattr(obj, '__name__') else 'anonymous'}>"
    #     return obj

    # 准备保存的数据
    save_data = {
        "conversation_id": context.conversation_id,
        "timestamp": datetime.now().isoformat(),
        "evaluation_results": {
            "consistency_evaluator": results.get("consistency_evaluator", {}) if results.get(
                "consistency_evaluator") else {},
            "feasibility_evaluator": results.get("feasibility_evaluator", {}) if results.get(
                "feasibility_evaluator") else {},
            "evaluation_integrator": results.get("evaluation_integrator", {}) if results.get(
                "evaluation_integrator") else {}
        }
    }

    # 保存到文件
    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(save_data, f, ensure_ascii=False, indent=2)

        logger.info(f"评估结果已保存到: {filepath}")

    except Exception as e:
        logger.error(f"保存结果文件失败: {str(e)}")


async def main():
    """主函数"""
    try:
        results = await run_m2_evaluation()
        logger.info("模块二评估测试完成")
        return results
    except Exception as e:
        logger.error(f"模块二评估测试失败: {str(e)}")
        return None


if __name__ == "__main__":
    # 运行异步主函数
    results = asyncio.run(main())

    if results:
        logger.info("评估测试成功完成")
    else:
        logger.error("评估测试失败")
        sys.exit(1)