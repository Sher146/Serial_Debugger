export type ConnectionState = "disconnected" | "connecting" | "connected" | "error";

export interface DataParams {
  dataBits: 7 | 8;
  parity: "none" | "even" | "odd";
  stopBits: 1 | 2;
  flow: "none" | "hardware";
}

export type LineEnding = "none" | "cr" | "lf" | "crlf";

export type DisplayFormat = "ascii" | "hex";

export interface LogEntry {
  id: string;
  timestamp: Date;
  direction: "RX" | "TX";
  raw: string;
  format: DisplayFormat;
}

export interface Preset {
  id: string;
  name: string;
  content: string;
  mode: "ascii" | "hex";
  enabled: boolean;
  note: string;
}
