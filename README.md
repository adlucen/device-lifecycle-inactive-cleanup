# Device Lifecycle — Inactive Device Cleanup Sample

A PowerShell 7 snippet demonstrating how to automate the cleanup of inactive Windows devices in Entra ID using Microsoft Graph API, running as an Azure Automation runbook.

## What it shows
- Certificate-based authentication against Microsoft Graph (no client secrets)
- Querying Intune-managed devices filtered by `approximateLastSignInDateTime`
- Disabling stale device objects in Entra ID
- Notifying the device owner's manager via Graph Mail API

## Part of a larger solution
This snippet is extracted from a full **device lifecycle automation** solution that tracks device state across multiple stages (active → inactive → disabled → removed), syncs status to ServiceNow, manages exception groups, and uses an Azure Automation Hybrid Worker to clean up on-premises AD DS objects alongside Entra ID, Intune, Autopilot, and Microsoft Defender.

## Stack
`PowerShell 7` · `Azure Automation` · `Microsoft Graph API` · `Entra ID` · `Microsoft Intune` · `Windows Autopilot` · `Azure Table Storage` · `Microsoft Defender` · `ServiceNow`
