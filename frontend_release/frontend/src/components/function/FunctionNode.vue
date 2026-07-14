<script setup>
import { computed } from 'vue'
import { ArrowDown, ArrowRight } from '@element-plus/icons-vue'

const props = defineProps({
  node: {
    type: Object,
    required: true
  },
  level: {
    type: Number,
    default: 0
  },
  searchKeyword: {
    type: String,
    default: ''
  },
  expandedNodes: {
    type: Set,
    default: () => new Set()
  }
})

const emit = defineEmits(['node-click', 'toggle-expand'])

// 计算属性
const hasChildren = computed(() => {
  return props.node.children && props.node.children.length > 0
})

const isExpanded = computed(() => {
  return props.expandedNodes.has(props.node.id)
})

const isHighlighted = computed(() => {
  if (!props.searchKeyword) return false
  const keyword = props.searchKeyword.toLowerCase()
  return (props.node.title?.toLowerCase().includes(keyword) ||
      props.node.id?.toLowerCase().includes(keyword))
})

// 方法
const handleClick = (e) => {
  emit('node-click', props.node, e)
}

const toggleExpand = () => {
  emit('toggle-expand', props.node.id)
}

const getNodeIcon = (node) => {
  const iconMap = {
    'DOMAIN': 'fa-solid fa-folder',
    'WORKFLOW': 'fa-solid fa-file-lines',
    'CAPABILITY': 'fa-solid fa-file-lines',
    'EXCEPTION': 'fa-solid fa-triangle-exclamation',
    'INTEGRATION': 'fa-solid fa-cloud-arrow-up',
    'SUPPORT': 'fa-solid fa-gear',
    'CONFIG': 'fa-solid fa-sliders',
    'TASK': 'fa-solid fa-list-check'
  }
  return iconMap[node.node_type] || 'fa-solid fa-file'
}

const getNodeIconClass = (node) => {
  const colorMap = {
    'DOMAIN': node.granularity === 'EPIC' ? 'warning' : 'primary',
    'WORKFLOW': 'neutral',
    'CAPABILITY': 'neutral',
    'EXCEPTION': 'warning',
    'INTEGRATION': 'primary',
    'SUPPORT': 'info',
    'CONFIG': 'success',
    'TASK': 'secondary'
  }
  return colorMap[node.node_type] || 'neutral'
}
</script>


<template>
  <div class="function-node" :class="{ 'has-children': hasChildren }">
    <!-- 节点内容 -->
    <div
        class="node-content"
        :style="{ paddingLeft: level * 16 + 'px' }"
        @click="handleClick"
    >
      <!-- 展开/折叠图标 -->
      <span v-if="hasChildren" class="expand-icon" @click.stop="toggleExpand">
        <el-icon :class="{ expanded: isExpanded }">
          <ArrowRight v-if="!isExpanded" />
          <ArrowDown v-else />
        </el-icon>
      </span>
      <span v-else class="expand-placeholder"></span>

      <!-- 节点图标 -->
      <span class="node-icon" :class="getNodeIconClass(node)">
        <i :class="getNodeIcon(node)"></i>
      </span>

      <!-- 节点文本 -->
      <span class="node-text" :class="{ 'search-highlight': isHighlighted }">
        {{ node.title }}
        <span v-if="node.id" class="node-id">({{ node.id }})</span>
      </span>

      <!-- 节点标签 -->
      <span v-if="node.node_type && node.granularity" class="node-tags">
        <span class="type-tag">{{ node.node_type }}</span>
        <span class="level-tag">{{ node.granularity }}</span>
      </span>
    </div>

    <!-- 子节点 -->
    <el-collapse-transition>
      <div v-show="isExpanded && hasChildren" class="children-container">
        <function-node
            v-for="child in node.children"
            :key="child.id"
            :node="child"
            :level="level + 1"
            :search-keyword="searchKeyword"
            :expanded-nodes="expandedNodes"
            @node-click="(n, e) => $emit('node-click', n, e)"
            @toggle-expand="$emit('toggle-expand', $event)"
        />
      </div>
    </el-collapse-transition>
  </div>
</template>


<style scoped>
.function-node {
  margin-bottom: 4px;
}

.node-content {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s;
  min-height: 32px;
}

.node-content:hover {
  background-color: #f5f7fa;
}

.expand-icon {
  width: 16px;
  height: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.2s;
}

.expand-icon.expanded {
  transform: rotate(90deg);
}

.expand-placeholder {
  width: 16px;
  height: 16px;
}

.node-icon {
  font-size: 14px;
  width: 16px;
  text-align: center;
}

.node-icon.warning {
  color: #faad14;
}

.node-icon.primary {
  color: #1677ff;
}

.node-icon.neutral {
  color: #86909c;
}

.node-icon.info {
  color: #13c2c2;
}

.node-icon.success {
  color: #52c41a;
}

.node-icon.secondary {
  color: #8c8c8c;
}

.node-text {
  flex: 1;
  font-weight: 500;
  font-size: 14px;
}

.node-text.search-highlight {
  background-color: #fff566;
  padding: 2px 4px;
  border-radius: 2px;
}

.node-id {
  font-size: 12px;
  color: #8c8c8c;
  margin-left: 4px;
}

.node-desc {
  font-size: 12px;
  color: #8c8c8c;
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.node-tags {
  display: flex;
  gap: 4px;
}

.type-tag, .level-tag {
  font-size: 10px;
  padding: 1px 4px;
  border-radius: 2px;
  background-color: #f5f5f5;
  color: #595959;
}

.children-container {
  margin-left: 16px;
}
</style>