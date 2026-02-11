$environments = @("dev", "test", "acc", "prod")

foreach ($env in $environments) {
    $keyFile = "$env-ca.key"
    $pemFile = "$env-ca-ready.key"

    if (Test-Path $keyFile) {
        Write-Host "Converting $keyFile naar PEM..." -ForegroundColor Yellow
        
        # 1. Lees de Microsoft Blob weer in
        $keyBase64 = Get-Content $keyFile -Raw
        $keyBytes = [Convert]::FromBase64String($keyBase64)
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.ImportCspBlob($keyBytes)

        # 2. Exporteer naar PKCS#8 (De standaard voor Kubernetes/OpenSSL)
        $pkcs8Bytes = $rsa.ExportPkcs8PrivateKey()
        $pkcs8Base64 = [Convert]::ToBase64String($pkcs8Bytes, [Base64FormattingOptions]::InsertLineBreaks)
        
        # 3. Voeg de PEM-headers toe
        $pemContent = "-----BEGIN PRIVATE KEY-----`r`n$pkcs8Base64`r`n-----END PRIVATE KEY-----"
        
        Set-Content -Path $pemFile -Value $pemContent -Encoding Ascii
        Write-Host "Succes! Gebruik nu: $pemFile" -ForegroundColor Green
    }
}