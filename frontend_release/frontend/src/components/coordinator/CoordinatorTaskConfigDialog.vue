<script setup>
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { ArrowDown, ArrowRight } from '@element-plus/icons-vue'
import chatAPI from '@/api/chat'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
  /** 写入 POST /coordinator/start 的 config 片段（省略键即后端默认） */
  config: {
    type: Object,
    default: () => ({}),
  },
})

const emit = defineEmits(['update:modelValue', 'update:config'])

const loading = ref(false)
const loadError = ref('')
const catalog = ref(null)
/** 已展开的组 key（可多选并存） */
const expandedGroupKeys = ref(new Set())

function isGroupExpanded(key) {
  return expandedGroupKeys.value.has(key)
}

function close() {
  emit('update:modelValue', false)
}

function emitConfig(next) {
  emit('update:config', { ...next })
}

function groupsList() {
  const g = catalog.value?.groups
  return Array.isArray(g) ? g : []
}

function defaultOptionForGroup(group) {
  const opts = group?.options
  if (!Array.isArray(opts)) return null
  const byFlag = opts.find((o) => o?.is_default === true)
  if (byFlag) return byFlag
  const dv = group?.default_value
  const byVal = opts.find((o) => o && Object.is(o.value, dv))
  return byVal || opts[0] || null
}

function keyIsOmitted(key) {
  return !Object.prototype.hasOwnProperty.call(props.config || {}, key)
}

function effectiveValue(group) {
  const key = group?.key
  if (!key) return undefined
  if (!keyIsOmitted(key)) {
    return props.config[key]
  }
  const defOpt = defaultOptionForGroup(group)
  return defOpt?.value ?? group?.default_value
}

/** 收起状态下列头展示的当前选项文案 */
function selectionPreview(group) {
  const opts = group?.options
  if (!Array.isArray(opts)) return ''
  const ev = effectiveValue(group)
  const hit = opts.find((o) => o && Object.is(o.value, ev))
  return hit?.label ? String(hit.label) : String(ev ?? '')
}

function setGroupValue(group, rawValue, { omit = false } = {}) {
  const key = group?.key
  if (!key) return
  const next = { ...(props.config || {}) }
  if (omit) {
    delete next[key]
  } else {
    next[key] = rawValue
  }
  emitConfig(next)
}

function onSelectPreset(group, opt) {
  const omit =
    opt?.is_default === true ||
    (group.omit_means_default === true &&
      Object.is(opt?.value, group.default_value))

  if (omit) {
    setGroupValue(group, undefined, { omit: true })
    return
  }
  setGroupValue(group, opt.value)
}

function onRadioGroupChange(group, val) {
  const opt = Array.isArray(group.options)
    ? group.options.find((o) => o && Object.is(o.value, val))
    : null
  if (opt) {
    onSelectPreset(group, opt)
  }
}

function toggleAccordion(key) {
  const next = new Set(expandedGroupKeys.value)
  if (next.has(key)) next.delete(key)
  else next.add(key)
  expandedGroupKeys.value = next
}

function resetAllDefaults() {
  emitConfig({})
}

async function loadCatalog() {
  loading.value = true
  loadError.value = ''
  const res = await chatAPI.getCoordinatorTaskChoiceGroups()
  loading.value = false
  if (!res.success) {
    loadError.value = res.message || '加载失败'
    catalog.value = null
    return
  }
  catalog.value = res.data
}

watch(
  () => props.modelValue,
  (open) => {
    if (open) {
      expandedGroupKeys.value = new Set()
      void loadCatalog()
    }
  }
)

function copyHint() {
  const hint = catalog.value?.usage_hint
  if (typeof hint === 'string' && hint.trim()) {
    navigator.clipboard?.writeText(hint.trim()).then(
      () => ElMessage.success('已复制说明'),
      () => {}
    )
  }
}
</script>

<template>
  <el-dialog
    :model-value="modelValue"
    title="解析任务编排配置"
    width="min(960px, 94vw)"
    destroy-on-close
    class="coord-task-config-dialog"
    align-center
    @update:model-value="emit('update:modelValue', $event)"
  >
    <div v-if="loading" class="state-block muted">加载配置项…</div>
    <div v-else-if="loadError" class="state-block error">{{ loadError }}</div>
    <template v-else-if="catalog">
      <div v-if="catalog.usage_hint" class="usage-hint-row">
        <span class="usage-hint-text">{{ catalog.usage_hint }}</span>
        <el-button link type="primary" size="small" @click="copyHint">复制说明</el-button>
      </div>

      <div class="accordion-horizontal">
        <div
          v-for="group in groupsList()"
          :key="group.key"
          class="accordion-column"
          :class="{ 'is-expanded': isGroupExpanded(group.key) }"
        >
          <button
            type="button"
            class="accordion-trigger"
            :aria-expanded="isGroupExpanded(group.key)"
            @click="toggleAccordion(group.key)"
          >
            <span class="accordion-trigger-main">
              <el-icon class="accordion-chevron">
                <ArrowDown v-if="isGroupExpanded(group.key)" />
                <ArrowRight v-else />
              </el-icon>
              <span class="accordion-title">{{ group.title }}</span>
            </span>
            <span v-if="!isGroupExpanded(group.key)" class="accordion-preview">
              {{ selectionPreview(group) }}
            </span>
          </button>

          <div v-show="isGroupExpanded(group.key)" class="accordion-panel">
            <p class="group-summary">{{ group.summary }}</p>
            <el-radio-group
              class="option-list"
              :model-value="effectiveValue(group)"
              @change="(v) => onRadioGroupChange(group, v)"
            >
              <div v-for="(opt, idx) in group.options || []" :key="idx" class="option-row">
                <el-radio :value="opt.value">
                  <span class="opt-label">{{ opt.label }}</span>
                  <span v-if="opt.description" class="opt-desc">{{ opt.description }}</span>
                </el-radio>
              </div>
            </el-radio-group>
          </div>
        </div>
      </div>

      <div class="dialog-actions-inner">
        <el-button text type="primary" @click="resetAllDefaults">恢复全部默认（不传键）</el-button>
      </div>
    </template>

    <template #footer>
      <el-button @click="close">关闭</el-button>
    </template>
  </el-dialog>
</template>

<style scoped>
.state-block {
  padding: 12px 0;
  font-size: 14px;
}
.state-block.muted {
  color: #86909c;
}
.state-block.error {
  color: #f53f3f;
}
.usage-hint-row {
  margin: 0 0 14px;
  padding: 10px 12px;
  background: #f7f8fa;
  border-radius: 8px;
  font-size: 13px;
  color: #4e5969;
  line-height: 1.45;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.usage-hint-text {
  flex: 1;
  min-width: 0;
}
.accordion-horizontal {
  display: flex;
  flex-direction: row;
  align-items: stretch;
  gap: 12px;
  min-height: 120px;
}
.accordion-column {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  border: 1px solid #e5e6eb;
  border-radius: 10px;
  background: #fff;
  overflow: hidden;
}
/** 横向多列：各列可独立展开；多列同时展开时保持等分宽度 */
.accordion-column.is-expanded {
  box-shadow: 0 0 0 1px rgba(22, 119, 255, 0.2);
}
.accordion-trigger {
  width: 100%;
  margin: 0;
  padding: 12px 10px;
  border: none;
  background: #fafafa;
  cursor: pointer;
  text-align: left;
  font: inherit;
  color: #1d2129;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 6px;
  transition: background 0.15s;
}
.accordion-trigger:hover {
  background: #f0f1f3;
}
.accordion-column.is-expanded .accordion-trigger {
  background: rgba(22, 119, 255, 0.06);
  border-bottom: 1px solid #e5e6eb;
}
.accordion-trigger-main {
  display: flex;
  align-items: flex-start;
  gap: 6px;
}
.accordion-chevron {
  flex-shrink: 0;
  margin-top: 2px;
  font-size: 14px;
  color: #86909c;
}
.accordion-title {
  font-weight: 600;
  font-size: 14px;
  line-height: 1.35;
}
.accordion-preview {
  font-size: 12px;
  color: #1677ff;
  padding-left: 22px;
  line-height: 1.3;
  word-break: break-word;
}
.accordion-panel {
  flex: 1;
  padding: 12px 10px 14px;
  max-height: 280px;
  overflow-y: auto;
}
.group-summary {
  margin: 0 0 12px;
  font-size: 12px;
  color: #86909c;
  line-height: 1.45;
}
.option-list {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
}
.option-row {
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid #ebeef5;
  transition: border-color 0.15s, background 0.15s;
}
.option-row:hover {
  background: #f7f8fa;
}
.option-row :deep(.el-radio) {
  width: 100%;
  height: auto;
  align-items: flex-start;
  margin-right: 0;
  white-space: normal;
}
.option-row :deep(.el-radio__label) {
  display: flex;
  flex-direction: column;
  gap: 4px;
  line-height: 1.4;
}
.opt-label {
  font-size: 13px;
  color: #1d2129;
}
.opt-desc {
  font-size: 12px;
  color: #86909c;
}
.dialog-actions-inner {
  margin-top: 14px;
}

@media (max-width: 720px) {
  .accordion-horizontal {
    flex-direction: column;
    min-height: 0;
  }
  .accordion-column.is-expanded {
    flex: 1;
  }
  .accordion-panel {
    max-height: 240px;
  }
}
</style>
