<#
.SYNOPSIS
    Gera as senhas fortes (secrets/*.txt) usadas pela stack.

.DESCRIPTION
    Não sobrescreve arquivos já existentes — rode uma vez por ambiente.
    O certificado TLS público não é gerado por este script: é responsabilidade
    do proxy externo (Coolify ou outro) na frente desta stack — veja
    docs/04-certificados-tls.md.
#>

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$secretsDir = Join-Path $root "secrets"

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

New-SecretFile -Path (Join-Path $secretsDir "postgres_password.txt") -Label "Senha do Postgres"
New-SecretFile -Path (Join-Path $secretsDir "kc_admin_password.txt") -Label "Senha do admin do Keycloak"

Write-Host ""
Write-Host "Pronto. Próximos passos:"
Write-Host "  1. cp .env.example .env   e revise os valores (KC_HOSTNAME, AD_*, etc.)"
Write-Host "  2. Coloque o certificado da CA do Active Directory em ./certs/"
Write-Host "  3. docker compose up -d --build"
Write-Host "  4. Configure o proxy externo (Coolify ou outro) apontando para keycloak:8080"
