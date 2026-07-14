<script setup>
import { ref, watch, nextTick, onMounted, onUnmounted, computed } from 'vue'
import { ElMessageBox } from 'element-plus'
import { Close } from '@element-plus/icons-vue'
import * as echarts from 'echarts'
import { useChatStore } from '@/stores/chatStore'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  },
  /** 被点击的节点行元素，用于实时 getBoundingClientRect */
  anchorEl: {
    type: Object,
    default: null
  },
  /** 功能节点对象（与 FunctionNode 一致） */
  node: {
    type: Object,
    default: null
  },
  /** 面包屑路径文案，如 "F-1 > F-1.1" */
  pathLabel: {
    type: String,
    default: ''
  },
  /** 主协调已完成、可对节点发起重拆 */
  refineEnabled: {
    type: Boolean,
    default: false,
  },
  /** 正在提交重拆或协调器忙碌 */
  refineBusy: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['close', 'refine-node'])

const chatStore = useChatStore()

const cardRef = ref(null)
const position = ref({ left: 0, top: 0 })
const activeTab = ref('basic')
/** 子功能层关系图：仅子节点之间依赖，按类型分子 Tab */
const layerGraphKindTab = ref('EXEC_ORDER')
/** 子功能层树图（ECharts） */
const layerTreeChartRef = ref(null)
let layerTreeChart = null
let layerTreeResizeObserver = null
let layerGraphResizeDebounce = 0
let layerChartLayoutRetries = 0
const LAYER_CHART_LAYOUT_MAX_RETRIES = 24
/** 节点重拆：可选补充说明，随二次确认后提交 */
const refineInstruction = ref('')
/** 本轮重拆：可实现性细化最大深度（默认 1，最小为 1） */
const refineMaxFeasibilityDepth = ref(1)

const REFINE_MAX_DEPTH_HELP =
  '以当前节点为根的可实现性细化最大子层深度：默认为 1，至少为 1。不建议设为 3 以上。'

/** 与 .function-detail-card（3001）及 MessageBox 相比，Tooltip 默认 z-index 过低，需抬高浮层 */
const TOOLTIP_POPPER_CLASS = 'fdc-tooltip-popper'

function resolvedRefineMaxDepth() {
  const rawDepth = refineMaxFeasibilityDepth.value
  const depthNum = Number(rawDepth)
  return Number.isFinite(depthNum)
    ? Math.max(1, Math.min(20, Math.trunc(depthNum)))
    : 1
}

const canOfferRefine = computed(() => {
  if (!props.refineEnabled || props.refineBusy) return false
  const id = props.node?.id
  return typeof id === 'string' && id.trim() && id !== 'virtual-root'
})

async function confirmRefineNode() {
  if (!canOfferRefine.value || !props.node?.id) return
  const title = (props.node.title && String(props.node.title).trim()) || props.node.id
  const depth = resolvedRefineMaxDepth()
  try {
    await ElMessageBox.confirm(
      `确定要对节点「${title}」重新执行子需求列表、一致性与可实现性尾部吗？任务在后台运行，可通过「中止任务」协作式停止。本轮可实现性细化最大深度为 ${depth}。`,
      '确认重拆节点',
      {
        confirmButtonText: '开始重拆',
        cancelButtonText: '取消',
        type: 'warning',
        distinguishCancelAndClose: true,
      }
    )
  } catch {
    return
  }
  const instruction = refineInstruction.value.trim()
  const maxFeasibilityRefinementDepth = resolvedRefineMaxDepth()
  emit('refine-node', {
    nodeId: props.node.id,
    userInstruction: instruction,
    maxFeasibilityRefinementDepth,
  })
}

const descriptionText = computed(() => {
  const n = props.node
  if (!n) return '—'
  return (n.desc ?? n.description ?? '').trim() || '—'
})

const typeGranularityText = computed(() => {
  const n = props.node
  if (!n) return '—'
  const t = n.node_type ?? '—'
  const g = n.granularity ?? '—'
  return `${t} / ${g}`
})

/** 支持多种后端字段命名 */
const outgoingList = computed(() => {
  const n = props.node
  if (!n) return []
  const raw =
    n.outgoing_dependencies ??
    n.outgoing_deps ??
    n.depends_on ??
    (Array.isArray(n.dependencies?.outgoing) ? n.dependencies.outgoing : null)
  return Array.isArray(raw) ? raw : []
})

const incomingList = computed(() => {
  const n = props.node
  if (!n) return []
  const raw =
    n.incoming_dependencies ??
    n.incoming_deps ??
    n.dependents ??
    (Array.isArray(n.dependencies?.incoming) ? n.dependencies.incoming : null)
  return Array.isArray(raw) ? raw : []
})

/** 无依赖边时隐藏「依赖关系」页签 */
const showDepsTab = computed(
  () => outgoingList.value.length > 0 || incomingList.value.length > 0
)

const DEP_KIND_ORDER = ['EXEC_ORDER', 'DATA', 'RESOURCE']

/** 三类依赖数量角标色（与评估报告蓝 / 绿 / 黄一致） */
const DEP_KIND_COUNT_CLASS = {
  EXEC_ORDER: 'fdc-deps-kind-count--exec',
  DATA: 'fdc-deps-kind-count--data',
  RESOURCE: 'fdc-deps-kind-count--resource',
}

/** 三种依赖类型：与后端 dependency_type 对齐 */
const DEP_KIND_SPEC = {
  EXEC_ORDER: {
    label: '执行顺序',
    subtitle: '拓扑依赖',
    hint: '必须先完成前置再执行后续，用于主流程排序。',
  },
  DATA: {
    label: '数据 / 契约',
    subtitle: '状态传递',
    hint: '字段产出与消费，如筛选入参、查询结果、导出载荷。',
  },
  RESOURCE: {
    label: '资源约束',
    subtitle: '外部约束',
    hint: '权限、SDK、文件 IO 等；关注 resources_required。',
  },
}

/**
 * @param {object} item
 * @returns {'EXEC_ORDER' | 'DATA' | 'RESOURCE'}
 */
function normalizeDepKind(item) {
  const k = String(item?.dependency_type ?? item?.dependencyType ?? '')
    .toUpperCase()
    .trim()
  if (k === 'EXEC_ORDER' || k === 'DATA' || k === 'RESOURCE') return k
  return 'DATA'
}

function isDepKindAmbiguous(item) {
  const raw = String(item?.dependency_type ?? item?.dependencyType ?? '').trim()
  if (!raw) return true
  const k = raw.toUpperCase()
  return !DEP_KIND_ORDER.includes(k)
}

/** 与 FunctionTree 一致：按节点 id 数字序排序子节点 */
function compareFunctionNodeIds(a, b) {
  const sa = typeof a === 'string' ? a : ''
  const sb = typeof b === 'string' ? b : ''
  if (sa === sb) return 0
  if (sa === 'virtual-root') return -1
  if (sb === 'virtual-root') return 1
  return sa.localeCompare(sb, undefined, { numeric: true, sensitivity: 'base' })
}

/** 当前节点在功能树下是否还有子层可展示 */
const hasSubtreeForLayerChart = computed(() => {
  const n = props.node
  if (!n || typeof n !== 'object') return false
  return Array.isArray(n.children) && n.children.length > 0
})

/** 自功能树汇总全部依赖边（ outgoing 去重） */
function collectAllDependencyEdgesFromTree(root) {
  if (!root || typeof root !== 'object') return []
  const out = []
  const seen = new Set()
  function walk(n) {
    if (!n || typeof n !== 'object') return
    const list = n.outgoing_dependencies
    if (Array.isArray(list)) {
      for (const e of list) {
        if (!e || typeof e !== 'object') continue
        const from = e.from
        const to = e.to
        if (typeof from !== 'string' || typeof to !== 'string' || !from || !to) continue
        const idKey = e.dep_id != null && String(e.dep_id).trim() ? String(e.dep_id).trim() : ''
        const key = idKey ? `id:${idKey}` : `e:${from}>${to}`
        if (seen.has(key)) continue
        seen.add(key)
        out.push(e)
      }
    }
    const ch = n.children
    if (Array.isArray(ch)) {
      for (const c of ch) walk(c)
    }
  }
  walk(root)
  return out
}

function severityShortZh(item) {
  if (!item || typeof item !== 'object') return '—'
  const key = String(item.severity ?? '').toUpperCase().trim()
  const m = { HIGH: '高', MEDIUM: '中', LOW: '低' }
  return m[key] || (item.severity ? String(item.severity) : '—')
}

function layerDepKindLineColor(kind) {
  if (kind === 'EXEC_ORDER') return '#1890ff'
  if (kind === 'DATA') return '#52c41a'
  if (kind === 'RESOURCE') return '#faad14'
  return '#8c8c8c'
}

/** 在画布像素坐标系中，按节点数自适应圆周半径与圆点大小 */
function computePeerLayerGraphLayout(count, chartW, chartH) {
  const n = Math.max(1, count)
  const w = Math.max(chartW || 0, 280)
  const h = Math.max(chartH || 0, 280)
  const cx = w / 2
  const cy = h / 2
  const minDim = Math.min(w, h)

  const margin = Math.max(24, Math.round(minDim * 0.07))
  const fillFactor = n <= 2 ? 0.5 : n <= 4 ? 0.56 : n <= 7 ? 0.64 : 0.72
  const maxRadius = minDim / 2 - margin

  const estRadius = maxRadius * fillFactor
  const chordPx = n === 1 ? minDim : 2 * estRadius * Math.sin(Math.PI / n)

  let symbolSize
  if (n === 1) {
    symbolSize = Math.min(26, minDim * 0.18)
  } else {
    const byChord = chordPx * 0.38
    const byDensity = 24 - (n - 1) * 0.65
    symbolSize = Math.max(11, Math.min(byChord, byDensity, 26))
  }
  symbolSize = Math.round(symbolSize)

  const edgeArrowSize = Math.max(5, Math.round(symbolSize * 0.34))
  const radiusPx = Math.max(
    36,
    maxRadius * fillFactor - symbolSize / 2 - edgeArrowSize - 6
  )

  return {
    symbolSize,
    labelFontSize: Math.max(9, Math.round(symbolSize * 0.46)),
    edgeArrowSize,
    radiusPx,
    cx,
    cy,
    pad: Math.ceil(symbolSize / 2 + edgeArrowSize + 12),
  }
}

/** 抽象坐标系中等分圆周，并做 bbox 中心化 */
function layoutCirclePositionsCentered(count, radius) {
  if (count <= 0) return []
  if (count === 1) return [{ x: 0, y: 0 }]
  const raw = []
  for (let i = 0; i < count; i++) {
    const ang = -Math.PI / 2 + (2 * Math.PI * i) / count
    raw.push({ x: radius * Math.cos(ang), y: radius * Math.sin(ang) })
  }
  let minX = Infinity
  let maxX = -Infinity
  let minY = Infinity
  let maxY = -Infinity
  for (const p of raw) {
    minX = Math.min(minX, p.x)
    maxX = Math.max(maxX, p.x)
    minY = Math.min(minY, p.y)
    maxY = Math.max(maxY, p.y)
  }
  const mx = (minX + maxX) / 2
  const my = (minY + maxY) / 2
  return raw.map((p) => ({ x: p.x - mx, y: p.y - my }))
}

/**
 * 仅子节点之间、指定 dependency_type 的依赖；不画父→子分解边
 * layout:none + 正方形绘图区，保证等比缩放；节点少时缩小数据半径避免过稀疏。
 */
function buildPeerChildLayerGraph(parent, depKind, allEdges, chartW, chartH) {
  const kids = getDirectChildrenSorted(parent)
  if (!kids.length) return { nodes: [], links: [] }

  const idSet = new Set()
  for (const k of kids) {
    const id = typeof k.id === 'string' && k.id.trim() ? k.id.trim() : ''
    if (id) idSet.add(id)
  }

  const peerEdges = allEdges.filter((e) => {
    if (!e) return false
    const fromId = String(e.from ?? '').trim()
    const toId = String(e.to ?? '').trim()
    return (
      fromId &&
      toId &&
      idSet.has(fromId) &&
      idSet.has(toId) &&
      normalizeDepKind(e) === depKind
    )
  })

  const n = kids.length
  const layout = computePeerLayerGraphLayout(n, chartW, chartH)
  const nodeCircleSize = layout.symbolSize
  const nodeLabelFontSize = layout.labelFontSize
  const coords = layoutCirclePositionsCentered(n, 100)
  const nodeColor = layerDepKindLineColor(depKind)

  const nodes = []
  for (let i = 0; i < n; i++) {
    const c = kids[i]
    const cidRaw = typeof c.id === 'string' ? c.id.trim() : ''
    const cid = cidRaw || `child-${i}`
    const { x, y } = coords[i] ?? { x: 0, y: 0 }

    nodes.push({
      id: cid,
      name: cid,
      x,
      y,
      childIndex: i + 1,
      nodeId: cid,
      nodeTitle: String(c.title ?? '').trim(),
      nodeDesc: String(c.desc ?? c.description ?? '').trim(),
      nodeType: c.node_type ?? '—',
      symbol: 'circle',
      symbolSize: nodeCircleSize,
      itemStyle: {
        color: nodeColor,
        borderColor: 'rgba(255,255,255,0.92)',
        borderWidth: nodeCircleSize >= 22 ? 2 : 1.5,
        shadowBlur: nodeCircleSize >= 22 ? 4 : 2,
        shadowColor: 'rgba(15,20,30,0.12)',
      },
      label: {
        show: true,
        position: 'inside',
        color: '#fff',
        fontSize: nodeLabelFontSize,
        fontWeight: 700,
        formatter: (p) => String(p.data?.childIndex ?? ''),
      },
    })
  }

  const lineColor = layerDepKindLineColor(depKind)
  const links = peerEdges.map((e, ei) => {
    const fromId = String(e.from ?? '').trim()
    const toId = String(e.to ?? '').trim()
    return {
      source: fromId,
      target: toId,
      edgeRaw: e,
      lineStyle: {
        width: 2.5,
        color: lineColor,
        curveness: 0.15 + (ei % 5) * 0.04,
        opacity: 1,
      },
      label: {
        show: false,
      },
    }
  })

  const plotSide = Math.max(Math.min(chartW, chartH) - layout.pad * 2, 120)

  return {
    nodes,
    links,
    layout: {
      ...layout,
      plotSide,
    },
  }
}

/** 当前父节点下，子节点之间的依赖条数（按类型） */
const layerPeerEdgeCountByKind = computed(() => {
  const counts = { EXEC_ORDER: 0, DATA: 0, RESOURCE: 0 }
  const parent = props.node
  if (!parent?.children?.length) return counts
  const kids = getDirectChildrenSorted(parent)
  const idSet = new Set(kids.map((k) => k?.id).filter((id) => typeof id === 'string' && id.trim()))
  if (!idSet.size) return counts
  const edges = collectAllDependencyEdgesFromTree(chatStore.functionTreeData)
  for (const e of edges) {
    if (!e || typeof e !== 'object') continue
    const f = String(e.from ?? '').trim()
    const t = String(e.to ?? '').trim()
    if (!idSet.has(f) || !idSet.has(t)) continue
    const k = normalizeDepKind(e)
    if (counts[k] !== undefined) counts[k] += 1
  }
  return counts
})

/** 子层 peer 依赖总数 > 0 */
const hasLayerPeerEdges = computed(() =>
  DEP_KIND_ORDER.some((k) => layerPeerEdgeCountByKind.value[k] > 0)
)

/** 仅展示数量 > 0 的子类型 Tab */
const visibleLayerGraphKinds = computed(() =>
  DEP_KIND_ORDER.filter((k) => layerPeerEdgeCountByKind.value[k] > 0)
)

/** 展示「子功能层依赖图」：有子节点且子层之间存在至少一条 peer 依赖 */
const showLayerTreeTab = computed(
  () => hasSubtreeForLayerChart.value && hasLayerPeerEdges.value
)

function pickDefaultLayerGraphKind() {
  const c = layerPeerEdgeCountByKind.value
  for (const k of DEP_KIND_ORDER) {
    if (c[k] > 0) return k
  }
  return 'EXEC_ORDER'
}

function truncateGraphLabel(s, max) {
  const t = String(s ?? '').trim()
  if (!t) return '—'
  return t.length > max ? `${t.slice(0, max)}…` : t
}

/**
 * 仅取一层子节点（不展开孙层），排序规则与功能树一致
 */
function getDirectChildrenSorted(root) {
  if (!root || typeof root !== 'object') return []
  const raw = Array.isArray(root.children) ? root.children : []
  return [...raw].sort((a, b) => compareFunctionNodeIds(a?.id, b?.id))
}

function disposeLayerTreeChart() {
  clearTimeout(layerGraphResizeDebounce)
  layerChartLayoutRetries = 0
  if (layerTreeResizeObserver) {
    layerTreeResizeObserver.disconnect()
    layerTreeResizeObserver = null
  }
  if (layerTreeChart) {
    layerTreeChart.dispose()
    layerTreeChart = null
  }
}

function bindLayerTreeResize() {
  if (layerTreeResizeObserver) {
    layerTreeResizeObserver.disconnect()
    layerTreeResizeObserver = null
  }
  const el = layerTreeChartRef.value
  if (!el) return
  layerTreeResizeObserver = new ResizeObserver(() => {
    clearTimeout(layerGraphResizeDebounce)
    layerGraphResizeDebounce = window.setTimeout(() => {
      if (activeTab.value === 'layerTree' && props.visible && showLayerTreeTab.value) {
        renderLayerTreeChart()
      } else {
        layerTreeChart?.resize()
      }
    }, 100)
  })
  layerTreeResizeObserver.observe(el)
}

function renderLayerTreeChart() {
  const el = layerTreeChartRef.value
  if (!el || !props.visible || activeTab.value !== 'layerTree') return
  if (!showLayerTreeTab.value || !hasSubtreeForLayerChart.value || !props.node) return

  const rect = el.getBoundingClientRect()
  const w = Math.floor(rect.width) || el.clientWidth || 0
  const h = Math.floor(rect.height) || el.clientHeight || 0

  if (w < 48 || h < 48) {
    if (layerChartLayoutRetries < LAYER_CHART_LAYOUT_MAX_RETRIES) {
      layerChartLayoutRetries += 1
      requestAnimationFrame(() => renderLayerTreeChart())
    }
    return
  }
  layerChartLayoutRetries = 0

  const allEdges = collectAllDependencyEdgesFromTree(chatStore.functionTreeData)
  const { nodes, links, layout } = buildPeerChildLayerGraph(
    props.node,
    layerGraphKindTab.value,
    allEdges,
    w,
    h
  )
  if (!nodes.length) return

  const { edgeArrowSize, plotSide } = layout

  if (!layerTreeChart) {
    layerTreeChart = echarts.init(el, null, { renderer: 'canvas' })
    bindLayerTreeResize()
  }
  layerTreeChart.resize({ width: w, height: h })

  layerTreeChart.setOption(
    {
      animationDurationUpdate: 550,
      tooltip: {
        trigger: 'item',
        enterable: true,
        confine: true,
        formatter: (p) => {
          if (p?.dataType === 'edge') {
            const raw = p?.data?.edgeRaw
            const ed = raw && typeof raw === 'object' ? raw : p?.data
            if (!ed || typeof ed !== 'object') return ''
            const flow = `${ed.from} → ${ed.to}`
            const desc = depDescription(ed)
            const typeLabel = dependencyTypeShortLabel(ed)
            let html = `${flow}<br/><span style="font-size:12px;color:#595959">重要度 ${severityShortZh(
              ed
            )} · 触发 ${depTriggerDisplay(ed)}</span>`
            if (typeLabel) {
              html += `<br/><span style="font-size:11px;color:#8c8c8c">${typeLabel}</span>`
            }
            if (desc) {
              html += `<br/><span style="font-size:12px;color:#8c8c8c">${desc}</span>`
            }
            return html
          }
          const d = p?.data
          if (!d || typeof d !== 'object') return ''
          const id = d.nodeId ?? ''
          const title = d.nodeTitle ?? ''
          const desc = (d.nodeDesc && String(d.nodeDesc).trim()) || ''
          const head = title ? `${id}<br/><b>${title}</b>` : id
          const descHtml = desc ? `<br/><span style="color:#8c8c8c;font-size:12px">${desc}</span>` : ''
          return `${head}${descHtml}`
        },
      },
      series: [
        {
          type: 'graph',
          layout: 'none',
          left: 'center',
          top: 'middle',
          width: plotSide,
          height: plotSide,
          animation: true,
          animationDuration: 450,
          animationDurationUpdate: 350,
          data: nodes,
          links,
          roam: true,
          scaleLimit: { min: 0.35, max: 2.6 },
          draggable: true,
          edgeSymbol: ['none', 'arrow'],
          edgeSymbolSize: [0, edgeArrowSize],
          lineStyle: {
            opacity: 1,
          },
          emphasis: {
            focus: 'adjacency',
            blurScope: 'coordinateSystem',
            lineStyle: { width: 3.5, opacity: 1 },
          },
        },
      ],
    },
    { notMerge: true }
  )
  /** 首次切 Tab 时容器可能仍为 0 高，延迟 resize 才能出图 */
  requestAnimationFrame(() => {
    layerTreeChart?.resize({ width: w, height: h })
  })
}

/** dependency_type 中文短标签（tooltip） */
function dependencyTypeShortLabel(item) {
  const k = String(item?.dependency_type ?? item?.dependencyType ?? '')
    .toUpperCase()
    .trim()
  const map = {
    EXEC_ORDER: '执行顺序',
    DATA: '数据/契约',
    RESOURCE: '资源约束',
  }
  return map[k] || ''
}

/** 重要度：依赖若未满足/被破坏时对业务的影响程度（字段名为 severity，取值 HIGH / MEDIUM / LOW） */
const IMPORTANCE_HELP =
  '重要度表示：这条依赖如果被违背或无法满足，对主流程、数据一致性或体验的影响有多大。高通常意味着应优先保证；中为重要但往往可降级；低表示影响面小或较易补救。'

/** 触发：接口返回的 `trigger` 已由服务端本地化为中文短句，前端直接展示即可 */
const TRIGGER_HELP =
  '触发表示：这条依赖在什么时机或事件下才需要被满足。文案由服务端与 REST/SSE 保持一致；若为空多为历史数据或未标注。'

/** 仅箭头文案：F-1.1 → F-1.2 */
function formatDepFlowArrow(item) {
  if (typeof item === 'string') return item
  if (!item || typeof item !== 'object') return ''
  const from = item.from
  const to = item.to
  if (typeof from === 'string' && from && typeof to === 'string' && to) {
    return `${from} → ${to}`
  }
  const target = item.target_id ?? item.to ?? item.target ?? ''
  if (typeof target === 'string' && target.trim()) return target.trim()
  return '—'
}

function severityLabel(item) {
  if (!item || typeof item !== 'object') return ''
  const raw = item.severity
  if (!raw || typeof raw !== 'string') return ''
  const key = raw.trim().toUpperCase()
  const map = { HIGH: '高', MEDIUM: '中', LOW: '低' }
  return map[key] ? `重要度 ${map[key]}` : raw.trim()
}

function severityTagType(item) {
  const key = String(item?.severity ?? '').toUpperCase().trim()
  if (key === 'HIGH') return 'danger'
  if (key === 'MEDIUM') return 'warning'
  if (key === 'LOW') return 'info'
  return 'info'
}

function depDescription(item) {
  if (!item || typeof item !== 'object') return ''
  return String(item.note ?? item.description ?? item.requirement ?? '').trim()
}

/** 直接绑定后端 trigger（已为中文展示文案）；空则兜底 */
function depTriggerDisplay(item) {
  if (!item || typeof item !== 'object') return '—'
  const t = item.trigger
  if (typeof t === 'string' && t.trim()) return t.trim()
  return '—'
}

function depDirectionExplain(item) {
  if (!item || typeof item !== 'object') return ''
  return String(item.direction_explain ?? '').trim()
}

function depDegradeHint(item) {
  if (!item || typeof item !== 'object') return ''
  const mode = String(item.degradation_mode ?? '').trim()
  const note = String(item.degradation_note ?? '').trim()
  if (mode && note) return `[${mode}] ${note}`
  return mode || note
}

function depResourcesRequired(item) {
  const r = item?.resources_required
  return Array.isArray(r) ? r : []
}

function depProvidesList(item) {
  const r = item?.provides
  return Array.isArray(r) ? r : []
}

function depRequiresList(item) {
  const r = item?.requires
  return Array.isArray(r) ? r : []
}

function formatContractField(f) {
  if (!f || typeof f !== 'object') return ''
  const field = f.field != null ? String(f.field) : ''
  const dt = f.data_type != null ? String(f.data_type) : ''
  const src = f.source != null ? String(f.source) : ''
  const req = f.required === true ? '必填' : f.required === false ? '可选' : ''
  return [field, dt, src, req].filter(Boolean).join(' · ')
}

function formatResourceRequiredRow(r) {
  if (!r || typeof r !== 'object') return ''
  const kind = r.kind != null ? String(r.kind) : ''
  const name = r.name != null ? String(r.name) : ''
  const notes = r.notes != null ? String(r.notes) : ''
  return [kind, name, notes].filter(Boolean).join(' · ')
}

function depEdgeKey(item, idx, kind) {
  if (!item || typeof item !== 'object') return `${kind}-${idx}`
  const id = item.dep_id ?? item.id ?? item.dependency_id
  if (typeof id === 'string' && id.trim()) return `${kind}-${id.trim()}`
  const f = typeof item.from === 'string' ? item.from : ''
  const t = typeof item.to === 'string' ? item.to : ''
  if (f && t) return `${kind}-${f}>${t}`
  return `${kind}-${idx}`
}

function clampPosition() {
  const anchor = props.anchorEl?.getBoundingClientRect?.()
  const el = cardRef.value
  if (!anchor || !el) return

  const margin = 8
  const gap = 10
  const rect = el.getBoundingClientRect()
  const vw = window.innerWidth
  const vh = window.innerHeight

  let left = anchor.right + gap
  let top = anchor.top

  if (left + rect.width > vw - margin) {
    left = anchor.left - rect.width - gap
  }
  if (left < margin) left = margin
  if (top + rect.height > vh - margin) {
    top = vh - rect.height - margin
  }
  if (top < margin) top = margin

  position.value = { left, top }
}

function updateLayout() {
  if (!props.visible) return
  nextTick(() => clampPosition())
}

function onClose() {
  emit('close')
}

function onKeydown(e) {
  if (e.key === 'Escape' && props.visible) {
    e.preventDefault()
    onClose()
  }
}

/** 切到其他窗口/标签后定位易与锚点脱节，切走时直接关闭 */
function onVisibilityChange() {
  if (document.hidden && props.visible) {
    onClose()
  }
}

/** 页面窗口失焦（切到别的应用、另一个浏览器窗口等）时关闭 */
function onWindowBlur() {
  if (props.visible) {
    onClose()
  }
}

function isPointerOnAnchoredUi(target) {
  if (!(target instanceof Element)) return false
  const card = cardRef.value
  const anchor = props.anchorEl
  if (card?.contains?.(target)) return true
  if (anchor?.contains?.(target)) return true
  // Element Plus 弹层挂在 body，需视为「仍属于本浮层交互」
  if (target.closest?.('.el-popper')) return true
  if (target.closest?.('.el-overlay')) return true
  return false
}

/** 捕获阶段：任意点击落在卡片/锚点/ElementPlus 弹出层外则关闭（点击失焦） */
function onDocumentPointerDownCapture(e) {
  if (!props.visible) return
  if (isPointerOnAnchoredUi(e.target)) return
  onClose()
}

watch(
  () => [props.visible, props.node, props.anchorEl],
  () => {
    if (props.visible) {
      activeTab.value = 'basic'
      layerGraphKindTab.value = pickDefaultLayerGraphKind()
      refineInstruction.value = ''
      refineMaxFeasibilityDepth.value = 1
      updateLayout()
    } else {
      disposeLayerTreeChart()
    }
  }
)

watch([showLayerTreeTab, showDepsTab], () => {
  if (!showLayerTreeTab.value && activeTab.value === 'layerTree') {
    activeTab.value = 'basic'
  }
  if (!showDepsTab.value && activeTab.value === 'deps') {
    activeTab.value = 'basic'
  }
})

watch(activeTab, (tab) => {
  updateLayout()
  if (tab === 'layerTree') {
    layerGraphKindTab.value = pickDefaultLayerGraphKind()
    nextTick(() => {
      renderLayerTreeChart()
      /** 子功能层拉长卡片高度后，重新夹紧视口内位置并再绘一次图 */
      nextTick(() => {
        updateLayout()
        renderLayerTreeChart()
      })
    })
  }
})

watch(layerGraphKindTab, () => {
  if (props.visible && activeTab.value === 'layerTree') {
    nextTick(() => renderLayerTreeChart())
  }
})

watch(
  layerPeerEdgeCountByKind,
  (c) => {
    if (!props.visible || activeTab.value !== 'layerTree') return
    if (c[layerGraphKindTab.value] === 0) {
      const next = DEP_KIND_ORDER.find((k) => c[k] > 0)
      layerGraphKindTab.value = next ?? 'EXEC_ORDER'
      nextTick(() => renderLayerTreeChart())
    }
  },
  { deep: true }
)

watch(
  () => chatStore.functionTreeData,
  () => {
    if (props.visible && activeTab.value === 'layerTree') {
      nextTick(() => renderLayerTreeChart())
    }
  },
  { deep: true }
)

watch(
  () => props.node,
  () => {
    if (props.visible && activeTab.value === 'layerTree') {
      nextTick(() => renderLayerTreeChart())
    }
  },
  { deep: true }
)

onMounted(() => {
  window.addEventListener('resize', updateLayout)
  window.addEventListener('scroll', updateLayout, true)
  window.addEventListener('blur', onWindowBlur)
  document.addEventListener('keydown', onKeydown)
  document.addEventListener('visibilitychange', onVisibilityChange)
  document.addEventListener('pointerdown', onDocumentPointerDownCapture, true)
})

onUnmounted(() => {
  disposeLayerTreeChart()
  window.removeEventListener('resize', updateLayout)
  window.removeEventListener('scroll', updateLayout, true)
  window.removeEventListener('blur', onWindowBlur)
  document.removeEventListener('keydown', onKeydown)
  document.removeEventListener('visibilitychange', onVisibilityChange)
  document.removeEventListener('pointerdown', onDocumentPointerDownCapture, true)
})
</script>

<template>
  <Teleport to="body">
    <div
      v-if="visible && node"
      ref="cardRef"
      class="function-detail-card"
      :style="{ left: position.left + 'px', top: position.top + 'px' }"
      role="dialog"
      aria-modal="true"
      aria-labelledby="function-detail-title"
    >
        <header class="fdc-header">
          <h2 id="function-detail-title" class="fdc-title">功能详情</h2>
          <button type="button" class="fdc-close" aria-label="关闭" @click="onClose">
            <el-icon :size="18"><Close /></el-icon>
          </button>
        </header>

        <nav class="fdc-tabs" aria-label="详情分页">
          <button
            type="button"
            class="fdc-tab"
            :class="{ active: activeTab === 'basic' }"
            @click="activeTab = 'basic'"
          >
            基本信息
          </button>
          <button
            v-if="showLayerTreeTab"
            type="button"
            class="fdc-tab"
            :class="{ active: activeTab === 'layerTree' }"
            @click="activeTab = 'layerTree'"
          >
            子功能层依赖图
          </button>
          <button
            v-if="showDepsTab"
            type="button"
            class="fdc-tab"
            :class="{ active: activeTab === 'deps' }"
            @click="activeTab = 'deps'"
          >
            依赖关系
          </button>
        </nav>

        <div v-show="activeTab === 'basic'" class="fdc-body">
          <dl class="fdc-kv">
            <div class="fdc-row">
              <dt>名称</dt>
              <dd>{{ node.title || '—' }}</dd>
            </div>
            <div class="fdc-row">
              <dt>ID</dt>
              <dd>{{ node.id || '—' }}</dd>
            </div>
            <div class="fdc-row">
              <dt>类型/粒度</dt>
              <dd>{{ typeGranularityText }}</dd>
            </div>
            <div class="fdc-row">
              <dt>所属路径</dt>
              <dd>{{ pathLabel || '—' }}</dd>
            </div>
          </dl>

          <div class="fdc-block">
            <div class="fdc-label">描述</div>
            <div class="fdc-box">{{ descriptionText }}</div>
          </div>

          <div v-if="refineEnabled" class="fdc-block fdc-refine">
            <div class="fdc-label">节点重拆</div>
            <p class="fdc-refine-hint muted">
              在已完成主协调的前提下，对当前节点重新跑子需求拆分及后续一致性与可实现性分析。可选填写补充说明；可实现性细化深度在下方单独选择。其余编排参数仍来自底部「解析任务」齿轮。
            </p>
            <el-input
              v-model="refineInstruction"
              type="textarea"
              :rows="2"
              maxlength="2000"
              show-word-limit
              placeholder="补充说明（可选）"
              :disabled="!canOfferRefine"
            />
            <div class="fdc-refine-depth">
              <span class="fdc-refine-depth-label">
                <el-tooltip
                  :content="REFINE_MAX_DEPTH_HELP"
                  :popper-class="TOOLTIP_POPPER_CLASS"
                  placement="top"
                  :show-after="200"
                >
                  <span class="fdc-refine-depth-label-text">可实现性细化最大深度</span>
                </el-tooltip>
              </span>
              <el-input-number
                v-model="refineMaxFeasibilityDepth"
                :min="1"
                :max="20"
                :step="1"
                :disabled="!canOfferRefine"
                controls-position="right"
                class="fdc-refine-depth-input"
              />
            </div>
            <el-button
              type="primary"
              plain
              class="fdc-refine-btn"
              :disabled="!canOfferRefine"
              :loading="refineBusy"
              @click="confirmRefineNode"
            >
              重拆此节点
            </el-button>
          </div>
        </div>

        <div v-show="activeTab === 'layerTree'" class="fdc-body fdc-body--layer-tree">
          <div
            v-if="visibleLayerGraphKinds.length"
            class="fdc-deps-kind-nav"
            role="tablist"
            aria-label="子层依赖类型"
          >
            <button
              v-for="k in visibleLayerGraphKinds"
              :key="'lg-' + k"
              type="button"
              class="fdc-deps-kind-btn"
              :class="{ active: layerGraphKindTab === k }"
              role="tab"
              :aria-selected="layerGraphKindTab === k"
              @click="layerGraphKindTab = k"
            >
              <span class="fdc-deps-kind-title">{{ DEP_KIND_SPEC[k].label }}</span>
              <span class="fdc-deps-kind-sub">{{ DEP_KIND_SPEC[k].subtitle }}</span>
              <span class="fdc-deps-kind-count" :class="DEP_KIND_COUNT_CLASS[k]">
                {{ layerPeerEdgeCountByKind[k] }}
              </span>
            </button>
          </div>
          <p class="fdc-deps-kind-blurb muted">{{ DEP_KIND_SPEC[layerGraphKindTab].hint }}</p>
          <p class="fdc-layer-hint muted">
            完整标题与描述请悬浮在圆点上查看<br />
            依赖的重要度、触发与说明请悬浮在连线上查看<br />
            可拖拽平移、滚轮缩放
          </p>
          <div
            ref="layerTreeChartRef"
            class="fdc-layer-chart"
            role="img"
            aria-label="子功能层关系图"
          />
        </div>

        <div v-show="activeTab === 'deps'" class="fdc-body fdc-body--deps">
          <p class="fdc-deps-legend muted">
            <el-tooltip
              :content="IMPORTANCE_HELP"
              :popper-class="TOOLTIP_POPPER_CLASS"
              placement="top"
              :show-after="200"
            >
              <span class="fdc-deps-legend-link">重要度</span>
            </el-tooltip>
            <span class="fdc-deps-legend-sep">·</span>
            <el-tooltip
              :content="TRIGGER_HELP"
              :popper-class="TOOLTIP_POPPER_CLASS"
              placement="top"
              :show-after="200"
            >
              <span class="fdc-deps-legend-link">触发</span>
            </el-tooltip>
          </p>

          <div class="fdc-deps-scroll">
            <div class="fdc-block fdc-block--dense">
              <div class="fdc-label muted">发起的依赖 (Outgoing)</div>
              <div v-if="outgoingList.length" class="fdc-box fdc-box--dense">
                <div
                  v-for="(item, idx) in outgoingList"
                  :key="depEdgeKey(item, idx, 'o')"
                  class="fdc-dep-item"
                >
                  <div class="fdc-dep-line fdc-dep-line--grid">
                    <div class="fdc-dep-badges">
                      <el-tag
                        v-if="isDepKindAmbiguous(item)"
                        size="small"
                        type="info"
                        effect="plain"
                      >
                        归入本类（类型未标注）
                      </el-tag>
                      <el-tooltip
                        v-if="severityLabel(item)"
                        :content="IMPORTANCE_HELP"
                        :popper-class="TOOLTIP_POPPER_CLASS"
                        placement="top"
                        :show-after="200"
                      >
                        <span class="fdc-tag-inline">
                          <el-tag size="small" :type="severityTagType(item)" effect="plain">
                            {{ severityLabel(item) }}
                          </el-tag>
                        </span>
                      </el-tooltip>
                      <el-tag v-if="item.dep_id" size="small" effect="plain" class="fdc-dep-id-tag">
                        {{ item.dep_id }}
                      </el-tag>
                    </div>
                    <div class="fdc-dep-flow">
                      <span class="fdc-dep-arrow-text">{{ formatDepFlowArrow(item) }}</span>
                    </div>
                  </div>
                  <div v-if="depDescription(item)" class="fdc-dep-note">{{ depDescription(item) }}</div>
                  <div v-if="depDirectionExplain(item)" class="fdc-dep-extra muted">
                    {{ depDirectionExplain(item) }}
                  </div>
                  <div v-if="depDegradeHint(item)" class="fdc-dep-degrade muted">
                    {{ depDegradeHint(item) }}
                  </div>
                  <div class="fdc-dep-meta">
                    <el-tooltip
                      :content="TRIGGER_HELP"
                      :popper-class="TOOLTIP_POPPER_CLASS"
                      placement="top"
                      :show-after="200"
                    >
                      <span class="fdc-dep-meta-k">触发</span>
                    </el-tooltip>
                    <el-tag type="info" effect="plain" size="small" class="fdc-dep-trigger-tag">
                      {{ depTriggerDisplay(item) }}
                    </el-tag>
                  </div>
                  <div
                    v-if="depProvidesList(item).length || depRequiresList(item).length"
                    class="fdc-dep-contract"
                  >
                    <div v-if="depProvidesList(item).length" class="fdc-dep-contract-col">
                      <div class="fdc-mini-label">产出 provides</div>
                      <ul class="fdc-mini-list">
                        <li v-for="(p, pi) in depProvidesList(item)" :key="'p-' + pi">
                          {{ formatContractField(p) }}
                        </li>
                      </ul>
                    </div>
                    <div v-if="depRequiresList(item).length" class="fdc-dep-contract-col">
                      <div class="fdc-mini-label">消费 requires</div>
                      <ul class="fdc-mini-list">
                        <li v-for="(r, ri) in depRequiresList(item)" :key="'r-' + ri">
                          {{ formatContractField(r) }}
                        </li>
                      </ul>
                    </div>
                  </div>
                  <div v-if="depResourcesRequired(item).length" class="fdc-dep-res-block">
                    <div class="fdc-mini-label">resources_required</div>
                    <ul class="fdc-mini-list">
                      <li v-for="(res, ri) in depResourcesRequired(item)" :key="'res-' + ri">
                        {{ formatResourceRequiredRow(res) }}
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
              <div v-else class="fdc-plain muted">无</div>
            </div>

            <div class="fdc-block fdc-block--dense fdc-block--last">
              <div class="fdc-label muted">被依赖的关系 (Incoming)</div>
              <div v-if="incomingList.length" class="fdc-box fdc-box--dense">
                <div
                  v-for="(item, idx) in incomingList"
                  :key="depEdgeKey(item, idx, 'i')"
                  class="fdc-dep-item"
                >
                  <div class="fdc-dep-line fdc-dep-line--grid">
                    <div class="fdc-dep-badges">
                      <el-tag
                        v-if="isDepKindAmbiguous(item)"
                        size="small"
                        type="info"
                        effect="plain"
                      >
                        归入本类（类型未标注）
                      </el-tag>
                      <el-tooltip
                        v-if="severityLabel(item)"
                        :content="IMPORTANCE_HELP"
                        :popper-class="TOOLTIP_POPPER_CLASS"
                        placement="top"
                        :show-after="200"
                      >
                        <span class="fdc-tag-inline">
                          <el-tag size="small" :type="severityTagType(item)" effect="plain">
                            {{ severityLabel(item) }}
                          </el-tag>
                        </span>
                      </el-tooltip>
                      <el-tag v-if="item.dep_id" size="small" effect="plain" class="fdc-dep-id-tag">
                        {{ item.dep_id }}
                      </el-tag>
                    </div>
                    <div class="fdc-dep-flow">
                      <span class="fdc-dep-arrow-text">{{ formatDepFlowArrow(item) }}</span>
                    </div>
                  </div>
                  <div v-if="depDescription(item)" class="fdc-dep-note">{{ depDescription(item) }}</div>
                  <div v-if="depDirectionExplain(item)" class="fdc-dep-extra muted">
                    {{ depDirectionExplain(item) }}
                  </div>
                  <div v-if="depDegradeHint(item)" class="fdc-dep-degrade muted">
                    {{ depDegradeHint(item) }}
                  </div>
                  <div class="fdc-dep-meta">
                    <el-tooltip
                      :content="TRIGGER_HELP"
                      :popper-class="TOOLTIP_POPPER_CLASS"
                      placement="top"
                      :show-after="200"
                    >
                      <span class="fdc-dep-meta-k">触发</span>
                    </el-tooltip>
                    <el-tag type="info" effect="plain" size="small" class="fdc-dep-trigger-tag">
                      {{ depTriggerDisplay(item) }}
                    </el-tag>
                  </div>
                  <div
                    v-if="depProvidesList(item).length || depRequiresList(item).length"
                    class="fdc-dep-contract"
                  >
                    <div v-if="depProvidesList(item).length" class="fdc-dep-contract-col">
                      <div class="fdc-mini-label">产出 provides</div>
                      <ul class="fdc-mini-list">
                        <li v-for="(p, pi) in depProvidesList(item)" :key="'ip-' + pi">
                          {{ formatContractField(p) }}
                        </li>
                      </ul>
                    </div>
                    <div v-if="depRequiresList(item).length" class="fdc-dep-contract-col">
                      <div class="fdc-mini-label">消费 requires</div>
                      <ul class="fdc-mini-list">
                        <li v-for="(r, ri) in depRequiresList(item)" :key="'ir-' + ri">
                          {{ formatContractField(r) }}
                        </li>
                      </ul>
                    </div>
                  </div>
                  <div v-if="depResourcesRequired(item).length" class="fdc-dep-res-block">
                    <div class="fdc-mini-label">resources_required</div>
                    <ul class="fdc-mini-list">
                      <li v-for="(res, ri) in depResourcesRequired(item)" :key="'ires-' + ri">
                        {{ formatResourceRequiredRow(res) }}
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
              <div v-else class="fdc-plain muted">无</div>
            </div>
          </div>
        </div>
    </div>
  </Teleport>
</template>

<style scoped>
.function-detail-card {
  position: fixed;
  z-index: 3001;
  width: 480px;
  max-width: 480px;
  box-sizing: border-box;
  max-height: calc(100vh - 24px);
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background: #ffffff;
  border-radius: 10px;
  box-shadow: 0 8px 24px rgba(15, 20, 30, 0.12), 0 2px 8px rgba(15, 20, 30, 0.06);
}

.fdc-header {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 18px 12px;
  border-bottom: 1px solid #f0f0f0;
}

.fdc-title {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: #262626;
}

.fdc-close {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 4px;
  border: none;
  background: transparent;
  color: #8c8c8c;
  border-radius: 4px;
  cursor: pointer;
  line-height: 1;
}

.fdc-close:hover {
  color: #595959;
  background: #f5f5f5;
}

.fdc-tabs {
  flex-shrink: 0;
  display: flex;
  gap: 8px;
  padding: 12px 18px 0;
}

.fdc-tab {
  border: none;
  background: transparent;
  padding: 6px 14px;
  font-size: 14px;
  color: #8c8c8c;
  border-radius: 6px;
  cursor: pointer;
  line-height: 1.4;
}

.fdc-tab:hover {
  color: #595959;
}

.fdc-tab.active {
  background: #e6f7ff;
  color: #1890ff;
  font-weight: 500;
}

.fdc-body {
  padding: 16px 18px 18px;
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
}

.fdc-body--layer-tree {
  overflow: hidden;
  display: flex;
  flex-direction: column;
  flex: 1 1 auto;
  min-height: 0;
  width: 100%;
  box-sizing: border-box;
  align-items: stretch;
  padding: 12px 14px 18px;
}

.fdc-layer-hint {
  margin: 0 0 8px;
  font-size: 12px;
  line-height: 1.45;
  flex-shrink: 0;
}

.fdc-layer-hint.muted {
  color: #8c8c8c;
}

.fdc-layer-chart {
  flex: 1 1 auto;
  min-height: 0;
  align-self: center;
  width: min(100%, 320px);
  max-height: 100%;
  aspect-ratio: 1 / 1;
  height: auto;
  margin: 0 auto;
  box-sizing: border-box;
  border-radius: 8px;
  background: #fafbfc;
  border: 1px solid #f0f0f0;
  overflow: hidden;
  position: relative;
}

.fdc-layer-chart :deep(canvas) {
  display: block;
}

/* —— 依赖关系：三子类 Tab + 可滚动内容区（避免密集重叠）—— */
.fdc-body--deps {
  display: flex;
  flex-direction: column;
  padding: 12px 14px 14px;
  min-height: 0;
  overflow: hidden;
}

.fdc-deps-kind-nav {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 6px;
  flex-shrink: 0;
}

.fdc-deps-kind-btn {
  flex: 1 1 calc(33.333% - 8px);
  min-width: 112px;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 2px;
  padding: 8px 10px;
  border: 1px solid #e8e8e8;
  border-radius: 8px;
  background: #fafafa;
  cursor: pointer;
  text-align: left;
  line-height: 1.35;
  transition:
    border-color 0.15s ease,
    background 0.15s ease;
}

.fdc-deps-kind-btn:hover {
  border-color: #91caff;
  background: #f0f9ff;
}

.fdc-deps-kind-btn.active {
  border-color: #1890ff;
  background: #e6f7ff;
}

.fdc-deps-kind-title {
  font-size: 13px;
  font-weight: 600;
  color: #262626;
}

.fdc-deps-kind-sub {
  font-size: 11px;
  color: #8c8c8c;
}

.fdc-deps-kind-count {
  align-self: flex-end;
  margin-top: 2px;
  font-size: 12px;
  font-weight: 600;
}

.fdc-deps-kind-count--exec {
  color: #1890ff;
}

.fdc-deps-kind-count--data {
  color: #52c41a;
}

.fdc-deps-kind-count--resource {
  color: #faad14;
}

.fdc-deps-kind-count.muted {
  color: #bfbfbf;
  font-weight: 500;
}

.fdc-deps-kind-blurb {
  margin: 0 0 8px;
  font-size: 12px;
  line-height: 1.45;
  flex-shrink: 0;
}

.fdc-deps-scroll {
  flex: 1 1 auto;
  min-height: 0;
  max-height: min(52vh, 440px);
  overflow-y: auto;
  overflow-x: hidden;
  padding-right: 4px;
  scrollbar-gutter: stable;
  -webkit-overflow-scrolling: touch;
}

.fdc-block--dense {
  margin-bottom: 12px;
}

.fdc-block--dense.fdc-block--last {
  margin-bottom: 0;
}

.fdc-box--dense {
  padding: 10px 10px;
}

.fdc-dep-line--grid {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.fdc-dep-badges {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-start;
  gap: 6px;
  max-width: 100%;
}

.fdc-dep-extra {
  margin-top: 4px;
  font-size: 12px;
  line-height: 1.45;
  word-break: break-word;
}

.fdc-dep-degrade {
  margin-top: 4px;
  font-size: 11px;
  line-height: 1.4;
  word-break: break-word;
}

.fdc-dep-contract {
  display: grid;
  grid-template-columns: 1fr;
  gap: 8px;
  margin-top: 8px;
}

@media (min-width: 380px) {
  .fdc-dep-contract {
    grid-template-columns: 1fr 1fr;
  }
}

.fdc-mini-label {
  font-size: 11px;
  color: #8c8c8c;
  margin-bottom: 4px;
}

.fdc-mini-list {
  margin: 0;
  padding-left: 1.15em;
  font-size: 11px;
  line-height: 1.5;
  color: #434343;
  word-break: break-word;
}

.fdc-dep-res-block {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px dashed #f0f0f0;
}

.fdc-dep-id-tag {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 11px;
}

.fdc-kv {
  margin: 0 0 16px;
}

.fdc-row {
  display: grid;
  grid-template-columns: 88px 1fr;
  gap: 8px 12px;
  font-size: 14px;
  margin-bottom: 10px;
}

.fdc-row dt {
  margin: 0;
  color: #8c8c8c;
}

.fdc-row dd {
  margin: 0;
  color: #262626;
  word-break: break-word;
}

.fdc-block {
  margin-bottom: 16px;
}

.fdc-block:last-child {
  margin-bottom: 0;
}

.fdc-label {
  font-size: 14px;
  color: #8c8c8c;
  margin-bottom: 8px;
}

.fdc-label.muted {
  color: #8c8c8c;
}

.fdc-box {
  background: #f5f7fa;
  border-radius: 8px;
  padding: 12px 14px;
  font-size: 14px;
  color: #262626;
  line-height: 1.5;
}

.fdc-plain {
  font-size: 14px;
  color: #262626;
}

.fdc-plain.muted {
  color: #8c8c8c;
}

.fdc-dep-item + .fdc-dep-item {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid #e8e8e8;
}

.fdc-dep-line {
  font-size: 14px;
  color: #262626;
}

.fdc-dep-line--rich {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.fdc-dep-flow {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 8px;
  font-size: 14px;
  color: #262626;
}

.fdc-deps-legend {
  margin: 0 0 12px;
  font-size: 12px;
  line-height: 1.5;
}

.fdc-deps-legend-link {
  color: #1890ff;
  cursor: help;
  border-bottom: 1px dashed rgba(24, 144, 255, 0.45);
}

.fdc-deps-legend-sep {
  margin: 0 6px;
  color: #bfbfbf;
}

.fdc-tag-inline {
  display: inline-flex;
  vertical-align: middle;
  cursor: help;
}

.fdc-dep-meta {
  margin-top: 6px;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: #595959;
}

.fdc-dep-meta-k {
  color: #8c8c8c;
  cursor: help;
  flex-shrink: 0;
}

.fdc-dep-trigger-tag {
  max-width: 100%;
  white-space: normal;
  height: auto;
  line-height: 1.45;
}

.fdc-dep-arrow-text {
  word-break: break-all;
}

.fdc-dep-note {
  margin-top: 4px;
  font-size: 12px;
  color: #8c8c8c;
}

.fdc-refine {
  margin-top: 8px;
  padding-top: 16px;
  border-top: 1px solid #f0f0f0;
}

.fdc-refine-hint {
  margin: 0 0 10px;
  font-size: 13px;
  line-height: 1.5;
}

.fdc-refine-hint.muted {
  color: #8c8c8c;
}

.fdc-refine-depth {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 12px;
}

.fdc-refine-depth-label {
  flex-shrink: 0;
  font-size: 13px;
  color: #595959;
}

.fdc-refine-depth-label-text {
  cursor: help;
  border-bottom: 1px dashed rgba(24, 144, 255, 0.45);
}

.fdc-refine-depth-input {
  width: 132px;
  flex-shrink: 0;
}

.fdc-refine-btn {
  margin-top: 10px;
  width: 100%;
}
</style>

<style>
/* Tooltip 默认 z-index 低于功能详情卡(3001)与 ElMessageBox/Dialog，抬高 popper */
.el-popper.fdc-tooltip-popper {
  z-index: 10000 !important;
}
</style>
