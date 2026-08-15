import { useEffect, useRef } from "react";
import type { DataParams } from "../types";

interface Props {
  anchor: DOMRect;
  params: DataParams;
  onChange: (params: DataParams) => void;
  onClose: () => void;
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16 }}>
      <span style={{ color: "var(--muted)", fontSize: 12, flexShrink: 0 }}>{label}</span>
      {children}
    </div>
  );
}

const selectStyle: React.CSSProperties = {
  background: "#0d0e10",
  border: "1px solid var(--border-mid)",
  borderRadius: 5,
  color: "var(--text)",
  fontSize: 12,
  fontFamily: "var(--font-mono)",
  padding: "3px 6px",
  outline: "none",
  cursor: "pointer",
};

export default function AdvancedParamsPopover({ anchor, params, onChange, onClose }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        onClose();
      }
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [onClose]);

  const top = anchor.bottom + 6;
  const left = anchor.left;

  return (
    <div
      ref={ref}
      style={{
        position: "fixed",
        top,
        left,
        background: "var(--panel)",
        border: "1px solid var(--border-mid)",
        borderRadius: 10,
        padding: "14px 16px",
        zIndex: 100,
        width: 240,
        display: "flex",
        flexDirection: "column",
        gap: 12,
        boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
      }}
    >
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--text)", marginBottom: 2 }}>通信参数</div>

      <Row label="数据位">
        <select
          value={params.dataBits}
          onChange={(e) => onChange({ ...params, dataBits: Number(e.target.value) as 7 | 8 })}
          style={selectStyle}
        >
          <option value={8} style={{ background: "#1a1c1f" }}>8</option>
          <option value={7} style={{ background: "#1a1c1f" }}>7</option>
        </select>
      </Row>

      <Row label="校验位">
        <select
          value={params.parity}
          onChange={(e) => onChange({ ...params, parity: e.target.value as DataParams["parity"] })}
          style={selectStyle}
        >
          <option value="none" style={{ background: "#1a1c1f" }}>无 (None)</option>
          <option value="even" style={{ background: "#1a1c1f" }}>偶校验 (Even)</option>
          <option value="odd" style={{ background: "#1a1c1f" }}>奇校验 (Odd)</option>
        </select>
      </Row>

      <Row label="停止位">
        <select
          value={params.stopBits}
          onChange={(e) => onChange({ ...params, stopBits: Number(e.target.value) as 1 | 2 })}
          style={selectStyle}
        >
          <option value={1} style={{ background: "#1a1c1f" }}>1</option>
          <option value={2} style={{ background: "#1a1c1f" }}>2</option>
        </select>
      </Row>

      <Row label="流控制">
        <select
          value={params.flow}
          onChange={(e) => onChange({ ...params, flow: e.target.value as DataParams["flow"] })}
          style={selectStyle}
        >
          <option value="none" style={{ background: "#1a1c1f" }}>无 (None)</option>
          <option value="hardware" style={{ background: "#1a1c1f" }}>硬件 (RTS/CTS)</option>
        </select>
      </Row>

      <div style={{ height: 1, background: "var(--border)", marginTop: 2 }} />
      <button
        onClick={onClose}
        style={{
          background: "var(--accent)",
          border: "none",
          borderRadius: 6,
          color: "#fff",
          fontSize: 12,
          fontWeight: 500,
          padding: "5px 0",
          cursor: "pointer",
          width: "100%",
        }}
      >
        确认
      </button>
    </div>
  );
}
