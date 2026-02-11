$environments = @("dev", "test", "acc", "prod")
$orgName = "NWB Bank"
$country = "NL"

Write-Host "Starting CA CSR & PEM Key generation..." -ForegroundColor Cyan

foreach ($env in $environments) {
    $envUpper = $env.ToUpper()
    $keyFile = "$env-ca.key"        # Microsoft Blob (voor intern gebruik)
    $pemFile = "$env-ca-ready.key"  # PKCS#8 PEM (voor Kubernetes/OpenSSL)
    $csrFile = "$env-ca.csr"        # De aanvraag
    $commonName = "$orgName $envUpper Intermediate CA"

    Write-Host "`nProcessing Environment: $envUpper" -ForegroundColor Yellow

    # --- 1. PRIVATE KEY (Genereren of Laden) ---
    if (-not (Test-Path $keyFile)) {
        Write-Host "  [1/3] Generating New Private Key (4096 bit)..."
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(4096)
        
        # Sla op als Microsoft Blob
        $keyBytes = $rsa.ExportCspBlob($true)
        $keyBase64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
        Set-Content -Path $keyFile -Value $keyBase64 -Encoding Ascii
    } else {
        Write-Host "  [1/3] Private Key aanwezig. Laden..." -ForegroundColor Gray
        $keyBase64 = Get-Content $keyFile -Raw
        $keyBytes = [Convert]::FromBase64String($keyBase64)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.ImportCspBlob($keyBytes)
    }

    # --- 2. PEM CONVERSIE (Export naar PKCS#8) ---
    Write-Host "  [2/3] Converting Key to PKCS#8 PEM format..."
    try {
        $pkcs8Bytes = $rsa.ExportPkcs8PrivateKey()
        $pkcs8Base64 = [Convert]::ToBase64String($pkcs8Bytes, [Base64FormattingOptions]::InsertLineBreaks)
        $pemContent = "-----BEGIN PRIVATE KEY-----`r`n$pkcs8Base64`r`n-----END PRIVATE KEY-----"
        Set-Content -Path $pemFile -Value $pemContent -Encoding Ascii
        Write-Host "        -> Key opgeslagen in: $pemFile" -ForegroundColor Gray
    } catch {
        Write-Error "Fout bij PEM export: $_"
    }

    # --- 3. CSR GENERATIE (Met CA Extensies) ---
    Write-Host "  [3/3] Generating CSR with CA extensions..."
    $distinguishedName = "CN=$commonName, O=$orgName, C=$country"
    $subject = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName $distinguishedName
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1

    $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, $hashAlgorithm, $padding)

    # Voeg Basic Constraints toe (Cruciaal voor CA: True)
    $basicConstraints = New-Object System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension($true, $false, 0, $true)
    $request.CertificateExtensions.Add($basicConstraints)

    # Voeg Key Usage toe (Certificaten en CRL's tekenen)
    $keyUsageFlags = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign
    $keyUsage = New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension($keyUsageFlags, $true)
    $request.CertificateExtensions.Add($keyUsage)

    # Sla CSR op
    $csrBytes = $request.CreateSigningRequest()
    $csrBase64 = [Convert]::ToBase64String($csrBytes, [Base64FormattingOptions]::InsertLineBreaks)
    $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`r`n$csrBase64`r`n-----END CERTIFICATE REQUEST-----"
    Set-Content -Path $csrFile -Value $csrPem -Encoding Ascii

    Write-Host "  Succes: CSR en PEM-Key gegenereerd voor $envUpper" -ForegroundColor Green
}

Write-Host "`nKlaar! Alle bestanden staan in de huidige map." -ForegroundColor Cyan