import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// The last action line of an answer (skill c-bpm-sk-next-step). The Stop hook
// c-bpm-hk-ask-matt-after-clear caches the same line per tmux pane, so the pane
// shows it again right after /clear. LINE_RE and the pane cache path are a
// contract with that hook; tests/bash/c-bpm-hk-ask-matt-after-clear.bats runs
// both parsers over tests/fixtures/next-step-lines.tsv.
const PANE = 'last-recommendation'
const TITLE = 'Last recommendation'
const LINE_RE = /\*\*(Robert, du bist dran|Claude ist dran[^*]*):\*\*.*$/gm
const line = atom({ plugin: 'c-bpm-md-last-recommendation', key: 'line' } as const, '', { shape: 'line-1' })

const lastLine = (text: string): string => {
  const all = text.match(LINE_RE)
  return all?.[all.length - 1]?.trim() ?? ''
}

// What was recommended last here: the pane's cache of the Stop hook, else the
// mod's own store per directory. /clear empties $.state without a new
// session.start, so the pane falls back to this whenever its value is empty.
const saved = async ($: EngineInterface): Promise<string> => {
  const pane = await $.env.get('TMUX_PANE')
  const home = await $.env.get('HOME')
  if (pane && home) {
    const file = `${home}/.cache/c-bpm-next-step/pane-${pane.replace(/[^A-Za-z0-9]/g, '')}`
    const found = lastLine(await $.fs.read(file).catch(() => ''))
    if (found) return found
  }
  return String((await $.store.get(`cwd:${$.session.cwd()}`)) ?? '')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'last-recommendation', description: 'Open the pane with the last recommended next step' })
    void $.ui.open({ id: PANE, title: TITLE })
    return next(e)
  })

  on('command.run', { command: 'last-recommendation' }, async $ => {
    await $.ui.open({ id: PANE, title: TITLE })
    return { text: 'Pane "Last recommendation" opened.' }
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId) {
      const found = lastLine(e.answer)
      if (found) {
        await update($, line, () => found)
        await $.store.set(`cwd:${$.session.cwd()}`, found)
      }
    }
    return done
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const text = (await read($, line)) || (await saved($))
    if (!text) return <Text dimColor>No recommendation yet.</Text>
    const m = text.match(/^\*\*([^*]+):\*\*\s*(.*)$/)
    const who = m?.[1] ?? ''
    const rest = (m?.[2] ?? text).replace(/\*\*/g, '')
    const [step, why] = rest.split(/\s(?=ask-matt |Grund: )/)
    return (
      <Box flexDirection="column">
        {who && <Text bold color={who.startsWith('Robert') ? 'yellow' : 'green'}>{who}</Text>}
        <Text>{step}</Text>
        {why && <Text dimColor>{why}</Text>}
      </Box>
    )
  })
}
