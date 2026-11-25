import type { Register } from 'claude-code'

const LIMIT = 8

export const register: Register = on => {
  // 行頭の / は engine 自身が語の先頭で絞った候補を出し、文中でも名前の先頭の一致は engine が出す。
  // 重ねると同じ行が 2 度出るので、文中で先頭が一致しない名前だけを足す。
  on('prompt.autocomplete', { token: /^\/./ }, async ($, e, next) => {
    const prev = await next(e)
    if (e.start === 0) return prev
    const q = e.token.slice(1).toLowerCase()
    const hits = (await $.command.list())
      .filter(c => {
        const n = c.name.toLowerCase()
        return n.includes(q) && !n.startsWith(q)
      })
      .slice(0, LIMIT)
      .map(c => ({ text: `/${c.name}`, description: c.description }))
    return { suggestions: [...prev.suggestions, ...hits] }
  })
}
