<#
.Synopsis
    Creates Active Directory Users, and optionally adds them to Groups.
.Description
    Configure-Users reads a CSV file containing Active Directory Users to create a set of users
    within the Users container in Active Directory. This command can create groups within the AWS
    Directory Service (which stores them in an OU), by specifying a Switch.
    Users can optionally be added to additional groups.
.Parameter UserName
    Specifies a user account that has permission to add groups to the domain.
    The default is 'Admin'.
.Parameter Password
    Specifies the password for the user account.
.Parameter DomainName
    Specifies the domain for the user account.
.Parameter UsersPath
    Specifies the path to the Users input CSV file.
    The default value is '.\Users.csv'.
.Parameter DirectoryService
    Indicates use of the AWS DirectoryService.
    This creates Users in the correct OU.
.Example
    Configure-Users -UserName Admin -Password <Password> -DomainName <Domain>
    Creates Users using the default ./Users.csv file.
.Example
    Configure-Users -UserName Admin -Password <Password> -DomainName <Domain> -UsersPath 'C:\cfn\temp\CustomUsers.csv'
    Creates Users using a custom CSV file.
.Example
    Configure-Users -UserName Admin -Password <Password> -DomainName <Domain> -UsersPath 'C:\cfn\temp\CustomUsers.csv' -DirectoryService
    Creates Users using a custom CSV file in the OU required by the AWS DirectoryService.
.Notes
       Author: Michael Crawford
    Copyright: 2018 by DXC.technology
             : Permission to use is granted but attribution is appreciated

    This command assumes it will be run on a computer joined to the domain.
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [string]$UserName = "Admin",

    [Parameter(Mandatory=$true)]
    [string]$Password,

    [Parameter(Mandatory=$true)]
    [string]$DomainName,

    [Parameter(Mandatory=$false)]
    [string]$UsersPath = ".\Users.csv",

    [switch]$DirectoryService
)

Try {
    $SecurePassword = ConvertTo-SecureString -String "$Password" -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential("$UserName@$DomainName", $SecurePassword)

    # We use the Password of the Domain Administrator to Encrypt Stored User Initial Passwords
    $Encoder = [System.Text.Encoding]::UTF8
    $Key = $Encoder.GetBytes($Password.PadRight(24))

    $DistinguishedName = (Get-ADDomain -Current LocalComputer -Credential $Credential).DistinguishedName
    $DNSRoot = (Get-ADDomain -Current LocalComputer -Credential $Credential).DNSRoot
    $NetBIOSName = (Get-ADDomain -Current LocalComputer -Credential $Credential).NetBIOSName

    $Users = @()
    If (Test-Path $UsersPath) {
        $Users = Import-CSV $UsersPath
    }
    Else {
        Throw  "-UsersPath $UsersPath is invalid."
    }

    if ($DirectoryService) {
        Write-Verbose "Configuring DirectoryService"
        $Path = "OU=Users,OU=$NetBIOSName,$DistinguishedName"
    }
    Else {
        Write-Verbose "Configuring ActiveDirectory"
        $Path = "CN=Users,$DistinguishedName"
    }

    Write-Host
    Write-CloudFormationHost "Adding Users to $Path"

    ForEach ($User In $Users) {
        Try {
            If (Get-ADUser -Filter "SamAccountName -eq '$($User.SamAccountName)'" -Credential $Credential) {
                Write-Verbose "User $($User.Name) exists"
            }
            Else {
                Write-Verbose "User $($User.Name) does not exist"
                $SecurePassword = ConvertTo-SecureString -String "$($User.EncryptedPassword)" -Key $Key
                New-ADUser -Name "$($User.Name)" `
                           -Path $Path `
                           -SamAccountName "$($User.SamAccountName)" `
                           -UserPrincipalName "$($User.SamAccountName)@$DNSRoot" `
                           -GivenName "$($User.GivenName)" `
                           -Surname "$($User.Surname)" `
                           -AccountPassword $SecurePassword `
                           -ChangePasswordAtLogon $([System.Convert]::ToBoolean($User.ChangePasswordAtLogon)) `
                           -CannotChangePassword $([System.Convert]::ToBoolean($User.CannotChangePassword)) `
                           -PasswordNeverExpires $([System.Convert]::ToBoolean($User.PasswordNeverExpires)) `
                           -Enabled $([System.Convert]::ToBoolean($User.Enabled))`
                           -Description "$($User.Description)" `
                           -Credential $Credential
                Write-CloudFormationHost "User $($User.Name) created"
            }
        }
        Catch {
            Write-CloudFormationWarning "User $($User.Name) could not be created, Error: $($_.Exception.Message)"
        }

        if ($($User.Groups)) {
            $UserGroups = ($User.Groups).split(',')
            ForEach ($UserGroup in $UserGroups) {
                Try {
                    Add-ADGroupMember -Identity "$UserGroup" `
                                      -Members "$($User.SamAccountName)" `
                                      -Credential $Credential
                    Write-CloudFormationHost "User $($User.Name) added to Group $UserGroup"
                }
                Catch {
                    Write-CloudFormationWarning "User $($User.Name) could not be added to Group $UserGroup, Error: $($_.Exception.Message)"
                }
            }
        }
    }
}
Catch {
    $_ | Send-CloudFormationFailure
}

Start-Sleep 1
