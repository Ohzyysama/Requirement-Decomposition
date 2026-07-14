<script setup>
import {ref, computed, watch, onMounted, onUnmounted} from 'vue'
import {ElMessage, ElMessageBox} from "element-plus"
import {Search, Loading, CircleClose, Refresh, DocumentCopy, Download, Setting, Remove, Delete, ArrowDown, Expand, MagicStick, Plus} from '@element-plus/icons-vue'
import chatAPI from '@/api/chat.js' // ★ 新增：用于调用下载报告接口
import {useChatStore, CONVERSATION_PLACEHOLDER_TITLE} from '@/stores/chatStore'
import CoordinatorTaskConfigDialog from '@/components/coordinator/CoordinatorTaskConfigDialog.vue'
import FunctionTree from '@/components/function/FunctionTree.vue'
import FunctionDetailCard from '@/components/function/FunctionDetailCard.vue'
import EvaluationReport from '@/components/evaluation/EvaluationReport.vue'

const chatStore = useChatStore()
const inputMessage = ref('')
const taskConfigDialogVisible = ref(false)
/** 与 POST /coordinator/start 的 config 对齐；仅包含用户显式覆盖的键 */
const coordinatorStartConfig = ref({})

// ── SR 结构化表单 ──────────────────────────────────────────────────────────────
const srFormVisible = ref(false)
const srPasteText = ref('')

const SR_FIELDS = [
  { key: 'title',        label: '需求标题',         type: 'input',    required: true  },
  { key: 'desc',         label: '需求描述',         type: 'textarea', required: true  },
  { key: 'value',        label: '需求价值',         type: 'textarea', required: false },
  { key: 'scenario',     label: '需求场景',         type: 'textarea', required: false },
  { key: 'targetUsers',  label: '目标用户',         type: 'input',    required: false },
  { key: 'constraints',  label: '限制约束',         type: 'textarea', required: false },
  { key: 'externalDeps', label: '外部依赖',         type: 'textarea', required: false },
  { key: 'performance',  label: '性能指标',         type: 'input',    required: false },
  { key: 'power',        label: '功耗指标',         type: 'input',    required: false },
  { key: 'romRam',       label: 'ROM&RAM',          type: 'input',    required: false },
  { key: 'acceptance',   label: '验收标准',         type: 'textarea', required: false },
  { key: 'device',       label: '验收设备',         type: 'input',    required: false },
  { key: 'products',     label: '适用产品',         type: 'input',    required: false },
  { key: 'productDiff',  label: '适用产品差异分析', type: 'textarea', required: false },
  { key: 'extra',        label: '视觉/生态/安全等扩展维度', type: 'textarea', required: false },
]

const FIELD_ALIASES = {
  '需求标题':           'title',
  '需求描述':           'desc',
  '需求价值':           'value',
  '需求场景':           'scenario',
  '目标用户':           'targetUsers',
  '限制约束':           'constraints',
  '外部依赖':           'externalDeps',
  '性能指标':           'performance',
  '功耗指标':           'power',
  'ROM&RAM':            'romRam',
  'ROM＆RAM':           'romRam',
  '验收标准':           'acceptance',
  '验收设备':           'device',
  '适用产品差异分析':   'productDiff',
  '适用产品':           'products',
  '视觉/生态/安全等扩展维度': 'extra',
  '视觉．生态．安全等扩展维度': 'extra',
}

const emptyForm = () => Object.fromEntries(SR_FIELDS.map(f => [f.key, '']))
const srForm = ref(emptyForm())

/** 从粘贴文本自动解析到 srForm */
function parseSrText() {
  const text = srPasteText.value
  if (!text.trim()) { ElMessage.warning('请先粘贴需求文本'); return }

  const form = emptyForm()

  // 匹配 [字段名]<空白><内容> 或 字段名（中文冒号/英文冒号）<内容>
  // 支持跨行内容：到下一个 [字段] 为止
  const blockRe = /\[([^\]]+)\]\s+([\s\S]*?)(?=\n\[|\n[^\s\[].+[：:]\s|\s*$)/g
  let m
  while ((m = blockRe.exec(text)) !== null) {
    const rawKey = m[1].trim()
    const val = m[2].trim()
    const key = FIELD_ALIASES[rawKey]
    if (key) form[key] = val
  }

  // 补充：匹配「字段名\t内容」表格格式
  const tableRe = /^\[?([^\]|\t\n]+)\]?\t(.+)$/gm
  while ((m = tableRe.exec(text)) !== null) {
    const rawKey = m[1].trim()
    const val = m[2].trim()
    const key = FIELD_ALIASES[rawKey]
    if (key && !form[key]) form[key] = val
  }

  // 提取 SR-ID 行中的标题（兜底）
  if (!form.title) {
    const titleLine = text.match(/^SR-\d+\s+(.+)$/m)
    if (titleLine) form.title = titleLine[1].trim()
  }

  srForm.value = form
  srPasteText.value = ''
  ElMessage.success('解析完成，请核对各字段内容')
}

/** 将表单拼成 SR 格式字符串，填入输入框并关闭对话框 */
function applySrForm() {
  if (!srForm.value.title.trim()) { ElMessage.warning('需求标题不能为空'); return }
  if (!srForm.value.desc.trim())  { ElMessage.warning('需求描述不能为空'); return }

  const lines = []
  for (const f of SR_FIELDS) {
    const v = srForm.value[f.key]?.trim()
    if (v) lines.push(`[${f.label}] ${v}`)
  }
  inputMessage.value = lines.join('\n')
  srFormVisible.value = false
  ElMessage.success('已填入输入框，点击"开始分析"提交')
}

function resetSrForm() {
  srForm.value = emptyForm()
  srPasteText.value = ''
}

function conversationTitle(row) {
  if (!row) return ''
  const title = row.title
  if (
    typeof title === 'string' &&
    title.trim() &&
    title.trim() !== CONVERSATION_PLACEHOLDER_TITLE
  ) {
    const t = title.trim()
    return t.length > 52 ? `${t.slice(0, 52)}…` : t
  }
  return CONVERSATION_PLACEHOLDER_TITLE
}

function conversationSubtitle(row) {
  const d = row.updated_at ?? row.created_at ?? row.createdAt
  if (!d) return ''
  try {
    const date = new Date(d)
    return Number.isNaN(date.getTime()) ? '' : date.toLocaleString()
  } catch {
    return ''
  }
}

/** 列表第二行：占位标题时用 original_requirement 摘要区分；否则仅时间 */
function conversationListSecondaryLine(row) {
  const dateLine = conversationSubtitle(row)
  if (!row) return dateLine
  const title = row.title
  const isPlaceholder =
    title == null ||
    String(title).trim() === '' ||
    String(title).trim() === CONVERSATION_PLACEHOLDER_TITLE
  if (isPlaceholder && typeof row.original_requirement === 'string' && row.original_requirement.trim()) {
    const prev = row.original_requirement.trim()
    const preview = prev.length > 48 ? `${prev.slice(0, 48)}…` : prev
    return dateLine ? `${preview} · ${dateLine}` : preview
  }
  return dateLine
}

/** 与 chatStore FAILED_STATUSES 对齐，便于侧栏标记失败会话 */
function conversationRowIsFailed(row) {
  if (!row || typeof row !== 'object') return false
  const st = String(row.status ?? row.processing_status ?? row.state ?? row.coordinator_status ?? '')
    .toLowerCase()
    .trim()
  return st === 'failed' || st === 'error' || st === 'cancelled' || st === 'canceled'
}

const functionDetailOpen = ref(false)
const functionDetailNode = ref(null)
const functionDetailAnchorEl = ref(null)
const functionDetailPathLabel = ref('')

function findPathToNode(root, targetId, chain = []) {
  if (!root || !targetId) return null
  const next = [...chain, root]
  if (root.id === targetId) return next
  const children = root.children
  if (!Array.isArray(children)) return null
  for (const c of children) {
    const hit = findPathToNode(c, targetId, next)
    if (hit) return hit
  }
  return null
}

function formatFunctionPath(chain) {
  if (!chain?.length) return ''
  return chain
    .filter((n) => n.id !== 'virtual-root')
    .map((n) => n.id)
    .join(' > ')
}

function handleNodeClick(node, evt) {
  functionDetailAnchorEl.value = evt?.currentTarget ?? null
  functionDetailNode.value = node ?? null
  functionDetailPathLabel.value = formatFunctionPath(
    findPathToNode(chatStore.functionTreeData, node?.id)
  )
  functionDetailOpen.value = true
}

function closeFunctionDetail() {
  functionDetailOpen.value = false
  functionDetailNode.value = null
  functionDetailAnchorEl.value = null
}

const stopTaskLoading = ref(false)
const deletingConversationId = ref(null)

async function requestDeleteConversation(row) {
  const id = row?.id
  if (!id) return
  try {
    await ElMessageBox.confirm(
      '删除后无法恢复，确定删除该对话？',
      '删除对话',
      {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger',
      }
    )
  } catch {
    return
  }
  deletingConversationId.value = id
  try {
    const r = await chatStore.deleteConversation(id)
    if (!r.success) {
      ElMessage.error(r.message || '删除失败')
      return
    }
    ElMessage.success('已删除')
  } catch (e) {
    ElMessage.error(e?.message || '删除失败')
  } finally {
    deletingConversationId.value = null
  }
}

async function requestStopTask() {
  try {
    await ElMessageBox.confirm(
      '确定要中止当前正在运行的分析任务吗？系统将请求协作式停止，已生成的部分内容会尽量保留。',
      '中止任务',
      {
        confirmButtonText: '确定中止',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger',
      }
    )
  } catch {
    return
  }
  stopTaskLoading.value = true
  try {
    const r = await chatStore.stopCoordinatorTask()
    if (!r.success) {
      ElMessage.error(r.message || '中止请求失败')
      return
    }
    const msg = r.data?.message
    if (typeof msg === 'string' && msg.trim()) {
      ElMessage.info(msg.trim())
    } else {
      ElMessage.success('已发送停止请求')
    }
  } catch (e) {
    ElMessage.error(e?.message || '中止失败')
  } finally {
    stopTaskLoading.value = false
  }
}

async function handleRefineNode({ nodeId, userInstruction, maxFeasibilityRefinementDepth }) {
  // 重拆耗时常在后台跑完；用户一点「开始重拆」就应关掉功能详情浮层，而不是等整段 SSE 结束
  closeFunctionDetail()
  try {
    const result = await chatStore.refineCoordinatorNode(nodeId, {
      userInstruction,
      config: {
        ...coordinatorStartConfig.value,
        max_feasibility_refinement_depth: maxFeasibilityRefinementDepth,
      },
    })
    if (result?.skipped) return
    if (!result?.ok) return
    ElMessage.success('节点重拆已完成')
  } catch (e) {
    ElMessage.error((e && e.message) || '节点重拆失败')
  }
}

onMounted(() => {
  chatStore.fetchConversationsList()
})

watch(
  () => chatStore.currentConversation,
  (c) => {
    const req = c?.original_requirement
    if (typeof req === 'string' && req.trim()) {
      inputMessage.value = req.trim()
    }
  }
)

// 响应式数据
const treePanelWidth = ref(600) // 默认左侧面板宽度
const isResizing = ref(false)
const startX = ref(0)
const startWidth = ref(0)

// 计算属性
const isProcessing = computed(() =>
    chatStore.processingStatus === chatStore.ProcessingStatus.CREATING ||
    chatStore.processingStatus === chatStore.ProcessingStatus.STARTING ||
    chatStore.processingStatus === chatStore.ProcessingStatus.PROCESSING
)

/** 已收到功能树（含合包或预览），左侧展示树与依赖；右侧报告区仍为进行中 */
const showStreamingSplit = computed(
    () => isProcessing.value && !!chatStore.functionTreeData
)

const isCompleted = computed(() =>
    chatStore.processingStatus === chatStore.ProcessingStatus.COMPLETED
)

const hasError = computed(() =>
    chatStore.processingStatus === chatStore.ProcessingStatus.ERROR
)

/** 未选对话且空闲：欢迎页 */
const showWelcome = computed(
    () =>
        !chatStore.selectedConversationId &&
        chatStore.processingStatus === chatStore.ProcessingStatus.IDLE &&
        !chatStore.conversationDetailLoading
)

/** 已选对话但尚无任务结果（详情已加载完） */
const isViewingIdleConversation = computed(
    () =>
        !!chatStore.selectedConversationId &&
        chatStore.processingStatus === chatStore.ProcessingStatus.IDLE &&
        !chatStore.conversationDetailLoading
)

/**
 * 发送消息/处理需求
 */
async function sendMessage() {
  if (!inputMessage.value.trim()) {
    ElMessage.warning('请输入需求描述')
    return
  }

  try {
    await chatStore.processRequirement(inputMessage.value.trim(), {
      ...coordinatorStartConfig.value,
    })

    if (isCompleted.value) {
      ElMessage.success('需求分析完成！')
    }
  } catch (error) {
    ElMessage.error('处理需求失败: ' + (error?.message || '未知错误'))
  }
}

/**
 * 重新处理
 */
async function retryProcessing() {
  if (!inputMessage.value.trim()) return

  try {
    await chatStore.retryProcessing(inputMessage.value.trim(), {
      ...coordinatorStartConfig.value,
    })
  } catch (error) {
    ElMessage.error('重新处理失败: ' + (error?.message || '未知错误'))
  }
}

function stripForExport(v) {
  if (v == null) return v
  return JSON.parse(JSON.stringify(v))
}

/** 与导出文件、复制剪贴板共用：对话、评估、功能树快照 */
function buildReportExportPayload() {
  const conv = chatStore.currentConversation
  return {
    exported_at: new Date().toISOString(),
    conversation: conv ? stripForExport(conv) : null,
    evaluation: stripForExport(chatStore.evaluationData),
    function_tree: stripForExport(chatStore.functionTreeData),
  }
}

/** 复制与「导出报告」相同结构的 JSON 到剪贴板 */
async function copyReportToClipboard() {
  try {
    const str = JSON.stringify(buildReportExportPayload(), null, 2)
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(str)
    } else {
      const ta = document.createElement('textarea')
      ta.value = str
      ta.setAttribute('readonly', '')
      ta.style.position = 'fixed'
      ta.style.left = '-9999px'
      document.body.appendChild(ta)
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
    }
    ElMessage.success('报告已复制到剪贴板')
  } catch (e) {
    console.error(e)
    ElMessage.error('复制失败，请重试或改用导出报告')
  }
}

/**
 * 导出当前需求分析报告为 JSON（对话信息、评估、功能树）
 */
function exportReportJson() {
  try {
    const conv = chatStore.currentConversation
    const id = conv?.id ?? 'unknown'
    const payload = buildReportExportPayload()
    const str = JSON.stringify(payload, null, 2)
    const blob = new Blob([str], { type: 'application/json;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `需求分析报告-${id}.json`
    a.rel = 'noopener'
    a.click()
    URL.revokeObjectURL(url)
    ElMessage.success('报告已导出')
  } catch (e) {
    console.error(e)
    ElMessage.error('导出失败，请检查控制台')
  }
}

// ★ 新增：下载四类独立报告的公共入口
async function downloadReport(type) {
  const taskId = chatStore.selectedConversationId
  if (!taskId) {
    ElMessage.warning('请先选择一个对话')
    return
  }
  try {
    const result = await chatAPI.downloadReport(taskId, type)
    if (!result.success) {
      ElMessage.error(result.message || '下载失败')
    } else {
      ElMessage.success('报告已开始下载')
    }
  } catch (e) {
    ElMessage.error(e?.message || '下载失败')
  }
}

/**
 * 导出下拉菜单统一处理
 * full: 完整报告（前端JSON）
 * decomposition / consistency / granularity / feasibility: 后端单类报告
 * evaluation_all: 依次下载三个评估报告
 */
async function handleExportCommand(command) {
  if (command === 'full') {
    exportReportJson()
    return
  }
  if (command === 'ar_markdown') {
    const taskId = chatStore.selectedConversationId
    if (!taskId) { ElMessage.warning('请先选择一个对话'); return }
    const result = await chatAPI.downloadArReport(taskId)
    if (!result.success) ElMessage.error(result.message || '导出失败')
    else ElMessage.success('AR 需求文档已导出')
    return
  }
  await downloadReport(command)
}

/**
 * 清除结果
 */
function clearResults() {
  chatStore.resetState()
  inputMessage.value = ''
  coordinatorStartConfig.value = {}
}

/**
 * 开始拖拽调整大小
 */
function startResize(event) {
  isResizing.value = true
  startX.value = event.clientX || event.touches[0].clientX
  startWidth.value = treePanelWidth.value
  
  document.addEventListener('mousemove', handleResize)
  document.addEventListener('mouseup', stopResize)
  document.addEventListener('touchmove', handleResize)
  document.addEventListener('touchend', stopResize)
  
  event.preventDefault()
}

/**
 * 处理拖拽调整
 */
function handleResize(event) {
  if (!isResizing.value) return
  
  const currentX = event.clientX || event.touches[0].clientX
  const deltaX = currentX - startX.value
  const newWidth = Math.max(300, Math.min(800, startWidth.value + deltaX))
  
  treePanelWidth.value = newWidth
}

/**
 * 停止拖拽调整
 */
function stopResize() {
  isResizing.value = false
  document.removeEventListener('mousemove', handleResize)
  document.removeEventListener('mouseup', stopResize)
  document.removeEventListener('touchmove', handleResize)
  document.removeEventListener('touchend', stopResize)
}

// 组件卸载时清理
onUnmounted(() => {
  chatStore.resetState()
})
</script>

<template>
  <div class="home-container">
    <div class="common-layout">
      <el-container>
        <!-- 主内容区域 -->
        <el-main style="color: black;">
          <div class="chat-page-inner">
            <aside class="conversations-pane" aria-label="对话列表">
              <div class="conversations-pane-header">
                <span class="conversations-pane-title">对话列表</span>
                <el-button
                    text
                    size="small"
                    :loading="chatStore.conversationsLoading"
                    @click="chatStore.fetchConversationsList()"
                >
                  <el-icon><Refresh /></el-icon>
                </el-button>
              </div>
              <div class="conversations-pane-new">
                <el-button
                    type="primary"
                    size="small"
                    round
                    style="width:100%"
                    @click="clearResults"
                >
                  <el-icon><Plus /></el-icon> 新建分析
                </el-button>
              </div>
              <div v-if="chatStore.conversationsError" class="conversations-error">
                {{ chatStore.conversationsError }}
              </div>
              <el-scrollbar class="conversations-scroll">
                <div v-if="chatStore.conversationsLoading && chatStore.conversationsList.length === 0" class="conversations-loading-hint">
                  加载中…
                </div>
                <el-empty
                    v-else-if="!chatStore.conversationsLoading && chatStore.conversationsList.length === 0"
                    description="暂无对话"
                    :image-size="72"
                />
                <ul v-else class="conversations-ul">
                  <li
                      v-for="c in chatStore.conversationsList"
                      :key="c.id"
                      class="conversation-row"
                      :class="{
                        active: chatStore.selectedConversationId === c.id,
                        'conversation-row--failed': conversationRowIsFailed(c),
                      }"
                      @click="chatStore.openConversation(c)"
                  >
                    <div class="conversation-row-head">
                      <div class="conversation-row-title-wrap">
                        <div class="conversation-row-title">{{ conversationTitle(c) }}</div>
                      </div>
                      <div class="conversation-row-actions">
                        <el-tag v-if="conversationRowIsFailed(c)" type="danger" size="small" effect="plain" round>
                          失败
                        </el-tag>
                        <el-button
                            text
                            type="danger"
                            size="small"
                            class="conversation-row-delete"
                            :loading="deletingConversationId === c.id"
                            :aria-label="`删除对话 ${conversationTitle(c)}`"
                            @click.stop="requestDeleteConversation(c)"
                        >
                          <el-icon><Delete /></el-icon>
                        </el-button>
                      </div>
                    </div>
                    <div v-if="conversationListSecondaryLine(c)" class="conversation-row-sub">{{
                        conversationListSecondaryLine(c)
                      }}</div>
                    <div v-if="conversationSubtitle(c)" class="conversation-row-time">{{
                        conversationSubtitle(c)
                      }}</div>
                  </li>
                </ul>
              </el-scrollbar>
            </aside>
            <div class="chat-box">
            <!-- 欢迎界面 -->
            <div v-if="showWelcome" class="welcome-container">
              <img src="../assets/logo.svg" class="welcome-avatar" alt="需求分析助手">
              <div class="welcome-text">
                <div class="greeting-main" style="color: black;">你好～</div>
                <div class="greeting-sub" style="color: black;">
                  我是你的需求分析助手，请输入您的功能需求，我将为您进行结构化分析和评估
                </div>
              </div>
            </div>

            <!-- 加载对话详情 -->
            <div v-else-if="chatStore.conversationDetailLoading" class="processing-container">
              <div class="processing-content">
                <el-icon class="loading-icon"><Loading /></el-icon>
                <span class="loading-text">正在加载对话…</span>
              </div>
            </div>

            <!-- 进行中且已有功能树：左右分栏，右侧报告区显示加载 -->
            <div v-else-if="showStreamingSplit" class="results-container results-streaming">
              <div class="results-header">
                <div class="header-left">
                  <div class="streaming-header-content">
                    <h2>需求分析进行中</h2>
                    <el-button
                        type="danger"
                        plain
                        size="small"
                        :loading="stopTaskLoading"
                        @click="requestStopTask"
                    >
                      <el-icon><Remove /></el-icon>
                      中止任务
                    </el-button>
                  </div>
                  <span class="score-badge streaming-badge">{{ chatStore.progressMessage || '正在生成分项评估…' }}</span>
                </div>
              </div>

              <div class="split-container">
                <div class="tree-panel" :style="{ width: treePanelWidth + 'px' }">
                  <div class="panel-content">
                    <FunctionTree
                        :data="chatStore.functionTreeData"
                        :searchable="true"
                        @node-click="handleNodeClick"
                    />
                  </div>
                </div>

                <div
                    class="resize-handle"
                    @mousedown="startResize"
                    @touchstart="startResize"
                ></div>

                <div class="report-panel report-panel--streaming">
                  <div class="panel-header">
                    <h3>一致性与可实现性评估报告</h3>
                  </div>
                  <div class="panel-content report-streaming-body">
                    <el-icon class="loading-icon report-inline-loading"><Loading /></el-icon>
                    <p class="report-streaming-text">{{ chatStore.progressMessage || '正在生成分项评估…' }}</p>
                    <p class="report-streaming-hint">功能点与依赖已根据最新拆分更新，完整报告将在任务完成后以对话详情为准展示。</p>
                  </div>
                </div>
              </div>

              <FunctionDetailCard
                  :visible="functionDetailOpen"
                  :node="functionDetailNode"
                  :anchor-el="functionDetailAnchorEl"
                  :path-label="functionDetailPathLabel"
                  :refine-enabled="false"
                  :refine-busy="true"
                  @close="closeFunctionDetail"
                  @refine-node="handleRefineNode"
              />
            </div>

            <!-- 处理状态显示（尚无功能树时的全屏等待） -->
            <div v-else-if="isProcessing" class="processing-container">
              <div class="processing-content">
                <div class="loading-container">
                  <el-icon class="loading-icon">
                    <Loading/>
                  </el-icon>
                  <span class="loading-text">{{ chatStore.progressMessage }}</span>
                </div>
                <div class="progress-details">
                  <p>正在分析您的需求，请稍候...</p>
                  <p class="hint">这个过程可能需要几分钟时间</p>
                  <div class="progress-actions">
                    <el-button
                        type="danger"
                        plain
                        :loading="stopTaskLoading"
                        @click="requestStopTask"
                    >
                      <el-icon><Remove /></el-icon>
                      中止任务
                    </el-button>
                  </div>
                </div>
              </div>
            </div>

            <!-- 错误状态 -->
            <div v-else-if="hasError" class="error-container">
              <div class="error-content">
                <el-icon class="error-icon" color="#ff4d4f">
                  <CircleClose/>
                </el-icon>
                <div class="error-text">
                  <h3>处理失败</h3>
                  <p>{{ chatStore.errorMessage }}</p>
                </div>
                <el-button type="primary" @click="retryProcessing" :loading="isProcessing">
                  重新尝试
                </el-button>
              </div>
            </div>

            <!-- 已选对话但暂无结果 -->
            <div v-else-if="isViewingIdleConversation" class="browse-conversation-container">
              <div class="browse-inner">
                <h3 class="browse-title">{{ conversationTitle(chatStore.currentConversation) }}</h3>
                <p v-if="chatStore.currentConversation?.original_requirement" class="browse-desc">
                  {{ chatStore.currentConversation.original_requirement }}
                </p>
                <p class="browse-hint">该对话暂无已保存的分析结果。在下方输入需求可发起新的分析。</p>
              </div>
            </div>

            <!-- 结果展示 -->
            <div v-else-if="isCompleted" class="results-container">
              <!-- 顶部结果概览 -->
              <div class="results-header">
                <div class="header-left">
                  <h2>需求分析结果</h2>
                  <span class="score-badge">
                    完成(综合评分：{{ Math.round((chatStore.evaluationData?.overall_score ?? 0.88) * 100) }})
                  </span>
                </div>
                <div class="header-actions">
                  <el-button type="text" @click="clearResults">
                    <el-icon>
                      <Refresh/>
                    </el-icon>
                    新建分析
                  </el-button>
                </div>
              </div>

              <!-- 左右分栏布局 -->
              <div class="split-container">
                <!-- 功能树区域 -->
                <div class="tree-panel" :style="{ width: treePanelWidth + 'px' }">
                  <div class="panel-content">
                    <FunctionTree
                        :data="chatStore.functionTreeData"
                        :searchable="true"
                        @node-click="handleNodeClick"
                    />
                  </div>
                </div>

                <!-- 拖拽分隔线 -->
                <div 
                  class="resize-handle" 
                  @mousedown="startResize"
                  @touchstart="startResize"
                ></div>

                <!-- 评估报告区域 -->
                <div class="report-panel">
                  <div class="panel-header">
                    <h3>一致性与可实现性评估报告</h3>
                    <div class="panel-actions">
                      <el-button type="text" size="small" @click="copyReportToClipboard">
                        <el-icon><DocumentCopy /></el-icon>复制报告
                      </el-button>
                      <el-dropdown trigger="click" @command="handleExportCommand">
                        <el-button type="text" size="small">
                          <el-icon><Download /></el-icon>导出报告
                          <el-icon style="margin-left:2px;font-size:12px"><ArrowDown /></el-icon>
                        </el-button>
                        <template #dropdown>
                          <el-dropdown-menu>
                            <el-dropdown-item command="full">完整报告</el-dropdown-item>
                            <el-dropdown-item command="ar_markdown" divided>AR 需求文档</el-dropdown-item>
                            <el-dropdown-item command="evaluation" divided>评估报告</el-dropdown-item>
                          </el-dropdown-menu>
                        </template>
                      </el-dropdown>
                    </div>
                  </div>
                  <div class="panel-content">
                    <EvaluationReport
                        :evaluation-data="chatStore.evaluationData"
                    />
                  </div>
                </div>
              </div>

              <FunctionDetailCard
                  :visible="functionDetailOpen"
                  :node="functionDetailNode"
                  :anchor-el="functionDetailAnchorEl"
                  :path-label="functionDetailPathLabel"
                  :refine-enabled="isCompleted"
                  :refine-busy="isProcessing"
                  @close="closeFunctionDetail"
                  @refine-node="handleRefineNode"
              />
            </div>

            <div v-else class="welcome-container">
              <p class="browse-hint" style="color: #86909c">无法展示该状态，请刷新页面或重选对话。</p>
            </div>
            </div>
          </div>
        </el-main>

        <!-- 底部输入区域 -->
        <el-footer>
          <div class="input-container">
            <el-input
                class="input-class"
                size="large"
                v-model="inputMessage"
                placeholder="请描述功能需求（建议说明场景、对象与目标，便于分析）"
                @keyup.enter="sendMessage"
                clearable
                :prefix-icon="Search"
                :disabled="isProcessing"
            />
            <el-tooltip content="展开结构化表单填写 SR 需求" placement="top">
              <el-button
                  size="large"
                  round
                  aria-label="展开 SR 表单"
                  @click="srFormVisible = true"
                  :disabled="isProcessing"
              >
                <el-icon><Expand /></el-icon>
              </el-button>
            </el-tooltip>
            <el-tooltip content="解析编排：重试次数、细化深度、一致性耗尽后是否继续等" placement="top">
              <el-button
                  size="large"
                  round
                  aria-label="解析任务配置"
                  @click="taskConfigDialogVisible = true"
                  :disabled="isProcessing"
              >
                <el-icon><Setting /></el-icon>
              </el-button>
            </el-tooltip>
            <el-button
                size="large"
                type="primary"
                round
                @click="sendMessage"
                :disabled="!inputMessage || isProcessing"
                :loading="isProcessing"
            >
              {{ isProcessing ? '分析中...' : '开始分析' }}
            </el-button>
          </div>
        </el-footer>

        <!-- SR 结构化表单对话框 -->
        <el-dialog
            v-model="srFormVisible"
            title="填写 SR 需求"
            width="800px"
            :close-on-click-modal="false"
            @close="srPasteText = ''"
            class="sr-form-dialog"
        >
          <!-- 智能解析区 -->
          <div class="sr-parse-card">
            <div class="sr-parse-header">
              <el-icon class="sr-parse-icon"><MagicStick /></el-icon>
              <span class="sr-parse-title">智能解析</span>
              <span class="sr-parse-hint">粘贴 SR 格式文本，自动识别并填入各字段</span>
            </div>
            <el-input
                v-model="srPasteText"
                type="textarea"
                :rows="4"
                placeholder="将完整的 SR 需求文本粘贴至此，支持 [字段名] 内容 或表格格式..."
                class="sr-parse-textarea"
                resize="none"
            />
            <div class="sr-parse-actions">
              <el-button type="primary" size="small" @click="parseSrText" :disabled="!srPasteText.trim()">
                <el-icon><MagicStick /></el-icon> 开始解析
              </el-button>
              <el-button size="small" plain @click="srPasteText = ''" :disabled="!srPasteText.trim()">清空</el-button>
            </div>
          </div>

          <!-- 字段表单 -->
          <div class="sr-field-scrollbar">
            <el-form :model="srForm" label-position="top" class="sr-field-form">

              <div class="sr-section-label">基本信息</div>
              <el-form-item label="需求标题" required>
                <el-input v-model="srForm.title" placeholder="简洁描述该 SR 的核心能力域" clearable class="sr-input" />
              </el-form-item>
              <el-form-item label="需求描述" required>
                <el-input v-model="srForm.desc" type="textarea" :rows="4" placeholder="详细描述该需求的范围、各子能力及边界..." resize="none" class="sr-input" />
              </el-form-item>

              <div class="sr-section-label">业务背景</div>
              <div class="sr-grid-2">
                <el-form-item label="需求价值">
                  <el-input v-model="srForm.value" type="textarea" :rows="3" placeholder="对用户/产品的核心价值..." resize="none" class="sr-input" />
                </el-form-item>
                <el-form-item label="需求场景">
                  <el-input v-model="srForm.scenario" type="textarea" :rows="3" placeholder="典型使用场景与触发路径..." resize="none" class="sr-input" />
                </el-form-item>
              </div>
              <div class="sr-grid-2">
                <el-form-item label="目标用户">
                  <el-input v-model="srForm.targetUsers" placeholder="如：全体听歌用户" clearable class="sr-input" />
                </el-form-item>
                <el-form-item label="适用产品">
                  <el-input v-model="srForm.products" placeholder="如：手机 / 平板 / 车机" clearable class="sr-input" />
                </el-form-item>
              </div>

              <div class="sr-section-label">约束与依赖</div>
              <el-form-item label="限制约束">
                <el-input v-model="srForm.constraints" type="textarea" :rows="2" placeholder="技术/业务约束条件..." resize="none" class="sr-input" />
              </el-form-item>
              <el-form-item label="外部依赖">
                <el-input v-model="srForm.externalDeps" type="textarea" :rows="2" placeholder="依赖的系统能力或三方服务..." resize="none" class="sr-input" />
              </el-form-item>

              <div class="sr-section-label">性能基线</div>
              <div class="sr-grid-3">
                <el-form-item label="性能指标">
                  <el-input v-model="srForm.performance" placeholder="如：起播 < 300ms" clearable class="sr-input" />
                </el-form-item>
                <el-form-item label="功耗指标">
                  <el-input v-model="srForm.power" placeholder="如：息屏 < 3%/h" clearable class="sr-input" />
                </el-form-item>
                <el-form-item label="ROM&RAM">
                  <el-input v-model="srForm.romRam" placeholder="如：< 100MB / 400MB" clearable class="sr-input" />
                </el-form-item>
              </div>

              <div class="sr-section-label">验收</div>
              <el-form-item label="验收标准">
                <el-input v-model="srForm.acceptance" type="textarea" :rows="4" placeholder="逐条列出可测试的验收标准..." resize="none" class="sr-input" />
              </el-form-item>
              <div class="sr-grid-2">
                <el-form-item label="验收设备">
                  <el-input v-model="srForm.device" placeholder="如：HarmonyOS NEXT（API 12+）手机" clearable class="sr-input" />
                </el-form-item>
                <el-form-item label="适用产品差异分析">
                  <el-input v-model="srForm.productDiff" placeholder="各端行为差异说明..." clearable class="sr-input" />
                </el-form-item>
              </div>

              <div class="sr-section-label">扩展维度</div>
              <el-form-item label="视觉 / 生态 / 安全等扩展维度">
                <el-input v-model="srForm.extra" type="textarea" :rows="2" placeholder="视觉规范、生态接入、安全要求等补充信息..." resize="none" class="sr-input" />
              </el-form-item>

            </el-form>
          </div>

          <template #footer>
            <div class="sr-dialog-footer">
              <el-button @click="resetSrForm" plain>重置</el-button>
              <div>
                <el-button @click="srFormVisible = false">取消</el-button>
                <el-button type="primary" @click="applySrForm">填入输入框</el-button>
              </div>
            </div>
          </template>
        </el-dialog>
        <CoordinatorTaskConfigDialog
            v-model="taskConfigDialogVisible"
            v-model:config="coordinatorStartConfig"
        />
      </el-container>
    </div>
  </div>
</template>

<style scoped>
.home-container {
  height: 100%;
  width: 100%;
}

.el-container {
  height: calc(100vh - 120px);
}

.el-main {
  background: white;
  padding: 0;
}

.chat-page-inner {
  display: flex;
  height: 100%;
  min-height: 0;
}

.conversations-pane {
  width: 272px;
  flex-shrink: 0;
  border-right: 1px solid #e5e6eb;
  background: #f7f8fa;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.conversations-pane-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 12px 8px;
  flex-shrink: 0;
}

.conversations-pane-new {
  padding: 0 12px 10px;
  flex-shrink: 0;
}

.conversations-pane-title {
  font-weight: 600;
  font-size: 14px;
  color: #1d2129;
}

.conversations-error {
  padding: 0 12px 8px;
  font-size: 12px;
  color: #f53f3f;
  line-height: 1.4;
}

.conversations-scroll {
  flex: 1;
  min-height: 0;
  padding: 0 8px 12px;
}

.conversations-loading-hint {
  padding: 16px 8px;
  font-size: 13px;
  color: #86909c;
  text-align: center;
}

.conversations-ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.conversation-row {
  padding: 10px 10px;
  margin-bottom: 6px;
  border-radius: 8px;
  background: #fff;
  border: 1px solid #e5e6eb;
  cursor: pointer;
  transition: border-color 0.15s, box-shadow 0.15s;
}

.conversation-row:hover {
  border-color: #1677ff;
}

.conversation-row.active {
  border-color: #1677ff;
  box-shadow: 0 0 0 1px rgba(22, 119, 255, 0.15);
}

.conversation-row-head {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  justify-content: space-between;
}

.conversation-row-title-wrap {
  flex: 1;
  min-width: 0;
}

.conversation-row-actions {
  display: flex;
  align-items: flex-start;
  gap: 4px;
  flex-shrink: 0;
}

.conversation-row-actions :deep(.el-tag) {
  flex-shrink: 0;
}

.conversation-row-delete {
  padding: 4px;
  margin: -4px -4px -4px 0;
}

.conversation-row--failed:not(.active) {
  border-color: #ffccc7;
  background: #fff8f7;
}

.conversation-row-title {
  font-size: 13px;
  font-weight: 500;
  color: #1d2129;
  line-height: 1.35;
  word-break: break-word;
  min-width: 0;
}

.conversation-row-sub {
  margin-top: 4px;
  font-size: 11px;
  color: #86909c;
}

.conversation-row-time {
  margin-top: 2px;
  font-size: 11px;
  color: #c0c4cc;
}

.chat-box {
  flex: 1;
  min-width: 0;
  height: 100%;
  overflow-y: auto;
}

.browse-conversation-container {
  min-height: calc(100vh - 240px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
}

.browse-inner {
  max-width: 520px;
  text-align: center;
}

.browse-title {
  margin: 0 0 12px;
  font-size: 18px;
  color: #1d2129;
  font-weight: 600;
}

.browse-desc {
  margin: 0 0 16px;
  font-size: 14px;
  color: #4e5969;
  line-height: 1.5;
}

.browse-hint {
  margin: 0;
  font-size: 14px;
  color: #86909c;
  line-height: 1.5;
}

.el-footer {
  background: lightgrey;
  padding-left: 10%;
  padding-right: 10%;
  height: 80px;
  display: flex;
  justify-content: center;
  align-items: center;
  border-top: 1px solid #ebeef5;
  border-radius: 15px;
}

.input-container {
  width: 100%;
  display: flex;
  gap: 12px;
  align-items: center;
}

/* ── SR 对话框：智能解析卡片 ── */
.sr-parse-card {
  background: #f5f7fa;
  border: 1px solid #e4e7ed;
  border-radius: 10px;
  padding: 14px 16px 12px;
  margin-bottom: 16px;
}
.sr-parse-header {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 10px;
}
.sr-parse-icon {
  color: var(--el-color-primary);
  font-size: 15px;
}
.sr-parse-title {
  font-size: 13px;
  font-weight: 600;
  color: #303133;
}
.sr-parse-hint {
  font-size: 12px;
  color: #909399;
}
.sr-parse-actions {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}

/* ── SR 对话框：字段表单 ── */
.sr-field-scrollbar {
  max-height: 52vh;
  overflow-y: auto;
  overflow-x: hidden;
  padding-right: 6px;
  margin-right: -6px;
}
.sr-field-form {
  padding: 0 2px 4px;
}
.sr-section-label {
  font-size: 11px;
  font-weight: 600;
  color: #909399;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin: 18px 0 10px;
  padding-left: 2px;
  border-left: 3px solid var(--el-color-primary);
  padding-left: 7px;
}
.sr-section-label:first-child {
  margin-top: 4px;
}
.sr-grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0 16px;
}
.sr-grid-3 {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 0 16px;
}
.sr-dialog-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
}

/* SR 对话框内的输入框样式由文件末尾非 scoped 块处理（el-dialog teleport 到 body 外） */

:deep(.el-input__wrapper) {
  border-radius: 95px;
  border: 0;
  box-shadow: 0 0 0 0;
}

/* 欢迎界面样式 */
.welcome-container {
  height: calc(100vh - 240px);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}

.welcome-avatar {
  width: 150px;
  height: 150px;
  margin-bottom: 30px;
}

.welcome-text {
  text-align: center;
}

.greeting-main {
  font-size: 28px;
  font-weight: 700;
  margin-bottom: 12px;
}

.greeting-sub {
  font-size: 18px;
  font-weight: 500;
  color: #666;
  max-width: 500px;
  line-height: 1.5;
}

/* 处理中样式 */
.processing-container {
  height: calc(100vh - 240px);
  display: flex;
  align-items: center;
  justify-content: center;
}

.processing-content {
  text-align: center;
}

.loading-container {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  margin-bottom: 20px;
}

.loading-icon {
  animation: spin 1s linear infinite;
  font-size: 24px;
  color: #1677ff;
}

.loading-text {
  font-size: 16px;
  font-weight: 500;
  color: #4e5969;
}

.progress-details {
  color: #86909c;
}

.hint {
  font-size: 14px;
  margin-top: 8px;
}

.progress-actions {
  margin-top: 20px;
  display: flex;
  justify-content: center;
}

/* 错误样式 */
.error-container {
  height: calc(100vh - 240px);
  display: flex;
  align-items: center;
  justify-content: center;
}

.error-content {
  text-align: center;
}

.error-icon {
  font-size: 48px;
  margin-bottom: 16px;
}

.error-text h3 {
  margin: 0 0 8px 0;
  color: #4e5969;
}

.error-text p {
  margin: 0 0 20px 0;
  color: #86909c;
}

/* 结果展示样式 */
.results-container {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.results-header {
  padding: 20px 24px;
  border-bottom: 1px solid #e5e6eb;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 16px;
}

.header-left h2 {
  margin: 0;
  color: #4e5969;
  font-size: 18px;
}

.streaming-header-content {
  display: flex;
  align-items: center;
  gap: 12px;
}

.streaming-header-content h2 {
  margin: 0;
  color: #4e5969;
  font-size: 18px;
  white-space: nowrap;
}

.score-badge {
  padding: 4px 8px;
  background: rgba(82, 196, 26, 0.1);
  color: #52c41a;
  border-radius: 4px;
  font-size: 12px;
}

.tabs-container {
  flex: 1;
  overflow: hidden;
}

.results-tabs {
  height: 100%;
}

:deep(.results-tabs .el-tabs__content) {
  height: calc(100% - 55px);
  padding: 0;
}

:deep(.results-tabs .el-tab-pane) {
  height: 100%;
}

.tab-content {
  height: 100%;
  overflow: auto;
}

/* 左右分栏布局 */
.split-container {
  flex: 1;
  display: flex;
  overflow: hidden;
  position: relative;
}

.tree-panel {
  background: white;
  border-right: 1px solid #e5e6eb;
  display: flex;
  flex-direction: column;
  min-width: 300px;
  max-width: 800px;
}

.report-panel {
  flex: 1;
  background: white;
  display: flex;
  flex-direction: column;
  min-width: 400px;
}

.panel-header {
  padding: 16px 20px;
  border-bottom: 1px solid #e5e6eb;
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-shrink: 0;
}

.panel-header h3 {
  margin: 0;
  color: #4e5969;
  font-size: 16px;
  font-weight: 600;
}

.panel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.panel-content {
  flex: 1;
  overflow: auto;
  padding: 0;
}

/* 拖拽分隔线 */
.resize-handle {
  width: 4px;
  background: #e5e6eb;
  cursor: col-resize;
  position: relative;
  z-index: 10;
  transition: background-color 0.2s;
  flex-shrink: 0;
}

.resize-handle:hover,
.resize-handle:active {
  background: #1677ff;
}

.resize-handle::before {
  content: '';
  position: absolute;
  left: -2px;
  top: 0;
  width: 8px;
  height: 100%;
  cursor: col-resize;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

/* 流式加载报告样式 */
.results-streaming .report-streaming-body {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 40px 24px;
  min-height: 300px;
  background: linear-gradient(135deg, #f5f7fa 0%, #f0f1f3 100%);
}

.results-streaming .report-inline-loading {
  font-size: 48px;
  color: #1677ff;
  animation: spin 1.5s linear infinite;
}

.results-streaming .report-streaming-text {
  margin: 0;
  font-size: 16px;
  font-weight: 500;
  color: #4e5969;
  text-align: center;
}

.results-streaming .report-streaming-hint {
  margin: 8px 0 0 0;
  font-size: 13px;
  color: #86909c;
  text-align: center;
  line-height: 1.5;
  max-width: 360px;
}
</style>
<!-- 非 scoped：el-dialog teleport 到 body 外，必须用全局选择器才能覆盖 -->
<style>
/* SR 对话框 dialog body */
.sr-form-dialog .el-dialog__body {
  padding: 16px 20px 8px !important;
  overflow: hidden !important;
}
/* SR 对话框表单标签 */
.sr-form-dialog .el-form-item__label {
  font-size: 13px !important;
  color: #606266 !important;
  font-weight: 500 !important;
  padding-bottom: 4px !important;
  line-height: 1.4 !important;
}
.sr-form-dialog .el-form-item {
  margin-bottom: 14px !important;
}
/* SR 单行输入框：始终显示边框 */
.sr-form-dialog .sr-input .el-input__wrapper {
  border-radius: 6px !important;
  border: none !important;
  box-shadow: 0 0 0 1px #dcdfe6 !important;
}
.sr-form-dialog .sr-input .el-input__wrapper:hover {
  box-shadow: 0 0 0 1px var(--el-color-primary-light-3) !important;
}
.sr-form-dialog .sr-input .el-input__wrapper.is-focus {
  box-shadow: 0 0 0 1px var(--el-color-primary) !important;
}
/* SR 多行输入框 */
.sr-form-dialog .sr-input .el-textarea__inner {
  border-radius: 6px !important;
  border: none !important;
  box-shadow: 0 0 0 1px #dcdfe6 !important;
  font-family: inherit !important;
  resize: none !important;
}
.sr-form-dialog .sr-input .el-textarea__inner:hover {
  box-shadow: 0 0 0 1px var(--el-color-primary-light-3) !important;
}
.sr-form-dialog .sr-input .el-textarea__inner:focus {
  box-shadow: 0 0 0 1px var(--el-color-primary) !important;
  outline: none !important;
}
/* 智能解析 textarea */
.sr-form-dialog .sr-parse-textarea .el-textarea__inner {
  border-radius: 6px !important;
  border: none !important;
  box-shadow: 0 0 0 1px #dcdfe6 !important;
  font-size: 12.5px !important;
  font-family: inherit !important;
  resize: none !important;
}
.sr-form-dialog .sr-parse-textarea .el-textarea__inner:hover {
  box-shadow: 0 0 0 1px var(--el-color-primary-light-3) !important;
}
.sr-form-dialog .sr-parse-textarea .el-textarea__inner:focus {
  box-shadow: 0 0 0 1px var(--el-color-primary) !important;
  outline: none !important;
}
</style>
