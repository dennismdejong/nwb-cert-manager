<#
.SYNOPSIS
    Imports PFX certificates as Kubernetes TLS secrets for NWB Bank DTAP environments.

.DESCRIPTION
    This script iterates through the OTAP environments (dev, test, acc, prod),
    extracts the Private Key and Certificate from a PFX file, and creates/updates
    a Kubernetes TLS secret in the specified cluster context.

.PARAMETER PfxPassword
    The password for the PFX files. If not provided, you will be prompted.

.NOTES
    - Requires 'kubectl' in the system PATH.
    - Does not require 'openssl'. Uses native .NET X509Certificate2.
    - Assumes PFX files are named '{env}-ca.pfx' (e.g., dev-ca.pfx).
    - You must configure the $clusterContexts hashtable below to match your kubeconfig.
#>

param(
    [Parameter(Mandatory=$false)]
    [System.Security.SecureString]$PfxPassword
)

# --- CONFIGURATION ---
$secretName = "nwb-workspace-ca-secret"
$namespace = "cert-manager"
$environments = @("dev", "test", "acc", "prod")

# MAP ENVIRONMENTS TO YOUR KUBECTL CONTEXTS HERE
# Example: "dev" = "my-dev-cluster-context"
$clusterContexts = @{
    "dev"  = "kind-dev"   # Replace with actual context name
    "test" = "kind-test"  # Replace with actual context name
    "acc"  = "kind-acc"   # Replace with actual context name
    "prod" = "kind-prod"  # Replace with actual context name
}
# ---------------------

# Prompt for password if not provided
if (-not $PfxPassword) {
    $PfxPassword = Read-Host "Enter Password for PFX files" -AsSecureString
}
# Convert SecureString to PlainText for OpenSSL (sensitive, but necessary for the command)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PfxPassword)
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

Write-Host "Starting Secret Import for OTAP environments..." -ForegroundColor Cyan

foreach ($env in $environments) {
    $pfxFile = "$env-ca.pfx"
    $context = $clusterContexts[$env]
    
    Write-Host "Processing Environment: $env.ToUpper()" -ForegroundColor Yellow

    # 1. Check for PFX
    if (-not (Test-Path $pfxFile)) {
        Write-Host "  Warning: PFX file '$pfxFile' not found. Skipping." -ForegroundColor DarkYellow
        continue
    }

    # 2. Check Context
    if (-not $context) {
        Write-Host "  Error: No kube-context defined for '$env'. Check configuration." -ForegroundColor Red
        continue
    }

    Write-Host "  Extracting certificates from $pfxFile..."
    
    # Temporary files for extraction
    $tempKey = "$env-temp.key"
    $tempCert = "$env-temp.crt"

    try {
        # Load PFX using .NET
        # We assume the PFX password was provided. If empty, pass empty string or null.
        $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        $certObj = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxFile, $PfxPassword, $flags)

        # 1. Export Certificate (PEM)
        $certBytes = $certObj.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $certBase64 = [Convert]::ToBase64String($certBytes, [Base64FormattingOptions]::InsertLineBreaks)
        $certPem = "-----BEGIN CERTIFICATE-----`n$certBase64`n-----END CERTIFICATE-----"
        Set-Content -Path $tempCert -Value $certPem -Encoding Ascii

        # 2. Export Private Key (PEM PKCS#8)
        # Check if PrivateKey is RSA
        $privateKey = $certObj.GetRSAPrivateKey()
        if ($privateKey) {
             $keyBytes = $privateKey.ExportPkcs8PrivateKey()
             $keyBase64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
             $keyPem = "-----BEGIN PRIVATE KEY-----`n$keyBase64`n-----END PRIVATE KEY-----"
             Set-Content -Path $tempKey -Value $keyPem -Encoding Ascii
        } else {
            throw "Private key is not RSA or is not exportable."
        }

        # 3. Create/Update Kubernetes Secret
        Write-Host "  Uploading secret to context '$context'..."
        
        # We use dry-run + apply to enable "upsert" (update if exists) behavior
        # This prevents "AlreadyExists" errors
        $secretCmd = "kubectl create secret tls $secretName --cert=$tempCert --key=$tempKey --namespace=$namespace --dry-run=client -o yaml"
        
        # Execute and pipe to apply
        Invoke-Expression $secretCmd | kubectl apply --context=$context -f - 

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Successfully updated secret '$secretName' in '$env'" -ForegroundColor Green
        } else {
            Write-Host "  Failed to apply secret to '$env'" -ForegroundColor Red
        }

    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
    } finally {
        # Cleanup temp files
        if (Test-Path $tempKey) { Remove-Item $tempKey }
        if (Test-Path $tempCert) { Remove-Item $tempCert }
        # Dispose cert object if possible (good practice, though PS handles it mostly)
        if ($certObj) { $certObj.Dispose() }
    }
    
    Write-Host "----------------------------------------"
}

Write-Host "All operations complete." -ForegroundColor Cyan
