import { exec } from "child_process";

export function runPublish(): Promise<{ ok: boolean; error?: string }> {
  return new Promise((resolve) => {
    exec("npm run publish-schedule", (err, stdout, stderr) => {
      if (err) {
        console.error("publish-schedule failed:", err.message);
        if (stderr) console.error("publish-schedule stderr:", stderr);
        resolve({ ok: false, error: err.message });
        return;
      }
      if (stdout) console.log("publish-schedule:", stdout);
      resolve({ ok: true });
    });
  });
}
