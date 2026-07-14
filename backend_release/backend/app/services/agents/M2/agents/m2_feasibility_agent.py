"""
M2可实现性评估智能体
负责执行可实现性规则检查，集成FPA功能点分析：
1. 内聚度评估
2. 功能点规模评估（FPA）
3. 工作量估算评估
4. 粒度合理性评估
5. 资源约束匹配评估
6. 技术复杂性评估
"""
import asyncio
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime
import re
from collections import defaultdict

from app.services.agents.M2.m2_base_agent import M2BaseAgent
from app.schemas.agent import AgentInput, BaseAgentOutput
from app.services.agents.M2.schemas.m2_feasibility import (
    FeasibilityCheckResponse, FeasibilityEvaluationResult,
)
from app.schemas.evaluation import (
    RuleSeverity,
    RuleCategory,
    IssueType,
    RuleCheckResult,
    FPAAssessmentResult,
    FPAFunctionClassification,
    CohesionAssessmentResult,
    CohesionAssessmentItem

)
from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

class M2FeasibilityEvaluatorAgent(M2BaseAgent):
    """M2可实现性评估智能体（集成FPA分析）"""

    def __init__(self):
        super().__init__(
            name="M2-FeasibilityEvaluator",
            description="可实现性评估智能体，集成FPA功能点分析，评估功能需求的可实现性",
            system_prompt="""你是一个专业的可实现性评估专家，负责对软件需求进行功能点分析（FPA）和可实现性评估。

            你的任务是：
            1. 基于功能描述进行内聚度评估
            2. 分析功能点规模与工作量估算
            3. 评估技术复杂性和资源约束匹配度
            4. 提供粒度合理性和实现可行性建议
            
            对于每个检查项，你需要：
            - 基于FPA方法进行客观分析
            - 明确说明是否通过检查
            - 如果未通过，详细描述问题和风险
            - 提供具体的解决方案建议
            - 给出置信度评估
            
            请基于FPA标准和事实进行分析，提供准确、实用的可行性评估。"""
        )

        # FPA配置参数
        self.fpa_config = {
            "productivity_factor": 6.72,  # 生产力因子：6.72人时/功能点
            "day_workload": 21.75,        # 每月工作21.75天
            "hour_workload": 8.0,        # 每天每人工作8小时
            "monthly_cost": 27795.0,     # 人均月成本：27795元
        }

    async def execute(self, input_data: AgentInput) -> BaseAgentOutput:
        """执行可实现性评估（集成FPA分析）"""
        try:
            art = input_data.artifacts or {}
            function_list = art.get("function_list", []) if isinstance(art, dict) else []
            normalizer_result = art.get("normalizer_result", {}) if isinstance(art, dict) else {}
            requirement_text = normalizer_result.get("normalized_requirement", "") if isinstance(normalizer_result, dict) else ""
            context = input_data.context or {}

            # TODO：约束信息的确定
            resource_constraints = context.get("resource_constraints", {})
            platform_constraints = context.get("platform_constraints", {})

            logger.info(f"[{input_data.task_id}] 开始可实现性评估（集成FPA）")

            # 执行FPA功能点分析（针对每个子功能）
            fpa_results = await self._perform_per_function_fpa_analysis(function_list, requirement_text, input_data)

            # 执行各项可实现性检查（基于单个功能点）
            rule_results = []

            # 1. 内聚度评估（LLM语义分析）
            llm_cohesion_result = await self._check_cohesion_degree_llm(function_list, requirement_text, input_data)
            rule_results.append(llm_cohesion_result)

            # 2. 功能点规模评估（基于单个功能点）
            rule_results.append(self._check_function_point_scale_per_function(fpa_results, function_list))

            # 3. 工作量估算评估（基于单个功能点）
            rule_results.append(self._check_workload_estimation_per_function(fpa_results, resource_constraints, function_list))

            # 4. 粒度合理性评估（基于单个功能点）
            rule_results.append(self._check_granularity_reasonableness_per_function(fpa_results, function_list))

            # 5. 资源约束匹配评估（基于单个功能点）
            rule_results.append(self._check_resource_constraint_match_per_function(fpa_results, resource_constraints, function_list))

            # 6. 技术复杂性评估（基于单个功能点）
            rule_results.append(self._check_technical_complexity_per_function(fpa_results, function_list))

            # 构建评估结果
            evaluation_result = self._build_evaluation_result(rule_results, fpa_results)

            response = FeasibilityCheckResponse(
                result=evaluation_result,
                check_details={"rule_count": len(rule_results)},
                project_scale_classification=self._classify_project_scale(sum(fpa_result.total_afp for fpa_result in fpa_results))
            )

            return BaseAgentOutput(
                result=response.model_dump(),
                quality_flags=self._extract_quality_flags(evaluation_result),
                warnings=self._extract_warnings(evaluation_result),
                evidence=self._extract_evidence(evaluation_result)
            )

        except Exception as e:
            logger.error(f"可实现性评估失败: {str(e)}", exc_info=True)
            return BaseAgentOutput(
                result={},
                quality_flags=["execution_error"],
                warnings=[f"可实现性评估执行失败: {str(e)}"]
            )

    async def _perform_per_function_fpa_analysis(
        self,
        function_list: List[Dict[str, Any]],
        requirement_text: str,
        input_data: AgentInput
    ) -> List[FPAAssessmentResult]:
        """对每个子功能执行独立的FPA功能点分析"""
        try:
            fpa_results = []
            
            # 计算整体TCF（技术复杂性因子）
            overall_tcf = self._calculate_tcf(function_list, requirement_text)
            
            for func in function_list:
                # 对每个功能单独分类和计算
                classification = self._classify_function(func, requirement_text)
                
                # 单个功能的UFP就是该功能的功能点
                function_ufp = classification.function_points
                
                # 单个功能的AFP = UFP × TCF
                function_afp = function_ufp * overall_tcf
                
                # 单个功能的工作量估算
                function_estimated_workload = (function_afp * self.fpa_config["productivity_factor"]) / (
                    self.fpa_config["day_workload"] * self.fpa_config["hour_workload"])
                
                function_estimated_cost = function_estimated_workload * self.fpa_config["monthly_cost"]
                function_estimated_duration = self._estimate_duration_cocomo(function_afp)
                
                # 构建单个功能的详细分析
                detailed_analysis = {
                    "function_id": func.get("id", ""),
                    "ufp_calculation": {
                        "formula": "UFP = 功能类型权重",
                        "function_type": classification.function_type,
                        "complexity": classification.complexity,
                        "function_ufp": function_ufp
                    },
                    "tcf_calculation": {
                        "formula": "TCF = 0.65 + 0.01 × ∑(通用系统特性评分)",
                        "tcf": overall_tcf
                    },
                    "afp_calculation": {
                        "formula": "AFP = UFP × TCF",
                        "function_afp": function_afp
                    },
                    "estimation_details": {
                        "workload_formula": "估算工作量 = AFP * 生产力因子",
                        "cost_formula": "估算成本 = 估算工作量 × 人均月成本",
                        "duration_formula": "基于COCOMO模型预测"
                    }
                }
                
                fpa_result = FPAAssessmentResult(
                    total_ufp=function_ufp,
                    total_afp=function_afp,
                    tcf=overall_tcf,
                    estimated_workload=function_estimated_workload,
                    estimated_cost=function_estimated_cost,
                    estimated_duration=function_estimated_duration,
                    function_classifications=[classification],
                    detailed_analysis=detailed_analysis
                )
                
                fpa_results.append(fpa_result)
            
            return fpa_results

        except Exception as e:
            logger.error(f"单功能FPA分析失败: {str(e)}", exc_info=True)
            # 返回空列表
            return []

    def _classify_function(self, func: Dict[str, Any], requirement_text: str) -> FPAFunctionClassification:
        """功能分类"""
        func_id = func.get("id", "")
        func_desc = func.get("desc", "") + " " + func.get("title", "")

        # 基于关键词分析确定功能类型
        func_type = self._determine_function_type(func_desc)

        # 基于描述复杂度确定复杂度等级
        complexity = self._determine_complexity(func_desc)

        # 计算功能点数
        function_points = self._calculate_function_points(func_type, complexity)

        return FPAFunctionClassification(
            function_id=func_id,
            function_type=func_type,
            complexity=complexity,
            function_points=function_points,
            description=f"功能{func_id}分类为{func_type}，复杂度{complexity}"
        )

    def _determine_function_type(self, func_desc: str) -> str:
        """确定功能类型"""
        desc_lower = func_desc.lower()

        # 外部输入（EI）
        ei_keywords = ["输入", "录入", "添加", "创建", "导入", "上传"]
        if any(keyword in desc_lower for keyword in ei_keywords):
            return "EI"

        # 外部输出（EO）
        eo_keywords = ["输出", "导出", "下载", "打印", "生成", "显示"]
        if any(keyword in desc_lower for keyword in eo_keywords):
            return "EO"

        # 外部查询（EQ）
        eq_keywords = ["查询", "搜索", "查找", "检索", "查看", "列表"]
        if any(keyword in desc_lower for keyword in eq_keywords):
            return "EQ"

        # 内部逻辑文件（ILF）
        ilf_keywords = ["存储", "保存", "数据库", "文件", "记录", "数据"]
        if any(keyword in desc_lower for keyword in ilf_keywords):
            return "ILF"

        # 外部接口文件（EIF）
        eif_keywords = ["接口", "API", "集成", "对接", "外部", "第三方"]
        if any(keyword in desc_lower for keyword in eif_keywords):
            return "EIF"

        # 默认返回EI
        return "EI"

    def _determine_complexity(self, func_desc: str) -> str:
        """确定复杂度"""
        desc_length = len(func_desc)

        if desc_length < 20:
            return "LOW"
        elif desc_length < 50:
            return "MEDIUM"
        else:
            return "HIGH"

    def _calculate_function_points(self, func_type: str, complexity: str) -> int:
        """计算功能点数"""
        # 功能类型权重
        type_weights = {
            "EI": {"LOW": 3, "MEDIUM": 4, "HIGH": 6},
            "EO": {"LOW": 4, "MEDIUM": 5, "HIGH": 7},
            "EQ": {"LOW": 3, "MEDIUM": 4, "HIGH": 6},
            "ILF": {"LOW": 7, "MEDIUM": 10, "HIGH": 15},
            "EIF": {"LOW": 5, "MEDIUM": 7, "HIGH": 10}
        }

        return type_weights.get(func_type, {}).get(complexity, 3)


    def _calculate_tcf(self, function_list: List[Dict[str, Any]], requirement_text: str) -> float:
        """计算技术复杂性因子"""
        # 基于功能描述和需求文本分析完整的14个GSC评分

        gsc_scores = self._get_gsc_scores(requirement_text)

        # 计算总GSC评分
        total_gsc_score = sum(gsc_scores.values())

        # 计算TCF
        tcf = 0.65 + (0.01 * total_gsc_score)

        # 限制TCF范围（IFPUG标准：0.65-1.35）
        return max(0.65, min(1.35, tcf))

    def _get_gsc_scores(self, requirement_text: str) -> Dict[str, int]:
        """获取完整的14个GSC评分（用于详细分析报告）"""
        gsc_scores = {}

        #TODO:利用LLM分析需求文本，提取GSC评分相关的信息

        # 1. 数据通信复杂性
        data_comm_keywords = ["网络", "通信", "传输", "API", "接口", "socket", "websocket", "消息队列"]
        gsc_scores["data_communications"] = self._score_gsc(requirement_text, data_comm_keywords)

        # 2. 分布式处理需求
        distributed_keywords = ["分布式", "集群", "负载均衡", "微服务", "多节点", "分布式系统", "服务网格"]
        gsc_scores["distributed_processing"] = self._score_gsc(requirement_text, distributed_keywords)

        # 3. 性能要求
        performance_keywords = ["性能", "响应时间", "并发", "吞吐量", "延迟", "QPS", "TPS", "优化", "加速"]
        gsc_scores["performance"] = self._score_gsc(requirement_text, performance_keywords)

        # 4. 使用频率
        usage_frequency_keywords = ["频繁", "高并发", "实时", "24小时", "不间断", "高峰", "峰值"]
        gsc_scores["heavily_used_configuration"] = self._score_gsc(requirement_text, usage_frequency_keywords)

        # 5. 事务处理率
        transaction_keywords = ["事务", "交易", "订单", "支付", "结算", "批量处理", "事务一致性"]
        gsc_scores["transaction_rate"] = self._score_gsc(requirement_text, transaction_keywords)

        # 6. 在线数据输入
        online_input_keywords = ["在线", "实时", "即时", "表单", "录入", "提交", "验证", "校验"]
        gsc_scores["online_data_entry"] = self._score_gsc(requirement_text, online_input_keywords)

        # 7. 终端用户效率
        user_efficiency_keywords = ["用户体验", "易用", "便捷", "快捷", "效率", "自动化", "智能"]
        gsc_scores["end_user_efficiency"] = self._score_gsc(requirement_text, user_efficiency_keywords)

        # 8. 在线更新
        online_update_keywords = ["在线更新", "热更新", "动态配置", "实时生效", "无需重启", "配置中心"]
        gsc_scores["online_update"] = self._score_gsc(requirement_text, online_update_keywords)

        # 9. 复杂处理逻辑
        complex_processing_keywords = ["复杂", "算法", "计算", "分析", "推理", "决策", "规则引擎", "AI"]
        gsc_scores["complex_processing"] = self._score_gsc(requirement_text, complex_processing_keywords)

        # 10. 可重用性
        reusability_keywords = ["复用", "组件", "模块", "通用", "标准化", "框架", "库", "SDK"]
        gsc_scores["reusability"] = self._score_gsc(requirement_text, reusability_keywords)

        # 11. 安装便利性
        installation_keywords = ["安装", "部署", "配置", "环境", "依赖", "容器", "Docker", "K8s"]
        gsc_scores["installation_ease"] = self._score_gsc(requirement_text, installation_keywords)

        # 12. 操作便利性
        operational_keywords = ["操作", "管理", "监控", "日志", "告警", "运维", "维护", "备份"]
        gsc_scores["operational_ease"] = self._score_gsc(requirement_text, operational_keywords)

        # 13. 多站点部署
        multi_site_keywords = ["多站点", "多地", "跨地域", "异地", "容灾", "备份", "主备", "集群"]
        gsc_scores["multiple_sites"] = self._score_gsc(requirement_text, multi_site_keywords)

        # 14. 变更便利性
        change_keywords = ["变更", "扩展", "升级", "迭代", "版本", "兼容", "迁移", "重构"]
        gsc_scores["facilitate_change"] = self._score_gsc(requirement_text, change_keywords)

        return gsc_scores

    def _score_gsc(self, text: str, keywords: List[str]) -> int:
        """评分通用系统特性（基于IFPUG标准）"""
        text_lower = text.lower()
        keyword_count = sum(1 for keyword in keywords if keyword in text_lower)

        # IFPUG标准评分机制：
        # 0分：无影响
        # 1分：轻微影响
        # 3分：中等影响
        # 5分：显著影响
        if keyword_count == 0:
            return 0  # 无影响
        elif keyword_count <= 2:
            return 1  # 轻微影响
        elif keyword_count <= 4:
            return 3  # 中等影响
        else:
            return 5  # 显著影响

    def _estimate_duration_cocomo(self, total_afp: float) -> float:
        """基于COCOMO模型估算工期"""
        # COCOMO基础模型：工作量 = a × (规模)^b;
        # 工期 = c × (工作量)^d
        # 这里使用简化的COCOMO模型，基于AFP进行估算
        #	table[3][4]=
        #	{//a,b,c,d
        #	2.4,1.05,2.5,0.38,//成熟项目
        #	3.0,1.12,2.5,0.35,//中型项目
        #	3.6,1.20,2.5,0.32,//大型项目
        #	};
        if total_afp <= 50:
            # 小型项目：线性关系
            return 2.5 * ((2.4 * (total_afp ** 1.05)) ** 0.38)
        elif total_afp <= 200:
            # 中型项目：规模效应开始显现
            return 2.5 * ((3.0 * (total_afp ** 1.12)) ** 0.35)
        else:
            # 大型项目：规模效应显著
            return 2.5 * ((3.6 * (total_afp ** 1.20)) ** 0.32)

    async def _check_cohesion_degree_llm(
        self,
        function_list: List[Dict[str, Any]],
        requirement_text: str,
        input_data: AgentInput
    ) -> RuleCheckResult:
        """检查内聚度（LLM语义分析）"""
        try:
            # 构建功能描述列表供LLM分析
            function_descriptions = []
            for func in function_list:
                func_desc = func.get("desc", "") + " " + func.get("title", "")
                function_descriptions.append({
                    "id": func.get("id", ""),
                    "description": func_desc
                })

            # 调用LLM进行内聚度分析
            llm_result = await self._call_llm_with_schema(
                llm_model=(input_data.config or {}).get("model") or "qwen-coder-plus",
                messages=self._build_cohesion_messages(function_descriptions, requirement_text),
                response_model=CohesionAssessmentResult
            )

            # 转换LLM结果为RuleCheckResult格式
            return self._convert_cohesion_llm_result_to_rule_result(llm_result)

        except Exception as e:
            logger.error(f"LLM内聚度评估失败: {str(e)}", exc_info=True)
            return RuleCheckResult(
                rule_id="feasibility_001",
                rule_name="内聚度评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.LOW_COHESION,
                description=f"LLM内聚度评估执行失败: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查LLM服务是否正常",
                evidence={"error": str(e)},
                passed=False
            )

    def _build_cohesion_messages(self, function_descriptions: List[Dict[str, str]], requirement_text: str) -> List[Dict[str, str]]:
        """构建内聚度评估的LLM消息"""
        cohesion_prompt = """你是一个专业的软件架构评估专家，负责分析功能描述的内聚度。

        内聚度评估标准：
        - 高内聚：功能职责单一，相关性强，实现复杂度低
        - 中内聚：功能职责相对集中，有一定相关性  
        - 低内聚：功能职责分散，相关性弱，实现复杂度高

        请对以下功能描述进行内聚度评估：
        """

        # 添加功能描述
        for i, func in enumerate(function_descriptions, 1):
            cohesion_prompt += f"\n{i}. 功能 {func['id']}: {func['description']}"

        cohesion_prompt += "\n\n请分析每个功能的内聚度，并识别低内聚的功能。"

        return [
            {"role": "system", "content": cohesion_prompt},
            {"role": "user", "content": f"原始需求：{requirement_text}"}
        ]

    def _convert_cohesion_llm_result_to_rule_result(self, llm_result: CohesionAssessmentResult) -> RuleCheckResult:
        """将LLM内聚度评估结果转换为RuleCheckResult格式"""
        try:
            low_cohesion_count = len(llm_result.low_cohesion_functions)

            if low_cohesion_count > 0:
                # 存在低内聚功能
                low_cohesion_ids = [item.function_id for item in llm_result.low_cohesion_functions]
                low_cohesion_descriptions = [item.assessment for item in llm_result.low_cohesion_functions]
                return RuleCheckResult(
                    rule_id="feasibility_001",
                    rule_name="内聚度评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.LOW_COHESION,
                    description=f"发现{low_cohesion_count}个低内聚功能: {', '.join(low_cohesion_descriptions)}",
                    affected_nodes=low_cohesion_ids,
                    affected_dependencies=[],
                    recommendation="低内聚功能建议重新拆分或重构",
                    evidence={
                        "low_cohesion_functions": [
                            {
                                "function_id": item.function_id,
                                "cohesion_level": item.cohesion_level,
                                "assessment": item.assessment,
                                "confidence": item.confidence
                            } for item in llm_result.low_cohesion_functions
                        ],
                        "overall_assessment": llm_result.overall_assessment
                    },
                    passed=False
                )
            else:
                # 所有功能内聚度良好
                return RuleCheckResult(
                    rule_id="feasibility_001",
                    rule_name="内聚度评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.LOW_COHESION,
                    description="所有功能内聚度均在合理范围内",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"overall_assessment": llm_result.overall_assessment},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_001",
                rule_name="内聚度评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.LOW_COHESION,
                description=f"转换内聚度评估结果时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查LLM评估结果格式是否正确",
                evidence={"error": str(e)},
                passed=False
            )


    def _check_function_point_scale_per_function(self, fpa_results: List[FPAAssessmentResult], function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查单个功能点规模（基于单个功能点）"""
        try:
            affected_nodes = []
            
            for i, fpa_result in enumerate(fpa_results):
                function_afp = fpa_result.total_afp
                
                # 单个功能点规模评估标准
                if function_afp > 15:  # 大型功能
                    function_id = function_list[i].get("id", f"function_{i}")
                    affected_nodes.append(function_id)
            
            if affected_nodes:
                return RuleCheckResult(
                    rule_id="feasibility_002",
                    rule_name="功能点规模评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.FUNCTION_POINT_SCALE_ISSUE,
                    description=f"发现{len(affected_nodes)}个功能点规模过大的子功能",
                    affected_nodes=affected_nodes,
                    affected_dependencies=[],
                    recommendation="大型功能建议进一步拆分以降低实现复杂度",
                    evidence={"affected_functions": affected_nodes, "threshold": 15},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="feasibility_002",
                    rule_name="功能点规模评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.FUNCTION_POINT_SCALE_ISSUE,
                    description="所有子功能点规模合理",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"total_functions": len(function_list)},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_002",
                rule_name="功能点规模评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.FUNCTION_POINT_SCALE_ISSUE,
                description=f"检查功能点规模时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查FPA分析结果是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_workload_estimation_per_function(self, fpa_results: List[FPAAssessmentResult], resource_constraints: Dict[str, Any], function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查单个功能工作量估算（基于单个功能点）"""
        try:
            affected_nodes = []
            
            for i, fpa_result in enumerate(fpa_results):
                function_workload = fpa_result.estimated_workload
                
                # 单个功能工作量评估标准
                if function_workload > 0.5:  # 超过0.5人月为高工作量功能
                    function_id = function_list[i].get("id", f"function_{i}")
                    affected_nodes.append(function_id)
            
            if affected_nodes:
                return RuleCheckResult(
                    rule_id="feasibility_003",
                    rule_name="工作量估算评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.WORKLOAD_EXCEEDED,
                    description=f"发现{len(affected_nodes)}个工作量过高的子功能",
                    affected_nodes=affected_nodes,
                    affected_dependencies=[],
                    recommendation="高工作量功能建议重新评估或分阶段实现",
                    evidence={"affected_functions": affected_nodes, "threshold": 0.5},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="feasibility_003",
                    rule_name="工作量估算评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.WORKLOAD_EXCEEDED,
                    description="所有子功能工作量估算合理",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"total_functions": len(function_list)},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_003",
                rule_name="工作量估算评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.WORKLOAD_EXCEEDED,
                description=f"检查工作量估算时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                    recommendation="检查FPA分析结果是否正确",
                evidence={"error": str(e)},
                passed=False
            )


    def _check_granularity_reasonableness_per_function(self, fpa_results: List[FPAAssessmentResult], function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查单个功能粒度合理性（基于单个功能点）"""
        try:
            too_coarse_nodes = []  # 粒度过粗的功能
            too_fine_nodes = []    # 粒度过细的功能
            
            for i, fpa_result in enumerate(fpa_results):
                function_afp = fpa_result.total_afp
                function_id = function_list[i].get("id", f"function_{i}")
                
                # 单个功能粒度评估标准
                if function_afp < 1:  # 粒度过细
                    too_fine_nodes.append(function_id)
                elif function_afp > 15:  # 粒度过粗
                    too_coarse_nodes.append(function_id)
            
            if too_coarse_nodes or too_fine_nodes:
                description_parts = []
                if too_coarse_nodes:
                    description_parts.append(f"{len(too_coarse_nodes)}个功能粒度过粗")
                if too_fine_nodes:
                    description_parts.append(f"{len(too_fine_nodes)}个功能粒度过细")
                
                recommendation_parts = []
                if too_coarse_nodes:
                    recommendation_parts.append("粒度过粗功能建议进一步拆分")
                if too_fine_nodes:
                    recommendation_parts.append("粒度过细功能建议合并相关功能")
                
                return RuleCheckResult(
                    rule_id="feasibility_004",
                    rule_name="粒度合理性评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.GRANULARITY_ISSUE,
                    description=f"发现{'，'.join(description_parts)}",
                    affected_nodes=too_coarse_nodes + too_fine_nodes,
                    affected_dependencies=[],
                    recommendation="; ".join(recommendation_parts),
                    evidence={
                        "too_coarse_functions": too_coarse_nodes,
                        "too_fine_functions": too_fine_nodes,
                        "thresholds": {"too_fine": 1, "too_coarse": 15}
                    },
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="feasibility_004",
                    rule_name="粒度合理性评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.GRANULARITY_ISSUE,
                    description="所有子功能粒度合理",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"total_functions": len(function_list)},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_004",
                rule_name="粒度合理性评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.GRANULARITY_ISSUE,
                description=f"检查粒度合理性时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查功能列表和FPA分析结果是否正确",
                evidence={"error": str(e)},
                passed=False
            )


    def _check_resource_constraint_match_per_function(self, fpa_results: List[FPAAssessmentResult], resource_constraints: Dict[str, Any], function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查单个功能资源约束匹配（基于单个功能点）"""
        try:
            affected_nodes = []
            
            # 获取资源约束
            available_workload_per_function = resource_constraints.get("available_workload_per_function", 1.0)
            
            for i, fpa_result in enumerate(fpa_results):
                function_workload = fpa_result.estimated_workload
                
                # 单个功能资源约束匹配评估
                if function_workload > available_workload_per_function:
                    function_id = function_list[i].get("id", f"function_{i}")
                    affected_nodes.append(function_id)
            
            if affected_nodes:
                return RuleCheckResult(
                    rule_id="feasibility_005",
                    rule_name="资源约束匹配评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.ERROR,
                    issue_type=IssueType.RESOURCE_CONSTRAINT_MISMATCH,
                    description=f"发现{len(affected_nodes)}个功能超出资源约束限制",
                    affected_nodes=affected_nodes,
                    affected_dependencies=[],
                    recommendation="超出资源约束的功能建议调整范围或增加资源",
                    evidence={
                        "affected_functions": affected_nodes,
                        "threshold": available_workload_per_function
                    },
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="feasibility_005",
                    rule_name="资源约束匹配评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.RESOURCE_CONSTRAINT_MISMATCH,
                    description="所有子功能资源约束匹配",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"total_functions": len(function_list)},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_005",
                rule_name="资源约束匹配评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.RESOURCE_CONSTRAINT_MISMATCH,
                description=f"检查资源约束匹配时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查资源约束和FPA分析结果是否正确",
                evidence={"error": str(e)},
                passed=False
            )

    def _check_technical_complexity_per_function(self, fpa_results: List[FPAAssessmentResult], function_list: List[Dict[str, Any]]) -> RuleCheckResult:
        """检查单个功能技术复杂性（基于单个功能点）"""
        try:
            affected_nodes = []
            high_complexity_functions = []
            
            # 技术复杂性评估基于功能类型和复杂度
            for i, fpa_result in enumerate(fpa_results):
                if fpa_result.function_classifications:
                    classification = fpa_result.function_classifications[0]
                    function_id = function_list[i].get("id", f"function_{i}")
                    
                    # 高复杂性功能识别标准
                    is_high_complexity = (
                        classification.complexity == "HIGH" or
                        classification.function_type in ["EO", "ILF"]  # 外部输出和内部逻辑文件通常更复杂
                    )
                    
                    if is_high_complexity:
                        high_complexity_functions.append({
                            "function_id": function_id,
                            "function_type": classification.function_type,
                            "complexity": classification.complexity
                        })
                        affected_nodes.append(function_id)
            
            if affected_nodes:
                return RuleCheckResult(
                    rule_id="feasibility_006",
                    rule_name="技术复杂性评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.WARNING,
                    issue_type=IssueType.HIGH_TECHNICAL_COMPLEXITY,
                    description=f"发现{len(affected_nodes)}个技术复杂性较高的子功能",
                    affected_nodes=affected_nodes,
                    affected_dependencies=[],
                    recommendation="高复杂性功能建议采用简化实现或技术验证",
                    evidence={"high_complexity_functions": high_complexity_functions},
                    passed=False
                )
            else:
                return RuleCheckResult(
                    rule_id="feasibility_006",
                    rule_name="技术复杂性评估",
                    category=RuleCategory.FEASIBILITY,
                    severity=RuleSeverity.INFO,
                    issue_type=IssueType.HIGH_TECHNICAL_COMPLEXITY,
                    description="所有子功能技术复杂性合理",
                    affected_nodes=[],
                    affected_dependencies=[],
                    recommendation="无需动作",
                    evidence={"total_functions": len(function_list)},
                    passed=True
                )

        except Exception as e:
            return RuleCheckResult(
                rule_id="feasibility_006",
                rule_name="技术复杂性评估",
                category=RuleCategory.FEASIBILITY,
                severity=RuleSeverity.ERROR,
                issue_type=IssueType.HIGH_TECHNICAL_COMPLEXITY,
                description=f"检查技术复杂性时发生错误: {str(e)}",
                affected_nodes=[],
                affected_dependencies=[],
                recommendation="检查FPA分析结果是否正确",
                evidence={"error": str(e)},
                passed=False
            )


    def _build_evaluation_result(self, rule_results: List[RuleCheckResult], fpa_results: List[FPAAssessmentResult]) -> FeasibilityEvaluationResult:
        """构建可实现性评估结果（基于单个子功能）"""
        total_checks = len(rule_results)
        passed_checks = sum(1 for r in rule_results if r.passed)
        failed_checks = total_checks - passed_checks

        # 计算评分（通过率）
        base_score = passed_checks / total_checks if total_checks > 0 else 0.0

        # 分离关键问题和警告
        critical_issues = [r for r in rule_results if not r.passed and r.severity == RuleSeverity.ERROR]
        warnings = [r for r in rule_results if not r.passed and r.severity == RuleSeverity.WARNING]
        penalty = len(critical_issues) * 0.1

        # 计算整体项目指标（用于规模调整）
        total_afp = sum(fpa_result.total_afp for fpa_result in fpa_results) if fpa_results else 0
        avg_tcf = sum(fpa_result.tcf for fpa_result in fpa_results) / len(fpa_results) if fpa_results else 0.65

        # 规模适应性调整因子
        scale_adjustment_factor = self._calculate_scale_adjustment(total_afp)
        technical_complexity_factor = avg_tcf
        # 最终评分 = 基础评分 - 关键问题扣分
        score = max(0.0, base_score - penalty)
        score = score * scale_adjustment_factor * technical_complexity_factor
        score = min(1.0, score)  # 限制在0-1范围内

        # 构建整体FPA分析结果（用于向后兼容）
        if fpa_results:
            # 计算整体指标
            total_ufp = sum(fpa_result.total_ufp for fpa_result in fpa_results)
            total_estimated_workload = sum(fpa_result.estimated_workload for fpa_result in fpa_results)
            total_estimated_cost = sum(fpa_result.estimated_cost for fpa_result in fpa_results)

            # 合并所有功能分类
            all_classifications = []
            for fpa_result in fpa_results:
                all_classifications.extend(fpa_result.function_classifications)

            fpa_analysis = FPAAssessmentResult(
                total_ufp=total_ufp,
                total_afp=total_afp,
                tcf=avg_tcf,
                estimated_workload=total_estimated_workload,
                estimated_cost=total_estimated_cost,
                estimated_duration=self._estimate_duration_cocomo(total_afp),
                function_classifications=all_classifications
            )
        else:
            fpa_analysis = None

        return FeasibilityEvaluationResult(
            score=score,
            total_checks=total_checks,
            passed_checks=passed_checks,
            failed_checks=failed_checks,
            rule_results=rule_results,
            critical_issues=critical_issues,
            warnings=warnings,
            fpa_analysis=fpa_analysis,
            cohesion_assessment={},
            granularity_assessment={},
            resource_constraint_match={},
            scale_adjustment_factor=scale_adjustment_factor,
            technical_complexity_factor=technical_complexity_factor
        )


    def _calculate_scale_adjustment(self, total_afp: float) -> float:
        """计算规模适应性调整因子"""
        if total_afp < 50:
            return 1.1  # 小型项目：规模优势
        elif total_afp < 300:
            return 1.0  # 中型项目：标准规模
        elif total_afp < 1000:
            return 0.9  # 大型项目：规模挑战
        else:
            return 0.8  # 超大型项目：高风险规模

    def _classify_project_scale(self, total_afp: float) -> Dict[str, Any]:
        """项目规模分类"""
        if total_afp < 50:
            return {"scale": "small", "description": "小型项目", "risk_level": "low"}
        elif total_afp < 300:
            return {"scale": "medium", "description": "中型项目", "risk_level": "medium"}
        elif total_afp < 1000:
            return {"scale": "large", "description": "大型项目", "risk_level": "high"}
        else:
            return {"scale": "very_large", "description": "超大型项目", "risk_level": "critical"}

    def _extract_quality_flags(self, evaluation_result: FeasibilityEvaluationResult) -> List[str]:
        """提取质量标记"""
        flags = []

        if evaluation_result.score < 0.6:
            flags.append("low_feasibility_score")

        if len(evaluation_result.critical_issues) > 0:
            flags.append("critical_feasibility_issues")

        if evaluation_result.fpa_analysis and evaluation_result.fpa_analysis.estimated_workload > 6:
            flags.append("high_workload")

        return flags

    def _extract_warnings(self, evaluation_result: FeasibilityEvaluationResult) -> List[str]:
        """提取警告信息"""
        warnings = []

        for issue in evaluation_result.critical_issues:
            warnings.append(f"关键可实现性问题: {issue.description}")

        for warning in evaluation_result.warnings:
            warnings.append(f"可实现性警告: {warning.description}")

        return warnings

    def _extract_evidence(self, evaluation_result: FeasibilityEvaluationResult) -> List[str]:
        """提取证据信息"""
        evidence = []

        for result in evaluation_result.rule_results:
            if not result.passed and result.evidence:
                evidence.append(f"{result.rule_name}: {str(result.evidence)}")

        if evaluation_result.fpa_analysis:
            evidence.append(f"FPA分析: AFP={evaluation_result.fpa_analysis.total_afp:.1f}, 工作量={evaluation_result.fpa_analysis.estimated_workload:.1f}人月")
                
        return evidence