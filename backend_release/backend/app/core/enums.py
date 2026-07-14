from enum import Enum


class TaskMode(str, Enum):
    AUTO = "auto"


class PipelineStage(str, Enum):
    """管线阶段枚举 — 协调器唯一状态源；落库/API/SSE/final_result 均使用其 .value。

    合法转换路径（简化）：
        idle → split → consistency
        consistency → consistency（内层重拆循环，保持同阶段）
        consistency → refine_sub_ar → consistency/feasibility
        consistency → feasibility → done
        任意阶段 → error
    """

    IDLE = "idle"
    SPLIT = "split"
    CONSISTENCY = "consistency"
    REFINE_SUB_AR = "refine_sub_ar"
    FEASIBILITY = "feasibility"
    DONE = "done"
    ERROR = "error"
