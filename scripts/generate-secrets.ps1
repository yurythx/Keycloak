<#
.SYNOPSIS
    Gera as senhas fortes (secrets/*.txt) e, se o OpenSSL estiver disponível,
    um certificado TLS autoassinado para desenvolvimento (nginx/certs/*.pem).

.DESCRIPTION
    Não sobrescreve arquivos já existentes — rode uma vez por ambiente.
    Para produção, troque o certificado autoassinado pelo emitido pela CA
    da empresa (veja README.md).
#>

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$secretsDir = Join-Path $root "secrets"
$certsDir = Join-Path $root "nginx\certs"

function New-StrongPassword {
    param([int]$Length = 32)
    $bytes = New-Object byte[] $Length
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return [Convert]::ToBase64String($bytes).Substring(0, $Length) -replace '[/+=]', '-'
}

function New-SecretFile {
    param([string]$Path, [string]$Label)
    if (Test-Path $Path) {
        Write-Host "[skip] $Label já existe em $Path"
        return
    }
    $password = New-StrongPassword
    # Sem newline no final para não incluir "\n" acidental na senha lida pelo container
    [System.IO.File]::WriteAllText($Path, $password)
    Write-Host "[ok]   $Label gerado em $Path"
}

New-Item -ItemType Directory -Force -Path $secretsDir | Out-Null
New-Item -ItemType Directory -Force -Path $certsDir | Out-Null

New-SecretFile -Path (Join-Path $secretsDir "postgres_password.txt") -Label "Senha do Postgres"
New-SecretFile -Path (Join-Path $secretsDir "kc_admin_password.txt") -Label "Senha do admin do Keycloak"

$certPath = Join-Path $certsDir "fullchain.pem"
$keyPath = Join-Path $certsDir "privkey.pem"

if ((Test-Path $certPath) -and (Test-Path $keyPath)) {
    Write-Host "[skip] Certificado TLS já existe em nginx/certs/"
}
elseif (Get-Command openssl -ErrorAction SilentlyContinue) {
    Write-Host "[ok]   Gerando certificado autoassinado (APENAS para dev/teste)..."
    & openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
        -keyout $keyPath -out $certPath `
        -subj "/CN=auth.local" `
        -addext "subjectAltName=DNS:auth.local,DNS:localhost"
    Write-Host "[ok]   Certificado gerado em nginx/certs/ — SUBSTITUA por um certificado real antes de ir para produção."
}
else {
    Write-Warning "OpenSSL não encontrado no PATH. Gere manualmente 'nginx/certs/fullchain.pem' e 'nginx/certs/privkey.pem' (certificado real da sua CA, ou autoassinado) antes de subir o Nginx."
}

Write-Host ""
Write-Host "Pronto. Próximos passos:"
Write-Host "  1. cp .env.example .env   e revise os valores (KC_HOSTNAME, AD_*, etc.)"
Write-Host "  2. Coloque o certificado da CA do Active Directory em ./certs/"
Write-Host "  3. docker compose up -d --build"
