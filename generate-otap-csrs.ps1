<#
.SYNOPSIS
    Generates Private Keys and CSRs for NWB Bank DTAP environments.

.DESCRIPTION
    This script iterates through the OTAP environments (dev, test, acc, prod),
    generates a 4096-bit RSA private key, and creates a Certificate Signing Request (CSR)
    configured for the "NWB Bank [ENV] Intermediate CA".

.NOTES
    Does not require 'openssl'. Uses native .NET System.Security.Cryptography.
#>

$environments = @("dev", "test", "acc", "prod")
$orgName = "NWB Bank"
$country = "NL"

Write-Host "Starting CSR generation for OTAP environments..." -ForegroundColor Cyan

foreach ($env in $environments) {
    $envUpper = $env.ToUpper()
    $keyFile = "$env-ca.key"
    $csrFile = "$env-ca.csr"
    $commonName = "$orgName $envUpper Intermediate CA"
    $subject = "/C=$country/O=$orgName/CN=$commonName"

    Write-Host "Processing Environment: $envUpper" -ForegroundColor Yellow

    # 1. Generate Private Key (RSA 4096)
    if (-not (Test-Path $keyFile)) {
        Write-Host "  Generating Private Key ($keyFile)..."
        
        $rsa = [System.Security.Cryptography.RSA]::Create(4096)
        
        # Export as PKCS#8 PEM
        $keyBytes = $rsa.ExportPkcs8PrivateKey()
        $keyBase64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
        $keyPem = "-----BEGIN PRIVATE KEY-----`n$keyBase64`n-----END PRIVATE KEY-----"
        
        Set-Content -Path $keyFile -Value $keyPem -Encoding Ascii
    } else {
        Write-Host "  Private Key ($keyFile) already exists. Skipping generation." -ForegroundColor Gray
        # Load existing key to generate CSR
        $keyContent = Get-Content $keyFile -Raw
        $keyBase64 = $keyContent.Replace("-----BEGIN PRIVATE KEY-----", "").Replace("-----END PRIVATE KEY-----", "").Trim()
        $keyBytes = [Convert]::FromBase64String($keyBase64)
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $bytesRead = 0
        $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$bytesRead)
    }

    # 2. Generate CSR
    Write-Host "  Generating CSR ($csrFile)..."
    
    $distinguishedName = "CN=$commonName, O=$orgName, C=$country"
    $subject = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName $distinguishedName
    
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($subject, $rsa, $hashAlgorithm, $padding)

    # Create Signing Request
    $csrBytes = $request.CreateSigningRequest()
    $csrBase64 = [Convert]::ToBase64String($csrBytes, [Base64FormattingOptions]::InsertLineBreaks)
    $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`n$csrBase64`n-----END CERTIFICATE REQUEST-----"
    
    Set-Content -Path $csrFile -Value $csrPem -Encoding Ascii

    if (Test-Path $csrFile) {
        Write-Host "  Successfully created $csrFile" -ForegroundColor Green
    } else {
        Write-Host "  Error creating CSR for $env" -ForegroundColor Red
    }
    
    Write-Host "----------------------------------------"
}

Write-Host "All operations complete." -ForegroundColor Cyan
