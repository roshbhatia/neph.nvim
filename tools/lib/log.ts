import { appendFileSync } from "node:fs";
import process from "node:process";

const LOG_PATH = `/tmp/neph-debug-${process.ppid}.log`;
const enabled = !!process.env.NEPH_DEBUG;

export function debug(module: string, message: string): void {
  if (!enabled) return;
  const now = new Date();
  const ts = [
    String(now.getHours()).padStart(2, "0"),
    String(now.getMinutes()).padStart(2, "0"),
    String(now.getSeconds()).padStart(2, "0"),
  ].join(":") + "." + String(now.getMilliseconds()).padStart(3, "0");
  const line = `[${ts}] [ts] [${module}] ${message}\n`;
  try {
    appendFileSync(LOG_PATH, line);
  } catch {
    // Cannot write log — silently ignore
  }
}
