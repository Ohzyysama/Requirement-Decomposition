<script setup>
import {PieChart, Warning, Document, Pointer} from '@element-plus/icons-vue'

const props = defineProps({
  evaluationData: {
    type: Object,
    default: null
  }
})

// 格式化分数（0-1转换为0-100）
const getFormattedScore = (score) => {
  if (score === undefined || score === null) return 0
  return Math.round(score * 100)
}

// 获取总问题数量
const getTotalIssuesCount = () => {
  const consistencyWarnings = props.evaluationData?.consistency_result?.warnings?.length || 0
  const feasibilityWarnings = props.evaluationData?.feasibility_result?.warnings?.length || 0
  return consistencyWarnings + feasibilityWarnings
}

// 获取通过的规则数量
const getPassedRulesCount = (ruleResults) => {
  if (!ruleResults || !Array.isArray(ruleResults)) return 0
  return ruleResults.filter(rule => rule.passed).length
}

// 获取失败的规则数量
const getFailedRulesCount = (ruleResults) => {
  if (!ruleResults || !Array.isArray(ruleResults)) return 0
  return ruleResults.filter(rule => !rule.passed).length
}

// 获取问题严重性样式类
const getIssueSeverityClass = (issue) => {
  const severityMap = {
    'error': 'severity-error',
    'warning': 'severity-warning',
    'info': 'severity-info'
  }
  return severityMap[issue.severity] || 'severity-info'
}

// 获取评分颜色
const getScoreColor = (score) => {
  if (score >= 80) return '#52c41a' // 绿色
  if (score >= 60) return '#faad14' // 黄色
  return '#ff4d4f' // 红色
}

// 获取风险等级样式类
const getRiskLevelClass = (riskLevel) => {
  const riskMap = {
    'low': 'risk-low',
    'medium': 'risk-medium',
    'high': 'risk-high'
  }
  return riskMap[riskLevel] || 'risk-unknown'
}

// 获取风险等级文本
const getRiskLevelText = (riskLevel) => {
  const riskTextMap = {
    'low': '低',
    'medium': '中',
    'high': '高'
  }
  return riskTextMap[riskLevel] || '未知'
}
</script>

<template>
  <div class="evaluation-report">
    <!-- 报告概览 -->
    <div class="report-overview">
      <h3 class="overview-title">
        <el-icon><PieChart /></el-icon>报告概览
      </h3>
      <div class="overview-grid">
        <div class="overview-item">
          <span class="label">综合评分：</span>
          <span class="value score-overall">{{ getFormattedScore(evaluationData?.overall_score) }}</span>
        </div>
        <div class="overview-item">
          <span class="label">一致性评分：</span>
          <span class="value score-consistency">{{ getFormattedScore(evaluationData?.consistency_score) }}</span>
        </div>
        <div class="overview-item">
          <span class="label">可实现性评分：</span>
          <span class="value score-feasibility">{{ getFormattedScore(evaluationData?.feasibility_score) }}</span>
        </div>
        <div class="overview-item">
          <span class="label">风险等级：</span>
          <span class="value risk-level" :class="getRiskLevelClass(evaluationData?.risk_level)">
            {{ getRiskLevelText(evaluationData?.risk_level) }}
          </span>
        </div>
        <div class="overview-item">
          <span class="label">问题数量：</span>
          <span class="value issue-count">{{ getTotalIssuesCount() }}</span>
        </div>
      </div>
      <div v-if="evaluationData?.summary" class="overview-summary">
        <span class="summary-label">评估摘要：</span>
        <span class="summary-text">{{ evaluationData.summary }}</span>
      </div>
    </div>

    <!-- 问题列表 -->
    <div v-if="getTotalIssuesCount() > 0" class="issues-section">
      <h3 class="section-title">
        <el-icon><Warning /></el-icon>发现的问题 ({{ getTotalIssuesCount() }}个)
      </h3>
      <div class="issues-list">
        <!-- 一致性评估问题 -->
        <div
            v-for="(warning, index) in evaluationData?.consistency_result?.warnings || []"
            :key="`consistency-${warning.rule_id || index}`"
            class="issue-item"
            :class="getIssueSeverityClass(warning)"
        >
          <div class="issue-header">
            <span class="issue-type">{{ warning.category || 'CONSISTENCY' }}</span>
            <span class="issue-source">一致性评估</span>
            <span class="issue-title">{{ warning.rule_name || '一致性检查' }}</span>
          </div>
          <div class="issue-description">{{ warning.description }}</div>
          <div v-if="warning.affected_nodes && warning.affected_nodes.length > 0" class="affected-nodes">
            <span class="nodes-label">影响节点：</span>
            <span class="nodes-list">{{ warning.affected_nodes.join(', ') }}</span>
          </div>
          <div v-if="warning.recommendation" class="issue-recommendation">
            <strong>建议：</strong>{{ warning.recommendation }}
          </div>
        </div>

        <!-- 可实现性评估问题 -->
        <div
            v-for="(warning, index) in evaluationData?.feasibility_result?.warnings || []"
            :key="`feasibility-${warning.rule_id || index}`"
            class="issue-item"
            :class="getIssueSeverityClass(warning)"
        >
          <div class="issue-header">
            <span class="issue-type">{{ warning.category || 'FEASIBILITY' }}</span>
            <span class="issue-source">可实现性评估</span>
            <span class="issue-title">{{ warning.rule_name || '可实现性检查' }}</span>
          </div>
          <div class="issue-description">{{ warning.description }}</div>
          <div v-if="warning.affected_nodes && warning.affected_nodes.length > 0" class="affected-nodes">
            <span class="nodes-label">影响节点：</span>
            <span class="nodes-list">{{ warning.affected_nodes.join(', ') }}</span>
          </div>
          <div v-if="warning.recommendation" class="issue-recommendation">
            <strong>建议：</strong>{{ warning.recommendation }}
          </div>
        </div>
      </div>
    </div>

    <!-- 详细评估结果 -->
    <div class="detailed-evaluation">
      <h3 class="section-title">
        <el-icon><Document /></el-icon>详细评估
      </h3>
      <div class="evaluation-details">
        <!-- 一致性评估 -->
        <div class="evaluation-category">
          <h4 class="category-title">一致性评估</h4>
          <div class="category-content">
            <div class="score-bar">
              <div class="score-label">一致性得分：</div>
              <div class="score-progress">
                <el-progress
                    :percentage="getFormattedScore(evaluationData?.consistency_score)"
                    :show-text="false"
                />
                <span class="score-value">{{ getFormattedScore(evaluationData?.consistency_score) }}</span>
              </div>
            </div>
            <div v-if="evaluationData?.consistency_result" class="category-details">
              <div class="rule-stats">
                <span>检查规则：{{ evaluationData.consistency_result.rule_results?.length || 0 }}个</span>
                <span class="passed">通过：{{ getPassedRulesCount(evaluationData.consistency_result.rule_results) }}个</span>
                <span class="failed">失败：{{ getFailedRulesCount(evaluationData.consistency_result.rule_results) }}个</span>
              </div>
              <div v-if="evaluationData.consistency_result.warnings && evaluationData.consistency_result.warnings.length > 0" class="warnings-count">
                发现警告：{{ evaluationData.consistency_result.warnings.length }}个
              </div>
            </div>
          </div>
        </div>

        <!-- 可实现性评估 -->
        <div class="evaluation-category">
          <h4 class="category-title">可实现性评估</h4>
          <div class="category-content">
            <div class="score-bar">
              <div class="score-label">可实现性得分：</div>
              <div class="score-progress">
                <el-progress
                    :percentage="getFormattedScore(evaluationData?.feasibility_score)"
                    :color="getScoreColor(getFormattedScore(evaluationData?.feasibility_score))"
                    :show-text="false"
                />
                <span class="score-value">{{ getFormattedScore(evaluationData?.feasibility_score) }}</span>
              </div>
            </div>
            <div v-if="evaluationData?.feasibility_result" class="category-details">
              <div class="rule-stats">
                <span>检查规则：{{ evaluationData.feasibility_result.rule_results?.length || 0 }}个</span>
                <span class="passed">通过：{{ getPassedRulesCount(evaluationData.feasibility_result.rule_results) }}个</span>
                <span class="failed">失败：{{ getFailedRulesCount(evaluationData.feasibility_result.rule_results) }}个</span>
              </div>
              <div v-if="evaluationData.feasibility_result.warnings && evaluationData.feasibility_result.warnings.length > 0" class="warnings-count">
                发现警告：{{ evaluationData.feasibility_result.warnings.length }}个
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 推荐建议 -->
    <div v-if="evaluationData?.recommendation" class="recommendations-section">
      <h3 class="section-title">
        <el-icon><Pointer /></el-icon>推荐建议
      </h3>
      <div class="recommendations-list">
        <div class="recommendation-item">
          <span class="rec-text">{{ evaluationData.recommendation }}</span>
        </div>
      </div>
    </div>

    <!-- 空状态 -->
    <div v-if="!evaluationData" class="empty-state">
      <el-empty description="暂无评估数据" />
    </div>
  </div>
</template>



<style scoped>
.evaluation-report {
  height: 100%;
  overflow-y: auto;
  padding: 24px;
}

.report-overview {
  background: #f5f7fa;
  border: 1px solid #e5e6eb;
  border-radius: 8px;
  padding: 20px;
  margin-bottom: 24px;
}

.overview-title {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 0 16px 0;
  font-size: 16px;
  font-weight: 600;
  color: #4e5969;
}

.overview-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 16px;
}

.overview-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.overview-item .label {
  color: #86909c;
  font-size: 14px;
}

.overview-item .value {
  font-weight: 600;
  font-size: 18px;
}

.score-overall {
  color: #1677ff;
}

.score-consistency {
  color: #52c41a;
}

.score-feasibility {
  color: #faad14;
}

.issue-count {
  color: #ff4d4f;
}

.risk-level {
  font-weight: 600;
  font-size: 14px;
  padding: 2px 8px;
  border-radius: 4px;
}

.risk-low {
  background-color: #f6ffed;
  color: #52c41a;
  border: 1px solid #b7eb8f;
}

.risk-medium {
  background-color: #fffbe6;
  color: #faad14;
  border: 1px solid #ffe58f;
}

.risk-high {
  background-color: #fff2f0;
  color: #ff4d4f;
  border: 1px solid #ffccc7;
}

.risk-unknown {
  background-color: #f5f5f5;
  color: #8c8c8c;
  border: 1px solid #d9d9d9;
}

.overview-summary {
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e5e6eb;
}

.summary-label {
  font-weight: 600;
  color: #4e5969;
  font-size: 14px;
}

.summary-text {
  color: #86909c;
  font-size: 14px;
  line-height: 1.5;
  margin-left: 8px;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0 0 16px 0;
  font-size: 16px;
  font-weight: 600;
  color: #4e5969;
}

.issues-section {
  margin-bottom: 24px;
}

.issues-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.issue-item {
  padding: 16px;
  border-radius: 6px;
  border-left: 4px solid #e5e6eb;
}

.issue-item.severity-error {
  border-left-color: #ff4d4f;
  background-color: #fff2f0;
}

.issue-item.severity-warning {
  border-left-color: #faad14;
  background-color: #fffbe6;
}

.issue-item.severity-info {
  border-left-color: #1677ff;
  background-color: #f0f6ff;
}

.issue-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}

.issue-type {
  font-size: 12px;
  padding: 2px 6px;
  border-radius: 3px;
  background-color: rgba(0, 0, 0, 0.1);
}

.issue-source {
  font-size: 12px;
  padding: 2px 6px;
  border-radius: 3px;
  background-color: #e6f7ff;
  color: #1890ff;
  border: 1px solid #91d5ff;
}

.issue-title {
  font-weight: 600;
  color: #4e5969;
}

.issue-description {
  color: #86909c;
  margin-bottom: 8px;
  line-height: 1.5;
}

.affected-nodes {
  font-size: 12px;
  color: #86909c;
}

.nodes-label {
  font-weight: 500;
}

.issue-recommendation {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid #e5e6eb;
  color: #4e5969;
  font-size: 14px;
}

.detailed-evaluation {
  margin-bottom: 24px;
}

.evaluation-details {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.evaluation-category {
  background: white;
  border: 1px solid #e5e6eb;
  border-radius: 6px;
  padding: 16px;
}

.category-title {
  margin: 0 0 12px 0;
  font-size: 14px;
  font-weight: 600;
  color: #4e5969;
}

.category-content {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.score-bar {
  display: flex;
  align-items: center;
  gap: 12px;
}

.score-label {
  min-width: 100px;
  color: #86909c;
  font-size: 14px;
}

.score-progress {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 8px;
}

:deep(.score-progress .el-progress-bar) {
  flex: 1;
}

.score-value {
  min-width: 30px;
  text-align: right;
  font-weight: 600;
  color: #4e5969;
}

.category-details {
  color: #86909c;
  font-size: 14px;
  line-height: 1.5;
}

.rule-stats {
  display: flex;
  gap: 16px;
  margin-bottom: 8px;
  font-size: 13px;
}

.rule-stats .passed {
  color: #52c41a;
  font-weight: 500;
}

.rule-stats .failed {
  color: #ff4d4f;
  font-weight: 500;
}

.warnings-count {
  font-size: 13px;
  color: #faad14;
  font-weight: 500;
}

.recommendations-section {
  margin-bottom: 24px;
}

.recommendations-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.recommendation-item {
  padding: 12px;
  background: #f0f6ff;
  border-radius: 4px;
  border-left: 3px solid #1677ff;
}

.rec-text {
  color: #4e5969;
  line-height: 1.5;
}

.empty-state {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>