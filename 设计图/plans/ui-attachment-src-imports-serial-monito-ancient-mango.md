# Plan: Serial Monitor UI — 串口调试助手

## Context

The user has provided a detailed UI design spec (`src/imports/Serial_Monitor_UI_____V1.0.html`) for a macOS-style serial port debugging assistant. The current `App.tsx` is a bare placeholder with an animated dot-grid background. The goal is to replace it with a fully functional serial monitor UI in React + Tailwind CSS v4 — capturing the professional "engineering tool" aesthetic described in the spec, adapted for the web.

## Aesthetic Stance

**Data-dense terminal tool.** Dark background, maximum readability, precision type hierarchy:
- Ground: near-black `#0d0e10` page, `#141517` panels, `#0a0b0d` console area
- Accent Blue `#2997ff` (primary actions), Green `#30d158` (connected/RX), Orange `#ff9f0a` (attention), Red `#ff453a` (error/TX send fail)
- **Fonts**: Inter (UI labels, 13–14px) + JetBrains Mono (console data, 12px) via Google Fonts CSS2 `@import`
- Borders: hairline `rgba(255,255,255,0.08)`, no shadows
- Radius: 6px components, 10px panels

## Layout

```
┌──────────────────────────────────────────────────────┐
│  TOOLBAR: Port | Baud | 8N1 | ● Status | Connect btn │
├───────────────────────────────────┬──────────────────┤
│  RECEIVE CONSOLE (flex-grow)      │  PRESET PANEL    │
│  12:04:21.326  RX  55 AA 01 00    │  ─ Presets ─     │
│  12:04:22.041  TX  AT+RST\r\n     │  ☑ 查询状态       │
│  12:04:22.512  RX  ready          │  ☑ 重启设备       │
│                                   │  ○ 读取版本       │
├───────────────────────────────────│──────────────────┤
│  SEND AREA                        │  间隔 1000ms      │
│  [ASCII│HEX] [input ............] │  [开始循环]       │
│  行结束符: CRLF  |  自动发送: 关   │                   │
├───────────────────────────────────┴──────────────────┤
│  STATUS BAR: port | baud | RX:1024B TX:64B | 未记录  │
└──────────────────────────────────────────────────────┘
```

## Files to Create / Modify

### Modify
- **`src/index.css`** — Add Google Fonts `@import` (Inter, JetBrains Mono) before existing Tailwind import. Add CSS custom properties for color tokens, scrollbar hiding.
- **`src/App.tsx`** — Full replacement with the serial monitor shell, state management (connection state, log entries, presets, settings), and component composition.

### Create
- **`src/components/ConnectionToolbar.tsx`** — Port selector dropdown, baud rate picker, 8N1 params badge, advanced-params popover trigger, connection status badge (gray/orange/green/red), primary connect/disconnect button.
- **`src/components/ReceiveConsole.tsx`** — Scrollable log area with `RX`/`TX` tagged rows (monospace), toolbar row with Pause, Clear, ASCII/HEX toggle, Timestamp toggle, Auto-scroll toggle. "Return to latest" floating button when scrolled up.
- **`src/components/SendEditor.tsx`** — ASCII/HEX mode toggle, line-ending selector (None/CR/LF/CRLF), monospace text input, Send button (⌘↩), auto-send toggle with interval.
- **`src/components/PresetInspector.tsx`** — Preset list with enable checkboxes, single-send buttons, edit/delete, loop interval input, Start/Stop loop button.
- **`src/components/StatusBar.tsx`** — Port + baud summary, RX/TX byte counters, log status indicator, last-error display.
- **`src/components/AdvancedParamsPopover.tsx`** — Data bits, parity, stop bits, flow control selectors in a popover overlay.
- **`src/components/PresetEditModal.tsx`** — Sheet/modal for creating/editing presets (name, content, ASCII/HEX, enabled, note). Real-time HEX validation.

## State Architecture (in App.tsx)

```ts
// Connection
connectionState: 'disconnected' | 'connecting' | 'connected' | 'error'
selectedPort: string
baudRate: number
dataParams: { dataBits: 8|7, parity: 'none'|'even'|'odd', stopBits: 1|2, flow: 'none'|'hardware' }

// Console
logEntries: Array<{ id, timestamp, direction: 'RX'|'TX', data: string, format: 'ascii'|'hex' }>
displayFormat: 'ascii' | 'hex'
showTimestamps: boolean
autoScroll: boolean
isPaused: boolean

// Send
sendMode: 'ascii' | 'hex'
lineEnding: 'none' | 'cr' | 'lf' | 'crlf'
sendText: string
autoSendEnabled: boolean
autoSendInterval: number

// Presets
presets: Array<{ id, name, content, mode, enabled, note }>
loopRunning: boolean
loopInterval: number

// Stats
rxBytes: number
txBytes: number
logStatus: 'inactive' | 'recording'
```

## Simulated Data

The app will simulate live serial data with `setInterval` when connected, generating realistic RX entries (hex bytes, AT command responses). This makes the UI feel real without actual Web Serial API integration. The simulation will be toggleable.

## Key Interactions to Implement

1. Connect/Disconnect toggle with state machine (disconnected → connecting → connected, with 1.5s simulated delay)
2. Auto-scroll: pause when user scrolls up, resume when reaching bottom, show "↓ Return to latest" FAB
3. Pause display: freeze console rendering, continue accepting data in buffer, resume shows buffered entries
4. Send with ⌘+Enter keyboard shortcut
5. HEX validation in send editor and preset edit form
6. Preset loop with configurable interval
7. Advanced params popover (locked when connected)
8. Preset add/edit modal with validation
9. Clear console (instant, no confirm)
10. ASCII/HEX display format toggle (re-renders existing entries)

## CSS Strategy

Use Tailwind utility classes throughout. Custom tokens via `@theme` in `src/index.css` or inline CSS variables for the color palette. Dark-first design (no light mode variant needed).

## Fonts

Add to top of `src/index.css` before `@import 'tailwindcss'`:
```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap');
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap');
```

## Verification

1. Preview in the Figma Make canvas — check that all 5 main regions render correctly
2. Click Connect → simulate connecting state (1.5s) → connected state with live RX entries
3. Type in send area, press ⌘+Enter → TX entry appears in console
4. Scroll up in console → "Return to latest" button appears → click → auto-scrolls down
5. Toggle Pause → orange banner appears, data continues buffering
6. Edit a preset → modal opens, save → updated in list
7. Start loop → status bar shows loop active, entries fire at interval
8. Test advanced params popover opens/closes, fields lock when connected
