function New-DjoinFile {
    <#
    .SYNOPSIS
        Function to generate a blob file accepted by djoin.exe tool (offline domain join)
    .DESCRIPTION
        Function to generate a blob file accepted by djoin.exe tool (offline domain join)
        This function can create a file compatible with djoin with the Blob initially provisionned.
    .PARAMETER Blob
        Specifies the blob generated by djoin
    .PARAMETER DestinationFile
        Specifies the full path of the file that will be created
        Default is c:\temp\djoin.tmp
    .EXAMPLE
        New-DjoinFile -Blob $Blob -DestinationFile C:\temp\test.tmp
    .NOTES
        Francois-Xavier.Cat
        LazyWinAdmin.com
        @lazywinadmin
        github.com/lazywinadmin
    .LINK
        https://github.com/lazywinadmin/PowerShell/tree/master/TOOL-New-DjoinFile
    .LINK
        https://lazywinadmin.com/2016/07/offline-domain-join-copying-djoin.html
    .LINK
        https://msdn.microsoft.com/en-us/library/system.io.fileinfo(v=vs.110).aspx
    #>
    [Cmdletbinding()]
    PARAM (
        [Parameter(Mandatory = $true)]
        [String]$Blob,
        [Parameter(Mandatory = $False)]
        [System.IO.FileInfo]$DestinationFile = "$env:temp\djoin.tmp"
    )

    PROCESS {
        TRY {
            # Create a byte object
            $bytechain = New-Object -TypeName byte[] -ArgumentList 2
            # Add the first two character for Unicode Encoding
            $bytechain[0] = 255
            $bytechain[1] = 254

            # Creates a write-only FileStream
            $FileStream = $DestinationFile.Openwrite()

            # Append Hash as byte
            $bytechain += [System.Text.Encoding]::unicode.GetBytes($Blob)
            # Append two extra 0 bytes characters
            $bytechain += 0
            $bytechain += 0

            # Write back to the file
            $FileStream.write($bytechain, 0, $bytechain.Length)

            # Close the file Stream
            $FileStream.Close()
        }
        CATCH {
            $Error[0]
        }
    }
}


Function Join-DeviceOffline {
    [Cmdletbinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [String]$Blob,
        [Parameter(Mandatory = $false)]
        [System.IO.FileInfo]$File = "$env:temp\djoin.tmp",
        [boolean]$Reboot
    )
    If($DebugPreference){Start-Transcript -Path 'C:\Windows\Logs\JoinDeviceOffline.log'}
    ## Get the name of this function
    [string]${CmdletName} = $MyInvocation.MyCommand

    #if blob specified, attempt to build file
    If($PSBoundParameters.ContainsKey('Blob')){
        New-DjoinFile -Blob $blob -DestinationFile $File
    }

    #attempt to use ODJ file to joine the domain
    Try{
        Start-Process "$env:systemroot\System32\djoin.exe" -ArgumentList "djoin /requestODJ /loadfile $File /windowspath $env:SystemRoot /localos" -PassThru -Wait -ErrorAction Stop
    }
    Catch{
        Write-Host ("{0} :: Failed to Offline Domain Join: {1}" -f ${CmdletName}) -ForegroundColor Gray
    }
    Finally {
        #cleanup file after
        Remove-Item $File -Force | Out-Null
        If($DebugPreference){Stop-Transcript}

        If($Reboot){
            Restart-Computer -Force
        }

    }

}


Function Join-Domain{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName,

        [Parameter(Mandatory=$true)]
        [string]$UserName,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [string]$Computer = 'localhost',

        [Parameter(Mandatory=$false)]
        [string]$OU,

        [Parameter(Mandatory=$false)]
        [switch]$ForceReboot
    )
    If($DebugPreference){Start-Transcript -Path 'C:\Windows\Logs\JoinDomain.log'}
    $pass = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName,$pass

    #Splat the command depending on OU param
    If($OU){
       $DomainJoinParam = @{
            ComputerName = $Computer
            Credential = $cred
            DomainName = $DomainName
            OUPath = $OU.replace('LDAP://','')
            Restart = $ForceReboot
       }
    }
    Else{
        $DomainJoinParam = @{
            ComputerName = $Computer
            Credential = $cred
            DomainName = $DomainName
            Restart = $ForceReboot
       }
    }

    try {
        #call command
        Add-Computer @DomainJoinParam -Force -ErrorAction stop
    }
    catch {
        If($OU){
            Write-LogEntry ("Unable to Join the domain [{0}] in OU [{3}] using credentials [{1}]. {2}" -f $DomainJoinParam.DomainName,$cred.UserName,$_.exception.message,$OU.replace('LDAP://','')) -Severity 3 -Outhost
        }Else{
            Write-LogEntry ("Unable to Join the domain [{0}] using credentials [{1}]. {2}" -f $DomainJoinParam.DomainName,$cred.UserName,$_.exception.message) -Severity 3 -Outhost
        }
        Exit -2
    }
    Finally{
        If($DebugPreference){Stop-Transcript}
    }
}

function Test-IsValidDN
{
    <#
        .SYNOPSIS
            Cmdlet will check if the input string is a valid distinguishedname.
        .DESCRIPTION
            Cmdlet will check if the input string is a valid distinguishedname.
            Cmdlet is intended as a diagnostic tool for input validation
        .PARAMETER ObjectDN
            A string representing the object distinguishedname.
        .EXAMPLE
            PS C:\> Test-IsValidDN -ObjectDN 'Value1'
        .NOTES
            Additional information about the function.
    #>

    [OutputType([bool])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('DN', 'DistinguishedName')]
        [string]
        $ObjectDN
    )
    #remove LDAP from query (If exists)
    $ObjectDN = $ObjectDN.replace('LDAP://','')
    
    # Define DN Regex
    [regex]$distinguishedNameRegex = '^(?:(?<cn>CN=(?<name>(?:[^,]|\,)*)),)?(?:(?<path>(?:(?:CN|OU)=(?:[^,]|\,)+,?)+),)?(?<domain>(?:DC=(?:[^,]|\,)+,?)+)$'

    return $ObjectDN -match $distinguishedNameRegex
}

Function Join-Unattend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.IO.FileInfo]$UnattendXML,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Workgroup','Domain','ODJ')]
        [string]$JoinType ='Domain',

        [Parameter(Mandatory=$false)]
        [string]$BlobData,

        [Parameter(Mandatory=$false)]
        [Alias('DeviceName')]
        [string]$ComputerName,

        [Parameter(Mandatory=$false)]
        [Alias('WorkgroupName')]
        [string]$DomainName,

        [Parameter(Mandatory=$false)]
        [string]$UserName,

        [Parameter(Mandatory=$false)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [string]$OU,

        [Parameter(Mandatory=$false)]
        [switch]$ForceSysprep
    )

    If( ($JoinType -eq 'Domain' -and [string]::IsNullOrEmpty($DomainName)) -and [string]::IsNullOrEmpty($UserName) -and [string]::IsNullOrEmpty($Password) ){
        Write-LogEntry "Unable able to continue with Domain Join. Required Parameters not found" -Severity 3 -Outhost; Exit -1
    }
    Else{
        #Add cred to unattend
        $Domain = $UserName.split('\')[0]
        $UserAccount = $UserName.split('\')[1]
    }

    If( ($JoinType -eq 'ODJ' -and [string]::IsNullOrEmpty($BlobData)) ){
        Write-LogEntry "Unable able to continue with Offline Domain Join. Required Parameters not found" -Severity 3 -Outhost; Exit -1
    }

    If( ($JoinType -eq 'Workgroup' -and [string]::IsNullOrEmpty($DomainName)) ){
        $DomainName = 'Workgroup'
    }

    If($OU){
        $BoolDN = Test-IsValidDN -ObjectDn $OU
        If(!$BoolDN){Write-LogEntry ("Invalid OU path [{0}], unable to continue" -f $OU) -Severity 3 -Outhost; Exit -1}
    }
    If($DebugPreference){Start-Transcript -Path 'C:\Windows\Logs\JoinUnattend.log'}
    #start working Unattend
    [xml]$xml = New-Object XML
    $xml.Load($UnattendXML)
    $nsm = New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $nsm.AddNamespace('ns', $xml.DocumentElement.NamespaceURI)

    $UnattendComponent = $xml.unattend.settings.component | Where {$_.name -eq 'Microsoft-Windows-UnattendedJoin'}
    $SpecializeNode = $xml.SelectNodes('//ns:settings', $nsm) | Where {$_.pass -eq 'specialize'}

    If($null -eq $SpecializeNode){Write-LogEntry ("Specialize phase does not exist un unattend, unable to continue" -f $OU) -Severity 3 -Outhost; Exit -1}
    <# TODO Build specialize node #>

    If($null -eq $UnattendComponent)
    {
        <# add UnattendedJoin component to unattend.xml. Example:
		<component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
			<Identification>
				<Credentials>
					<Username></Username>
					<Domain></Domain>
					<Password>/Password>
				</Credentials>
				<JoinDomain></JoinDomain>
				<JoinWorkgroup></JoinWorkgroup>
			</Identification>
		</component>
		#>
        $UnattendedJoinElement = $SpecializeNode.AppendChild($xml.CreateElement('component'))
        $UnattendedJoinElement.SetAttribute('name','Microsoft-Windows-UnattendedJoin')
        $UnattendedJoinElement.SetAttribute('processorArchitecture','amd64')
        $UnattendedJoinElement.SetAttribute('publicKeyToken','31bf3856ad364e35')
        $UnattendedJoinElement.SetAttribute('language','neutral')
        $UnattendedJoinElement.SetAttribute('versionScope','nonSxS')
        $UnattendedJoinElement.SetAttribute('xmlns:wcm','http://schemas.microsoft.com/WMIConfig/2002/State')
        #$UnattendedJoinElement.RemoveAttribute("xmlns")
        $IdentificationElement = $UnattendedJoinElement.AppendChild($xml.CreateElement('Identification'));

        switch($JoinType){

            'Workgroup' {
                    $JoinWorkgroupText = $xml.CreateElement('JoinWorkgroup')
                    $JoinWorkgroupText.set_innerText($DomainName)
                    $IdentificationElement.AppendChild($JoinWorkgroupText) | Out-Null
                }

            'Domain'    {
                    $CredentialsElement = $IdentificationElement.AppendChild($xml.CreateElement('Credentials'));
                    #$CredentialsElement.AppendChild($xml.CreateElement('Username')) | Out-Null

                    $UsernameText = $xml.CreateElement('Username')
                    $UsernameText.set_innerText($UserAccount)
                    $CredentialsElement.AppendChild($UsernameText) | Out-Null

                    #$CredentialsElement.AppendChild($xml.CreateElement('Domain')) | Out-Null
                    $DomainText = $xml.CreateElement('Domain')
                    $DomainText.set_innerText($Domain)
                    $CredentialsElement.AppendChild($DomainText) | Out-Null

                    #$CredentialsElement.AppendChild($xml.CreateElement('Password')) | Out-Null
                    $PasswordText = $xml.CreateElement('Password')
                    $PasswordText.set_innerText($Password)
                    $CredentialsElement.AppendChild($PasswordText) | Out-Null

                    $JoinDomainText = $xml.CreateElement('JoinDomain')
                    $JoinDomainText.set_innerText($DomainName)
                    $IdentificationElement.AppendChild($JoinDomainText) | Out-Null
                    If($OU){
                        $MachineObjectOUText = $xml.CreateElement('MachineObjectOU')
                        $MachineObjectOUText.set_innerText($OU.replace('LDAP://',''))
                        $IdentificationElement.AppendChild($MachineObjectOUText) | Out-Null
                    }
                }
            'ODJ'    {
                    $ProvisioningElement = $IdentificationElement.AppendChild($xml.CreateElement('Provisioning'));
                    $AccountDataText = $xml.CreateElement('AccountData')
                    $AccountDataText.set_innerText($BlobData)
                    $ProvisioningElement.AppendChild($AccountDataText) | Out-Null
                }
        }
    }
    Else
    {
        switch($JoinType){

            'Workgroup' {
                    $element = $xml.SelectSingleNode("//ns:JoinWorkgroup", $nsm)
                    $element.'#text' =  $DomainName
                }

            'Domain'    {
                    #inject domain credential
                    $xml.unattend.settings.component.Identification.Credentials.Username = $UserAccount
                    $xml.unattend.settings.component.Identification.Credentials.Domain = $Domain
                    $xml.unattend.settings.component.Identification.Credentials.Password = $Password

                    $element = $xml.SelectSingleNode("//ns:JoinDomain", $nsm)
                    $element.'#text' =  $DomainName
                    If($OU){
                        #determine if MachineObjectOU element exists; if not create it
                        #and add OU into to it.
                        $element = $xml.SelectSingleNode('//ns:MachineObjectOU', $nsm)
                        If($null -eq $element){
                            $IdentificationNode = $xml.SelectNodes('//ns:Identification', $nsm)
                            $OUText = $xml.CreateElement('MachineObjectOU')
                            $OUText.set_innerText($OU.replace('LDAP://',''))
                            $MachineObjectOUElement.AppendChild($OUText) | Out-Null
                        }
                        Else{
                            $element.'#text' =  $OU
                        }
                    }
                }
            'ODJ'    {
                    $element = $xml.SelectSingleNode("//ns:AccountData", $nsm)
                    If($null -eq $element){
                        $IdentificationNode = $xml.SelectNodes('//ns:Identification', $nsm)
                        $ProvisioningElement = $IdentificationNode.AppendChild($xml.CreateElement('Provisioning'));
                        $AccountDataText = $xml.CreateElement('AccountData')
                        $AccountDataText.set_innerText($BlobData)
                        $ProvisioningElement.AppendChild($AccountDataText) | Out-Null
                    }
                    Else{
                        $element.'#text' =  $BlobData
                    }
                }
        }
    }

    #clean up empty namespace
    $xml = [xml] $xml.OuterXml.Replace(" xmlns=`"`"", "")
    #save xml
    $xml.save($UnattendXML)
    If($DebugPreference){Stop-Transcript}

    If($ForceSysprep){
        $sysprep = 'C:\Windows\System32\Sysprep\Sysprep.exe'
        $arg = ('/generalize /oobe /shutdown /quiet /unattend:{0}' -f $UnattendXML)
        Start-Process -FilePath $sysprep -ArgumentList $arg -NoNewWindow -PassThru
    }

}