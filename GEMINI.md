# NWB Bank DTAP PKI & Cert Manager

## Project Overview
This project manages the Public Key Infrastructure (PKI) for NWB Bank's DTAP environments (Dev, Test, Acc, Prod) on the NKP platform. It combines a GitOps approach (using FluxCD) for managing `cert-manager` resources with local automation scripts for handling sensitive private keys and interactions with the corporate Windows AD CS Root CA.

**Core Technologies:**
*   **Kubernetes:** Target platform.
*   **cert-manager:** Manages certificates within the cluster.
*   **FluxCD:** Handles GitOps deployment of `ClusterIssuers` and `Certificates`.
*   **PowerShell:** Automates the local "bridge" tasks (Key/CSR generation, Secret upload).
*   **Windows AD CS:** The Root Authority that signs the intermediate CAs.

## Architecture & Workflow
The system follows a split-responsibility model:

1.  **Infrastructure (GitOps):** Defined in `nwb-dtap-pki/`. Flux synchronizes these manifests. This includes the `ClusterIssuer` definition, but *not* the secret it references.
2.  **Secrets (Local/Manual):** The Private Keys for the Intermediate CAs are generated locally, signed by the Root CA, and pushed directly to the cluster as Kubernetes Secrets. They are *never* committed to Git.

### Directory Structure
*   `nwb-dtap-pki/`
    *   `base/`: Shared Kustomize bases.
        *   `pki-issuer/`: Defines the `ClusterIssuer` (`nwb-workspace-ca-issuer`).
        *   `test-app/`: A sample application to verify certificate issuance.
    *   `clusters/`: Environment-specific overlays (`dev`, `prod`, etc.) used by Flux.
*   `generate-otap-csrs.ps1`: Automation to create Private Keys and CSRs.
*   `import-otap-secrets.ps1`: Automation to parse signed PFX files and upload them as Kubernetes Secrets.

## Setup & Usage

### 1. Initialization (Local)
Use the PowerShell scripts to bootstrap the environment. These scripts require `pwsh` and `kubectl`.

**A. Generate CSRs**
Generates 4096-bit RSA keys and CSRs for all environments (`dev`, `test`, `acc`, `prod`).
```bash
pwsh ./generate-otap-csrs.ps1
```
*Output:* `dev-ca.key`, `dev-ca.csr`, etc.

**B. Sign Certificates (Manual)**
1.  Take the generated `.csr` files to the Windows AD CS Web Enrollment portal.
2.  Submit request using the **Subordinate Certification Authority** template.
3.  Download the signed certificate as a **PFX** (or convert the signed CRT + Key to PFX locally).
4.  Name the files `dev-ca.pfx`, `test-ca.pfx`, etc.

**C. Import Secrets**
Extracts keys/certs from the PFX files and uploads them to the configured Kubernetes clusters.
*Note: You must configure the `$clusterContexts` map in the script before running.*
```bash
pwsh ./import-otap-secrets.ps1
```

### 2. Deployment (GitOps)
Once the secrets are in place (`nwb-workspace-ca-secret`), Flux will reconcile the manifests in `nwb-dtap-pki/`.

*   The `ClusterIssuer` will become Ready.
*   Applications (like `test-app`) can request certificates by referencing `nwb-workspace-ca-issuer`.

## Development Conventions
*   **Kustomize:** Use `base` for shared logic and `overlays` (in `clusters/`) for environment specifics.
*   **Security:**
    *   **NEVER** commit `.key`, `.pfx`, or `.crt` files to the repository.
    *   **NEVER** commit the Kubernetes Secret manifest containing the CA key.
*   **Naming:**
    *   Issuer Name: `nwb-workspace-ca-issuer`
    *   Secret Name: `nwb-workspace-ca-secret`
