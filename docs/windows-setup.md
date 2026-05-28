# Windows Setup Guide

Since this project uses Unix-native tools (bash, make), here are two ways to run it on Windows.

## Option A: PowerShell Native Scripts (Recommended — Zero Install)

If you have PowerShell 7+, Docker Desktop, kind, kubectl, istioctl, and helm already installed, run the PowerShell scripts directly:

```powershell
# 1. Setup
.\scripts\setup-kind.ps1

# 2. Verify
kubectl get pods -n payments
kubectl port-forward svc/payments-api -n payments 8083:8080
# In another terminal:
curl http://localhost:8083/health

# 3. Run demos
.\scripts\demo-self-healing.ps1
.\scripts\demo-canary.ps1

# 4. Tear down
.\scripts\teardown-kind.ps1
```

## Option B: Git Bash + Make (Best Long-Term)

1. **Install Git for Windows** (includes Git Bash):
   https://git-scm.com/download/win

2. **Install Make** via Chocolatey or winget:
   ```powershell
   # Option 1: Chocolatey
   choco install make

   # Option 2: winget
   winget install GnuWin32.Make
   # Then add C:\Program Files (x86)\GnuWin32\bin to your PATH
   ```

3. **Open Git Bash** (right-click in your project folder → "Git Bash Here")

4. **Run everything with make**:
   ```bash
   make kind-up
   make demo-self-healing
   make demo-canary
   make kind-down
   ```

## Option C: WSL2 (Most Authentic Linux Experience)

1. Install WSL2 + Ubuntu:
   ```powershell
   wsl --install -d Ubuntu
   ```

2. Inside Ubuntu, install Docker, kind, kubectl, istioctl, helm:
   ```bash
   # Docker (Docker Desktop with WSL2 backend is easiest)
   # kind
   curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
   chmod +x ./kind
   sudo mv ./kind /usr/local/bin/

   # kubectl
   curl -LO "https://dl.k8s/release/$(curl -L -s https://dl.k8s/release/stable.txt)/bin/linux/amd64/kubectl"
   chmod +x kubectl
   sudo mv kubectl /usr/local/bin/

   # istioctl
   curl -L https://istio.io/downloadIstio | sh -
   export PATH="$PATH:$HOME/istio-*/bin"

   # helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   ```

3. Run the project:
   ```bash
   cd /mnt/c/Users/nuts/sesh
   make kind-up
   ```

## Prerequisites Checklist

- [ ] Docker Desktop running (with Kubernetes enabled OR WSL2 backend)
- [ ] kind installed: `kind version`
- [ ] kubectl installed: `kubectl version --client`
- [ ] istioctl installed: `istioctl version`
- [ ] helm installed: `helm version`

## Troubleshooting

### "kind" is not recognized
Make sure Docker Desktop is running and kind is in your PATH. Restart your terminal after installing.

### Docker Desktop Kubernetes vs kind
You can use either. This project specifically uses kind for a clean, reproducible local cluster.

### Port conflicts (8080, 8081, 8083)
The setup uses different ports to avoid conflicts:
- ArgoCD: `8080`
- kind ingress: `8081`
- payments-api test: `8083`

If these are taken, change them in the port-forward commands.
