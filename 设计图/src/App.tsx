import { useState, useEffect, useRef, useCallback } from "react";
import type { ConnectionState, DataParams, DisplayFormat, LineEnding, LogEntry, Preset } from "./types";
import ConnectionToolbar from "./components/ConnectionToolbar";
import ReceiveConsole from "./components/ReceiveConsole";
import SendEditor from "./components/SendEditor";
import PresetInspector from "./components/PresetInspector";
import StatusBar from "./components/StatusBar";
import PresetEditModal from "./components/PresetEditModal";

// --- Simulation data ---
const RX_SAMPLES = [
  "55 AA 01 00 FF",
  "OK",
  "ready",
  "+CWMODE:1",
  "AT+RST\r\nready",
  "ERROR: timeout",
  "SEND OK",
  "0D 0A 00 FF A1 B2",
  ">",
  "+IPD,5:Hello",
  "WIFI CONNECTED",
  "WIFI GOT IP",
];

function generateId() {
  return Math.random().toString(36).slice(2, 10);
}

function appendLineEnding(text: string, lineEnding: LineEnding): string {
  if (lineEnding === "cr") return text + "\r";
  if (lineEnding === "lf") return text + "\n";
  if (lineEnding === "crlf") return text + "\r\n";
  return text;
}

const DEFAULT_PRESETS: Preset[] = [
  { id: "p1", name: "查询状态", content: "AT+CWMODE?", mode: "ascii", enabled: true, note: "查询当前工作模式" },
  { id: "p2", name: "重启设备", content: "AT+RST", mode: "ascii", enabled: true, note: "软重启模块" },
  { id: "p3", name: "读取版本", content: "AT+GMR", mode: "ascii", enabled: false, note: "读取固件版本" },
  { id: "p4", name: "心跳包", content: "55 AA 00 FF", mode: "hex", enabled: false, note: "定期发送心跳" },
];

export default function App() {
  const [connectionState, setConnectionState] = useState<ConnectionState>("disconnected");
  const [selectedPort, setSelectedPort] = useState("/dev/cu.usbserial-0001");
  const [baudRate, setBaudRate] = useState(115200);
  const [dataParams, setDataParams] = useState<DataParams>({
    dataBits: 8,
    parity: "none",
    stopBits: 1,
    flow: "none",
  });

  const [logEntries, setLogEntries] = useState<LogEntry[]>([]);
  const [displayFormat, setDisplayFormat] = useState<DisplayFormat>("ascii");
  const [showTimestamps, setShowTimestamps] = useState(true);
  const [autoScroll, setAutoScroll] = useState(true);
  const [isPaused, setIsPaused] = useState(false);
  const pauseBuffer = useRef<LogEntry[]>([]);

  const [sendMode, setSendMode] = useState<DisplayFormat>("ascii");
  const [lineEnding, setLineEnding] = useState<LineEnding>("crlf");
  const [autoSendEnabled, setAutoSendEnabled] = useState(false);
  const [autoSendInterval, setAutoSendInterval] = useState(1000);
  const [autoSendText, setAutoSendText] = useState("");

  const [presets, setPresets] = useState<Preset[]>(DEFAULT_PRESETS);
  const [loopRunning, setLoopRunning] = useState(false);
  const [loopInterval, setLoopInterval] = useState(1000);
  const [editingPreset, setEditingPreset] = useState<Preset | null | "new">(null);

  const [rxBytes, setRxBytes] = useState(0);
  const [txBytes, setTxBytes] = useState(0);
  const [logStatus] = useState<"inactive" | "recording">("inactive");
  const [lastError, setLastError] = useState("");
  const [showPresets, setShowPresets] = useState(true);

  const connectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const simulationTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const autoSendTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const loopTimer = useRef<ReturnType<typeof setInterval> | null>(null);
  const loopIndex = useRef(0);

  // --- Helpers ---
  const addEntry = useCallback((entry: LogEntry) => {
    if (isPaused) {
      pauseBuffer.current.push(entry);
    } else {
      setLogEntries((prev) => [...prev, entry]);
    }
  }, [isPaused]);

  const addRx = useCallback((data: string) => {
    const entry: LogEntry = {
      id: generateId(),
      timestamp: new Date(),
      direction: "RX",
      raw: data,
      format: "ascii",
    };
    addEntry(entry);
    setRxBytes((n) => n + data.length);
  }, [addEntry]);

  const addTx = useCallback((data: string) => {
    const entry: LogEntry = {
      id: generateId(),
      timestamp: new Date(),
      direction: "TX",
      raw: data,
      format: "ascii",
    };
    addEntry(entry);
    setTxBytes((n) => n + data.length);
  }, [addEntry]);

  // --- Connection ---
  function handleConnect() {
    setConnectionState("connecting");
    setLastError("");
    connectTimer.current = setTimeout(() => {
      // 10% chance of error for realism
      if (Math.random() < 0.1) {
        setConnectionState("error");
        setLastError("端口已被占用");
        return;
      }
      setConnectionState("connected");
      addRx("Serial Monitor connected.");
      startSimulation();
    }, 1500);
  }

  function handleDisconnect() {
    if (connectTimer.current) clearTimeout(connectTimer.current);
    stopSimulation();
    stopAutoSend();
    stopLoop();
    setConnectionState("disconnected");
    setAutoSendEnabled(false);
    setLoopRunning(false);
  }

  // --- Simulation ---
  function startSimulation() {
    if (simulationTimer.current) clearInterval(simulationTimer.current);
    simulationTimer.current = setInterval(() => {
      if (Math.random() < 0.7) {
        const sample = RX_SAMPLES[Math.floor(Math.random() * RX_SAMPLES.length)];
        addRx(sample);
      }
    }, 1200);
  }

  function stopSimulation() {
    if (simulationTimer.current) {
      clearInterval(simulationTimer.current);
      simulationTimer.current = null;
    }
  }

  // --- Send ---
  function handleSend(text: string) {
    if (connectionState !== "connected") return;
    const data = appendLineEnding(text, lineEnding);
    addTx(data);
    // Simulate echo/response
    setTimeout(() => {
      if (connectionState === "connected") {
        addRx(text.startsWith("AT") ? "OK" : ">");
      }
    }, 80 + Math.random() * 120);
  }

  // --- Auto send ---
  function handleAutoSendChange(enabled: boolean, interval: number) {
    setAutoSendEnabled(enabled);
    setAutoSendInterval(interval);
  }

  function stopAutoSend() {
    if (autoSendTimer.current) {
      clearInterval(autoSendTimer.current);
      autoSendTimer.current = null;
    }
  }

  useEffect(() => {
    stopAutoSend();
    if (autoSendEnabled && connectionState === "connected" && autoSendText.trim()) {
      autoSendTimer.current = setInterval(() => {
        handleSend(autoSendText);
      }, autoSendInterval);
    }
    return stopAutoSend;
  }, [autoSendEnabled, autoSendInterval, autoSendText, connectionState]);

  // --- Preset send ---
  function handleSendPreset(preset: Preset) {
    if (connectionState !== "connected") return;
    handleSend(preset.content);
  }

  // --- Loop ---
  function stopLoop() {
    if (loopTimer.current) {
      clearInterval(loopTimer.current);
      loopTimer.current = null;
    }
  }

  function handleLoopToggle() {
    if (loopRunning) {
      stopLoop();
      setLoopRunning(false);
    } else {
      const enabled = presets.filter((p) => p.enabled);
      if (enabled.length === 0) return;
      loopIndex.current = 0;
      loopTimer.current = setInterval(() => {
        const enabled2 = presets.filter((p) => p.enabled);
        if (enabled2.length === 0) return;
        const preset = enabled2[loopIndex.current % enabled2.length];
        handleSend(preset.content);
        loopIndex.current++;
      }, loopInterval);
      setLoopRunning(true);
    }
  }

  // --- Pause / Resume ---
  function handlePause() {
    setIsPaused(true);
    pauseBuffer.current = [];
  }

  function handleResume() {
    setIsPaused(false);
    if (pauseBuffer.current.length > 0) {
      setLogEntries((prev) => [...prev, ...pauseBuffer.current]);
      pauseBuffer.current = [];
    }
  }

  // --- Clear ---
  function handleClear() {
    setLogEntries([]);
    pauseBuffer.current = [];
  }

  // --- Presets ---
  function handleTogglePreset(id: string) {
    setPresets((prev) => prev.map((p) => (p.id === id ? { ...p, enabled: !p.enabled } : p)));
  }

  function handleDeletePreset(id: string) {
    setPresets((prev) => prev.filter((p) => p.id !== id));
  }

  function handleSavePreset(preset: Preset) {
    setPresets((prev) => {
      const idx = prev.findIndex((p) => p.id === preset.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = preset;
        return next;
      }
      return [...prev, preset];
    });
    setEditingPreset(null);
  }

  // --- Cleanup ---
  useEffect(() => {
    return () => {
      if (connectTimer.current) clearTimeout(connectTimer.current);
      stopSimulation();
      stopAutoSend();
      stopLoop();
    };
  }, []);

  const connected = connectionState === "connected";

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        background: "var(--bg)",
        color: "var(--text)",
        fontFamily: "var(--font-ui)",
        overflow: "hidden",
      }}
    >
      {/* Toolbar */}
      <ConnectionToolbar
        connectionState={connectionState}
        selectedPort={selectedPort}
        baudRate={baudRate}
        dataParams={dataParams}
        onPortChange={setSelectedPort}
        onBaudChange={setBaudRate}
        onDataParamsChange={setDataParams}
        onConnect={handleConnect}
        onDisconnect={handleDisconnect}
        showPresets={showPresets}
        onTogglePresets={() => setShowPresets((v) => !v)}
      />

      {/* Main workspace */}
      <div style={{ display: "flex", flex: 1, minHeight: 0, overflow: "hidden", position: "relative" }}>
        {/* Left: console + send */}
        <div style={{ display: "flex", flexDirection: "column", flex: 1, minWidth: 0, overflow: "hidden" }}>
          <ReceiveConsole
            entries={logEntries}
            displayFormat={displayFormat}
            showTimestamps={showTimestamps}
            autoScroll={autoScroll}
            isPaused={isPaused}
            onDisplayFormatChange={setDisplayFormat}
            onShowTimestampsChange={setShowTimestamps}
            onAutoScrollChange={setAutoScroll}
            onPause={handlePause}
            onResume={handleResume}
            onClear={handleClear}
          />
          <SendEditor
            connected={connected}
            sendMode={sendMode}
            lineEnding={lineEnding}
            autoSendEnabled={autoSendEnabled}
            autoSendInterval={autoSendInterval}
            onSendModeChange={setSendMode}
            onLineEndingChange={setLineEnding}
            onAutoSendChange={(enabled, interval) => {
              handleAutoSendChange(enabled, interval);
            }}
            onSend={(text) => {
              setAutoSendText(text);
              handleSend(text);
            }}
          />
        </div>

        {/* Right: Preset inspector */}
        {showPresets && (
          <PresetInspector
            presets={presets}
            connected={connected}
            loopRunning={loopRunning}
            loopInterval={loopInterval}
            onTogglePreset={handleTogglePreset}
            onSendPreset={handleSendPreset}
            onEditPreset={(preset) => setEditingPreset(preset)}
            onDeletePreset={handleDeletePreset}
            onNewPreset={() => setEditingPreset("new")}
            onLoopToggle={handleLoopToggle}
            onLoopIntervalChange={setLoopInterval}
          />
        )}
      </div>

      {/* Status bar */}
      <StatusBar
        port={selectedPort}
        baudRate={baudRate}
        rxBytes={rxBytes}
        txBytes={txBytes}
        logStatus={logStatus}
        lastError={lastError}
        connectionState={connectionState}
      />

      {/* Preset modal */}
      {editingPreset !== null && (
        <PresetEditModal
          preset={editingPreset === "new" ? null : editingPreset}
          onSave={handleSavePreset}
          onClose={() => setEditingPreset(null)}
        />
      )}
    </div>
  );
}
