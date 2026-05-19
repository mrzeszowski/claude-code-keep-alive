param([int]$Seconds = 0)

Add-Type -Namespace Win32 -Name PowerMgmt -MemberDefinition @'
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint esFlags);
'@

# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED  (matches caffeinate -dis)
[void][Win32.PowerMgmt]::SetThreadExecutionState([uint32]0x80000003)

if ($Seconds -gt 0) { Start-Sleep -Seconds $Seconds } else { Start-Sleep -Seconds 99999999 }
