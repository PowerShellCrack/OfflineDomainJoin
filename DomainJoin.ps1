<#
    .SYNOPSIS
        Script to join a Windows device to domain
    .DESCRIPTION
        Script is used to join the domain through different scenarios
    .PARAMETER JoinMethod
        Specifies what method to join system to domain: 'ODJ','Unattend','Windows'
    .PARAMETER JoinODJBlob
        Specifies the blob generated by djoin
    .PARAMETER JoinODJFile
        Specifies the file generated by djoin
    .PARAMETER UnattendFile
        Specifies the file path to unattend.xml. If in Task sequence OSDisk variable is used
    .PARAMETER JoinDomainName
        Specifies the domain name to join the device. Required when JoinMethod is Unattend. FQDN recommended
    .PARAMETER JoinUserName
        Specifies the domain account used to join the device. Required when JoinMethod is Unattend. Must be in format <domain>\<useraccount>
    .PARAMETER JoinPassword
        Specifies the domain account used to join the device. Required when JoinMethod is Unattend. 
    .PARAMETER JoinDomainOU
        Specifies the domain account used to join the device. Optional
    .PARAMETER Restart
    .EXAMPLE
        DomainJoin.ps1 -JoinMethod ODJ -JoinODJBlobFile <path to file> -Restart
    .EXAMPLE
        DomainJoin.ps1 -JoinMethod Unattend -JoinDomainName contoso.com -Join contoso\username -JoinPassword P@$$w0rd12
    .EXAMPLE
        DomainJoin.ps1 -JoinMethod Unattend -JoinODJBlob 'ARAIAMzMzMxIAwAAAAAAAAAA...'
    .EXAMPLE
        DomainJoin.ps1 -JoinMethod Windows -JoinDomainName contoso.com -Join contoso\username -JoinPassword P@$$w0rd12 -Restart
    .NOTES
        Author		: Dick Tracy II <richard.tracy@microsoft.com>
    	Source		: https://github.com/PowerShellCrack/OfflineDomainJoin
        Version		: 1.0.2
    .LINK
        https://github.com/PowerShellCrack/OfflineDomainJoin
    #>
[Cmdletbinding()]
Param (
    [Parameter(Mandatory=$False)]
    [ValidateSet('ODJ','Unattend','Windows')]
    [String]$JoinMethod = 'Windows',

    [Parameter(Mandatory=$False)]
    [string]$JoinODJBlob,

    [Parameter(Mandatory=$False)]
    $JoinODJFile,

    [Parameter(Mandatory=$False)]
    [string]$UnattendFile,

    [Parameter(Mandatory=$False)]
    [string]$JoinDomainName,

    [Parameter(Mandatory=$False)]
    [string]$JoinUserName,

    [Parameter(Mandatory=$False)]
    [string]$JoinPassword,

    [Parameter(Mandatory=$False)]
    [string]$JoinDomainOU,

    [Parameter(Mandatory=$False)]
    [switch]$Restart
)
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
If($Restart){$BoolRestart=$true}Else{$BoolRestart=$false}
##*=============================================
##* Runtime Function - REQUIRED
##*=============================================
#region FUNCTION: Check if running in WinPE
Function Test-WinPE{
    return Test-Path -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlset\Control\MiniNT
}
#endregion

#region FUNCTION: Check if running in ISE
Function Test-IsISE {
    # try...catch accounts for:
    # Set-StrictMode -Version latest
    try {
        return ($null -ne $psISE);
    }
    catch {
        return $false;
    }
}
#endregion

#region FUNCTION: Check if running in Visual Studio Code
Function Test-VSCode{
    if($env:TERM_PROGRAM -eq 'vscode') {
        return $true;
    }
    Else{
        return $false;
    }
}
#endregion

#region FUNCTION: Find script path for either ISE or console
Function Get-ScriptPath {
    <#
        .SYNOPSIS
            Finds the current script path even in ISE or VSC
        .LINK
            Test-VSCode
            Test-IsISE
    #>
    param(
        [switch]$Parent
    )

    Begin{}
    Process{
        if ($PSScriptRoot -eq "")
        {
            if (Test-IsISE)
            {
                $ScriptPath = $psISE.CurrentFile.FullPath
            }
            elseif(Test-VSCode){
                $context = $psEditor.GetEditorContext()
                $ScriptPath = $context.CurrentFile.Path
            }Else{
                $ScriptPath = (Get-location).Path
            }
        }
        else
        {
            $ScriptPath = $PSCommandPath
        }
    }
    End{

        If($Parent){
            Split-Path $ScriptPath -Parent
        }Else{
            $ScriptPath
        }
    }

}
#endregion

  
# Make PowerShell Disappear in WINPE
If(Test-WinPE){
    $windowcode = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $asyncwindow = Add-Type -MemberDefinition $windowcode -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $null = $asyncwindow::ShowWindowAsync((Get-Process -PID $pid).MainWindowHandle, 0)
}
##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VARIABLES: Building paths & values
# Use function to get paths because Powershell ISE & other editors have differnt results
[string]$scriptPath = Get-ScriptPath
[string]$scriptName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
[string]$scriptFileName = Split-Path -Path $scriptPath -Leaf
[string]$scriptRoot = Split-Path -Path $scriptPath -Parent

#Get required folder & File paths
[string]$FunctionPath = Join-Path -Path $scriptRoot -ChildPath 'Functions'

#*=============================================
##* Additional Runtime Function - REQUIRED
##*=============================================
#Load functions from external files
. "$FunctionPath\Environments.ps1"
. "$FunctionPath\Logging.ps1"
. "$FunctionPath\JoinTypeCmdlets.ps1"

#Return log path (either in task sequence or temp dir)
#build log name
[string]$FileName = $scriptName +'.log'
#build global log fullpath
$Global:LogFilePath = Join-Path (Test-SMSTSENV -ReturnLogPath -Verbose) -ChildPath $FileName
Write-Host "logging to file: $LogFilePath" -ForegroundColor Cyan
#*=============================================
##* MAIN
##*=============================================
#Grab variable from Task Sequence
If(Test-SMSTSENV){
    $JoinODJBlob = $tsenv.Value("OfflineDomainJoinBlob")
    Write-LogEntry ("OfflineDomainJoinBlob is now: {0}" -f $JoinODJBlob) -Severity 1 -Outhost
    $JoinODJFile = $tsenv.Value("OfflineDomainJoinFile")
    Write-LogEntry ("OfflineDomainJoinFile is now: {0}" -f $JoinODJFile) -Severity 1 -Outhost
    $ComputerName = $tsenv.Value("OSDComputerName")
    If($Null -eq $ComputerName){$ComputerName = $tsenv.Value("_SMSTSMachineName")}
    Write-LogEntry ("OSDComputerName is now: {0}" -f $ComputerName) -Severity 1 -Outhost
    $JoinDomainName = $tsenv.Value("OSDJoinDomainName")
    Write-LogEntry ("OSDJoinDomainName is now: {0}" -f $JoinDomainName) -Severity 1 -Outhost
    $JoinUserName = $tsenv.Value("OSDJoinAccount")
    Write-LogEntry ("OSDJoinAccount is now: {0}" -f $JoinUserName) -Severity 1 -Outhost
    $JoinPassword = $tsenv.Value("OSDJoinPassword")
    Write-LogEntry ("OSDJoinPassword is now: {0}" -f $OSDJoinPassword) -Severity 1 -Outhost
    $JoinDomainOU = $tsenv.Value("OSDJoinDomainOUName")
    Write-LogEntry ("OSDJoinDomainOUName is now: {0}" -f $JoinDomainOU) -Severity 1 -Outhost
    $OSDisk = $tsenv.Value("OSDisk")
    Write-LogEntry ("OSDisk is now: {0}" -f $OSDisk) -Severity 1 -Outhost
}

#force JoinMethod to 'Unattend' if running in PE
If( ($JoinMethod -eq 'Windows') -and (Test-WinPE) ){$JoinMethod = 'Unattend'}

# CHECK ODJ PARAMETERS
If($JoinMethod -eq 'ODJ' -and ( [string]::IsNullOrEmpty($JoinODJBlob) -or [string]::IsNullOrEmpty($JoinODJFile) ) ){
    Write-LogEntry "Unable to continue with ODJ. Required Parameters [JoinODJBlob or JoinODJFile] not found" -Severity 3 -Outhost; Exit -1
}

# CHECK DOMAIN JOIN PARAMETERS
If( ($JoinMethod -eq 'Windows') -and [string]::IsNullOrEmpty($JoinDomainName) -and [string]::IsNullOrEmpty($JoinUserName) -and [string]::IsNullOrEmpty($JoinPassword) ){
    Write-LogEntry "Unable to continue with Domain Join. Required Parameters [JoinDomainName,JoinUserName,JoinPassword] not found" -Severity 3 -Outhost; Exit -1
}

# CHECK DOMAIN JOIN PARAMETERS
If( ($JoinMethod -eq 'Unattend') -and [string]::IsNullOrEmpty($JoinDomainName) -and [string]::IsNullOrEmpty($JoinUserName) -and [string]::IsNullOrEmpty($JoinPassword) ){
    Write-LogEntry "Unable to apply Domain Join settings. Required [JoinDomainName,JoinUserName,JoinPassword] Parameters not found" -Severity 3 -Outhost; Exit -1
}

#DO THE JOIN ACTION
switch($JoinMethod){

    'ODJ'
    {
        If(Test-WinPE){
            If($JoinODJFile -and !$JoinODJBlob){
                $JoinODJBlob = Get-Content $File -Raw
            }
            Write-LogEntry ("Running: Join-Unattend -UnattendXML {0} JoinType ODJ -BlobData {1} -ForceSysprep" -f $Path,$JoinODJBlob) -Severity 1 -Outhost
            Join-Unattend -UnattendXML $Path -JoinType ODJ -BlobData $JoinODJBlob -ForceSysprep
        }
        ElseIf($JoinODJBlob){
            Write-LogEntry ("Running: Join-DeviceOffline -Blob {0}" -f $JoinODJBlob) -Severity 1 -Outhost
            Join-DeviceOffline -Blob $JoinODJBlob -Reboot:$Restart
        }
        ElseIf($JoinODJFile){
            Write-LogEntry ("Running: Join-DeviceOffline -File {0}" -f $JoinODJFile) -Severity 1 -Outhost
            Join-DeviceOffline -File $JoinODJFile -Reboot:$Restart
        }

    }

    'Unattend'
    {
        If($JoinDomainOU){
            $DomainJoinParam = @{
                JoinType = 'Domain'
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
                OU = $JoinDomainOU
            }
        }
        Else{
             $DomainJoinParam = @{
                JoinType = 'Domain'
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
            }
        }
        $DomainJoinString = ($DomainJoinParam.GetEnumerator() | Foreach { If($_.key -eq 'Password'){("-{0} ********" -f $_.key)}Else{("-{0} {1}" -f $_.key,$_.value)}}) -join ' '
        #if OSDisk is not specified, ASSUME first available drive letter is Windows
        If($null -eq $OSDisk){ $OSDisk = ((Get-Volume).DriveLetter | Select -first 1)+':'}

        If(Test-WinPE){
            If($JoinODJBlob){
                Write-LogEntry ("Running: Join-Unattend -UnattendXML '{0}\windows\panther\unattend.xml'  JoinType ODJ -BlobData {1} -ForceSysprep" -f $OSDisk,$JoinODJBlob) -Severity 1 -Outhost
                Join-Unattend -UnattendXML "$OSDisk\windows\panther\unattend.xml" -JoinType ODJ -BlobData $JoinODJBlob
            }
            ElseIf( $JoinODJFile ){
                $BlobContent = Get-Content $JoinODJFile -Raw
                Write-LogEntry ("Running: Join-Unattend -UnattendXML '{0}\windows\panther\unattend.xml'  JoinType ODJ -BlobData {1} -ForceSysprep" -f $OSDisk,$BlobContent) -Severity 1 -Outhost
                Join-Unattend -UnattendXML "$OSDisk\windows\panther\unattend.xml" -JoinType ODJ -BlobData $BlobContent
            }
            Else{
                Write-LogEntry ("Running: Join-Unattend -UnattendXML '{0}\windows\panther\unattend.xml' {1}" -f $OSDisk,$DomainJoinString) -Severity 1 -Outhost
                Join-Unattend -UnattendXML "$OSDisk\windows\panther\unattend.xml" @DomainJoinParam
            }

        }
        ElseIf(Test-SMSTSENV){
            If($UnattendFile){$Path = $UnattendFile}Else{$Path = "C:\windows\panther\unattend.xml"}

            If($JoinODJBlob){
                Write-LogEntry ("Running: Join-Unattend -UnattendXML {0} JoinType ODJ -BlobData {1} -ForceSysprep" -f $Path,$JoinODJBlob) -Severity 1 -Outhost
                Join-Unattend -UnattendXML $Path -JoinType ODJ -BlobData $JoinODJBlob -ForceSysprep
            }
            ElseIf( $JoinODJFile ){
                $BlobContent = Get-Content $JoinODJFile -Raw
                Write-LogEntry ("Running: Join-Unattend -UnattendXML {0} JoinType ODJ -BlobData {1} -ForceSysprep" -f $Path,$BlobContent) -Severity 1 -Outhost
                Join-Unattend -UnattendXML $Path -JoinType ODJ -BlobData $BlobContent -ForceSysprep
            }
            Else{
                Write-LogEntry ("Running: Join-Unattend -UnattendXML {0} {1} -DeviceName {2} -ForceSysprep" -f $Path,$DomainJoinString,$ComputerName) -Severity 1 -Outhost
                Join-Unattend -UnattendXML $Path @DomainJoinParam -DeviceName $ComputerName -ForceSysprep
            }
        }
        Else{
            Write-LogEntry ("Running: Join-Unattend -UnattendXML {0} {1}" -f $UnattendFile,$DomainJoinString) -Severity 1 -Outhost
            Join-Unattend -UnattendXML $UnattendFile @DomainJoinParam -ForceSysprep
        }
    }

    'Windows'
    {
        If($JoinDomainOU){
            $DomainJoinParam = @{
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
                OU = $JoinDomainOU
                ForceReboot = $BoolRestart
            }
        }
        Else{
             $DomainJoinParam = @{
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
                ForceReboot = $BoolRestart
            }
        }
        $DomainJoinString = ($DomainJoinParam.GetEnumerator() | Foreach { If($_.key -eq 'Password'){("-{0} ********" -f $_.key)}Else{("-{0} {1}" -f $_.key,$_.value)}}) -join ' '
        If(Test-WinPE){
            Write-LogEntry "Unable to Join Domain within WinPE. Must be running in Windows" -Severity 2 -Outhost
        }
        Else{
            Write-LogEntry ("Running: Join-Domain {0}" -f $DomainJoinString) -Severity 1 -Outhost
            Join-Domain @DomainJoinParam
            If($DomainJoinParam.ForceReboot -eq $False){
                Exit 3010
            }
        }
    }

    default
    {
        If($JoinDomainOU){
            $DomainJoinParam = @{
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
                OU = $JoinDomainOU
                ForceReboot = $BoolRestart
            }
        }
        Else{
             $DomainJoinParam = @{
                Username = $JoinUserName
                Password = $JoinPassword
                DomainName = $JoinDomainName
                ForceReboot = $BoolRestart
            }
        }
        $DomainJoinString = ($DomainJoinParam.GetEnumerator() | Foreach { If($_.key -eq 'Password'){("-{0} ********" -f $_.key)}Else{("-{0} {1}" -f $_.key,$_.value)}}) -join ' '

        If(Test-WinPE){
            Write-LogEntry "Unable to Join Domain within WinPE. Must be running in Windows" -Severity 2 -Outhost
        }
        Else{
            Write-LogEntry ("Running: Join-Domain {0}" -f $DomainJoinString) -Severity 1 -Outhost
            Join-Domain @DomainJoinParam
            If($DomainJoinParam.ForceReboot -eq $False){
                Exit 3010
            }
        }
    }

}