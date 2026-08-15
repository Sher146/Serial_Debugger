interface Props {
  port: string;
  baudRate: number;
  rxBytes: number;
  txBytes: number;
  logStatus: "inactive" | "recording";
  lastError: string;
  connectionState: string;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1048576).toFixed(1)} MB`;
}

export default function StatusBar({
  port,
  baudRate,
  rxBytes,
  txBytes,
  logStatus,
  lastError,
  connectionState,
}: Props) {
  const connected = connectionState === "connected";

  return (
    <div
      style={{
        height: 26,
        background: "var(--panel)",
        borderTop: "1px solid var(--border)",
        display: "flex",
        alignItems: "center",
        gap: 0,
        padding: "0 12px",
        flexShrink: 0,
        overflow: "hidden",
      }}
    >
      {/* Port + baud */}
      <StatusItem>
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none" style={{ opacity: 0.5 }}>
          <rect x="1" y="3" width="8" height="4" rx="1" stroke="currentColor" strokeWidth="1.1" />
          <path d="M3 3V2M5 3V1.5M7 3V2" stroke="currentColor" strokeWidth="1.1" strokeLinecap="round" />
        </svg>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11 }}>
          {port.split("/").pop() || port}
        </span>
        <Divider />
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11 }}>{baudRate}</span>
      </StatusItem>

      <Separator />

      {/* RX / TX counters */}
      <StatusItem>
        <span style={{ color: connected ? "var(--rx-color)" : "var(--muted-2)", fontSize: 11 }}>RX</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--text)" }}>
          {formatBytes(rxBytes)}
        </span>
        <Divider />
        <span style={{ color: connected ? "var(--tx-color)" : "var(--muted-2)", fontSize: 11 }}>TX</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--text)" }}>
          {formatBytes(txBytes)}
        </span>
      </StatusItem>

      <Separator />

      {/* Log status */}
      <StatusItem>
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: "50%",
            background: logStatus === "recording" ? "var(--red)" : "var(--muted-2)",
            boxShadow: logStatus === "recording" ? "0 0 4px var(--red)" : "none",
            flexShrink: 0,
          }}
        />
        <span style={{ fontSize: 11, color: logStatus === "recording" ? "var(--text)" : "var(--muted)" }}>
          {logStatus === "recording" ? "记录中" : "未记录"}
        </span>
      </StatusItem>

      {/* Last error */}
      {lastError && (
        <>
          <Separator />
          <StatusItem>
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
              <circle cx="5" cy="5" r="4" stroke="var(--red)" strokeWidth="1.1" />
              <path d="M5 3v2.5M5 6.8v.3" stroke="var(--red)" strokeWidth="1.2" strokeLinecap="round" />
            </svg>
            <span style={{ fontSize: 11, color: "var(--red)" }}>{lastError}</span>
          </StatusItem>
        </>
      )}

      <div style={{ flex: 1 }} />

      {/* Version */}
      <span style={{ fontSize: 10, color: "var(--muted-2)", fontFamily: "var(--font-mono)" }}>v1.0.0</span>
    </div>
  );
}

function StatusItem({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 5, padding: "0 6px" }}>
      {children}
    </div>
  );
}

function Separator() {
  return <div style={{ width: 1, height: 14, background: "var(--border)", flexShrink: 0 }} />;
}

function Divider() {
  return <span style={{ color: "var(--muted-2)", fontSize: 10, margin: "0 1px" }}>·</span>;
}
