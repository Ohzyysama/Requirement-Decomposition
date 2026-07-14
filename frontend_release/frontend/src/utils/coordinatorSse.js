/**
 * 协调任务 SSE：fetch + 解析命名事件（支持 Bearer；原生 EventSource 不可用）
 * @param {string} streamUrl - 完整 URL
 * @param {Object} options
 * @param {AbortSignal} options.signal
 * @param {(eventName: string, data: object) => void} options.onEvent
 */
export async function consumeCoordinatorSseStream(streamUrl, { signal, onEvent }) {
    const token = typeof localStorage !== 'undefined' ? localStorage.getItem('auth_token') : null

    let res
    try {
        res = await fetch(streamUrl, {
            method: 'GET',
            headers: {
                Accept: 'text/event-stream',
                ...(token ? { Authorization: `Bearer ${token}` } : {}),
            },
            credentials: 'omit',
            signal,
        })
    } catch (e) {
        if (e?.name === 'AbortError') return
        throw e
    }

    if (!res.ok) {
        const text = await res.text().catch(() => '')
        throw new Error(text || `SSE 请求失败 HTTP ${res.status}`)
    }

    const reader = res.body?.getReader()
    if (!reader) {
        throw new Error('SSE：响应无可读流')
    }

    const decoder = new TextDecoder()
    let buffer = ''

    const flushEvent = (rawBlock) => {
        const block = rawBlock.replace(/\r\n/g, '\n').trimEnd()
        if (!block) return

        let eventName = 'message'
        const dataLines = []

        for (const line of block.split('\n')) {
            if (line.startsWith('event:')) {
                eventName = line.slice(6).trim()
            } else if (line.startsWith('data:')) {
                dataLines.push(line.slice(5).replace(/^\s/, ''))
            }
        }

        const dataStr = dataLines.join('\n')
        if (!dataStr) return

        try {
            const data = JSON.parse(dataStr)
            onEvent(eventName, data)
        } catch (e) {
            console.error('SSE JSON 解析失败:', e, dataStr.slice(0, 200))
        }
    }

    try {
        while (true) {
            const { done, value } = await reader.read()
            if (done) break

            buffer += decoder.decode(value, { stream: true })
            buffer = buffer.replace(/\r\n/g, '\n')

            let sep
            while ((sep = buffer.indexOf('\n\n')) !== -1) {
                const chunk = buffer.slice(0, sep)
                buffer = buffer.slice(sep + 2)
                flushEvent(chunk)
            }
        }

        if (buffer.trim()) {
            flushEvent(buffer)
        }
    } catch (e) {
        if (e?.name === 'AbortError') return
        throw e
    } finally {
        reader.releaseLock()
    }
}
