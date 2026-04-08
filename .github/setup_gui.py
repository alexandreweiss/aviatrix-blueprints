#!/usr/bin/env python3
"""
Aviatrix Blueprints — Setup GUI

A lightweight local web GUI that wraps setup.sh.
Opens a browser form to collect configuration, then streams
the setup script output in real time.

Usage:
    cd blueprints/.github
    python3 setup_gui.py

No external dependencies — uses only the Python standard library.
"""

import http.server
import json
import os
import signal
import subprocess
import sys
import threading
import webbrowser

PORT = 8471
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SETUP_SCRIPT = os.path.join(SCRIPT_DIR, "setup.sh")

# ── HTML / CSS / JS ────────────────────────────────────────────

HTML_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aviatrix Blueprints Setup</title>
<style>
  :root {
    --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3a;
    --text: #e4e4e7; --muted: #71717a; --accent: #6366f1;
    --accent-hover: #818cf8; --green: #22c55e; --red: #ef4444;
    --yellow: #eab308; --radius: 10px;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
    background: var(--bg); color: var(--text);
    min-height: 100vh; padding: 2rem;
  }
  .container { max-width: 680px; margin: 0 auto; }
  .logo {
    text-align: center; margin-bottom: 2rem;
  }
  .logo h1 {
    font-size: 1.5rem; font-weight: 600; letter-spacing: -0.02em;
  }
  .logo p { color: var(--muted); font-size: 0.85rem; margin-top: 0.25rem; }

  /* Status bar */
  .status-bar {
    display: flex; gap: 0.5rem; flex-wrap: wrap;
    margin-bottom: 1.5rem; justify-content: center;
  }
  .status-pill {
    font-size: 0.75rem; padding: 0.3rem 0.7rem; border-radius: 99px;
    background: var(--surface); border: 1px solid var(--border);
    color: var(--muted); display: flex; align-items: center; gap: 0.35rem;
  }
  .status-pill .dot {
    width: 6px; height: 6px; border-radius: 50%; background: var(--muted);
  }
  .status-pill.ok .dot { background: var(--green); }
  .status-pill.err .dot { background: var(--red); }
  .status-pill.loading .dot {
    background: var(--yellow);
    animation: pulse 1s ease-in-out infinite;
  }
  @keyframes pulse { 50% { opacity: 0.4; } }

  /* Card */
  .card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: var(--radius); padding: 1.5rem; margin-bottom: 1rem;
  }
  .card h2 {
    font-size: 0.95rem; font-weight: 600; margin-bottom: 1rem;
    display: flex; align-items: center; gap: 0.5rem;
  }
  .card h2 .step {
    font-size: 0.7rem; background: var(--accent); color: #fff;
    padding: 0.15rem 0.5rem; border-radius: 99px;
  }

  /* Form */
  .field { margin-bottom: 0.85rem; }
  .field label {
    display: block; font-size: 0.8rem; font-weight: 500;
    margin-bottom: 0.3rem; color: var(--muted);
  }
  .field input, .field textarea {
    width: 100%; padding: 0.55rem 0.75rem; font-size: 0.85rem;
    background: var(--bg); border: 1px solid var(--border);
    border-radius: 6px; color: var(--text); outline: none;
    transition: border-color 0.15s;
  }
  .field input:focus, .field textarea:focus {
    border-color: var(--accent);
  }
  .field input::placeholder { color: var(--muted); opacity: 0.6; }
  .field .hint { font-size: 0.72rem; color: var(--muted); margin-top: 0.2rem; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem; }

  /* Toggle */
  .toggle-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0.6rem 0; border-bottom: 1px solid var(--border);
  }
  .toggle-row:last-child { border-bottom: none; }
  .toggle-row span { font-size: 0.85rem; }
  .toggle {
    position: relative; width: 40px; height: 22px; cursor: pointer;
  }
  .toggle input { display: none; }
  .toggle .slider {
    position: absolute; inset: 0; background: var(--border);
    border-radius: 99px; transition: 0.2s;
  }
  .toggle .slider::before {
    content: ''; position: absolute; width: 16px; height: 16px;
    left: 3px; bottom: 3px; background: var(--text);
    border-radius: 50%; transition: 0.2s;
  }
  .toggle input:checked + .slider { background: var(--accent); }
  .toggle input:checked + .slider::before { transform: translateX(18px); }

  /* Collapsible cloud sections */
  .cloud-section { display: none; margin-top: 0.75rem; }
  .cloud-section.visible { display: block; }

  /* Radio group */
  .radio-group { display: flex; gap: 0.5rem; }
  .radio-option {
    flex: 1; padding: 0.65rem 0.75rem; border-radius: 8px; cursor: pointer;
    border: 1px solid var(--border); background: var(--bg);
    transition: border-color 0.15s, background 0.15s;
  }
  .radio-option:hover { border-color: var(--accent); }
  .radio-option.selected {
    border-color: var(--accent); background: rgba(99,102,241,0.08);
  }
  .radio-option input { display: none; }
  .radio-content { display: flex; flex-direction: column; gap: 0.15rem; }
  .radio-content strong { font-size: 0.85rem; }
  .radio-content span { font-size: 0.72rem; color: var(--muted); }
  .radio-content code {
    font-family: 'SF Mono', 'Fira Code', monospace; font-size: 0.7rem;
    background: var(--surface); padding: 0.1rem 0.3rem; border-radius: 3px;
  }

  /* Button */
  .btn {
    width: 100%; padding: 0.7rem; font-size: 0.9rem; font-weight: 600;
    border: none; border-radius: 8px; cursor: pointer;
    background: var(--accent); color: #fff;
    transition: background 0.15s, opacity 0.15s;
    margin-top: 0.5rem;
  }
  .btn:hover { background: var(--accent-hover); }
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }

  /* Log output */
  .log-wrap {
    display: none; margin-top: 1rem;
  }
  .log-wrap.visible { display: block; }
  .log {
    background: #000; border: 1px solid var(--border); border-radius: 8px;
    padding: 1rem; font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
    font-size: 0.78rem; line-height: 1.6; max-height: 400px;
    overflow-y: auto; white-space: pre-wrap; word-break: break-all;
  }
  .log .ok { color: var(--green); }
  .log .err { color: var(--red); }
  .log .warn { color: var(--yellow); }
  .log .info { color: #60a5fa; }
  .log .bold { font-weight: 700; color: #fff; }

  /* Result banner */
  .result-banner {
    display: none; padding: 0.75rem 1rem; border-radius: 8px;
    font-size: 0.85rem; font-weight: 500; margin-top: 0.75rem;
    text-align: center;
  }
  .result-banner.success {
    display: block; background: rgba(34,197,94,0.12);
    border: 1px solid rgba(34,197,94,0.3); color: var(--green);
  }
  .result-banner.failure {
    display: block; background: rgba(239,68,68,0.12);
    border: 1px solid rgba(239,68,68,0.3); color: var(--red);
  }
</style>
</head>
<body>
<div class="container">
  <div class="logo">
    <h1>Aviatrix Blueprints Setup</h1>
    <p>GitHub Actions environment configuration</p>
  </div>

  <!-- Status pills -->
  <div class="status-bar" id="statusBar">
    <div class="status-pill loading" id="st-gh"><span class="dot"></span>GitHub</div>
    <div class="status-pill loading" id="st-tf"><span class="dot"></span>Terraform</div>
    <div class="status-pill loading" id="st-repo"><span class="dot"></span>Repository</div>
    <div class="status-pill loading" id="st-aws"><span class="dot"></span>AWS</div>
    <div class="status-pill loading" id="st-azure"><span class="dot"></span>Azure</div>
    <div class="status-pill loading" id="st-gcp"><span class="dot"></span>GCP</div>
  </div>

  <!-- Form -->
  <form id="setupForm" autocomplete="off">
    <div class="card">
      <h2><span class="step">1</span> Aviatrix Controller</h2>
      <div class="row">
        <div class="field">
          <label>Controller IP</label>
          <input name="aviatrix_controller" placeholder="10.0.1.100" required>
        </div>
        <div class="field">
          <label>Username</label>
          <input name="aviatrix_user" value="admin">
        </div>
      </div>
      <div class="field">
        <label>Password</label>
        <input name="aviatrix_pass" type="password" required>
      </div>
    </div>

    <div class="card">
      <h2><span class="step">2</span> Cloud Providers</h2>
      <p style="font-size:0.8rem; color:var(--muted); margin-bottom:0.75rem;">Enable one or more CSPs to configure credentials and secrets.</p>

      <!-- AWS -->
      <div class="toggle-row">
        <span>AWS</span>
        <label class="toggle">
          <input type="checkbox" id="awsToggle" checked onchange="toggleCloud('aws')">
          <span class="slider"></span>
        </label>
      </div>
      <div class="cloud-section visible" id="awsSection">
        <div class="row">
          <div class="field">
            <label>AWS Region</label>
            <input name="aws_region" value="us-east-2">
          </div>
          <div class="field">
            <label>IAM Role ARN (OIDC)</label>
            <input name="aws_role_arn" placeholder="arn:aws:iam::...:role/...">
          </div>
        </div>
        <div class="field">
          <label>Aviatrix-onboarded AWS Account Name</label>
          <input name="avx_aws_account" value="lab-test-aws">
        </div>
      </div>

      <!-- Azure -->
      <div class="toggle-row">
        <span>Azure</span>
        <label class="toggle">
          <input type="checkbox" id="azureToggle" onchange="toggleCloud('azure')">
          <span class="slider"></span>
        </label>
      </div>
      <div class="cloud-section" id="azureSection">
        <div class="row">
          <div class="field">
            <label>Azure Region</label>
            <input name="azure_region" value="East US 2">
          </div>
          <div class="field">
            <label>Aviatrix Azure Account Name</label>
            <input name="avx_azure_account" placeholder="lab-test-azure">
          </div>
        </div>
        <div class="field">
          <label>Azure Credentials JSON</label>
          <textarea name="azure_creds" rows="2" placeholder='{"clientId":"...","clientSecret":"...","subscriptionId":"...","tenantId":"..."}'></textarea>
        </div>
      </div>

      <!-- GCP -->
      <div class="toggle-row">
        <span>GCP</span>
        <label class="toggle">
          <input type="checkbox" id="gcpToggle" onchange="toggleCloud('gcp')">
          <span class="slider"></span>
        </label>
      </div>
      <div class="cloud-section" id="gcpSection">
        <div class="row">
          <div class="field">
            <label>GCP Region</label>
            <input name="gcp_region" value="us-central1">
          </div>
          <div class="field">
            <label>Aviatrix GCP Account Name</label>
            <input name="avx_gcp_account" placeholder="lab-test-gcp">
          </div>
        </div>
        <div class="field">
          <label>GCP Credentials JSON</label>
          <textarea name="gcp_creds" rows="2" placeholder='{"type":"service_account",...}'></textarea>
        </div>
      </div>
    </div>

    <div class="card">
      <h2><span class="step">3</span> Terraform Bootstrap</h2>
      <p style="font-size:0.8rem; color:var(--muted); margin-bottom:0.75rem;">The S3 state bucket can be created locally or via a GitHub Actions workflow.</p>
      <div class="radio-group">
        <label class="radio-option selected" id="optLocal">
          <input type="radio" name="bootstrap_mode" value="local" checked onchange="setBootstrapMode('local')">
          <div class="radio-content">
            <strong>Run locally</strong>
            <span>Runs <code>terraform apply</code> on this machine now</span>
          </div>
        </label>
        <label class="radio-option" id="optRemote">
          <input type="radio" name="bootstrap_mode" value="remote" onchange="setBootstrapMode('remote')">
          <div class="radio-content">
            <strong>GitHub Actions</strong>
            <span>Skips bootstrap — you trigger it from the Actions tab</span>
          </div>
        </label>
      </div>
    </div>

    <button type="submit" class="btn" id="runBtn">Run Setup</button>
  </form>

  <div class="log-wrap" id="logWrap">
    <div class="card" style="padding: 0.75rem;">
      <h2 style="margin-bottom: 0.5rem;">Output</h2>
      <div class="log" id="log"></div>
    </div>
    <div class="result-banner" id="resultBanner"></div>
  </div>
</div>

<script>
function toggleCloud(name) {
  const section = document.getElementById(name + 'Section');
  const toggle = document.getElementById(name + 'Toggle');
  section.classList.toggle('visible', toggle.checked);
}

function setBootstrapMode(mode) {
  document.getElementById('optLocal').classList.toggle('selected', mode === 'local');
  document.getElementById('optRemote').classList.toggle('selected', mode === 'remote');
}

// Preflight check
fetch('/api/preflight').then(r => r.json()).then(data => {
  for (const [key, val] of Object.entries(data)) {
    const el = document.getElementById('st-' + key);
    if (el) {
      el.classList.remove('loading');
      el.classList.add(val.ok ? 'ok' : 'err');
      if (val.detail) el.title = val.detail;
    }
  }
});

// Form submit
document.getElementById('setupForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = document.getElementById('runBtn');
  const logWrap = document.getElementById('logWrap');
  const log = document.getElementById('log');
  const banner = document.getElementById('resultBanner');

  btn.disabled = true;
  btn.textContent = 'Running...';
  logWrap.classList.add('visible');
  log.innerHTML = '';
  banner.className = 'result-banner';
  banner.style.display = 'none';

  const fd = new FormData(e.target);
  const body = {};
  fd.forEach((v, k) => { body[k] = v; });
  body.setup_aws = document.getElementById('awsToggle').checked;
  body.setup_azure = document.getElementById('azureToggle').checked;
  body.setup_gcp = document.getElementById('gcpToggle').checked;
  body.bootstrap_mode = document.querySelector('input[name="bootstrap_mode"]:checked').value;

  try {
    const res = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const reader = res.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const text = decoder.decode(value);
      log.innerHTML += colorize(text);
      log.scrollTop = log.scrollHeight;
    }

    // Check exit code from last line
    const lines = log.textContent.trim().split('\n');
    const last = lines[lines.length - 1];
    if (last.includes('EXIT_CODE:0')) {
      log.innerHTML = log.innerHTML.replace(/EXIT_CODE:\d+/, '');
      banner.textContent = 'Setup completed successfully!';
      banner.className = 'result-banner success';
    } else {
      banner.textContent = 'Setup failed. Check the output above.';
      banner.className = 'result-banner failure';
    }
  } catch (err) {
    log.innerHTML += '<span class="err">Connection error: ' + err.message + '</span>\n';
    banner.textContent = 'Setup failed.';
    banner.className = 'result-banner failure';
  }

  btn.disabled = false;
  btn.textContent = 'Run Setup Again';
});

function colorize(text) {
  return text
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/^(✓.*)$/gm, '<span class="ok">$1</span>')
    .replace(/^(✗.*)$/gm, '<span class="err">$1</span>')
    .replace(/^(!.*)$/gm, '<span class="warn">$1</span>')
    .replace(/^(▸.*)$/gm, '<span class="info">$1</span>')
    .replace(/^(═══.*═══)$/gm, '<span class="bold">$1</span>');
}
</script>
</body>
</html>
"""


class RequestHandler(http.server.BaseHTTPRequestHandler):
    """Minimal HTTP handler — serves the GUI and runs the setup script."""

    def log_message(self, fmt, *args):
        pass  # silence request logs

    def _cors(self):
        self.send_header("Cache-Control", "no-store")

    def do_GET(self):
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self._cors()
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode())
        elif self.path == "/api/preflight":
            self._handle_preflight()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/api/run":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            self._handle_run(body)
        else:
            self.send_error(404)

    # ── Preflight checks ───────────────────────────────────────

    def _handle_preflight(self):
        results = {}

        # AWS
        try:
            out = subprocess.run(
                ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
                capture_output=True, text=True, timeout=10,
            )
            results["aws"] = {"ok": out.returncode == 0, "detail": out.stdout.strip()}
        except Exception as e:
            results["aws"] = {"ok": False, "detail": str(e)}

        # GitHub CLI
        try:
            out = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True, timeout=10)
            results["gh"] = {"ok": out.returncode == 0}
        except Exception:
            results["gh"] = {"ok": False}

        # Terraform
        try:
            out = subprocess.run(["terraform", "version"], capture_output=True, text=True, timeout=10)
            results["tf"] = {"ok": out.returncode == 0}
        except Exception:
            results["tf"] = {"ok": False}

        # Azure CLI
        try:
            out = subprocess.run(["az", "account", "show", "--query", "name", "-o", "tsv"],
                                 capture_output=True, text=True, timeout=10)
            results["azure"] = {"ok": out.returncode == 0, "detail": out.stdout.strip()}
        except Exception:
            results["azure"] = {"ok": False, "detail": "az CLI not found"}

        # GCP CLI
        try:
            out = subprocess.run(["gcloud", "config", "get-value", "project"],
                                 capture_output=True, text=True, timeout=10)
            results["gcp"] = {"ok": out.returncode == 0 and bool(out.stdout.strip()),
                              "detail": out.stdout.strip()}
        except Exception:
            results["gcp"] = {"ok": False, "detail": "gcloud CLI not found"}

        # Repository
        try:
            out = subprocess.run(
                ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                capture_output=True, text=True, timeout=10, cwd=SCRIPT_DIR,
            )
            results["repo"] = {"ok": out.returncode == 0, "detail": out.stdout.strip()}
        except Exception:
            results["repo"] = {"ok": False}

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self._cors()
        self.end_headers()
        self.wfile.write(json.dumps(results).encode())

    # ── Run setup ──────────────────────────────────────────────

    def _handle_run(self, config):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Transfer-Encoding", "chunked")
        self._cors()
        self.end_headers()

        env = os.environ.copy()
        env.update({
            "GUI_MODE": "1",
            "CFG_BOOTSTRAP_MODE": config.get("bootstrap_mode", "local"),
            "CFG_AVIATRIX_CONTROLLER": config.get("aviatrix_controller", ""),
            "CFG_AVIATRIX_USER": config.get("aviatrix_user", "admin"),
            "CFG_AVIATRIX_PASS": config.get("aviatrix_pass", ""),
            "CFG_SETUP_AWS": "y" if config.get("setup_aws") else "n",
            "CFG_AWS_REGION": config.get("aws_region", "us-east-2"),
            "CFG_AVX_AWS_ACCOUNT": config.get("avx_aws_account", "lab-test-aws"),
            "CFG_AWS_ROLE_ARN": config.get("aws_role_arn", ""),
            "CFG_SETUP_AZURE": "y" if config.get("setup_azure") else "n",
            "CFG_AZURE_REGION": config.get("azure_region", "East US 2"),
            "CFG_AZURE_CREDS": config.get("azure_creds", ""),
            "CFG_AVX_AZURE_ACCOUNT": config.get("avx_azure_account", ""),
            "CFG_SETUP_GCP": "y" if config.get("setup_gcp") else "n",
            "CFG_GCP_REGION": config.get("gcp_region", "us-central1"),
            "CFG_GCP_CREDS": config.get("gcp_creds", ""),
            "CFG_AVX_GCP_ACCOUNT": config.get("avx_gcp_account", ""),
        })

        wrapper = os.path.join(SCRIPT_DIR, "setup_headless.sh")
        try:
            proc = subprocess.Popen(
                ["bash", wrapper],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                env=env, cwd=SCRIPT_DIR,
            )
            for line in iter(proc.stdout.readline, b""):
                chunk = line.decode("utf-8", errors="replace")
                # Strip ANSI escape codes for the web log
                import re
                chunk = re.sub(r"\033\[[0-9;]*m", "", chunk)
                self._send_chunk(chunk)
            proc.wait()
            self._send_chunk(f"EXIT_CODE:{proc.returncode}\n")
        except Exception as e:
            self._send_chunk(f"✗ Error: {e}\n")
            self._send_chunk("EXIT_CODE:1\n")

        self._send_chunk("")  # final empty chunk

    def _send_chunk(self, data):
        encoded = data.encode("utf-8")
        try:
            self.wfile.write(f"{len(encoded):x}\r\n".encode())
            self.wfile.write(encoded + b"\r\n")
            self.wfile.flush()
        except BrokenPipeError:
            pass


def main():
    server = http.server.HTTPServer(("127.0.0.1", PORT), RequestHandler)
    url = f"http://127.0.0.1:{PORT}"
    print(f"\n  Aviatrix Blueprints Setup GUI")
    print(f"  Listening on {url}")
    print(f"  Press Ctrl+C to stop\n")

    # Open browser after a brief delay
    threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Shutting down.")
        server.shutdown()


if __name__ == "__main__":
    main()
