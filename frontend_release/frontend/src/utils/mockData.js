/**
 * 模拟功能树数据
 */
export const mockFunctionTreeData = {
    id: 'F-1',
    desc: '实现一个办公审批平台，支持员工发起请假、报销、出差等申请，经过多级审批后归档，并提供进度查询和消息提醒功能。',
    title: '构建一个支持多类型申请、多级审批、归档、进度查询与消息提醒的办公审批平台',
    children: [
        {
            id: 'F-1.2',
            desc: '实现可配置的多级审批逻辑，支持按组织架构、角色或指定人员进行逐级或并行审批。',
            title: '多级审批流程引擎',
            children: [],
            node_type: 'WORKFLOW',
            granularity: 'FEATURE',
            acceptance_hint: [
                '审批流程应支持至少三级串行审批',
                '应允许管理员配置不同申请类型的审批路径'
            ]
        },
        {
            id: 'F-1.4',
            desc: '允许申请人和相关审批人实时查看当前申请所处的审批阶段、已通过节点及待处理人。',
            title: '审批进度实时查询',
            children: [],
            node_type: 'CAPABILITY',
            granularity: 'FEATURE',
            acceptance_hint: [
                '用户应能在个人中心查看所有本人相关的申请进度',
                '进度展示需包含当前审批人及历史审批记录'
            ]
        },
        {
            id: 'F-1.6',
            desc: '处理审批人长时间未处理、流程中断等异常情况，支持自动转交、催办或流程终止。',
            title: '异常处理与超时机制',
            children: [],
            node_type: 'EXCEPTION',
            granularity: 'STORY',
            acceptance_hint: [
                '审批超过48小时未处理应触发催办提醒',
                '支持管理员手动干预异常流程'
            ]
        },
        {
            id: 'F-1.7',
            desc: '提供审批类型、审批人规则、通知模板等基础配置能力，并控制不同角色的数据访问权限。',
            title: '基础配置与权限支撑',
            children: [
                {
                    id: 'F-1.7.1',
                    desc: '支持管理员配置各类申请类型（如请假、报销、出差）及其对应的多级审批规则。',
                    title: '审批类型与流程配置',
                    children: [],
                    node_type: 'CONFIG',
                    granularity: 'FEATURE',
                    acceptance_hint: [
                        'HR或管理员可新增/编辑申请类型',
                        '可为每种申请类型设置独立的审批人规则（如按职级、部门或指定人员）'
                    ]
                },
                {
                    id: 'F-1.7.2',
                    desc: '提供消息提醒模板的配置能力，用于审批发起、待办提醒、结果通知等场景。',
                    title: '通知模板管理',
                    children: [],
                    node_type: 'CONFIG',
                    granularity: 'FEATURE',
                    acceptance_hint: [
                        '支持自定义邮件/站内信模板内容',
                        '模板变量可包含申请人、审批状态、时间等动态字段'
                    ]
                }
            ],
            node_type: 'SUPPORT',
            granularity: 'FEATURE',
            acceptance_hint: [
                'HR或管理员可配置新申请类型及对应审批流',
                '普通员工仅能查看本人申请，审批人可查看待办及历史审批'
            ]
        },
        {
            id: 'F-1.1',
            desc: '支持员工发起请假、报销、出差等不同类型的申请，提供对应表单模板与数据校验。',
            title: '多类型申请表单管理',
            children: [
                {
                    id: 'F-1.1.1',
                    desc: '提供请假类型专用表单模板，包含开始时间、结束时间、请假类型（年假/病假等）、事由等字段，并实施必填与格式校验。',
                    title: '请假申请表单模板与校验',
                    children: [],
                    node_type: 'TASK',
                    granularity: 'STORY',
                    acceptance_hint: [
                        '表单必须包含至少4个核心字段：开始时间、结束时间、请假类型、事由',
                        '系统应在校验失败时提示具体错误字段及原因'
                    ]
                }
            ],
            node_type: 'CAPABILITY',
            granularity: 'FEATURE',
            acceptance_hint: [
                '系统应预置至少3种申请类型（请假、报销、出差）的表单模板',
                '每种表单应支持必填项校验与格式验证'
            ]
        }
    ],
    node_type: 'DOMAIN',
    granularity: 'EPIC',
    acceptance_hint: []
}

/**
 * 模拟评估数据
 */
export const mockEvaluationData = {
    summary: '项目综合评分为0.76，一致性表现优秀（1.00），可实现性良好（0.60），仅存在1个关于技术复杂性的警告。整体风险可控，建议继续推进。',
    risk_level: 'medium',
    overall_score: 0.7575000000000001,
    recommendation: 'proceed',
    consistency_score: 1,
    feasibility_score: 0.5958333333333334,
    integration_scope: null,
    consistency_result: {
        score: 1,
        warnings: [],
        per_child: [],
        rule_results: [
            {
                passed: true,
                rule_id: 'consistency_001',
                category: 'consistency',
                evidence: {},
                severity: 'info',
                rule_name: '依赖引用有效性',
                issue_type: 'invalid_dependency_reference',
                description: '所有依赖引用均有效',
                affected_nodes: [],
                recommendation: '无需动作',
                affected_dependencies: []
            }
        ]
    },
    feasibility_result: {
        score: 0.5958333333333334,
        warnings: [
            {
                rule_id: 'feasibility_001',
                category: 'feasibility',
                evidence: {},
                severity: 'warning',
                rule_name: '技术复杂性评估',
                issue_type: 'technical_complexity',
                description: '多级审批流程引擎涉及复杂的业务逻辑和状态管理',
                affected_nodes: ['F-1.2'],
                recommendation: '建议分阶段实施，先实现核心审批流程，再逐步扩展高级功能'
            }
        ],
        per_child: [],
        rule_results: [
            {
                passed: true,
                rule_id: 'feasibility_002',
                category: 'feasibility',
                evidence: {},
                severity: 'info',
                rule_name: '资源可行性',
                issue_type: 'resource_feasibility',
                description: '项目所需技术栈和资源在当前环境中可行',
                affected_nodes: [],
                recommendation: '无需动作',
                affected_dependencies: []
            }
        ]
    }
}

/**
 * 模拟处理进度数据
 */
export const mockProgressData = {
    stages: [
        { stage: 'normalizing', message: '正在标准化需求...' },
        { stage: 'decomposing', message: '正在分解功能需求...' },
        { stage: 'analyzing_dependencies', message: '正在分析依赖关系...' },
        { stage: 'evaluating_consistency', message: '正在评估一致性...' },
        { stage: 'evaluating_feasibility', message: '正在评估可实现性...' },
        { stage: 'integrating', message: '正在整合结果...' },
        { stage: 'refining', message: '正在优化结果...' }
    ]
}

/**
 * 模拟处理需求
 * @param {string} requirement - 需求文本
 * @param {number} delay - 延迟时间(毫秒)
 * @returns {Promise<Object>} 模拟结果
 */
export const mockProcessRequirement = (requirement, delay = 3000) => {
    return new Promise((resolve) => {
        setTimeout(() => {
            resolve({
                success: true,
                data: {
                    functionTree: mockFunctionTreeData,
                    evaluation: mockEvaluationData
                }
            })
        }, delay)
    })
}

/**
 * 模拟进度更新
 * @param {Function} callback - 回调函数
 * @param {number} interval - 间隔时间(毫秒)
 * @returns {Function} 停止函数
 */
export const mockProgressUpdates = (callback, interval = 1000) => {
    let currentStage = 0
    const stages = mockProgressData.stages

    const timer = setInterval(() => {
        if (currentStage < stages.length) {
            callback(stages[currentStage])
            currentStage++
        } else {
            clearInterval(timer)
        }
    }, interval)

    return () => clearInterval(timer)
}