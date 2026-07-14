"""
结果组装器（向后兼容入口）。

FinalResultAssembler 和 SsePayloadFactory 是正式的实现类。
ResultAssembler 作为向后兼容薄包装保留，代理到两个专用类。
"""
from app.services.coordinator.final_result_assembler import FinalResultAssembler
from app.services.coordinator.sse_payload_factory import SsePayloadFactory


class ResultAssembler(FinalResultAssembler, SsePayloadFactory):
    """
    向后兼容组合类，同时继承 FinalResultAssembler 与 SsePayloadFactory。
    新代码应直接使用对应专用类。
    """
