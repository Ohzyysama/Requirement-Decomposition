import { defineStore } from 'pinia'
import { ref, triggerRef } from 'vue'
import { ElMessage } from 'element-plus'
import chatAPI from '@/api/chat'

/** SSE event:error 与后端 orchestrator.coord_kind 对齐 */
const SSE_COORD_KIND_MAIN = 'main'
const SSE_COORD_KIND_REFINE_NODE = 'refine_node'
const SSE_PENDING_SSE_TIMEOUT_CODE = 'PENDING_SSE_TIMEOUT'

function isCoordinatorSsePendingTimeoutPayload(data) {
    return data && typeof data === 'object' && String(data.code || '').trim() === SSE_PENDING_SSE_TIMEOUT_CODE
}

/**
 * 区分主编排 vs 节点重拆；缺省按 main（兼容旧后端）。
 * 连接层 PENDING_SSE_TIMEOUT 无 coord_kind，此处不作为 refine。
 */
function getCoordinatorSseErrorCoordKind(data) {
    if (!data || typeof data !== 'object' || isCoordinatorSsePendingTimeoutPayload(data)) {
        return SSE_COORD_KIND_MAIN
    }
    const ck = data.coord_kind
    if (ck === SSE_COORD_KIND_REFINE_NODE) return SSE_COORD_KIND_REFINE_NODE
    if (ck === SSE_COORD_KIND_MAIN) return SSE_COORD_KIND_MAIN
    return SSE_COORD_KIND_MAIN
}

const emptyEvaluationView = () => ({
    summary: '',
    risk_level: 'unknown',
    recommendation: '未知',
    overall_score: 0,
    consistency_score: 0,
    feasibility_score: 0,
    integration_scope: null,
    consistency_result: {},
    feasibility_result: {},
})

function normalizeConversationList(raw) {
    if (!raw) return []
    if (Array.isArray(raw)) return raw
    const keys = ['items', 'conversations', 'data', 'results']
    for (const k of keys) {
        if (Array.isArray(raw[k])) return raw[k]
    }
    return []
}

const DONE_STATUSES = new Set(['completed', 'done', 'success', 'finished', 'succeeded'])
const FAILED_STATUSES = new Set(['failed', 'error', 'cancelled', 'canceled'])

function normStatus(s) {
    if (s == null) return ''
    return String(s).toLowerCase().trim()
}

/**
 * 从 Error code: 403 - {'error': { 'message': '...' }} 这类文本中解析出 message
 */
function extractEmbeddedErrorString(blob) {
    if (!blob || typeof blob !== 'string') return null
    const key = "'message': '"
    let start = blob.indexOf(key)
    let quote = "'"
    if (start === -1) {
        const key2 = '"message": "'
        start = blob.indexOf(key2)
        if (start === -1) return null
        start += key2.length
        quote = '"'
    } else {
        start += key.length
    }

    let out = ''
    for (let i = start; i < blob.length; i++) {
        const c = blob[i]
        if (c === '\\' && i + 1 < blob.length) {
            const n = blob[i + 1]
            if (n === 'n') {
                out += '\n'
                i++
                continue
            }
            if (n === "'" || n === '"' || n === '\\') {
                out += n
                i++
                continue
            }
            out += n
            i++
            continue
        }
        if (c === quote) return out || null
        out += c
    }
    return out.trim() || null
}

/**
 * 上游（如模型提供商）典型英文报错 → 中文简述；已是中文或非匹配文案则尽量不改动
 */
function localizeUpstreamErrorMessage(text) {
    if (!text || typeof text !== 'string') return text
    const t = text.trim()
    if (!t) return t
    const lower = t.toLowerCase()

    if (
        (lower.includes('free tier') && lower.includes('exhausted')) ||
        lower.includes('allocationquota.freetieronly') ||
        /\bfreetieronly\b/i.test(lower)
    ) {
        return '模型的免费用量已用尽。如需继续使用，请在提供商管理控制台关闭「仅限免费档」选项，或改用付费配额。'
    }
    if (lower.includes('rate limit') || lower.includes('too many requests')) {
        return '请求过于频繁，请稍后再试。'
    }
    if (/^insufficient_quota\b/i.test(lower) || lower.includes('quota exceeded')) {
        return '配额不足，请检查账户用量或充值后再试。'
    }
    if (lower.includes('invalid api key') || lower.includes('incorrect api key')) {
        return 'API 密钥无效，请检查后重试。'
    }
    if (
        lower === 'failed to fetch' ||
        lower.includes('networkerror') ||
        lower.includes('load failed')
    ) {
        return '网络请求失败，请检查网络连接或后端服务是否可用。'
    }

    return t.replace(/^error\s+code:\s*(\d+)\s*[-–—]\s*/i, '错误码 $1：').replace(/\s+/g, ' ').trim()
}

/**
 * 协调器 SSE event:error 的 data → 用户可读一句话
 */
function formatCoordinatorSseErrorMessage(data) {
    const asUserText = (s) => {
        if (typeof s !== 'string' || !s.trim()) return s
        const z = localizeUpstreamErrorMessage(s.trim())
        return z && z.trim() ? z.trim() : s.trim()
    }

    const pick = (v) => (typeof v === 'string' && v.trim() ? v.trim() : null)

    if (data == null) return '协调任务出错'
    if (typeof data === 'string') {
        const t = data.trim()
        if (!t) return '协调任务出错'
        const embedded = extractEmbeddedErrorString(t)
        const raw = embedded || (t.length > 400 ? `${t.slice(0, 400)}…` : t)
        return asUserText(raw)
    }
    if (typeof data !== 'object') return '协调任务出错'

    if (isCoordinatorSsePendingTimeoutPayload(data)) {
        const hint =
            pick(data.message) ||
            pick(data.msg) ||
            '等待协调启动超时，请重新连接 SSE 或先 POST 启动编排（start / refine-node）。'
        return asUserText(hint)
    }

    const direct = pick(data.message) || pick(data.msg) || pick(data.detail) || pick(data.reason)
    if (direct) return asUserText(direct)

    const errField = data.error
    if (typeof errField === 'string') {
        const s = errField.trim()
        const embedded = extractEmbeddedErrorString(s)
        const raw = embedded || (s.length > 400 ? `${s.slice(0, 400)}…` : s)
        return asUserText(raw)
    }
    if (errField && typeof errField === 'object') {
        const nested = pick(errField.message) || pick(errField.msg) || pick(errField.detail)
        if (nested) return asUserText(nested)
    }

    if (data.code != null && String(data.code).trim()) {
        return `错误码：${String(data.code).trim()}`
    }

    return '协调任务出错'
}

function unwrapConversationDetail(apiResult) {
    if (!apiResult || typeof apiResult !== 'object') return {}
    const inner = apiResult.data !== undefined ? apiResult.data : apiResult
    return inner && typeof inner === 'object' ? inner : {}
}

/**
 * GET /conversations/:id 常把跑批结果放在 conversation_metadata.final_result，
 * 与 SSE completed 里顶层的 final_result 字段对齐，供提取功能树与评估。
 */
function mergeConversationDetailPayload(payload) {
    if (!payload || typeof payload !== 'object') return payload
    const meta = payload.conversation_metadata
    if (!meta || typeof meta !== 'object') return payload

    /** 与 final_result 同级的 metadata 字段（部分接口把树/边放在 meta 根上） */
    const metaHoist = {}
    const maybeHoist = (key) => {
        if (meta[key] != null && payload[key] == null) {
            metaHoist[key] = meta[key]
        }
    }
    for (const key of [
        'function_tree_with_evaluation_meta',
        'function_tree_with_episode_meta',
        'function_list',
        'dependencies',
        'decomposition_root',
    ]) {
        maybeHoist(key)
    }

    const fr = meta.final_result
    if (!fr || typeof fr !== 'object') {
        return {
            ...metaHoist,
            ...payload,
        }
    }
    return {
        ...fr,
        ...metaHoist,
        ...payload,
        final_result: fr,
    }
}

/** 将单条依赖边规范为 { from, to }，兼容 source/target 等别名 */
function normalizeDependencyEdge(e) {
    if (!e || typeof e !== 'object') return null
    let from = e.from ?? e.source ?? e.source_id ?? e.prerequisite_id ?? e.prereq_id
    let to = e.to ?? e.target ?? e.target_id ?? e.consumer_id ?? e.dependent_id
    if (from != null && typeof from !== 'string') from = String(from).trim()
    if (to != null && typeof to !== 'string') to = String(to).trim()
    from = typeof from === 'string' ? from.trim() : ''
    to = typeof to === 'string' ? to.trim() : ''
    if (!from || !to) return null
    return { ...e, from, to }
}

/**
 * 从详情 / final_result / 协调快照中取 flat 依赖边列表（与后端 dependency_classifier 产物对齐）。
 * 新版接口可能只把边放在 coordination_live_snapshot.function_tree_dependencies_bundle.data 内，
 * 或仅挂在会话根上，故多路径合并并去重。
 */
function extractDependenciesList(payload) {
    if (!payload || typeof payload !== 'object') return []

    const buckets = []

    const pushArr = (arr) => {
        if (Array.isArray(arr) && arr.length) buckets.push(arr)
    }

    const meta = payload.conversation_metadata
    pushArr(payload.dependencies)
    pushArr(payload.final_result?.dependencies)
    pushArr(meta?.final_result?.dependencies)
    pushArr(meta?.dependencies)

    const snapWrap = meta?.coordination_live_snapshot?.function_tree_dependencies_bundle
    const inner = snapWrap?.data && typeof snapWrap.data === 'object' ? snapWrap.data : null
    if (inner?.dependencies) {
        const depBlock = inner.dependencies
        if (Array.isArray(depBlock.dependencies)) pushArr(depBlock.dependencies)
        else if (Array.isArray(depBlock)) pushArr(depBlock)
    }

    if (buckets.length === 0) return []

    const seen = new Set()
    const out = []
    for (const arr of buckets) {
        for (const raw of arr) {
            const e = normalizeDependencyEdge(raw)
            if (!e) continue
            const idKey = e.dep_id != null && String(e.dep_id).trim() ? String(e.dep_id).trim() : ''
            const key = idKey ? `id:${idKey}` : `e:${e.from}>${e.to}`
            if (seen.has(key)) continue
            seen.add(key)
            out.push(e)
        }
    }
    return out
}

/** 功能树对象：可能在根、final_result、metadata 或与 final_result 同级 */
function pickFunctionTreeSource(payload) {
    if (!payload || typeof payload !== 'object') return null
    const meta = payload.conversation_metadata
    const fr = meta?.final_result
    return (
        payload.function_tree_with_evaluation_meta ||
        fr?.function_tree_with_evaluation_meta ||
        meta?.function_tree_with_evaluation_meta ||
        payload.function_tree_with_episode_meta ||
        fr?.function_tree_with_episode_meta ||
        meta?.function_tree_with_episode_meta ||
        payload.function_tree ||
        payload.partial_function_tree ||
        fr?.function_tree ||
        null
    )
}

function pickFunctionList(payload) {
    if (!payload || typeof payload !== 'object') return null
    const meta = payload.conversation_metadata
    const fr = meta?.final_result
    const list =
        (Array.isArray(payload.function_list) && payload.function_list.length && payload.function_list) ||
        (Array.isArray(fr?.function_list) && fr.function_list.length && fr.function_list) ||
        (Array.isArray(meta?.function_list) && meta.function_list.length && meta.function_list) ||
        null
    return list
}

/**
 * 后端边语义：from 为提供方 / 前置，to 为消费方 / 依赖方。
 * - outgoing：本节点作为 to，依赖 from
 * - incoming：本节点作为 from，被 to 所依赖
 */
function mergeDependencyEdgesIntoTree(root, dependencies) {
    if (!root || typeof root !== 'object' || !Array.isArray(dependencies) || dependencies.length === 0) {
        return root
    }
    /** @type {Map<string, object[]>} */
    const byConsumer = new Map()
    /** @type {Map<string, object[]>} */
    const byPrereq = new Map()

    for (const d of dependencies) {
        const norm = normalizeDependencyEdge(d)
        if (!norm) continue
        const from = norm.from
        const to = norm.to
        if (typeof from !== 'string' || typeof to !== 'string' || !from || !to) continue
        if (!byConsumer.has(to)) byConsumer.set(to, [])
        byConsumer.get(to).push(norm)
        if (!byPrereq.has(from)) byPrereq.set(from, [])
        byPrereq.get(from).push(norm)
    }

    const walk = (node) => {
        if (!node || typeof node !== 'object') return
        const id = node.id
        if (typeof id === 'string' && id) {
            node.outgoing_dependencies = byConsumer.get(id) ?? []
            node.incoming_dependencies = byPrereq.get(id) ?? []
        }
        const ch = node.children
        if (Array.isArray(ch)) {
            for (const c of ch) walk(c)
        }
    }
    walk(root)
    return root
}

/** 与后端 CONVERSATION_PLACEHOLDER_TITLE 默认一致；占位标题时尚未产出 suggested 标题 */
export const CONVERSATION_PLACEHOLDER_TITLE = '新对话'

function nonEmptyObject(o) {
    return o && typeof o === 'object' && Object.keys(o).length > 0
}

/** 节点重拆（refine-node）请求 config 中可实现性细化最大深度（最小为 1）；未指定时默认 1 */
const DEFAULT_REFINE_MAX_FEASIBILITY_REFINEMENT_DEPTH = 1

function buildRefineCoordinatorConfig(userConfig = {}) {
    const merged = { ...(userConfig && typeof userConfig === 'object' ? userConfig : {}) }
    const raw = merged.max_feasibility_refinement_depth
    const missing =
        raw === undefined ||
        raw === null ||
        (typeof raw === 'string' && raw.trim() === '')
    if (missing) {
        merged.max_feasibility_refinement_depth = DEFAULT_REFINE_MAX_FEASIBILITY_REFINEMENT_DEPTH
    } else {
        const n = Number(raw)
        merged.max_feasibility_refinement_depth = Number.isFinite(n)
            ? Math.max(1, Math.min(20, Math.trunc(n)))
            : DEFAULT_REFINE_MAX_FEASIBILITY_REFINEMENT_DEPTH
    }
    return merged
}

/** 避免 {} 或未跑出的 final_result（仅有 error/metadata）误判为「有结果」 */
function finalPayloadHasRenderableContent(fr) {
    if (!fr || typeof fr !== 'object') return false
    if (
        nonEmptyObject(fr.function_tree_with_evaluation_meta) ||
        nonEmptyObject(fr.function_tree_with_episode_meta)
    ) {
        return true
    }
    if (Array.isArray(fr.function_list) && fr.function_list.length > 0) return true
    if (nonEmptyObject(fr.evaluation)) return true
    if (Array.isArray(fr.evaluation_episodes) && fr.evaluation_episodes.length > 0) return true
    if (typeof fr.message === 'string' && fr.message.trim()) return true
    return false
}

function extractFinalPayloadFromConversation(payload) {
    if (!payload || typeof payload !== 'object') return null
    const fr = payload.final_result
    if (fr && typeof fr === 'object') {
        const errorSignal =
            fr.error != null &&
            fr.error !== '' &&
            !(typeof fr.error === 'object' && !nonEmptyObject(fr.error))
        if (errorSignal && !finalPayloadHasRenderableContent(fr)) {
            return null
        }
        if (finalPayloadHasRenderableContent(fr)) return fr
    }
    if (
        nonEmptyObject(payload.function_tree_with_evaluation_meta) ||
        nonEmptyObject(payload.function_tree_with_episode_meta) ||
        (Array.isArray(payload.evaluation_episodes) && payload.evaluation_episodes.length > 0)
    ) {
        return payload
    }
    return null
}

/** 后端若用 done 布尔或 status 表示结束，则不再接 SSE */
function isConversationFailed(payload) {
    if (!payload || typeof payload !== 'object') return false
    const st = normStatus(
        payload.status ?? payload.processing_status ?? payload.state ?? payload.coordinator_status
    )
    if (FAILED_STATUSES.has(st)) return true
    const task =
        payload.current_task ?? payload.active_task ?? payload.latest_task ?? payload.coordinator_task ?? payload.task
    if (task && typeof task === 'object') {
        if (FAILED_STATUSES.has(normStatus(task.status ?? task.state))) return true
    }
    return false
}

function isConversationDone(payload) {
    if (!payload || typeof payload !== 'object') return false
    if (payload.done === false) return false
    if (payload.done === true || payload.is_complete === true || payload.completed === true) return true

    if (extractFinalPayloadFromConversation(payload)) return true

    const st = normStatus(
        payload.status ?? payload.processing_status ?? payload.state ?? payload.coordinator_status
    )
    if (DONE_STATUSES.has(st)) return true

    const task =
        payload.current_task ?? payload.active_task ?? payload.latest_task ?? payload.coordinator_task ?? payload.task
    if (task && typeof task === 'object' && DONE_STATUSES.has(normStatus(task.status ?? task.state))) {
        return true
    }
    return false
}

function buildConversationFailedErrorMessage(payload) {
    if (!payload || typeof payload !== 'object') return '任务失败'
    const frErr = payload.final_result?.error
    const nestedParsed =
        frErr !== undefined && frErr !== null && frErr !== ''
            ? formatCoordinatorSseErrorMessage(frErr)
            : ''
    const strErr = (v) =>
        typeof v === 'string' && v.trim() ? formatCoordinatorSseErrorMessage(v.trim()) : ''
    return (
        strErr(payload.last_error) ||
        strErr(payload.error_message) ||
        nestedParsed ||
        strErr(typeof payload.error === 'string' ? payload.error : '') ||
        strErr(typeof payload.detail === 'string' ? payload.detail : '') ||
        '任务失败'
    )
}

export const useChatStore = defineStore('chat', () => {
    const currentConversation = ref(null)
    const currentTask = ref(null)
    const functionTreeData = ref(null)
    const evaluationData = ref(null)
    const processingStatus = ref('idle')
    const progressMessage = ref('')
    const errorMessage = ref('')
    const conversationsList = ref([])
    const conversationsLoading = ref(false)
    const conversationsError = ref('')
    const selectedConversationId = ref(null)
    const conversationDetailLoading = ref(false)
    /** 切换对话 / 新建分析时递增，用于忽略被取代的 SSE 结果 */
    const viewEpoch = ref(0)
    /** @type {import('vue').Ref<AbortController | null>} */
    const sseAbortController = ref(null)
    /** SSE dependencies_preview 与 function_tree_preview 到达顺序不定；未并入树前暂存 */
    const pendingCoordinatorDependencies = ref([])
    /**
     * refine-node 的 SSE error（coord_kind=refine_node）：服务端可能已将会话恢复为重拆前；用于 Toast 且避免误报「重拆完成」。
     * @type {import('vue').Ref<{ epoch: number, message: string, nodeId?: string } | null>}
     */
    const pendingRefineNodeFailureDetail = ref(null)

    const ProcessingStatus = {
        IDLE: 'idle',
        CREATING: 'creating',
        STARTING: 'starting',
        PROCESSING: 'processing',
        COMPLETED: 'completed',
        ERROR: 'error',
    }

    const fetchConversationsList = async () => {
        conversationsLoading.value = true
        conversationsError.value = ''
        try {
            const result = await chatAPI.listConversations()
            if (!result.success) {
                conversationsError.value = result.message || '加载对话列表失败'
                conversationsList.value = []
                return
            }
            conversationsList.value = normalizeConversationList(result.data)
        } catch (e) {
            conversationsError.value = e?.message || '加载对话列表失败'
            conversationsList.value = []
        } finally {
            conversationsLoading.value = false
        }
    }

    const selectConversation = (conversation) => {
        if (!conversation?.id) return
        selectedConversationId.value = conversation.id
        currentConversation.value = conversation
    }

    /**
     * 删除服务端对话并更新列表；若删除的是当前查看项则重置视图并中断 SSE
     * @param {string} conversationId
     * @returns {Promise<{ success: boolean, message?: string }>}
     */
    const deleteConversation = async (conversationId) => {
        if (!conversationId || typeof conversationId !== 'string') {
            return { success: false, message: '对话无效' }
        }
        const result = await chatAPI.deleteConversation(conversationId)
        if (!result.success) {
            return { success: false, message: result.message || '删除失败' }
        }
        conversationsList.value = conversationsList.value.filter((c) => c.id !== conversationId)
        if (selectedConversationId.value === conversationId) {
            resetState()
        }
        return { success: true }
    }

    const stopExistingSse = () => {
        if (sseAbortController.value) {
            sseAbortController.value.abort()
            sseAbortController.value = null
        }
    }

    const applySuggestedConversationTitle = (title) => {
        const trimmed = typeof title === 'string' ? title.trim() : ''
        if (!trimmed) return
        const id = currentConversation.value?.id
        if (currentConversation.value) {
            currentConversation.value = { ...currentConversation.value, title: trimmed }
        }
        const list = conversationsList.value
        const idx = list.findIndex((c) => c.id === id)
        if (idx !== -1) {
            const next = [...list]
            next[idx] = { ...next[idx], title: trimmed }
            conversationsList.value = next
        }
    }

    /**
     * 与 SSE function_tree_dependencies_bundle 的 data 结构一致：tree.function_tree + dependencies.dependencies
     */
    const applyFunctionTreeDependenciesBundleInner = (inner, options = {}) => {
        const { clearEvaluation = true } = options
        if (!inner || typeof inner !== 'object') return false
        const treeWrap = inner.tree
        const ft = treeWrap?.function_tree ?? inner.function_tree
        const depBlock = inner.dependencies
        const deps = Array.isArray(depBlock?.dependencies)
            ? depBlock.dependencies
            : Array.isArray(depBlock)
              ? depBlock
              : []
        pendingCoordinatorDependencies.value = deps
        if (clearEvaluation) {
            evaluationData.value = null
        }
        if (ft && typeof ft === 'object') {
            const t = parseFunctionTree(ft, deps)
            if (t) {
                functionTreeData.value = t
                return true
            }
        }
        return false
    }

    /** 详情里 conversation_metadata.coordination_live_snapshot 的回填（刷新页面可恢复） */
    const hydrateCoordinatorLiveSnapshot = (payload) => {
        if (!payload || typeof payload !== 'object') return
        const wrap = payload.conversation_metadata?.coordination_live_snapshot?.function_tree_dependencies_bundle
        if (!wrap || typeof wrap !== 'object') return
        if (typeof wrap.stage === 'string' && wrap.stage.trim()) {
            progressMessage.value = getStageMessage(wrap.stage)
        }
        const inner = wrap.data && typeof wrap.data === 'object' ? wrap.data : null
        if (inner) {
            applyFunctionTreeDependenciesBundleInner(inner, { clearEvaluation: true })
        }
    }

    const applyPartialSnapshotFromDetail = (payload) => {
        const depEdges = extractDependenciesList(payload)
        const treeSrc = pickFunctionTreeSource(payload)
        if (treeSrc) {
            const t = parseFunctionTree(treeSrc, depEdges)
            if (t) functionTreeData.value = t
        } else {
            const fnList = pickFunctionList(payload)
            if (fnList) {
                const t = parseFunctionTree({ function_list: fnList }, depEdges)
                if (t) functionTreeData.value = t
            }
        }
        if (!functionTreeData.value) {
            const wrap = payload.conversation_metadata?.coordination_live_snapshot?.function_tree_dependencies_bundle
            const inner = wrap?.data && typeof wrap.data === 'object' ? wrap.data : null
            if (inner) {
                applyFunctionTreeDependenciesBundleInner(inner, { clearEvaluation: false })
            }
        }
        if (functionTreeData.value && depEdges.length === 0) {
            const inner = payload.conversation_metadata?.coordination_live_snapshot?.function_tree_dependencies_bundle?.data
            if (inner?.dependencies) {
                const depBlock = inner.dependencies
                const rawList = Array.isArray(depBlock?.dependencies)
                    ? depBlock.dependencies
                    : Array.isArray(depBlock)
                      ? depBlock
                      : []
                const norm = rawList.map(normalizeDependencyEdge).filter(Boolean)
                if (norm.length) mergeDependencyEdgesIntoTree(functionTreeData.value, norm)
            }
        }
        const ev = payload.evaluation ?? payload.partial_evaluation ?? payload.latest_evaluation
        if (ev && typeof ev === 'object') {
            evaluationData.value = parseEvaluationData(ev)
        } else {
            const fromEp = extractEvaluationFromFinalPayload(payload)
            if (fromEp) evaluationData.value = fromEp
        }
    }

    /**
     * 从列表进入对话：拉详情；已完成则还原结果；进行中则接 SSE
     */
    const openConversation = async (conversation) => {
        if (!conversation?.id) return
        viewEpoch.value++
        const epochLocal = viewEpoch.value
        stopExistingSse()

        selectedConversationId.value = conversation.id
        currentConversation.value = conversation
        errorMessage.value = ''
        conversationDetailLoading.value = true

        try {
            const result = await chatAPI.getConversationDetail(conversation.id)
            if (!result.success) throw new Error(result.message || '加载对话详情失败')
            const payload = mergeConversationDetailPayload(unwrapConversationDetail(result.data))

            if (viewEpoch.value !== epochLocal) return

            currentTask.value =
                payload.current_task ?? payload.active_task ?? payload.latest_task ?? payload.coordinator_task ?? null

            currentConversation.value = {
                ...conversation,
                ...payload,
                id: conversation.id,
            }

            functionTreeData.value = null
            evaluationData.value = null
            pendingCoordinatorDependencies.value = []
            processingStatus.value = ProcessingStatus.IDLE
            progressMessage.value = ''

            if (isConversationFailed(payload)) {
                processingStatus.value = ProcessingStatus.ERROR
                errorMessage.value = buildConversationFailedErrorMessage(payload)
                return
            }

            const finalPayload = extractFinalPayloadFromConversation(payload)
            if (finalPayload) {
                /** 传合并后的完整会话，确保 dependencies 能从根或 snapshot 等多处被 extractDependenciesList 读到 */
                applyCompletedPayload(payload)
                return
            }

            if (isConversationDone(payload)) {
                applyPartialSnapshotFromDetail(payload)
                processingStatus.value = ProcessingStatus.COMPLETED
                progressMessage.value = '需求分析完成！'
                return
            }

            processingStatus.value = ProcessingStatus.PROCESSING
            progressMessage.value = '连接进度流，等待任务更新…'

            hydrateCoordinatorLiveSnapshot(payload)

            const ac = new AbortController()
            sseAbortController.value = ac
            void watchCoordinatorSse(conversation.id, ac, epochLocal)
                .then(() => {
                    if (viewEpoch.value !== epochLocal) return
                    sseAbortController.value = null
                    void fetchConversationsList()
                })
                .catch((e) => {
                    if (viewEpoch.value !== epochLocal) return
                    sseAbortController.value = null
                    processingStatus.value = ProcessingStatus.ERROR
                    errorMessage.value = e?.message
                        ? formatCoordinatorSseErrorMessage(e.message)
                        : '进度流异常'
                })
        } catch (e) {
            if (viewEpoch.value !== epochLocal) return
            processingStatus.value = ProcessingStatus.ERROR
            errorMessage.value = e?.message
                ? formatCoordinatorSseErrorMessage(e.message)
                : '加载对话详情失败'
        } finally {
            if (viewEpoch.value === epochLocal) {
                conversationDetailLoading.value = false
            }
        }
    }

    const processRequirement = async (requirement, config = {}) => {
        try {
            resetState()
            await processWithRealAPI(requirement, config)
        } catch (error) {
            processingStatus.value = ProcessingStatus.ERROR
            errorMessage.value = error?.message
                ? formatCoordinatorSseErrorMessage(String(error.message))
                : '处理需求失败'
            console.error('处理需求失败:', error)
        }
    }

    const processWithRealAPI = async (requirement, config = {}) => {
        const epochAtStart = viewEpoch.value
        processingStatus.value = ProcessingStatus.CREATING
        progressMessage.value = '正在创建对话...'

        const conversationResult = await chatAPI.createConversation({
            original_requirement: requirement,
        })

        if (!conversationResult.success) {
            throw new Error(conversationResult.message)
        }

        const convId = conversationResult.data.id
        currentConversation.value = conversationResult.data
        selectedConversationId.value = convId

        processingStatus.value = ProcessingStatus.STARTING
        progressMessage.value = '已建立对话，连接进度流...'

        const ac = new AbortController()
        sseAbortController.value = ac
        const donePromise = watchCoordinatorSse(convId, ac, epochAtStart)

        const startResult = await chatAPI.startCoordinator(convId, config)

        if (!startResult.success) {
            ac.abort()
            sseAbortController.value = null
            void donePromise.catch(() => {})
            throw new Error(startResult.message)
        }

        currentTask.value = startResult.data
        processingStatus.value = ProcessingStatus.PROCESSING
        progressMessage.value = '协调器已启动，正在处理需求...'

        try {
            await donePromise
            if (viewEpoch.value !== epochAtStart) return
        } catch (e) {
            if (viewEpoch.value !== epochAtStart) return
            throw e
        } finally {
            if (viewEpoch.value === epochAtStart) {
                sseAbortController.value = null
                void fetchConversationsList()
            }
        }
    }

    const handleAgentTimeline = (payload) => {
        const span = payload?.span
        if (!span?.label) return
        if (span.status === 'running') {
            progressMessage.value = `${span.label} 运行中…`
        } else if (span.status === 'completed') {
            const dm = span.duration_minutes
            const tail =
                typeof dm === 'number' && Number.isFinite(dm)
                    ? `（约 ${dm.toFixed(1)} 分钟）`
                    : ''
            progressMessage.value = `${span.label} 已完成${tail}`
        }
    }

    const handleIntermediateResult = (payload) => {
        if (payload?.stage) {
            progressMessage.value = getStageMessage(payload.stage)
        }

        const ct = payload?.content_type
        const inner = payload?.data || {}

        switch (ct) {
            case 'pipeline_status': {
                const pct =
                    inner.overall_progress_percentage ??
                    inner.phase_progress_percentage ??
                    (typeof inner.overall_progress === 'number'
                        ? Math.round(inner.overall_progress)
                        : null)
                const note = typeof inner.progress_note === 'string' ? inner.progress_note : ''
                const desc = typeof inner.description === 'string' ? inner.description : ''
                const base = [getStageMessage(payload?.stage), desc, note].filter(Boolean).join(' — ')
                progressMessage.value =
                    pct != null && pct !== '' ? `${base}（约 ${pct}%）` : base
                break
            }
            case 'normalizer_preview': {
                const suggestedRaw =
                    (typeof inner.suggested_conversation_title === 'string'
                        ? inner.suggested_conversation_title
                        : '') ||
                    (typeof payload.suggested_conversation_title === 'string'
                        ? payload.suggested_conversation_title
                        : '')
                const suggested = suggestedRaw.trim()
                if (suggested) {
                    applySuggestedConversationTitle(suggested)
                }
                const summary =
                    typeof inner.summary === 'string' && inner.summary.trim()
                        ? inner.summary.trim()
                        : ''
                if (summary) {
                    progressMessage.value =
                        summary.length > 120 ? `${summary.slice(0, 120)}…` : summary
                }
                break
            }
            case 'function_tree_preview':
                if (inner.function_tree) {
                    const fromInner = extractDependenciesList(inner)
                    const depList =
                        fromInner.length > 0
                            ? fromInner
                            : [...pendingCoordinatorDependencies.value]
                    const t = parseFunctionTree(inner.function_tree, depList)
                    if (t) functionTreeData.value = t
                }
                break
            case 'dependencies_preview': {
                const deps = Array.isArray(inner.dependencies) ? inner.dependencies : []
                pendingCoordinatorDependencies.value = deps
                if (functionTreeData.value && deps.length > 0) {
                    mergeDependencyEdgesIntoTree(functionTreeData.value, deps)
                    triggerRef(functionTreeData)
                }
                break
            }
            case 'function_tree_dependencies_bundle':
                applyFunctionTreeDependenciesBundleInner(inner, { clearEvaluation: true })
                break
            case 'm2_agent_complete': {
                const ev = inner.evaluation
                if (ev && typeof ev === 'object') {
                    evaluationData.value = parseEvaluationData(ev)
                }
                const pickConsistencyBlock = (ce) => {
                    if (!ce || typeof ce !== 'object') return null
                    if (ce.consistency_result && typeof ce.consistency_result === 'object') {
                        return ce.consistency_result
                    }
                    if (ce.result && typeof ce.result === 'object') return ce.result
                    if (Array.isArray(ce.rule_results)) return ce
                    return null
                }
                const pickFeasibilityBlock = (fe) => {
                    if (!fe || typeof fe !== 'object') return null
                    if (fe.feasibility_result && typeof fe.feasibility_result === 'object') {
                        return fe.feasibility_result
                    }
                    if (fe.result && typeof fe.result === 'object') return fe.result
                    if (Array.isArray(fe.rule_results)) return fe
                    return null
                }
                const ce = inner.consistency_evaluation
                if (ce && typeof ce === 'object') {
                    const block = pickConsistencyBlock(ce)
                    const base = evaluationData.value || emptyEvaluationView()
                    evaluationData.value = {
                        ...base,
                        consistency_result: block || base.consistency_result,
                        consistency_score:
                            ce.consistency_score ?? ce.score ?? base.consistency_score ?? 0,
                    }
                }
                const fe = inner.feasibility_evaluation
                if (fe && typeof fe === 'object') {
                    const block = pickFeasibilityBlock(fe)
                    const base = evaluationData.value || emptyEvaluationView()
                    evaluationData.value = {
                        ...base,
                        feasibility_result: block || base.feasibility_result,
                        feasibility_score:
                            fe.feasibility_score ?? fe.score ?? base.feasibility_score ?? 0,
                    }
                }
                break
            }
            default:
                if (payload?.message) {
                    progressMessage.value = payload.message
                }
        }
    }

    /**
     * SSE completed：完整 final_result 或仅 { message }；可能含 stopped_by_user（用户中止）
     */
    const applyCompletedPayload = (data) => {
        const stoppedByUser = !!(data && typeof data === 'object' && data.stopped_by_user)

        const isBareMessage =
            data &&
            typeof data === 'object' &&
            Object.keys(data).length === 1 &&
            typeof data.message === 'string'

        if (isBareMessage) {
            progressMessage.value = data.message
            if (stoppedByUser) {
                processingStatus.value = ProcessingStatus.ERROR
                errorMessage.value = data.message || '任务已中止'
            } else {
                processingStatus.value = ProcessingStatus.COMPLETED
            }
            return
        }

        pendingCoordinatorDependencies.value = []
        const depEdges = extractDependenciesList(data)
        const treeMeta = pickFunctionTreeSource(data)
        const fnList = pickFunctionList(data)
        if (treeMeta) {
            functionTreeData.value = parseFunctionTree(treeMeta, depEdges)
        } else if (fnList) {
            functionTreeData.value = parseFunctionTree({ function_list: fnList }, depEdges)
        }
        if (!functionTreeData.value) {
            const wrap = data.conversation_metadata?.coordination_live_snapshot?.function_tree_dependencies_bundle
            const inner = wrap?.data && typeof wrap.data === 'object' ? wrap.data : null
            if (inner) {
                applyFunctionTreeDependenciesBundleInner(inner, { clearEvaluation: false })
            }
        }
        /** 边若仅在快照结构中、extractDependenciesList 因路径差异未拉到，则直接读快照补合并 */
        if (functionTreeData.value && depEdges.length === 0) {
            const inner = data.conversation_metadata?.coordination_live_snapshot?.function_tree_dependencies_bundle?.data
            if (inner?.dependencies) {
                const depBlock = inner.dependencies
                const rawList = Array.isArray(depBlock?.dependencies)
                    ? depBlock.dependencies
                    : Array.isArray(depBlock)
                      ? depBlock
                      : []
                const norm = rawList.map(normalizeDependencyEdge).filter(Boolean)
                if (norm.length) mergeDependencyEdgesIntoTree(functionTreeData.value, norm)
            }
        }

        const fromEpisodes = extractEvaluationFromFinalPayload(data)
        if (fromEpisodes) {
            evaluationData.value = fromEpisodes
        } else if (data.evaluation && typeof data.evaluation === 'object') {
            evaluationData.value = parseEvaluationData(data.evaluation)
        }

        const userMsg = typeof data.message === 'string' && data.message.trim() ? data.message.trim() : ''
        if (stoppedByUser) {
            progressMessage.value =
                userMsg || '已按您的操作中止，以下为当前已生成的结果（若有）'
            const stillRenderable = finalPayloadHasRenderableContent(data) || !!functionTreeData.value
            if (stillRenderable) {
                processingStatus.value = ProcessingStatus.COMPLETED
            } else {
                processingStatus.value = ProcessingStatus.ERROR
                errorMessage.value = progressMessage.value
            }
        } else {
            progressMessage.value = '需求分析完成！'
            processingStatus.value = ProcessingStatus.COMPLETED
        }
    }

    /**
     * SSE 结束后以服务端对话详情为准同步功能树、评估与状态（completed / error 均会拉取）
     */
    const finalizeCoordinatorSseFromServer = async (
        convId,
        {
            completedFallback = null,
            sseErrorMessage = null,
            sseErrorCoordKind = SSE_COORD_KIND_MAIN,
            sseErrorRefineLike = false,
            epochAtStart,
        } = {}
    ) => {
        if (epochAtStart != null && viewEpoch.value !== epochAtStart) return

        let payload = null
        try {
            const result = await chatAPI.getConversationDetail(convId)
            if (result.success) {
                payload = mergeConversationDetailPayload(unwrapConversationDetail(result.data))
            }
        } catch {
            /* 由下方 fallback 处理 */
        }

        if (epochAtStart != null && viewEpoch.value !== epochAtStart) return

        const convBase =
            currentConversation.value && currentConversation.value.id === convId
                ? currentConversation.value
                : { id: convId }

        if (payload) {
            currentConversation.value = {
                ...convBase,
                ...payload,
                id: convId,
            }
            currentTask.value =
                payload.current_task ??
                payload.active_task ??
                payload.latest_task ??
                payload.coordinator_task ??
                null
            pendingCoordinatorDependencies.value = []

            if (isConversationFailed(payload)) {
                processingStatus.value = ProcessingStatus.ERROR
                errorMessage.value = buildConversationFailedErrorMessage(payload)
                await fetchConversationsList()
                return
            }

            errorMessage.value = ''

            const finalPayload = extractFinalPayloadFromConversation(payload)
            if (finalPayload) {
                applyCompletedPayload(payload)
                await fetchConversationsList()
                return
            }

            if (isConversationDone(payload)) {
                applyPartialSnapshotFromDetail(payload)
                processingStatus.value = ProcessingStatus.COMPLETED
                progressMessage.value = '需求分析完成！'
                await fetchConversationsList()
                return
            }

            applyPartialSnapshotFromDetail(payload)
            processingStatus.value = ProcessingStatus.PROCESSING
            await fetchConversationsList()
            return
        }

        if (completedFallback != null && typeof completedFallback === 'object') {
            applyCompletedPayload(completedFallback)
            await fetchConversationsList()
            return
        }

        if (sseErrorMessage) {
            processingStatus.value = ProcessingStatus.ERROR
            if (sseErrorCoordKind === SSE_COORD_KIND_REFINE_NODE || sseErrorRefineLike) {
                errorMessage.value =
                    `节点重拆未成功，且未能同步会话详情：${sseErrorMessage}。请重新打开该对话或刷新后再试。`
            } else {
                errorMessage.value = sseErrorMessage
            }
            await fetchConversationsList()
        }
    }

    const watchCoordinatorSse = (convId, ac, epochAtStart, sseOptions = {}) => {
        const { trackRefineNodeFailures = false } = sseOptions
        let settled = false
        return new Promise((resolve, reject) => {
            const finishOk = () => {
                if (settled) return
                settled = true
                resolve()
            }
            const finishErr = (e) => {
                if (settled) return
                settled = true
                reject(e)
            }

            chatAPI
                .listenTaskProgress(convId, {
                    signal: ac.signal,
                    onEvent: (event, data) => {
                        if (event === 'intermediate_result') {
                            handleIntermediateResult(data)
                        } else if (event === 'heartbeat') {
                            /* 可选：调试 */
                        } else if (event === 'agent_timeline') {
                            handleAgentTimeline(data)
                        } else if (event === 'completed') {
                            void finalizeCoordinatorSseFromServer(convId, {
                                completedFallback: data,
                                epochAtStart,
                            })
                                .catch(() => {})
                                .finally(() => {
                                    finishOk()
                                    ac.abort()
                                })
                        } else if (event === 'error') {
                            if (epochAtStart != null && viewEpoch.value !== epochAtStart) {
                                finishOk()
                                ac.abort()
                                return
                            }

                            const pendingTimeout = isCoordinatorSsePendingTimeoutPayload(data)
                            const coordKind = getCoordinatorSseErrorCoordKind(data)
                            const explicitCoordKind =
                                data &&
                                typeof data === 'object' &&
                                data.coord_kind != null &&
                                String(data.coord_kind).trim() !== ''
                                    ? String(data.coord_kind).trim()
                                    : null

                            const refineFailureActsAsRollbackCandidate =
                                !pendingTimeout &&
                                (explicitCoordKind === SSE_COORD_KIND_REFINE_NODE ||
                                    (trackRefineNodeFailures && explicitCoordKind === null))

                            const refineTargetRaw =
                                explicitCoordKind === SSE_COORD_KIND_REFINE_NODE &&
                                data &&
                                typeof data === 'object' &&
                                data.refine_target_node_id != null
                                    ? String(data.refine_target_node_id).trim()
                                    : ''

                            const msg = formatCoordinatorSseErrorMessage(data)
                            progressMessage.value = msg

                            if (refineFailureActsAsRollbackCandidate && epochAtStart != null) {
                                pendingRefineNodeFailureDetail.value = {
                                    epoch: epochAtStart,
                                    message: msg,
                                    ...(refineTargetRaw ? { nodeId: refineTargetRaw } : {}),
                                }
                            }

                            void finalizeCoordinatorSseFromServer(convId, {
                                sseErrorMessage: msg,
                                sseErrorCoordKind: coordKind,
                                sseErrorRefineLike: refineFailureActsAsRollbackCandidate,
                                epochAtStart,
                            })
                                .catch(() => {})
                                .finally(() => {
                                    if (epochAtStart != null && viewEpoch.value !== epochAtStart) {
                                        if (pendingRefineNodeFailureDetail.value?.epoch === epochAtStart) {
                                            pendingRefineNodeFailureDetail.value = null
                                        }
                                        finishOk()
                                        ac.abort()
                                        return
                                    }

                                    const refineErrUi = refineFailureActsAsRollbackCandidate

                                    if (processingStatus.value === ProcessingStatus.ERROR) {
                                        if (refineErrUi) {
                                            finishOk()
                                        } else {
                                            finishErr(new Error(errorMessage.value || msg))
                                        }
                                    } else {
                                        finishOk()
                                    }
                                    ac.abort()
                                })
                        }
                    },
                })
                .then(() => {
                    if (!settled) {
                        finishErr(new Error('SSE 已结束，未收到 completed 事件'))
                    }
                })
                .catch((e) => {
                    if (e?.name === 'AbortError' && settled) return
                    if (e?.name === 'AbortError' && !settled) {
                        finishErr(new Error('SSE 已中止'))
                        return
                    }
                    finishErr(e)
                })
        })
    }

    const extractEvaluationFromFinalPayload = (data) => {
        if (!data || typeof data !== 'object') return null
        const eps = data.evaluation_episodes
        if (!Array.isArray(eps) || eps.length === 0) return null
        const last = eps[eps.length - 1]
        const bundle = last?.bundle?.evaluation
        if (bundle && typeof bundle === 'object') {
            return parseEvaluationData(bundle)
        }
        return null
    }

    const parseFunctionTree = (rawTree, dependencyEdges = null) => {
        if (!rawTree) {
            return null
        }

        const depList = Array.isArray(dependencyEdges) ? dependencyEdges : extractDependenciesList(rawTree)

        if (rawTree.children !== undefined) {
            const root = rawTree
            if (depList.length) mergeDependencyEdgesIntoTree(root, depList)
            return root
        }

        if (rawTree.function_list) {
            const functionList = rawTree.function_list
            const nodeMap = new Map()

            functionList.forEach((node) => {
                nodeMap.set(node.id, {
                    ...node,
                    children: [],
                })
            })

            const rootNodes = []

            functionList.forEach((node) => {
                const currentNode = nodeMap.get(node.id)

                if (!node.parent_id) {
                    rootNodes.push(currentNode)
                } else {
                    const parentNode = nodeMap.get(node.parent_id)
                    if (parentNode) {
                        parentNode.children.push(currentNode)
                    } else {
                        rootNodes.push(currentNode)
                    }
                }
            })

            if (rootNodes.length === 0) {
                return null
            }

            let root = null
            if (rootNodes.length === 1) {
                root = rootNodes[0]
            } else {
                root = {
                    id: 'virtual-root',
                    title: '功能树',
                    node_type: 'DOMAIN',
                    granularity: 'EPIC',
                    children: rootNodes,
                }
            }
            if (depList.length) mergeDependencyEdgesIntoTree(root, depList)
            return root
        }

        return null
    }

    const parseEvaluationData = (rawEvaluation) => {
        const r = rawEvaluation || {}
        const risk = r.risk_level || 'unknown'
        const rec = r.recommendation || 'unknown'
        return {
            summary: r.summary || '',
            risk_level: risk,
            recommendation: rec === 'unknown' ? '未知' : rec,
            overall_score: r.overall_score ?? 0,
            consistency_score: r.consistency_score ?? 0,
            feasibility_score: r.feasibility_score ?? 0,
            integration_scope: r.integration_scope ?? null,
            consistency_result: r.consistency_result || {},
            feasibility_result: r.feasibility_result || {},
        }
    }

    const getStageMessage = (stage) => {
        const messages = {
            normalizing: '正在标准化需求…',
            decomposing: '正在分解功能需求…',
            analyzing_dependencies: '正在分析依赖关系…',
            evaluating_consistency: '正在评估一致性…',
            evaluating_feasibility: '正在评估可实现性…',
            integrating: '正在整合结果…',
            refining: '正在优化结果…',
            idle: '等待开始…',
            split: '正在拆分任务…',
            error: '任务出错',
            task_created: '任务已创建',
            pipeline_status: '更新流水线状态…',
            completed: '处理已完成',
            processing: '正在处理…',
        }
        if (stage == null || stage === '') return '正在处理需求…'
        if (typeof stage === 'string' && /[\u4e00-\u9fff]/.test(stage)) return stage
        const k = String(stage).toLowerCase().trim()
        return messages[k] || messages[stage] || '正在处理需求…'
    }

    const resetState = () => {
        viewEpoch.value++
        stopExistingSse()

        currentConversation.value = null
        currentTask.value = null
        functionTreeData.value = null
        evaluationData.value = null
        pendingCoordinatorDependencies.value = []
        processingStatus.value = ProcessingStatus.IDLE
        progressMessage.value = ''
        errorMessage.value = ''
        selectedConversationId.value = null
        conversationDetailLoading.value = false
        pendingRefineNodeFailureDetail.value = null
    }

    const retryProcessing = async (requirement, config = {}) => {
        await processRequirement(requirement, config)
    }

    /**
     * 请求中止当前协调任务（主任务或节点重拆）；真正结束以 SSE completed（含 stopped_by_user）为准
     */
    const stopCoordinatorTask = async () => {
        const id = selectedConversationId.value || currentConversation.value?.id
        if (!id) {
            return { success: false, message: '未选择对话' }
        }
        const result = await chatAPI.stopCoordinator(id)
        if (!result.success) {
            return { success: false, message: result.message || '停止失败' }
        }
        return { success: true, data: result.data }
    }

    /**
     * 对已产出 final_result 的会话，对某功能节点发起重拆（须保持或新建 SSE 订阅）
     */
    const refineCoordinatorNode = async (nodeId, options = {}) => {
        const { userInstruction = '', config = {} } = options
        const convId = selectedConversationId.value || currentConversation.value?.id
        if (!convId) {
            throw new Error('未选择对话')
        }
        if (!nodeId || typeof nodeId !== 'string') {
            throw new Error('节点无效')
        }

        const busy =
            processingStatus.value === ProcessingStatus.CREATING ||
            processingStatus.value === ProcessingStatus.STARTING ||
            processingStatus.value === ProcessingStatus.PROCESSING
        if (busy) {
            throw new Error('已有任务进行中，请等待结束后再试')
        }

        const convSnapshot = currentConversation.value
            ? { ...currentConversation.value }
            : { id: convId }
        const epochLocal = viewEpoch.value

        pendingRefineNodeFailureDetail.value = null
        errorMessage.value = ''
        processingStatus.value = ProcessingStatus.PROCESSING
        progressMessage.value = '正在连接进度流并启动节点重拆…'

        stopExistingSse()
        const ac = new AbortController()
        sseAbortController.value = ac
        const donePromise = watchCoordinatorSse(convId, ac, epochLocal, {
            trackRefineNodeFailures: true,
        })

        const refineConfig = buildRefineCoordinatorConfig(config)
        const body = {
            node_id: nodeId,
            ...(userInstruction && String(userInstruction).trim()
                ? { user_instruction: String(userInstruction).trim() }
                : {}),
            config: refineConfig,
        }

        const startResult = await chatAPI.refineCoordinatorNode(convId, body)

        if (!startResult.success) {
            ac.abort()
            sseAbortController.value = null
            void donePromise.catch(() => {})
            await openConversation(convSnapshot)
            if (viewEpoch.value !== epochLocal) return { skipped: true }
            throw new Error(startResult.message || '节点重拆启动失败')
        }

        progressMessage.value = '节点重拆任务已启动，正在处理…'

        try {
            await donePromise
            if (viewEpoch.value !== epochLocal) {
                if (pendingRefineNodeFailureDetail.value?.epoch === epochLocal) {
                    pendingRefineNodeFailureDetail.value = null
                }
                return { skipped: true }
            }

            const p = pendingRefineNodeFailureDetail.value
            if (p && p.epoch === epochLocal) {
                const nid = p.nodeId ? `「${p.nodeId}」` : ''
                const headline = nid ? `节点${nid}本次重拆未成功` : '本次节点重拆未成功'
                ElMessage.warning(`${headline}（服务端已尝试恢复为重拆前状态）：${p.message}`)
                pendingRefineNodeFailureDetail.value = null
                return { ok: false, refineFailed: true }
            }

            pendingRefineNodeFailureDetail.value = null

            if (processingStatus.value === ProcessingStatus.ERROR) {
                return { ok: false }
            }
            return { ok: true }
        } catch (e) {
            if (pendingRefineNodeFailureDetail.value?.epoch === epochLocal) {
                pendingRefineNodeFailureDetail.value = null
            }
            throw e
        } finally {
            if (viewEpoch.value === epochLocal) {
                sseAbortController.value = null
                void fetchConversationsList()
            }
        }
    }

    return {
        currentConversation,
        currentTask,
        functionTreeData,
        evaluationData,
        processingStatus,
        progressMessage,
        errorMessage,
        conversationsList,
        conversationsLoading,
        conversationsError,
        selectedConversationId,

        fetchConversationsList,
        selectConversation,
        deleteConversation,
        openConversation,
        conversationDetailLoading,
        processRequirement,
        retryProcessing,
        resetState,
        ProcessingStatus,
        stopCoordinatorTask,
        refineCoordinatorNode,
    }
})
