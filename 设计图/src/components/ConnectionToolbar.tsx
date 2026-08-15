import { useState } from "react";
import type { ConnectionState, DataParams } from "../types";
import AdvancedParamsPopover from "./AdvancedParamsPopover";

const BAUD_RATES = [300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];

const MOCK_PORTS = [
  "/dev/cu.usbserial-0001",
  "/dev/cu.usbserial-A5XK3RJT",
  "/dev/ttyUSB0",
  "/dev/ttyACM0",
  "COM3",
  "COM4",
];

interface Props {
  connectionState: ConnectionState;
  selectedPort: string;
  baudRate: number;
  dataParams: DataParams;
  onPortChange: (port: string) => void;
  onBaudChange: (baud: number) => void;
  onDataParamsChange: (params: DataParams) => void;
  onConnect: () => void;
  onDisconnect: () => void;
  showPresets: boolean;
  onTogglePresets: () => void;
}

const statusConfig = {
  disconnected: { dot: "#6b6b70", label: "未连接", labelColor: "#6b6b70" },
  connecting: { dot: "#ff9f0a", label: "连接中…", labelColor: "#ff9f0a" },
  connected: { dot: "#30d158", label: "已连接", labelColor: "#30d158" },
  error: { dot: "#ff453a", label: "连接错误", labelColor: "#ff453a" },
};

export default function ConnectionToolbar({
  connectionState,
  selectedPort,
  baudRate,
  dataParams,
  onPortChange,
  onBaudChange,
  onDataParamsChange,
  onConnect,
  onDisconnect,
  showPresets,
  onTogglePresets,
}: Props) {
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [advancedAnchor, setAdvancedAnchor] = useState<DOMRect | null>(null);

  const isConnected = connectionState === "connected";
  const isConnecting = connectionState === "connecting";
  const locked = isConnected || isConnecting;
  const status = statusConfig[connectionState];

  const parityShort = { none: "N", even: "E", odd: "O" }[dataParams.parity];
  const paramsLabel = `${baudRate} · ${dataParams.dataBits}${parityShort}${dataParams.stopBits}`;

  function handleAdvancedClick(e: React.MouseEvent<HTMLButtonElement>) {
    setAdvancedAnchor((e.currentTarget as HTMLElement).getBoundingClientRect());
    setShowAdvanced((v) => !v);
  }

  return (
    <div
      style={{
        background: "var(--panel)",
        borderBottom: "1px solid var(--border)",
        padding: "0 16px",
        height: 48,
        display: "flex",
        alignItems: "center",
        gap: 8,
        flexShrink: 0,
        position: "relative",
        zIndex: 20,
      }}
    >
      {/* App icon + title */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginRight: 8 }}>
        <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
          <rect width="18" height="18" rx="4" fill="var(--accent)" fillOpacity="0.15" />
          <path d="M4 9h2M8 6l-2 3 2 3M10 6l2 3-2 3M14 9h-2" stroke="var(--accent)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span style={{ fontWeight: 600, fontSize: 13, letterSpacing: -0.2 }}>Serial Monitor</span>
      </div>

      <div style={{ width: 1, height: 20, background: "var(--border)", flexShrink: 0 }} />

      {/* Port selector */}
      <label style={{ color: "var(--muted)", fontSize: 12, flexShrink: 0 }}>端口</label>
      <select
        value={selectedPort}
        onChange={(e) => onPortChange(e.target.value)}
        disabled={locked}
        style={{
          background: "var(--panel-2, #1a1c1f)",
          border: "1px solid var(--border)",
          borderRadius: 6,
          color: locked ? "var(--muted)" : "var(--text)",
          fontSize: 12,
          fontFamily: "var(--font-mono)",
          padding: "3px 6px",
          cursor: locked ? "not-allowed" : "pointer",
          outline: "none",
          maxWidth: 200,
        }}
      >
        {MOCK_PORTS.map((p) => (
          <option key={p} value={p} style={{ background: "#1a1c1f" }}>
            {p}
          </option>
        ))}
      </select>

      {/* Baud rate */}
      <label style={{ color: "var(--muted)", fontSize: 12, flexShrink: 0 }}>波特率</label>
      <select
        value={baudRate}
        onChange={(e) => onBaudChange(Number(e.target.value))}
        disabled={locked}
        style={{
          background: "var(--panel-2, #1a1c1f)",
          border: "1px solid var(--border)",
          borderRadius: 6,
          color: locked ? "var(--muted)" : "var(--text)",
          fontSize: 12,
          fontFamily: "var(--font-mono)",
          padding: "3px 6px",
          cursor: locked ? "not-allowed" : "pointer",
          outline: "none",
        }}
      >
        {BAUD_RATES.map((b) => (
          <option key={b} value={b} style={{ background: "#1a1c1f" }}>
            {b}
          </option>
        ))}
      </select>

      {/* Advanced params chip */}
      <button
        onClick={handleAdvancedClick}
        disabled={locked}
        style={{
          background: showAdvanced ? "var(--accent-weak)" : "transparent",
          border: "1px solid var(--border)",
          borderRadius: 6,
          color: locked ? "var(--muted)" : showAdvanced ? "var(--accent)" : "var(--text)",
          fontSize: 12,
          fontFamily: "var(--font-mono)",
          padding: "3px 8px",
          cursor: locked ? "not-allowed" : "pointer",
          display: "flex",
          alignItems: "center",
          gap: 5,
          flexShrink: 0,
        }}
      >
        {paramsLabel}
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M2 3.5L5 6.5L8 3.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {/* Status */}
      <div style={{ display: "flex", alignItems: "center", gap: 6, marginLeft: 4, flexShrink: 0 }}>
        <span
          style={{
            width: 7,
            height: 7,
            borderRadius: "50%",
            background: status.dot,
            boxShadow: isConnected ? `0 0 6px ${status.dot}` : "none",
            flexShrink: 0,
            transition: "background 0.2s, box-shadow 0.2s",
          }}
        />
        <span style={{ color: status.labelColor, fontSize: 12, fontWeight: 500 }}>{status.label}</span>
        {isConnected && (
          <span style={{ color: "var(--muted)", fontSize: 11, fontFamily: "var(--font-mono)" }}>
            {selectedPort.split("/").pop()}
          </span>
        )}
      </div>

      {/* Spacer */}
      <div style={{ flex: 1 }} />

      {/* Preset toggle */}
      <button
        onClick={onTogglePresets}
        title={showPresets ? "隐藏预设" : "显示预设"}
        style={{
          background: showPresets ? "var(--accent-weak)" : "transparent",
          border: "1px solid var(--border)",
          borderRadius: 6,
          color: showPresets ? "var(--accent)" : "var(--muted)",
          padding: "4px 8px",
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          gap: 5,
          fontSize: 12,
          flexShrink: 0,
        }}
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M1 3h12M1 7h8M1 11h10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
        </svg>
        预设
      </button>

      {/* Connect / Disconnect */}
      {!isConnected && !isConnecting ? (
        <button
          onClick={onConnect}
          style={{
            background: "var(--accent)",
            border: "none",
            borderRadius: 7,
            color: "#fff",
            fontSize: 13,
            fontWeight: 500,
            padding: "5px 14px",
            cursor: "pointer",
            flexShrink: 0,
            letterSpacing: -0.1,
          }}
        >
          连接
        </button>
      ) : isConnecting ? (
        <button
          onClick={onDisconnect}
          style={{
            background: "var(--orange-weak)",
            border: "1px solid rgba(255,159,10,0.25)",
            borderRadius: 7,
            color: "var(--orange)",
            fontSize: 13,
            fontWeight: 500,
            padding: "5px 14px",
            cursor: "pointer",
            flexShrink: 0,
          }}
        >
          取消
        </button>
      ) : (
        <button
          onClick={onDisconnect}
          style={{
            background: "transparent",
            border: "1px solid rgba(255,69,58,0.3)",
            borderRadius: 7,
            color: "var(--red)",
            fontSize: 13,
            fontWeight: 500,
            padding: "5px 14px",
            cursor: "pointer",
            flexShrink: 0,
          }}
        >
          断开
        </button>
      )}

      {/* Advanced popover */}
      {showAdvanced && advancedAnchor && (
        <AdvancedParamsPopover
          anchor={advancedAnchor}
          params={dataParams}
          onChange={onDataParamsChange}
          onClose={() => setShowAdvanced(false)}
        />
      )}
    </div>
  );
}
