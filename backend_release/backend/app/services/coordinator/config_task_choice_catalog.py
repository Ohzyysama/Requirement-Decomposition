"""解析任务 config 可选值目录（供 GET 接口返回）。"""
from app.schemas.coordinator_task_config_choices import (
    CoordinatorTaskConfigChoiceGroup,
    CoordinatorTaskConfigChoiceOption,
    CoordinatorTaskConfigChoicesResponse,
)

# 与 pipeline_runner / sub_ar_refiner 中 cfg.get(..., default) 保持一致
_DEFAULT_CONSISTENCY_INNER_MAX_RETRIES = 1
_DEFAULT_MAX_FEASIBILITY_REFINEMENT_DEPTH = 1
_DEFAULT_CONTINUE_AFTER_CONSISTENCY_EXHAUSTED = False


def build_task_config_choice_catalog() -> CoordinatorTaskConfigChoicesResponse:
    inner_retries = CoordinatorTaskConfigChoiceGroup(
        key="consistency_inner_max_retries",
        title="一致性内层重试上限",
        summary=(
            "检查整棵需求树内部是否前后一致时，若未通过，除第一次检查外，还允许系统自动再调整几轮。"
            f"值为 0 表示一次不过就不再自动改；不单独设置时，系统默认值为 {_DEFAULT_CONSISTENCY_INNER_MAX_RETRIES}。"
            "下列选项名称中的数字为实际上传值，括号内仅为简要备注。"
        ),
        value_type="integer",
        default_value=_DEFAULT_CONSISTENCY_INNER_MAX_RETRIES,
        omit_means_default=True,
        options=[
            CoordinatorTaskConfigChoiceOption(
                value=0,
                label="0（不重试）",
                description="备注：一次不过就停止内层自动调整。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=1,
                label="1（默认）",
                description="备注：与系统推荐相同，最多再自动调整一轮。",
                is_default=True,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=2,
                label="2（多一轮）",
                description="备注：比默认多一轮，耗时会更长。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=3,
                label="3（偏多轮）",
                description="备注：多次自动调整，适合问题较难、愿意多花时间。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=4,
                label="4（高上限，不推荐）",
                description="备注：不推荐常规使用，耗时显著增加；若仍不够可自填更大整数。",
                is_default=False,
            ),
        ],
    )

    depth = CoordinatorTaskConfigChoiceGroup(
        key="max_feasibility_refinement_depth",
        title="可实现性细化最大相对深度",
        summary=(
            "发现需求在工程上不好落地时，系统可以自动把相关部分拆细、加深需求树的层级。"
            f"不在请求里单独设置时，系统默认值为 {_DEFAULT_MAX_FEASIBILITY_REFINEMENT_DEPTH}。"
            "（勿在 API 请求体中传 max_feasibility_refinement_depth=0；若需关闭此类自动细化可设置 enable_feasibility_refinement 为 false。）"
            "数字越大，树可能越深，耗时与费用通常越高。"
            "下列选项名称中的数字为实际上传值，括号内仅为简要备注。"
        ),
        value_type="integer",
        default_value=_DEFAULT_MAX_FEASIBILITY_REFINEMENT_DEPTH,
        omit_means_default=True,
        options=[
            CoordinatorTaskConfigChoiceOption(
                value=1,
                label="1（默认）",
                description="备注：与系统推荐相同，只往深处拆一层。",
                is_default=True,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=2,
                label="2（偏浅）",
                description="备注：适度控制深度。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=3,
                label="3（偏多层）",
                description="备注：允许可实现性细化拆至三层深度。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=4,
                label="4（较深）",
                description="备注：允许拆得更细。",
                is_default=False,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=5,
                label="5（更深，不推荐）",
                description="备注：不推荐常规使用，耗时显著增加。",
                is_default=False,
            ),
        ],
    )

    continue_after = CoordinatorTaskConfigChoiceGroup(
        key="continue_pipeline_after_consistency_exhausted",
        title="一致性耗尽后仍跑可实现性",
        summary=(
            "最外层一致性已经反复调整仍不理想时，是否还要继续后面的「好不好实现」一类分析。"
            "选「否」时一般会直接略过这一步，免得在明显对不齐的结果上再花时间。"
            "若不单独设置，系统默认选「否」。"
        ),
        value_type="boolean",
        default_value=_DEFAULT_CONTINUE_AFTER_CONSISTENCY_EXHAUSTED,
        omit_means_default=True,
        options=[
            CoordinatorTaskConfigChoiceOption(
                value=False,
                label="否",
                description="对不齐就不再往下做可实现性分析。",
                is_default=True,
            ),
            CoordinatorTaskConfigChoiceOption(
                value=True,
                label="是",
                description="即使对不齐也继续做完后续分析，便于留档或对比。",
                is_default=False,
            ),
        ],
    )

    return CoordinatorTaskConfigChoicesResponse(
        groups=[inner_retries, depth, continue_after],
        usage_hint=(
            "下面三项会随「开始解析」一起生效。"
            "保持系统推荐即可不用改。"
            "前两项请按整数提交：列表里写在最前面的是实际上传数字，括号内只是备注；也可在界面填列表外的其它整数。"
        ),
    )
