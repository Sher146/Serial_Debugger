import { useState } from "react";
import type { Preset } from "../types";

interface Props {
  presets: Preset[];
  connected: boolean;
  loopRunning: boolean;
  loopInterval: number;
  onTogglePreset: (id: string) => void;
  onSendPreset: (preset: Preset) => void;
  onEditPreset: (preset: Preset) => void;
  onDeletePreset: (id: string) => void;
  onNewPreset: () => void;
  onLoopToggle: () => void;
  onLoopIntervalChange: (ms: number) => void;
}

export default function PresetInspector({
  presets,
  connected,
  loopRunning,
  loopInterval,
  onTogglePreset,
  onSendPreset,
  onEditPreset,
  onDeletePreset,
  onNewPreset,
  onLoopToggle,
  onLoopIntervalChange,
}: Props) {
  const [intervalText, setIntervalText] = useState(String(loopInterval));
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);

  function handleIntervalChange(val: string) {
    setIntervalText(val);
    const n = parseInt(val, 10);
    if (!isNaN(n) && n >= 100) {
      onLoopIntervalChange(n);
    }
  }

  function handleDelete(id: string) {
    if (deleteConfirm === id) {
      onDeletePreset(id);
      setDeleteConfirm(null);
    } else {
      setDeleteConfirm(id);
      setTimeout(() => setDeleteConfirm(null), 3000);
    }
  }

  const enabledCount = presets.filter((p) => p.enabled).length;

  return (
    <div
      style={{
        width: 220,
        flexShrink: 0,
        background: "var(--panel)",
        borderLeft: "1px solid var(--border)",
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <div
        style={{
          padding: "0 12px",
          height: 36,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          borderBottom: "1px solid var(--border)",
          flexShrink: 0,
        }}
      >
        <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: "uppercase", color: "var(--muted)" }}>
          预设
        </span>
        <button
          onClick={onNewPreset}
          title="新建预设"
          style={{
            background: "var(--accent-weak)",
            border: "none",
            borderRadius: 5,
            color: "var(--accent)",
            fontSize: 11,
            padding: "2px 8px",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 3,
            fontWeight: 500,
          }}
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M5 1v8M1 5h8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
          新建
        </button>
      </div>

      {/* Preset list */}
      <div style={{ flex: 1, overflow: "auto", padding: "4px 0" }}>
        {presets.length === 0 ? (
          <div
            style={{
              padding: "24px 12px",
              textAlign: "center",
              color: "var(--muted-2)",
              fontSize: 12,
              lineHeight: 1.6,
            }}
          >
            暂无预设
            <br />
            <span
              onClick={onNewPreset}
              style={{ color: "var(--accent)", cursor: "pointer" }}
            >
              新建一个
            </span>
          </div>
        ) : (
          presets.map((preset) => (
            <PresetRow
              key={preset.id}
              preset={preset}
              connected={connected}
              deleteConfirm={deleteConfirm === preset.id}
              onToggle={() => onTogglePreset(preset.id)}
              onSend={() => onSendPreset(preset)}
              onEdit={() => onEditPreset(preset)}
              onDelete={() => handleDelete(preset.id)}
            />
          ))
        )}
      </div>

      {/* Loop controls */}
      <div
        style={{
          borderTop: "1px solid var(--border)",
          padding: "10px 12px",
          display: "flex",
          flexDirection: "column",
          gap: 8,
          flexShrink: 0,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <span style={{ fontSize: 11, color: "var(--muted)", fontWeight: 500 }}>
            循环发送
          </span>
          {loopRunning && (
            <span
              style={{
                fontSize: 10,
                color: "var(--green)",
                background: "var(--green-weak)",
                borderRadius: 3,
                padding: "1px 5px",
              }}
            >
              运行中
            </span>
          )}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <span style={{ fontSize: 11, color: "var(--muted)", flexShrink: 0 }}>间隔</span>
          <input
            type="number"
            value={intervalText}
            onChange={(e) => handleIntervalChange(e.target.value)}
            min={100}
            step={100}
            style={{
              flex: 1,
              background: "#0d0e10",
              border: "1px solid var(--border)",
              borderRadius: 5,
              color: "var(--text)",
              fontSize: 11,
              fontFamily: "var(--font-mono)",
              padding: "3px 6px",
              outline: "none",
              textAlign: "right",
              minWidth: 0,
            }}
          />
          <span style={{ color: "var(--muted)", fontSize: 11, flexShrink: 0 }}>ms</span>
        </div>

        <div style={{ fontSize: 11, color: "var(--muted-2)", lineHeight: 1.4 }}>
          {enabledCount} 个已启用的预设将循环发送
        </div>

        <button
          onClick={onLoopToggle}
          disabled={!connected || enabledCount === 0}
          style={{
            background: loopRunning
              ? "var(--red-weak)"
              : connected && enabledCount > 0
              ? "var(--green-weak)"
              : "transparent",
            border: `1px solid ${
              loopRunning
                ? "rgba(255,69,58,0.25)"
                : connected && enabledCount > 0
                ? "rgba(48,209,88,0.25)"
                : "var(--border)"
            }`,
            borderRadius: 6,
            color: loopRunning
              ? "var(--red)"
              : connected && enabledCount > 0
              ? "var(--green)"
              : "var(--muted)",
            fontSize: 12,
            fontWeight: 500,
            padding: "6px 0",
            width: "100%",
            cursor: connected && enabledCount > 0 ? "pointer" : "not-allowed",
          }}
        >
          {loopRunning ? "停止循环" : "开始循环"}
        </button>
      </div>
    </div>
  );
}

function PresetRow({
  preset,
  connected,
  deleteConfirm,
  onToggle,
  onSend,
  onEdit,
  onDelete,
}: {
  preset: Preset;
  connected: boolean;
  deleteConfirm: boolean;
  onToggle: () => void;
  onSend: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const [hovered, setHovered] = useState(false);

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        padding: "6px 10px",
        display: "flex",
        alignItems: "flex-start",
        gap: 7,
        background: hovered ? "rgba(255,255,255,0.03)" : "transparent",
        cursor: "default",
      }}
    >
      {/* Enable checkbox */}
      <input
        type="checkbox"
        checked={preset.enabled}
        onChange={onToggle}
        style={{ accentColor: "var(--accent)", marginTop: 2, flexShrink: 0, cursor: "pointer" }}
      />

      {/* Content */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            fontSize: 12,
            fontWeight: 500,
            color: preset.enabled ? "var(--text)" : "var(--muted)",
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
          }}
        >
          {preset.name}
        </div>
        <div
          style={{
            fontSize: 11,
            fontFamily: "var(--font-mono)",
            color: "var(--muted)",
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            marginTop: 1,
          }}
        >
          {preset.content.length > 20 ? preset.content.slice(0, 20) + "…" : preset.content}
        </div>
        <span
          style={{
            fontSize: 10,
            color: "var(--muted-2)",
            background: "rgba(255,255,255,0.04)",
            borderRadius: 3,
            padding: "0 4px",
            fontFamily: "var(--font-mono)",
            textTransform: "uppercase",
            letterSpacing: 0.3,
          }}
        >
          {preset.mode}
        </span>
      </div>

      {/* Actions */}
      {hovered && (
        <div style={{ display: "flex", flexDirection: "column", gap: 3, flexShrink: 0 }}>
          {/* Send */}
          <ActionBtn onClick={onSend} disabled={!connected} title="发送" color="var(--accent)">
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M1.5 5.5h8M6.5 2.5l3 3-3 3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </ActionBtn>
          {/* Edit */}
          <ActionBtn onClick={onEdit} title="编辑">
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M2 8.5l1.5-1.5L8 2.5 9 3.5l-4.5 4.5L3 9.5 2 8.5z" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </ActionBtn>
          {/* Delete */}
          <ActionBtn
            onClick={onDelete}
            title={deleteConfirm ? "再次点击确认删除" : "删除"}
            color={deleteConfirm ? "var(--red)" : undefined}
          >
            <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
              <path d="M2 3h7M4.5 3V2h2v1M3.5 3l.5 6h3L8 3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </ActionBtn>
        </div>
      )}
    </div>
  );
}

function ActionBtn({
  onClick,
  children,
  disabled,
  title,
  color,
}: {
  onClick: () => void;
  children: React.ReactNode;
  disabled?: boolean;
  title?: string;
  color?: string;
}) {
  return (
    <button
      onClick={disabled ? undefined : onClick}
      title={title}
      style={{
        background: "rgba(255,255,255,0.05)",
        border: "none",
        borderRadius: 4,
        color: disabled ? "var(--muted-2)" : color || "var(--muted)",
        padding: "3px",
        cursor: disabled ? "not-allowed" : "pointer",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        width: 20,
        height: 20,
      }}
    >
      {children}
    </button>
  );
}
