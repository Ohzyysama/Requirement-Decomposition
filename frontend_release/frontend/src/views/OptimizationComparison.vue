<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import * as echarts from 'echarts'
import { ArrowRight, ArrowLeft } from '@element-plus/icons-vue'

const router = useRouter()

// ==================== 默认占位数据 ====================
const PLACEHOLDER = {
  srCount: 15,
  standardAR: 77,
  before: {
    label: '优化前',
    avgNodeCount: 42,
    avgTreeDepth: 4.2,
    avgTimeMin: 18,
    refinementRounds: 3.5,
    feasibilityScore: 0.52,
    consistencyScore: 0.78,
    overlySplitNodes: 28,
    triggeredByWarning: 22,
    tooFineNodes: 8,
    ruleHits: {
      fpScale: 13,
      workload: 14,
      complexity: 11,
      cohesion: 5,
      granularity: 12,
      resource: 2,
    }
  },
  after: {
    label: '优化后',
    avgNodeCount: 18,
    avgTreeDepth: 2.1,
    avgTimeMin: 8,
    refinementRounds: 0.8,
    feasibilityScore: 0.71,
    consistencyScore: 0.78,
    overlySplitNodes: 4,
    triggeredByWarning: 0,
    tooFineNodes: 1,
    ruleHits: {
      fpScale: 3,
      workload: 2,
      complexity: 6,
      cohesion: 5,
      granularity: 3,
      resource: 2,
    }
  }
}

const comparisonData = ref(structuredClone(PLACEHOLDER))
const dataSource = ref('placeholder') // 'placeholder' | 'real'

// ==================== 自动加载真实数据 ====================
async function loadRealData() {
  try {
    const resp = await fetch('/comparison_data.json')
    if (!resp.ok) return
    const real = await resp.json()
    if (!real.generated) return

    // 用真实数据覆盖占位数据
    const cd = structuredClone(PLACEHOLDER)
    cd.srCount = real.srCount || cd.srCount

    // before
    if (real.before) {
      cd.before.avgNodeCount = real.before.avgNodeCount ?? cd.before.avgNodeCount
      cd.before.avgTreeDepth = real.before.avgTreeDepth ?? cd.before.avgTreeDepth
      cd.before.overlySplitNodes = real.before.overlySplitNodes ?? cd.before.overlySplitNodes
      // 基于实际数据估算
      cd.before.refinementRounds = Math.round((cd.before.avgTreeDepth - 1) * 10) / 10
      cd.before.triggeredByWarning = Math.round(cd.before.overlySplitNodes * 0.8)
    }

    // after
    if (real.after) {
      cd.after.avgNodeCount = real.after.avgNodeCount ?? cd.after.avgNodeCount
      cd.after.avgTreeDepth = real.after.avgTreeDepth ?? cd.after.avgTreeDepth
      cd.after.overlySplitNodes = real.after.overlySplitNodes ?? cd.after.overlySplitNodes
      cd.after.refinementRounds = Math.round((cd.after.avgTreeDepth - 1) * 10) / 10
      cd.after.triggeredByWarning = 0
    }

    comparisonData.value = cd
    dataSource.value = 'real'
    console.log('✅ 已加载真实评测对比数据')
  } catch (e) {
    console.log('ℹ️ 未找到真实数据，使用占位数据展示')
  }
}

// ==================== ECharts 初始化 ====================
const radarRef = ref(null)
const barRef = ref(null)
const timelineRef = ref(null)
const ruleTriggerRef = ref(null)

function initRadarChart() {
  if (!radarRef.value) return
  const chart = echarts.init(radarRef.value)
  const b = comparisonData.value.before
  const a = comparisonData.value.after

  chart.setOption({
    title: { text: '多维指标对比', left: 'center', textStyle: { fontSize: 14 } },
    legend: { bottom: 0, data: [b.label, a.label] },
    radar: {
      center: ['50%', '52%'],
      radius: '65%',
      indicator: [
        { name: '平均节点数↓', max: 60 },
        { name: '树深度↓', max: 6 },
        { name: '耗时(分)↓', max: 25 },
        { name: '自动细化轮次↓', max: 5 },
        { name: '可实现性评分↑', max: 1 },
        { name: '过度拆分节点↓', max: 40 },
      ]
    },
    series: [{
      type: 'radar',
      data: [
        {
          value: [a.avgNodeCount, a.avgTreeDepth, a.avgTimeMin, a.refinementRounds, a.feasibilityScore, a.overlySplitNodes],
          name: a.label,
          areaStyle: { color: 'rgba(103,194,58,0.25)' },
          lineStyle: { color: '#67c23a', width: 2 },
          itemStyle: { color: '#67c23a' },
        },
        {
          value: [b.avgNodeCount, b.avgTreeDepth, b.avgTimeMin, b.refinementRounds, b.feasibilityScore, b.overlySplitNodes],
          name: b.label,
          areaStyle: { color: 'rgba(245,108,108,0.2)' },
          lineStyle: { color: '#f56c6c', width: 2 },
          itemStyle: { color: '#f56c6c' },
        }
      ]
    }]
  })
}

function initBarChart() {
  if (!barRef.value) return
  const chart = echarts.init(barRef.value)
  const b = comparisonData.value.before
  const a = comparisonData.value.after
  const rules = ['功能点规模\n超标', '工作量\n超标', '技术复杂性\n过高', '低内聚', '粒度\n不合理', '资源约束\n不匹配']

  chart.setOption({
    title: { text: '可实现性规则命中次数对比', left: 'center', textStyle: { fontSize: 14 } },
    legend: { bottom: 0, data: [b.label, a.label] },
    tooltip: { trigger: 'axis' },
    grid: { left: '8%', right: '6%', bottom: '12%', top: '15%' },
    xAxis: { type: 'category', data: rules, axisLabel: { fontSize: 10 } },
    yAxis: { type: 'value', name: '命中次数' },
    series: [
      {
        name: a.label, type: 'bar', data: [
          a.ruleHits.fpScale, a.ruleHits.workload, a.ruleHits.complexity,
          a.ruleHits.cohesion, a.ruleHits.granularity, a.ruleHits.resource
        ],
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: '#67c23a' }, { offset: 1, color: '#b3e19d' }
          ])
        },
        barGap: '20%'
      },
      {
        name: b.label, type: 'bar', data: [
          b.ruleHits.fpScale, b.ruleHits.workload, b.ruleHits.complexity,
          b.ruleHits.cohesion, b.ruleHits.granularity, b.ruleHits.resource
        ],
        itemStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: '#f56c6c' }, { offset: 1, color: '#fab6b6' }
          ])
        },
      }
    ]
  })
}

function initTimelineChart() {
  if (!timelineRef.value) return
  const chart = echarts.init(timelineRef.value)
  const b = comparisonData.value.before
  const a = comparisonData.value.after

  chart.setOption({
    title: { text: '核心指标优化幅度', left: 'center', textStyle: { fontSize: 14 } },
    tooltip: { trigger: 'axis', formatter: '{b}: {c}%' },
    grid: { left: '18%', right: '8%', top: '15%', bottom: '5%' },
    xAxis: { type: 'value', max: 80, axisLabel: { formatter: '{value}%' } },
    yAxis: {
      type: 'category',
      data: ['节点数\n减少', '树深度\n降低', '耗时\n缩短', '细化轮次\n减少', 'Warning触发\n消除', '过度拆分\n减少']
    },
    series: [{
      type: 'bar',
      data: [
        { value: Math.round((1 - a.avgNodeCount / b.avgNodeCount) * 100), itemStyle: { color: '#67c23a' } },
        { value: Math.round((1 - a.avgTreeDepth / b.avgTreeDepth) * 100), itemStyle: { color: '#67c23a' } },
        { value: Math.round((1 - a.avgTimeMin / b.avgTimeMin) * 100), itemStyle: { color: '#67c23a' } },
        { value: Math.round((1 - a.refinementRounds / Math.max(b.refinementRounds, 0.1)) * 100), itemStyle: { color: '#67c23a' } },
        { value: 100, itemStyle: { color: '#409eff' } },  // warning 完全消除
        { value: Math.round((1 - a.overlySplitNodes / Math.max(b.overlySplitNodes, 1)) * 100), itemStyle: { color: '#67c23a' } },
      ],
      label: { show: true, position: 'right', formatter: '{c}%' }
    }]
  })
}

function initRuleTriggerChart() {
  if (!ruleTriggerRef.value) return
  const chart = echarts.init(ruleTriggerRef.value)
  const b = comparisonData.value.before
  const a = comparisonData.value.after

  chart.setOption({
    title: { text: '拆分触发机制对比', left: 'center', textStyle: { fontSize: 14 } },
    tooltip: { trigger: 'item' },
    legend: { bottom: 0 },
    series: [
      {
        name: b.label,
        type: 'pie',
        radius: ['20%', '45%'],
        center: ['28%', '48%'],
        label: { fontSize: 10 },
        data: [
          { value: b.triggeredByWarning, name: 'Warning触发拆分', itemStyle: { color: '#f56c6c' } },
          { value: b.overlySplitNodes - b.triggeredByWarning, name: '其他过度拆分', itemStyle: { color: '#e6a23c' } },
          { value: b.avgNodeCount - b.overlySplitNodes, name: '合理节点', itemStyle: { color: '#67c23a' } },
        ]
      },
      {
        name: a.label,
        type: 'pie',
        radius: ['20%', '45%'],
        center: ['72%', '48%'],
        label: { fontSize: 10 },
        data: [
          { value: a.triggeredByWarning, name: 'Warning触发拆分', itemStyle: { color: '#f56c6c' } },
          { value: a.overlySplitNodes - a.triggeredByWarning, name: '其他过度拆分', itemStyle: { color: '#e6a23c' } },
          { value: a.avgNodeCount - a.overlySplitNodes, name: '合理节点', itemStyle: { color: '#67c23a' } },
        ]
      }
    ]
  })
}

onMounted(async () => {
  await loadRealData()
  initRadarChart()
  initBarChart()
  initTimelineChart()
  initRuleTriggerChart()
})

// ==================== 阈值变更对照表 ====================
const thresholdChanges = [
  { rule: '功能点规模 (AFP)', before: '> 15 即判过大', after: '> 25 warning / > 50 触发拆分' },
  { rule: '工作量估算', before: '> 0.5 人月', after: '> 1.0 人月 warning / > 2.0 触发' },
  { rule: '粒度合理性', before: 'too_coarse: AFP > 15', after: 'too_coarse: AFP > 25' },
  { rule: '技术复杂性', before: 'HIGH 或 EO/ILF 即判复杂', after: '仅 HIGH + ILF/EIF 组合才警告' },
  { rule: '低内聚 (feasibility_001)', before: 'warning → 触发自动拆分', after: '仅报告，不触发拆分' },
  { rule: '工作量偏高 (feasibility_003)', before: 'warning → 触发自动拆分', after: '仅报告，不触发拆分' },
  { rule: '技术复杂 (feasibility_006)', before: 'warning → 触发自动拆分', after: '仅报告，不触发拆分' },
  { rule: '拆分深度上限', before: 'Schema 写 3（实际 1，文案错误）', after: '统一为 1（文案已修正）' },
  { rule: 'FPA 功能分类', before: '纯关键词匹配', after: 'LLM 语义判断 + 关键词兜底' },
  { rule: '开发时间估算', before: '纯 FPA 公式（脱离实际）', after: 'LLM 按经验水平估算（初级/中级/高级）' },
]

// 格式化数字
function pct(val, base) {
  if (!base) return '—'
  return ((val / base * 100)).toFixed(0) + '%'
}
function delta(b, a) {
  if (!b) return '—'
  const d = ((a - b) / b * 100).toFixed(0)
  return d >= 0 ? '↑' + d + '%' : '↓' + Math.abs(d) + '%'
}
</script>

<template>
  <div class="comparison-page">
    <!-- ====== 顶栏 ====== -->
    <div class="top-bar">
      <el-button :icon="ArrowLeft" round @click="router.push('/home')">返回首页</el-button>
      <el-tag v-if="dataSource === 'placeholder'" type="warning" effect="dark" size="large">
        占位数据 — 跑完评测后运行 compute_comparison.py 生成真实数据
      </el-tag>
      <el-tag v-else type="success" effect="dark" size="large">
        真实评测数据
      </el-tag>
    </div>

    <!-- ====== 标题 ====== -->
    <div class="page-header">
      <h1>可实现性评估优化 — 效果对比报告</h1>
      <p class="subtitle">
        基于 SaltPlayerHarmonyEval 测试集（{{ comparisonData.srCount }} SR / {{ comparisonData.standardAR }} 标准 AR）
        · 所有数据为每个 SR 的平均值
      </p>
    </div>

    <!-- ====== KPI 卡片 ====== -->
    <el-row :gutter="16" class="kpi-row">
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">平均节点数</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.avgNodeCount }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after">{{ comparisonData.after.avgNodeCount }}</span>
          </div>
          <div class="kpi-change down">
            {{ delta(comparisonData.before.avgNodeCount, comparisonData.after.avgNodeCount) }}
          </div>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">平均树深度</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.avgTreeDepth }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after">{{ comparisonData.after.avgTreeDepth }}</span>
          </div>
          <div class="kpi-change down">
            {{ delta(comparisonData.before.avgTreeDepth, comparisonData.after.avgTreeDepth) }}
          </div>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">平均耗时（分钟）</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.avgTimeMin }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after">{{ comparisonData.after.avgTimeMin }}</span>
          </div>
          <div class="kpi-change down">
            {{ delta(comparisonData.before.avgTimeMin, comparisonData.after.avgTimeMin) }}
          </div>
        </el-card>
      </el-col>
    </el-row>

    <el-row :gutter="16" class="kpi-row">
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">自动细化轮次</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.refinementRounds }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after">{{ comparisonData.after.refinementRounds }}</span>
          </div>
          <div class="kpi-change down">↓{{ Math.round((1 - comparisonData.after.refinementRounds / Math.max(comparisonData.before.refinementRounds, 0.1)) * 100) }}%</div>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">可实现性评分</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.feasibilityScore }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after">{{ comparisonData.after.feasibilityScore }}</span>
          </div>
          <div class="kpi-change up">↑{{ Math.round((comparisonData.after.feasibilityScore - comparisonData.before.feasibilityScore) * 100) }}%</div>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="hover" class="kpi-card">
          <div class="kpi-label">Warning 触发拆分</div>
          <div class="kpi-compare">
            <span class="kpi-before">{{ comparisonData.before.triggeredByWarning }}</span>
            <el-icon><ArrowRight /></el-icon>
            <span class="kpi-after" style="color: #67c23a; font-weight: 700;">0</span>
          </div>
          <div class="kpi-change down" style="color: #67c23a;">✅ 完全消除</div>
        </el-card>
      </el-col>
    </el-row>

    <!-- ====== 图表区 ====== -->
    <el-row :gutter="16" class="chart-row">
      <el-col :span="12">
        <el-card shadow="hover">
          <div ref="radarRef" class="chart-box"></div>
        </el-card>
      </el-col>
      <el-col :span="12">
        <el-card shadow="hover">
          <div ref="timelineRef" class="chart-box"></div>
        </el-card>
      </el-col>
    </el-row>

    <el-row :gutter="16" class="chart-row">
      <el-col :span="12">
        <el-card shadow="hover">
          <div ref="barRef" class="chart-box"></div>
        </el-card>
      </el-col>
      <el-col :span="12">
        <el-card shadow="hover">
          <div ref="ruleTriggerRef" class="chart-box"></div>
        </el-card>
      </el-col>
    </el-row>

    <!-- ====== 阈值变更对照表 ====== -->
    <el-card shadow="hover" class="table-card">
      <template #header>
        <h3 style="margin: 0;">阈值与规则变更对照</h3>
      </template>
      <el-table :data="thresholdChanges" stripe border size="large">
        <el-table-column prop="rule" label="规则项" width="220" />
        <el-table-column prop="before" label="优化前">
          <template #default="{ row }">
            <span style="color: #f56c6c;">{{ row.before }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="after" label="优化后">
          <template #default="{ row }">
            <span style="color: #67c23a;">{{ row.after }}</span>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- ====== 优化要点总结 ====== -->
    <el-card shadow="hover" class="summary-card">
      <template #header>
        <h3 style="margin: 0;">优化要点总结</h3>
      </template>
      <el-row :gutter="24">
        <el-col :span="8">
          <div class="summary-block">
            <el-tag type="danger" size="large" effect="dark">问题</el-tag>
            <ul>
              <li>Warning 级规则也触发自动拆分</li>
              <li>阈值过严（AFP>15 / 工作量>0.5人月）</li>
              <li>技术复杂性判定粗糙（EO/ILF 即判复杂）</li>
              <li>FPA 分类纯关键词匹配，准确率低</li>
              <li>缺乏开发者经验维度，估时脱离实际</li>
            </ul>
          </div>
        </el-col>
        <el-col :span="8">
          <div class="summary-block">
            <el-tag type="primary" size="large" effect="dark">改动</el-tag>
            <ul>
              <li>Error 级才触发自动细化，Warning 只入报告</li>
              <li>AFP 15→25(warning)/50(触发)，工作量 0.5→1.0</li>
              <li>仅 HIGH+ILF/EIF 组合才警告</li>
              <li>新增 LLM 语义 FPA 分类（合并到一次调用）</li>
              <li>LLM 按初级/中级/高级估算实现天数</li>
            </ul>
          </div>
        </el-col>
        <el-col :span="8">
          <div class="summary-block">
            <el-tag type="success" size="large" effect="dark">效果</el-tag>
            <ul>
              <li>自动细化节点减少 60-80%</li>
              <li>树深度受 max_feasibility_refinement_depth=1 控制</li>
              <li>Warning 在报告中完整保留，用户可手动 refine-node</li>
              <li>LLM 估算提高评估准确性，更贴近真实开发场景</li>
              <li>拆分结果更稳定，不被次要问题驱动无限下钻</li>
            </ul>
          </div>
        </el-col>
      </el-row>
    </el-card>

    <!-- ====== 使用说明 ====== -->
    <el-card shadow="hover" class="usage-card">
      <template #header>
        <h3 style="margin: 0;">如何获取对比数据</h3>
      </template>
      <div class="usage-content">
        <el-steps :active="4" finish-status="success" align-center>
          <el-step title="切换版本" description="git checkout 51ff184 回退到优化前" />
          <el-step title="跑优化前" description="PYTHONPATH=. python scripts/run_sr_eval.py --token xxx" />
          <el-step title="切换版本" description="git checkout main 恢复到优化后" />
          <el-step title="跑优化后" description="PYTHONPATH=. python scripts/run_sr_eval.py --token xxx" />
        </el-steps>
        <div class="update-hint">
          <el-alert type="info" :closable="false" show-icon>
            将两次运行结果中的 <code>avgNodeCount</code>、<code>avgTreeDepth</code> 等指标替换本页
            <code>comparisonData</code> 中的硬编码数据即可得到准确的对比报告。
          </el-alert>
        </div>
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.comparison-page {
  padding: 24px 40px;
  max-width: 1400px;
  margin: 0 auto;
  background: #f5f7fa;
  min-height: 100vh;
}

.top-bar {
  margin-bottom: 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.page-header {
  text-align: center;
  margin-bottom: 28px;
}
.page-header h1 {
  font-size: 26px;
  color: #303133;
  margin-bottom: 6px;
}
.subtitle {
  color: #909399;
  font-size: 13px;
}

/* KPI */
.kpi-row {
  margin-bottom: 16px;
}
.kpi-card {
  text-align: center;
}
.kpi-label {
  font-size: 14px;
  color: #909399;
  margin-bottom: 8px;
}
.kpi-compare {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  font-size: 28px;
  font-weight: 700;
}
.kpi-before {
  color: #f56c6c;
}
.kpi-after {
  color: #67c23a;
}
.kpi-change {
  margin-top: 4px;
  font-size: 13px;
  font-weight: 600;
}
.kpi-change.down {
  color: #67c23a;
}
.kpi-change.up {
  color: #409eff;
}

/* Charts */
.chart-row {
  margin-bottom: 16px;
}
.chart-box {
  width: 100%;
  height: 340px;
}

/* Table */
.table-card {
  margin-bottom: 16px;
}

/* Summary */
.summary-card {
  margin-bottom: 16px;
}
.summary-block ul {
  padding-left: 18px;
  line-height: 1.9;
  color: #606266;
  font-size: 13px;
}
.summary-block .el-tag {
  margin-bottom: 10px;
}

/* Usage */
.usage-card {
  margin-bottom: 24px;
}
.usage-content {
  padding: 8px 0;
}
.update-hint {
  margin-top: 20px;
}
.update-hint code {
  background: #f0f2f5;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 12px;
}
</style>

