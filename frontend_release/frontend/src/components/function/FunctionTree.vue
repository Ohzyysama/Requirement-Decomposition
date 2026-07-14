
<script setup>
import { ref, watch, computed } from 'vue'
import { Search, ArrowDown, ArrowUp } from '@element-plus/icons-vue'
import FunctionNode from './FunctionNode.vue'

const props = defineProps({
  data: {
    type: Object,
    default: null
  },
  searchable: {
    type: Boolean,
    default: true
  }
})

const emit = defineEmits(['node-click'])

// 响应式数据
const searchKeyword = ref('')
const expandedNodes = ref(new Set())

/** 按节点 id 分段数字排序（如 F-1.2 在 F-1.10 之前） */
function compareFunctionNodeIds(a, b) {
  const sa = typeof a === 'string' ? a : ''
  const sb = typeof b === 'string' ? b : ''
  if (sa === sb) return 0
  if (sa === 'virtual-root') return -1
  if (sb === 'virtual-root') return 1
  return sa.localeCompare(sb, undefined, { numeric: true, sensitivity: 'base' })
}

/** 深拷贝并逐层排序 children，不修改 store 里的原始树 */
function sortFunctionTreeNodes(node) {
  if (!node || typeof node !== 'object') return node
  const raw = Array.isArray(node.children) ? node.children : []
  const sorted = [...raw]
    .sort((c1, c2) => compareFunctionNodeIds(c1?.id, c2?.id))
    .map((ch) => sortFunctionTreeNodes(ch))
  return { ...node, children: sorted }
}

const displayTree = computed(() => {
  if (!props.data) return null
  return sortFunctionTreeNodes(props.data)
})

// 监听搜索关键词变化
watch(searchKeyword, (newVal, oldVal) => {
  if (!props.data) return

  if (newVal) {
    // 搜索时自动展开包含搜索结果的节点
    const expandMatchingNodes = (node) => {
      if (!node) return false

      const matchesSearch = (node.title?.toLowerCase().includes(newVal.toLowerCase()) ||
          node.id?.toLowerCase().includes(newVal.toLowerCase()))

      let shouldExpand = matchesSearch

      // 递归检查子节点
      if (node.children && node.children.length > 0) {
        for (const child of node.children) {
          if (expandMatchingNodes(child)) {
            shouldExpand = true
          }
        }
      }

      // 如果当前节点或子节点匹配搜索，则展开该节点
      if (shouldExpand && node.id) {
        expandedNodes.value.add(node.id)
      }

      return shouldExpand
    }

    // 执行展开逻辑
    expandMatchingNodes(props.data)
  } else {
    // 清空搜索后恢复默认：全部展开
    expandAll()
  }
})

// 方法
const handleNodeClick = (node, evt) => {
  emit('node-click', node, evt)
}

const expandAll = () => {
  const expandNode = (node) => {
    if (node.id) {
      expandedNodes.value.add(node.id)
    }
    if (node.children) {
      node.children.forEach(expandNode)
    }
  }
  if (props.data) {
    expandNode(props.data)
  }
}

const collapseAll = () => {
  expandedNodes.value.clear()
}

const toggleNodeExpand = (nodeId) => {
  if (expandedNodes.value.has(nodeId)) {
    expandedNodes.value.delete(nodeId)
  } else {
    expandedNodes.value.add(nodeId)
  }
}

// 有数据时默认展开全部（含刷新进入会话后）
watch(
  () => props.data,
  (tree) => {
    if (!tree) {
      expandedNodes.value.clear()
      return
    }
    expandAll()
  },
  { immediate: true }
)
</script>

<template>
  <div class="function-tree">
    <!-- 搜索和操作栏 -->
    <div class="tree-header">
      <div class="panel-header">
        <h3>功能点层次结构（功能树）</h3>
      </div>
      <div class="search-box">
        <el-input
            v-model="searchKeyword"
            placeholder="搜索节点"
            size="small"
            :prefix-icon="Search"
            clearable
        />
      </div>
      <div class="tree-actions">
        <el-button type="text" size="small" @click="expandAll">
          <el-icon><ArrowDown /></el-icon>展开全部
        </el-button>
        <el-button type="text" size="small" @click="collapseAll">
          <el-icon><ArrowUp /></el-icon>折叠全部
        </el-button>
      </div>
    </div>

    <!-- 功能树内容 -->
    <div class="tree-content">
      <div v-if="!data" class="empty-state">
        <el-empty description="暂无功能树数据" />
      </div>

      <div v-else class="tree-container">
        <function-node
            :node="displayTree"
            :level="0"
            :search-keyword="searchKeyword"
            :expanded-nodes="expandedNodes"
            @node-click="handleNodeClick"
            @toggle-expand="toggleNodeExpand"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.function-tree {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.tree-header {
  padding: 16px;
  border-bottom: 1px solid #e5e6eb;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.panel-header {
  flex-shrink: 0;
}

.panel-header h3 {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: #4e5969;
}

.search-box {
  flex: 1;
  max-width: 200px;
}

.tree-actions {
  display: flex;
  gap: 8px;
}

.tree-content {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

.empty-state {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.tree-container {
  font-size: 14px;
  line-height: 1.5;
}
</style>