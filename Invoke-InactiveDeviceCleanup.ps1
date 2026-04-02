#Requires -Version 7.0
<#
.SYNOPSIS
    Sample: Inactive Device Lifecycle Automation
.DESCRIPTION
    Demonstrates how to identify inactive Windows devices via Microsoft Graph,
    disable them in Entra ID, and notify the device owner's manager via mail.
    Uses certificate-based authentication — no client secrets in code.

    NOTE: Illustrative snippet. Production runbook includes Azure Table state
    tracking, configurable thresholds per exception group, Hybrid Worker for
    on-prem AD DS cleanup, full retry logic, and ServiceNow status updates.
    All sensitive values are stored as encrypted Automation Account variables.

.REQUIREMENTS
    - App registration with DeviceManagementManagedDevices.ReadWrite.All,
      Device.ReadWrite.All, Mail.Send Graph permissions
    - Certificate thumbprint stored as Automation Account variable
    - PowerShell 7.2 on Azure Automation
#>

param (
    [int]$InactiveDaysThreshold = 30
)

# ── Authentication ────────────────────────────────────────────────────────────
$tenantId     = Get-AutomationVariable -Name 'TenantId'
$clientId     = Get-AutomationVariable -Name 'AppClientId'
$certThumb    = Get-AutomationVariable -Name 'GraphCertThumbprint'
$notifySender = Get-AutomationVariable -Name 'NotificationSender'   # UPN of mailbox

$cert = Get-Item "Cert:\LocalMachine\My\$certThumb"

$tokenBody = @{
    grant_type            = 'client_credentials'
    client_id             = $clientId
    client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
    client_assertion      = (New-GraphJwtAssertion -Certificate $cert -ClientId $clientId -TenantId $tenantId)
    scope                 = 'https://graph.microsoft.com/.default'
}
$token       = (Invoke-RestMethod "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method Post -Body $tokenBody).access_token
$authHeaders = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

# ── Query inactive devices ────────────────────────────────────────────────────
$cutoffDate  = (Get-Date).AddDays(-$InactiveDaysThreshold).ToString('o')
$filterQuery = "operatingSystem eq 'Windows' and approximateLastSignInDateTime le $cutoffDate"
$deviceUrl   = "https://graph.microsoft.com/v1.0/devices?`$filter=$filterQuery&`$select=id,displayName,approximateLastSignInDateTime,registeredOwners"

$inactiveDevices = @()
do {
    $response        = Invoke-RestMethod $deviceUrl -Headers $authHeaders
    $inactiveDevices += $response.value
    $deviceUrl        = $response.'@odata.nextLink'
} while ($deviceUrl)

Write-Output "Found $($inactiveDevices.Count) devices inactive for $InactiveDaysThreshold+ days"

foreach ($device in $inactiveDevices) {

    # ── Disable the device object ─────────────────────────────────────────────
    $patchBody = @{ accountEnabled = $false } | ConvertTo-Json
    Invoke-RestMethod "https://graph.microsoft.com/v1.0/devices/$($device.id)" `
        -Method Patch -Headers $authHeaders -Body $patchBody | Out-Null

    Write-Output "Disabled: $($device.displayName)"

    # ── Notify manager ────────────────────────────────────────────────────────
    $ownerUrl = "https://graph.microsoft.com/v1.0/devices/$($device.id)/registeredOwners"
    $owners   = (Invoke-RestMethod $ownerUrl -Headers $authHeaders).value

    foreach ($owner in $owners) {
        $managerUrl = "https://graph.microsoft.com/v1.0/users/$($owner.id)/manager"
        $manager    = Invoke-RestMethod $managerUrl -Headers $authHeaders -ErrorAction SilentlyContinue
        if (-not $manager) { continue }

        $mailBody = @{
            message = @{
                subject      = "Device inactivity notice: $($device.displayName)"
                body         = @{
                    contentType = 'Text'
                    content     = "The device '$($device.displayName)' has been inactive for over $InactiveDaysThreshold days and has been disabled. Please arrange return or reactivation within 60 days to avoid removal."
                }
                toRecipients = @(@{ emailAddress = @{ address = $manager.mail } })
            }
        } | ConvertTo-Json -Depth 6

        Invoke-RestMethod "https://graph.microsoft.com/v1.0/users/$notifySender/sendMail" `
            -Method Post -Headers $authHeaders -Body $mailBody | Out-Null
    }
}

Write-Output "Cleanup pass complete."
