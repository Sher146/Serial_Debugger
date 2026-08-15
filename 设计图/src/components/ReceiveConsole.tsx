import { useEffect, useRef, useState, useCallback } from "react";
import type { LogEntry, DisplayFormat } from "../types";

interface Props {
  entries: LogEntry[];
  displayFormat: DisplayFormat;
  showTimestamps: boolean;
  autoScroll: boolean;
  isPaused: boolean;
  onDisplayFormatChange: (f: DisplayFormat) => void;
  onShowTimestampsChange: (v: boolean) => void;
  onAutoScrollChange: (v: boolean) => void;
  onPause: () => void;
  onResume: () => void;
  onClear: () => void;
}

function formatTimestamp(d: Date) {
  return d.toTimeString().slice(0, 8) + "." + String(d.getMilliseconds()).padStart(3, "0");
}

function renderData(entry: LogEntry, displayFormat: DisplayFormat): string {
  if (displayFormat === "hex") {
    // Convert string to hex bytes
    return entry.raw
      .split("")
      .map((c) => c.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0"))
      .join(" ");
  }
  return entry.raw;
}

export default function ReceiveConsole({
  entries,
  displayFormat,
  showTimestamps,
  autoScroll,
  isPaused,
  onDisplayFormatChange,
  onShowTimestampsChange,
  onAutoScrollChange,
  onPause,
  onResume,
  onClear,
}: Props) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showScrollBtn, setShowScrollBtn] = useState(false);
  const isNearBottom = useRef(true);

  const scrollToBottom = useCallback(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
      setShowScrollBtn(false);
      isNearBottom.current = true;
    }
  }, []);

  // Auto-scroll on new entries
  useEffect(() => {
    if (autoScroll && isNearBottom.current && !isPaused) {
      scrollToBottom();
    }
  }, [entries, autoScroll, isPaused, scrollToBottom]);

  function handleScroll() {
    const el = scrollRef.current;
    if (!el) return;
    const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    const near = distFromBottom < 60;
    isNearBottom.current = near;
    setShowScrollBtn(!near && entries.length > 0);
    if (!near && autoScroll) {
      onAutoScrollChange(false);
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, overflow: "hidden" }}>
      {/* Toolbar */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 6,
          padding: "0 12px",
          height: 36,
          borderBottom: "1px solid var(--border)",
          background: "var(--panel)",
          flexShrink: 0,
        }}
      >
        <span style={{ color: "var(--muted)", fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: "uppercase", marginRight: 4 }}>
          接收记录
        </span>

        <div style={{ width: 1, height: 14, background: "var(--border)", margin: "0 2px" }} />

        {/* Pause / Resume */}
        <ToolBtn
          onClick={isPaused ? onResume : onPause}
          active={isPaused}
          activeColor="var(--orange)"
          title={isPaused ? "恢复显示" : "暂停显示"}
        >
          {isPaused ? (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <path d="M3 2.5l7 3.5-7 3.5V2.5z" fill="currentColor" />
            </svg>
          ) : (
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
              <rect x="2.5" y="2" width="2.5" height="8" rx="1" fill="currentColor" />
              <rect x="7" y="2" width="2.5" height="8" rx="1" fill="currentColor" />
            </svg>
          )}
          {isPaused ? "恢复" : "暂停"}
        </ToolBtn>

        {/* Clear */}
        <ToolBtn onClick={onClear} title="清空记录">
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path d="M2 3h8M5 3V2h2v1M4 3l.5 7h3L8 3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          清空
        </ToolBtn>

        <div style={{ width: 1, height: 14, background: "var(--border)", margin: "0 2px" }} />

        {/* ASCII / HEX toggle */}
        <div
          style={{
            display: "flex",
            background: "#0d0e10",
            border: "1px solid var(--border)",
            borderRadius: 5,
            overflow: "hidden",
          }}
        >
          {(["ascii", "hex"] as DisplayFormat[]).map((f) => (
            <button
              key={f}
              onClick={() => onDisplayFormatChange(f)}
              style={{
                background: displayFormat === f ? "var(--accent)" : "transparent",
                border: "none",
                color: displayFormat === f ? "#fff" : "var(--muted)",
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
              {f}
            </button>
          ))}
        </div>

        {/* Timestamp toggle */}
        <ToolBtn onClick={() => onShowTimestampsChange(!showTimestamps)} active={showTimestamps} title="显示时间戳">
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <circle cx="6" cy="6" r="4.5" stroke="currentColor" strokeWidth="1.2" />
            <path d="M6 3.5V6l1.5 1.5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
          </svg>
          时间戳
        </ToolBtn>

        {/* Auto-scroll toggle */}
        <ToolBtn onClick={() => onAutoScrollChange(!autoScroll)} active={autoScroll} title="自动滚动">
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path d="M6 2v8M3 7l3 3 3-3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          跟随
        </ToolBtn>

        <div style={{ flex: 1 }} />

        {/* Entry count */}
        <span style={{ color: "var(--muted-2)", fontSize: 11, fontFamily: "var(--font-mono)" }}>
          {entries.length} 条
        </span>
      </div>

      {/* Pause banner */}
      {isPaused && (
        <div
          style={{
            background: "var(--orange-weak)",
            borderBottom: "1px solid rgba(255,159,10,0.2)",
            padding: "4px 12px",
            display: "flex",
            alignItems: "center",
            gap: 8,
            fontSize: 12,
            color: "var(--orange)",
            flexShrink: 0,
          }}
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <rect x="2.5" y="2" width="2.5" height="8" rx="1" fill="currentColor" />
            <rect x="7" y="2" width="2.5" height="8" rx="1" fill="currentColor" />
          </svg>
          <span>显示已暂停 · 后台继续接收数据</span>
          <button
            onClick={onResume}
            style={{
              marginLeft: "auto",
              background: "none",
              border: "none",
              color: "var(--orange)",
              fontSize: 12,
              cursor: "pointer",
              fontWeight: 500,
              padding: 0,
            }}
          >
            恢复显示
          </button>
        </div>
      )}

      {/* Log area */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        style={{
          flex: 1,
          overflow: "auto",
          background: "var(--console-bg)",
          padding: "8px 0",
          position: "relative",
        }}
      >
        {entries.length === 0 ? (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              height: "100%",
              color: "var(--muted-2)",
              fontSize: 13,
              gap: 8,
            }}
          >
            <svg width="32" height="32" viewBox="0 0 32 32" fill="none" opacity={0.4}>
              <path d="M8 10h16M8 16h12M8 22h8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
            <span>暂无数据 · 连接后开始接收</span>
          </div>
        ) : (
          entries.map((entry) => (
            <LogRow
              key={entry.id}
              entry={entry}
              displayFormat={displayFormat}
              showTimestamp={showTimestamps}
            />
          ))
        )}
      </div>

      {/* Scroll to bottom FAB */}
      {showScrollBtn && (
        <button
          onClick={scrollToBottom}
          style={{
            position: "absolute",
            bottom: 120,
            left: "50%",
            transform: "translateX(-50%)",
            background: "var(--panel)",
            border: "1px solid var(--border-mid)",
            borderRadius: 20,
            color: "var(--accent)",
            fontSize: 12,
            padding: "5px 14px",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 5,
            boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
            zIndex: 10,
          }}
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path d="M6 2v8M3 7l3 3 3-3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          返回最新数据
        </button>
      )}
    </div>
  );
}

function LogRow({
  entry,
  displayFormat,
  showTimestamp,
}: {
  entry: LogEntry;
  displayFormat: DisplayFormat;
  showTimestamp: boolean;
}) {
  const [hovered, setHovered] = useState(false);
  const isRx = entry.direction === "RX";

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: 0,
        padding: "1.5px 12px",
        background: hovered ? "rgba(255,255,255,0.025)" : "transparent",
        cursor: "default",
        minHeight: 20,
      }}
    >
      {/* Timestamp */}
      {showTimestamp && (
        <span
          style={{
            color: "var(--muted-2)",
            fontSize: 11,
            fontFamily: "var(--font-mono)",
            marginRight: 10,
            flexShrink: 0,
            lineHeight: "20px",
            userSelect: "none",
          }}
        >
          {formatTimestamp(entry.timestamp)}
        </span>
      )}

      {/* Direction badge */}
      <span
        style={{
          fontSize: 10,
          fontFamily: "var(--font-mono)",
          fontWeight: 500,
          color: isRx ? "var(--rx-color)" : "var(--tx-color)",
          background: isRx ? "var(--accent-weak)" : "var(--green-weak)",
          borderRadius: 3,
          padding: "1px 5px",
          marginRight: 10,
          flexShrink: 0,
          lineHeight: "18px",
          letterSpacing: 0.3,
          alignSelf: "flex-start",
          marginTop: 1,
        }}
      >
        {entry.direction}
      </span>

      {/* Data */}
      <span
        style={{
          fontFamily: "var(--font-mono)",
          fontSize: 12,
          color: isRx ? "var(--text)" : "rgba(232,232,234,0.75)",
          lineHeight: "20px",
          wordBreak: "break-all",
          flex: 1,
          whiteSpace: "pre-wrap",
        }}
      >
        {renderData(entry, displayFormat)}
      </span>

      {/* Copy button on hover */}
      {hovered && (
        <button
          onClick={() => navigator.clipboard.writeText(entry.raw)}
          title="复制"
          style={{
            background: "none",
            border: "none",
            color: "var(--muted)",
            cursor: "pointer",
            padding: "0 4px",
            flexShrink: 0,
            lineHeight: "20px",
          }}
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <rect x="4" y="1" width="7" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.2" />
            <path d="M1 4v7h7" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </div>
  );
}

function ToolBtn({
  onClick,
  children,
  active = false,
  activeColor = "var(--accent)",
  title,
}: {
  onClick: () => void;
  children: React.ReactNode;
  active?: boolean;
  activeColor?: string;
  title?: string;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      style={{
        background: active ? `color-mix(in srgb, ${activeColor} 15%, transparent)` : "transparent",
        border: "none",
        borderRadius: 5,
        color: active ? activeColor : "var(--muted)",
        fontSize: 12,
        padding: "2px 7px",
        cursor: "pointer",
        display: "flex",
        alignItems: "center",
        gap: 4,
      }}
    >
      {children}
    </button>
  );
}
