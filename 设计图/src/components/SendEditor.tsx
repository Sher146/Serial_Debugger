import { useState, useRef, useEffect } from "react";
import type { DisplayFormat, LineEnding } from "../types";

interface Props {
  connected: boolean;
  sendMode: DisplayFormat;
  lineEnding: LineEnding;
  autoSendEnabled: boolean;
  autoSendInterval: number;
  onSendModeChange: (m: DisplayFormat) => void;
  onLineEndingChange: (e: LineEnding) => void;
  onAutoSendChange: (enabled: boolean, interval: number) => void;
  onSend: (text: string) => void;
}

const LINE_ENDING_LABELS: Record<LineEnding, string> = {
  none: "无",
  cr: "CR",
  lf: "LF",
  crlf: "CRLF",
};

function isValidHex(s: string): boolean {
  const clean = s.replace(/\s/g, "");
  return clean.length % 2 === 0 && /^[0-9a-fA-F]*$/.test(clean);
}

export default function SendEditor({
  connected,
  sendMode,
  lineEnding,
  autoSendEnabled,
  autoSendInterval,
  onSendModeChange,
  onLineEndingChange,
  onAutoSendChange,
  onSend,
}: Props) {
  const [text, setText] = useState("");
  const [hexError, setHexError] = useState("");
  const [intervalText, setIntervalText] = useState(String(autoSendInterval));
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    setIntervalText(String(autoSendInterval));
  }, [autoSendInterval]);

  function validate(val: string): string {
    if (sendMode === "hex" && val.trim()) {
      if (!isValidHex(val)) {
        const clean = val.replace(/\s/g, "");
        if (clean.length % 2 !== 0) return "字节数为奇数，HEX 字符串长度须为偶数";
        return "包含非法字符，仅允许 0-9 A-F";
      }
    }
    return "";
  }

  function handleTextChange(val: string) {
    setText(val);
    setHexError(validate(val));
  }

  function handleSend() {
    if (!connected || !text.trim() || hexError) return;
    onSend(text);
    setText("");
    setHexError("");
    inputRef.current?.focus();
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      handleSend();
    }
  }

  function handleIntervalChange(val: string) {
    setIntervalText(val);
    const n = parseInt(val, 10);
    if (!isNaN(n) && n >= 100) {
      onAutoSendChange(autoSendEnabled, n);
    }
  }

  const canSend = connected && text.trim().length > 0 && !hexError;

  return (
    <div
      style={{
        background: "var(--panel)",
        borderTop: "1px solid var(--border)",
        flexShrink: 0,
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Toolbar row */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          padding: "6px 12px",
          borderBottom: "1px solid var(--border)",
        }}
      >
        <span style={{ color: "var(--muted)", fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: "uppercase", marginRight: 4 }}>
          发送
        </span>

        <div style={{ width: 1, height: 14, background: "var(--border)", margin: "0 2px" }} />

        {/* Mode toggle */}
        <div
          style={{
            display: "flex",
            background: "#0d0e10",
            border: "1px solid var(--border)",
            borderRadius: 5,
            overflow: "hidden",
          }}
        >
          {(["ascii", "hex"] as DisplayFormat[]).map((m) => (
            <button
              key={m}
              onClick={() => {
                onSendModeChange(m);
                setHexError(validate(text));
              }}
              style={{
                background: sendMode === m ? "var(--accent)" : "transparent",
                border: "none",
                color: sendMode === m ? "#fff" : "var(--muted)",
                fontSize: 11,
                fontFamily: "var(--font-mono)",
                fontWeight: 500,
                padding: "2px 8px",
                cursor: "pointer",
                textTransform: "uppercase",
                letterSpacing: 0.5,
                transition: "background 0.15s",
              }}
            >
              {m}
            </button>
          ))}
        </div>

        {/* Line ending */}
        <label style={{ color: "var(--muted)", fontSize: 12, flexShrink: 0 }}>行结束符</label>
        <select
          value={lineEnding}
          onChange={(e) => onLineEndingChange(e.target.value as LineEnding)}
          style={{
            background: "#0d0e10",
            border: "1px solid var(--border)",
            borderRadius: 5,
            color: "var(--text)",
            fontSize: 11,
            fontFamily: "var(--font-mono)",
            padding: "2px 6px",
            outline: "none",
            cursor: "pointer",
          }}
        >
          {(Object.keys(LINE_ENDING_LABELS) as LineEnding[]).map((k) => (
            <option key={k} value={k} style={{ background: "#1a1c1f" }}>
              {LINE_ENDING_LABELS[k]}
            </option>
          ))}
        </select>

        <div style={{ width: 1, height: 14, background: "var(--border)", margin: "0 2px" }} />

        {/* Auto send */}
        <label
          style={{
            display: "flex",
            alignItems: "center",
            gap: 5,
            color: autoSendEnabled ? "var(--orange)" : "var(--muted)",
            fontSize: 12,
            cursor: "pointer",
            userSelect: "none",
          }}
        >
          <input
            type="checkbox"
            checked={autoSendEnabled}
            onChange={(e) => onAutoSendChange(e.target.checked, autoSendInterval)}
            disabled={!connected}
            style={{ accentColor: "var(--orange)", cursor: "pointer" }}
          />
          自动发送
        </label>

        {autoSendEnabled && (
          <>
            <input
              type="number"
              value={intervalText}
              onChange={(e) => handleIntervalChange(e.target.value)}
              min={100}
              step={100}
              style={{
                background: "#0d0e10",
                border: "1px solid var(--border)",
                borderRadius: 5,
                color: "var(--orange)",
                fontSize: 11,
                fontFamily: "var(--font-mono)",
                padding: "2px 5px",
                width: 64,
                outline: "none",
                textAlign: "right",
              }}
            />
            <span style={{ color: "var(--muted)", fontSize: 11 }}>ms</span>
          </>
        )}

        {autoSendEnabled && (
          <span
            style={{
              display: "flex",
              alignItems: "center",
              gap: 4,
              fontSize: 11,
              color: "var(--orange)",
              background: "var(--orange-weak)",
              borderRadius: 4,
              padding: "1px 6px",
            }}
          >
            <span
              style={{
                width: 5,
                height: 5,
                borderRadius: "50%",
                background: "var(--orange)",
                animation: "pulse 1s infinite",
              }}
            />
            运行中
          </span>
        )}
      </div>

      {/* Input area */}
      <div style={{ display: "flex", gap: 0, alignItems: "stretch", minHeight: 72 }}>
        <textarea
          ref={inputRef}
          value={text}
          onChange={(e) => handleTextChange(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={!connected}
          placeholder={
            connected
              ? sendMode === "hex"
                ? "输入十六进制数据，例如 55 AA 01 00…"
                : "输入 ASCII 数据，⌘↩ 发送…"
              : "请先连接串口"
          }
          style={{
            flex: 1,
            background: "var(--console-bg)",
            border: "none",
            borderRight: "1px solid var(--border)",
            color: "var(--text)",
            fontFamily: "var(--font-mono)",
            fontSize: 12,
            padding: "10px 12px",
            resize: "none",
            outline: "none",
            lineHeight: 1.6,
            caretColor: "var(--accent)",
            opacity: connected ? 1 : 0.5,
          }}
        />

        {/* Send button column */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            justifyContent: "center",
            gap: 6,
            padding: "8px 12px",
            background: "var(--panel)",
            flexShrink: 0,
            minWidth: 80,
          }}
        >
          <button
            onClick={handleSend}
            disabled={!canSend}
            style={{
              background: canSend ? "var(--accent)" : "rgba(41,151,255,0.15)",
              border: "none",
              borderRadius: 7,
              color: canSend ? "#fff" : "var(--muted)",
              fontSize: 13,
              fontWeight: 500,
              padding: "7px 0",
              width: "100%",
              cursor: canSend ? "pointer" : "not-allowed",
              transition: "background 0.15s",
            }}
          >
            发送
          </button>
          <span style={{ color: "var(--muted-2)", fontSize: 10, fontFamily: "var(--font-mono)", letterSpacing: -0.2 }}>
            ⌘ ↩
          </span>
        </div>
      </div>

      {/* HEX validation error */}
      {hexError && (
        <div
          style={{
            padding: "4px 12px",
            background: "var(--red-weak)",
            borderTop: "1px solid rgba(255,69,58,0.15)",
            color: "var(--red)",
            fontSize: 11,
            display: "flex",
            alignItems: "center",
            gap: 5,
          }}
        >
          <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
            <circle cx="5.5" cy="5.5" r="4.5" stroke="currentColor" strokeWidth="1.2" />
            <path d="M5.5 3.5v2.5M5.5 7.5v.3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
          </svg>
          {hexError}
        </div>
      )}
    </div>
  );
}
