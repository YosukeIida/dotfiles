import type { Register } from 'claude-code'

// Herdr app の agents-tree が `~/.config/herdr-app/agent-view/<端末>.json` に書いた要求を読み、
// 押された subagent の画面へ切り替える。hc の端末の中でだけコマンドを登録する。
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    if (await $.env.get('HC_TERMINAL_ID')) {
      await $.command.register({
        name: 'herdr-agent-view',
        description: 'Open the subagent selected in Herdr',
        immediate: true,
      })
    }
    return result
  })

  on('command.run', { command: 'herdr-agent-view' }, async $ => {
    const home = await $.env.get('HOME')
    const terminal = await $.env.get('HC_TERMINAL_ID')
    if (!home || !terminal) return {}
    try {
      const text = (await $.fs.read(`${home}/.config/herdr-app/agent-view/${terminal}.json`)) as string
      const request = JSON.parse(text)
      if (request.expiresAt < (await $.clock.now())) return {}
      const shown = await $.ui.view(request.agentId ? { agentId: request.agentId } : {})
      if (shown.deny) await $.ui.toast(shown.deny)
    } catch {}
    return {}
  })
}
