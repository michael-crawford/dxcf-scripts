<#
.Synopsis
    Creates Active Directory Groups.
.Description
    Configure-Groups reads a CSV file containing Active Directory Groups to create a set of groups
    within the Users container in Active Directory. This command can create groups within the AWS
    Directory Service (which stores them in an OU), by specifying a Switch.
.Parameter UserName
    Specifies a user account that has permission to add groups to the domain.
    The default is 'Admin'.
.Parameter Password
    Specifies the password for the user account.
.Parameter DomainName
    Specifies the domain for the user account.
.Parameter GroupsPath
    Specifies the path to the Groups input CSV file.
    The default value is '.\Groups.csv'.
.Parameter DirectoryService
    Indicates use of the AWS DirectoryService.
    This creates Groups in the correct OU.
.Example
    Configure-Groups -UserName Admin -Password <Password> -DomainName <Domain>
    Creates Groups using the default ./Groups.csv file.
.Example
    Configure-Groups -UserName Admin -Password <Password> -DomainName <Domain> -GroupsPath 'C:\cfn\temp\CustomGroups.csv'
    Creates Groups using a custom CSV file.
.Example
    Configure-Groups -UserName Admin -Password <Password> -DomainName <Domain> -GroupsPath 'C:\cfn\temp\CustomGroups.csv' -DirectoryService
    Creates Groups using a custom CSV file in the OU required by the AWS DirectoryService.
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
    [string]$GroupsPath = ".\Groups.csv",

    [switch]$DirectoryService
)

Try {
    $SecurePassword = ConvertTo-SecureString -String "$Password" -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential("$UserName@$DomainName", $SecurePassword)

    $DistinguishedName = (Get-ADDomain -Current LocalComputer -Credential $Credential).DistinguishedName
    $DNSRoot = (Get-ADDomain -Current LocalComputer -Credential $Credential).DNSRoot
    $NetBIOSName = (Get-ADDomain -Current LocalComputer -Credential $Credential).NetBIOSName

    $Groups = @()
    If (Test-Path $GroupsPath) {
        $Groups = Import-CSV $GroupsPath
    }
    Else {
        Throw  "-GroupsPath $GroupsPath is invalid."
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
    Write-CloudFormationHost "Adding Groups to $Path"

    ForEach ($Group In $Groups) {
        Try {
            If (Get-ADGroup -Filter "Name -eq '$($Group.Name)'" -Credential $Credential) {
                Write-Verbose "Group $($Group.Name) exists"
            }
            Else {
                Write-Verbose "Group $($Group.Name) does not exist"
                New-ADGroup -Name "$($Group.Name)" `
                            -Path $Path `
                            -GroupScope $($Group.GroupScope) `
                            -GroupCategory $($Group.GroupCategory) `
                            -Description "$($Group.Description)" `
                            -Credential $Credential
                Write-CloudFormationHost "Group $($Group.Name) created"
            }
        }
        Catch {
            Write-CloudFormationWarning "Group $($Group.Name) could not be created, Error: $($_.Exception.Message)"
        }

        if ($($Group.Groups)) {
            $GroupGroups = ($Group.Groups).split(',')
            ForEach ($GroupGroup in $GroupGroups) {
                Try {
                    Add-ADGroupMember -Identity "$GroupGroup" `
                                      -Members "$($Group.SamAccountName)" `
                                      -Credential $Credential
                    Write-CloudFormationHost "Group $($Group.Name) added to Group $GroupGroup"
                }
                Catch {
                    Write-CloudFormationWarning "Group $($Group.Name) could not be added to Group $GroupGroup, Error: $($_.Exception.Message)"
                }
            }
        }
    }
}
Catch {
    $_ | Send-CloudFormationFailure
}

Start-Sleep 1
