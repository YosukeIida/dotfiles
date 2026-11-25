import type { Register } from 'claude-code'

const LIMIT = 8

export const register: Register = on => {
  // 行頭の / は engine 自身が語の先頭で絞った候補を出すので、重ねると同じ行が 2 度出る。
  on('prompt.autocomplete', { token: /^\/./ }, async ($, e, next) => {
    const prev = await next(e)
    if (e.start === 0) return prev
    const q = e.token.slice(1).toLowerCase()
    const hits = (await $.command.list())
      .filter(c => c.name.toLowerCase().includes(q))
      .sort((a, b) => Number(!a.name.toLowerCase().startsWith(q)) - Number(!b.name.toLowerCase().startsWith(q)))
      .slice(0, LIMIT)
      .map(c => ({ text: `/${c.name}`, description: c.description }))
    return { suggestions: [...prev.suggestions, ...hits] }
  })
}
