$environments = @("dev", "test", "acc", "prod")
$orgName = "NWB Bank"
$country = "NL"

Write-Host "Starting CSR generation for OTAP environments..." -ForegroundColor Cyan

foreach ($env in $environments) {
    $envUpper = $env.ToUpper()
    $keyFile = "$env-ca.key"
    $csrFile = "$env-ca.csr"
    $commonName = "$orgName $envUpper Intermediate CA"

    Write-Host "Processing Environment: $envUpper" -ForegroundColor Yellow

    # 1. Generate Private Key (RSA 4096)
    if (-not (Test-Path $keyFile)) {
        Write-Host "  Generating Private Key ($keyFile)..."
        
        $rsa = [System.Security.Cryptography.RSA]::Create(4096)
        
        # Oplossing voor PS 5.1: Gebruik de oudere ExportParameters methode
        # We exporteren de RSAParameters en bouwen de key handmatig (of gebruiken een blob)
        # Voor maximale compatibiliteit gebruiken we hier CspBlob:
        $keyBytes = $rsa.ExportCspBlob($true)
        $keyBase64 = [Convert]::ToBase64String($keyBytes, [Base64FormattingOptions]::InsertLineBreaks)
        
        # Let op: Dit is een MS-specifieke blob. Voor een echte PEM (PKCS#8) 
        # in PS 5.1 is wat meer 'low-level' werk nodig. 
        # Alternatief: We gebruiken een helper om de key te bewaren.
        Set-Content -Path $keyFile -Value $keyBase64 -Encoding Ascii
    } else {
        Write-Host "  Private Key ($keyFile) al aanwezig." -ForegroundColor Gray
        $keyBase64 = Get-Content $keyFile -Raw
        $keyBytes = [Convert]::FromBase64String($keyBase64)
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportCspBlob($keyBytes)
    }

    # 2. Generate CSR
    Write-Host "  Generating CSR ($csrFile)..."
    
    $distinguishedName = "CN=$commonName, O=$orgName, C=$country"
    $subject = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName $distinguishedName
    
    # In PS 5.1 moeten we de CertificateRequest iets anders aanroepen 
    # omdat de constructor soms kieskeurig is over het type RSA object.
    $hashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    
    # Gebruik de constructor: (DN, RSA, HashName, Padding)
    $request = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest($subject, $rsa, $hashAlgorithm, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    $csrBytes = $request.CreateSigningRequest()
    $csrBase64 = [Convert]::ToBase64String($csrBytes, [Base64FormattingOptions]::InsertLineBreaks)
    $csrPem = "-----BEGIN CERTIFICATE REQUEST-----`n$csrBase64`n-----END CERTIFICATE REQUEST-----"
    
    Set-Content -Path $csrFile -Value $csrPem -Encoding Ascii

    Write-Host "  Klaar: $csrFile" -ForegroundColor Green
    Write-Host "----------------------------------------"
}