$environments = @("dev", "test", "acc", "prod")
$orgName = "NWB Bank"
$country = "NL"

Write-Host "Starting CSR generation (Legacy Compatibility Mode)..." -ForegroundColor Cyan

foreach ($env in $environments) {
    $envUpper = $env.ToUpper()
    $keyFile = "$env-ca.key"
    $csrFile = "$env-ca.csr"
    $commonName = "$orgName $envUpper Intermediate CA"

    Write-Host "Processing Environment: $envUpper" -ForegroundColor Yellow

    # 1. Generate Private Key (Dwing RSACryptoServiceProvider af)
    if (-not (Test-Path $keyFile)) {
        Write-Host "  Generating Private Key..."
        
        # We gebruiken specifiek de oudere provider die ExportCspBlob ondersteunt
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(4096)
        
        # Exporteer de key als een blob en sla op als Base64
        $keyBytes = $rsa.ExportCspBlob($true)
        $keyBase64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
        Set-Content -Path $keyFile -Value $keyBase64 -Encoding Ascii
    } else {
        Write-Host "  Private Key aanwezig. Laden..." -ForegroundColor Gray
        $keyBase64 = Get-Content $keyFile -Raw
        $keyBytes = [Convert]::FromBase64String($keyBase64)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.ImportCspBlob($keyBytes)
    }

    # 2. Generate CSR
    Write-Host "  Generating CSR..."
    
    $distinguishedName = "CN=$commonName, O=$orgName, C=$country"
    $subject = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName $distinguishedName
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1

    # De CertificateRequest class accepteert de RSA provider
    $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, $hashAlgorithm, $padding)

    $csrBytes = $request.CreateSigningRequest()
    $csrBase64 = [Convert]::ToBase64String($csrBytes, [Base64FormattingOptions]::InsertLineBreaks)
    $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`r`n$csrBase64`r`n-----END CERTIFICATE REQUEST-----"
    
    Set-Content -Path $csrFile -Value $csrPem -Encoding Ascii

    Write-Host "  Succes: $csrFile" -ForegroundColor Green
    Write-Host "----------------------------------------"
}

Write-Host "Klaar!" -ForegroundColor Cyan