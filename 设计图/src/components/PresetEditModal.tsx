import { useState, useEffect } from "react";
import type { Preset } from "../types";

interface Props {
  preset: Preset | null;
  onSave: (preset: Preset) => void;
  onClose: () => void;
}

function isValidHex(s: string): boolean {
  const clean = s.replace(/\s/g, "");
  return clean.length % 2 === 0 && /^[0-9a-fA-F]*$/.test(clean);
}

function generateId() {
  return Math.random().toString(36).slice(2, 10);
}

const labelStyle: React.CSSProperties = {
  fontSize: 12,
  color: "var(--muted)",
  marginBottom: 4,
  display: "block",
  fontWeight: 500,
};

const inputStyle: React.CSSProperties = {
  background: "#0d0e10",
  border: "1px solid var(--border-mid)",
  borderRadius: 6,
  color: "var(--text)",
  fontSize: 13,
  padding: "7px 10px",
  outline: "none",
  width: "100%",
  fontFamily: "var(--font-ui)",
};

const monoInputStyle: React.CSSProperties = {
  ...inputStyle,
  fontFamily: "var(--font-mono)",
  fontSize: 12,
};

export default function PresetEditModal({ preset, onSave, onClose }: Props) {
  const isNew = !preset;
  const [name, setName] = useState(preset?.name ?? "");
  const [content, setContent] = useState(preset?.content ?? "");
  const [mode, setMode] = useState<"ascii" | "hex">(preset?.mode ?? "ascii");
  const [enabled, setEnabled] = useState(preset?.enabled ?? true);
  const [note, setNote] = useState(preset?.note ?? "");
  const [hexError, setHexError] = useState("");

  useEffect(() => {
    if (mode === "hex" && content.trim()) {
      if (!isValidHex(content)) {
        const clean = content.replace(/\s/g, "");
        if (clean.length % 2 !== 0) setHexError("HEX 字符串长度须为偶数");
        else setHexError("包含非法字符，仅允许 0-9 A-F");
      } else {
        setHexError("");
      }
    } else {
      setHexError("");
    }
  }, [content, mode]);

  function handleSave() {
    if (!name.trim() || !content.trim() || hexError) return;
    onSave({
      id: preset?.id ?? generateId(),
      name: name.trim(),
      content: content.trim(),
      mode,
      enabled,
      note: note.trim(),
    });
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === "Escape") onClose();
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) handleSave();
  }

  const canSave = name.trim().length > 0 && content.trim().length > 0 && !hexError;

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.6)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 200,
        backdropFilter: "blur(4px)",
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      onKeyDown={handleKeyDown}
    >
      <div
        style={{
          background: "var(--panel)",
          border: "1px solid var(--border-mid)",
          borderRadius: 14,
          width: 420,
          maxWidth: "calc(100vw - 32px)",
          padding: "22px 22px 18px",
          display: "flex",
          flexDirection: "column",
          gap: 0,
          boxShadow: "0 24px 64px rgba(0,0,0,0.6)",
        }}
      >
        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 18 }}>
          <h2 style={{ margin: 0, fontSize: 15, fontWeight: 600, letterSpacing: -0.3 }}>
            {isNew ? "新建预设" : "编辑预设"}
          </h2>
          <button
            onClick={onClose}
            style={{
              background: "rgba(255,255,255,0.06)",
              border: "none",
              borderRadius: 6,
              color: "var(--muted)",
              width: 24,
              height: 24,
              cursor: "pointer",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 14,
            }}
          >
            ×
          </button>
        </div>

        {/* Name */}
        <div style={{ marginBottom: 14 }}>
          <label style={labelStyle}>名称</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="预设名称"
            style={inputStyle}
            autoFocus
          />
        </div>

        {/* Mode + content */}
        <div style={{ marginBottom: hexError ? 4 : 14 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 4 }}>
            <label style={{ ...labelStyle, marginBottom: 0 }}>内容</label>
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
              {(["ascii", "hex"] as const).map((m) => (
                <button
                  key={m}
                  onClick={() => setMode(m)}
                  style={{
                    background: mode === m ? "var(--accent)" : "transparent",
                    border: "none",
                    color: mode === m ? "#fff" : "var(--muted)",
                    fontSize: 11,
                    fontFamily: "var(--font-mono)",
                    fontWeight: 500,
                    padding: "2px 8px",
                    cursor: "pointer",
                    textTransform: "uppercase",
                    letterSpacing: 0.5,
                  }}
                >
                  {m}
                </button>
              ))}
            </div>
          </div>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={mode === "hex" ? "例如: 55 AA 01 00 FF" : "输入发送内容…"}
            rows={3}
            style={{ ...monoInputStyle, resize: "vertical", lineHeight: 1.6 }}
          />
        </div>

        {/* HEX error */}
        {hexError && (
          <div
            style={{
              padding: "5px 8px",
              marginBottom: 10,
              background: "var(--red-weak)",
              border: "1px solid rgba(255,69,58,0.2)",
              borderRadius: 5,
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

        {/* Enabled */}
        <div style={{ marginBottom: 14 }}>
          <label
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              cursor: "pointer",
              userSelect: "none",
            }}
          >
            <input
              type="checkbox"
              checked={enabled}
              onChange={(e) => setEnabled(e.target.checked)}
              style={{ accentColor: "var(--accent)", cursor: "pointer" }}
            />
            <span style={{ fontSize: 13, color: "var(--text)" }}>启用此预设</span>
          </label>
        </div>

        {/* Note */}
        <div style={{ marginBottom: 18 }}>
          <label style={labelStyle}>备注（可选）</label>
          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="添加备注说明…"
            style={inputStyle}
          />
        </div>

        <div style={{ height: 1, background: "var(--border)", marginBottom: 14 }} />

        {/* Actions */}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
          <button
            onClick={onClose}
            style={{
              background: "transparent",
              border: "1px solid var(--border)",
              borderRadius: 7,
              color: "var(--muted)",
              fontSize: 13,
              fontWeight: 500,
              padding: "7px 18px",
              cursor: "pointer",
            }}
          >
            取消
          </button>
          <button
            onClick={handleSave}
            disabled={!canSave}
            style={{
              background: canSave ? "var(--accent)" : "rgba(41,151,255,0.2)",
              border: "none",
              borderRadius: 7,
              color: canSave ? "#fff" : "var(--muted)",
              fontSize: 13,
              fontWeight: 500,
              padding: "7px 18px",
              cursor: canSave ? "pointer" : "not-allowed",
            }}
          >
            保存
          </button>
        </div>
      </div>
    </div>
  );
}
