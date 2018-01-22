PARAM([string]$Domain,[string]$SearchBase)

#Copyright (c) 2014, Unify Solutions Pty Ltd
#All rights reserved.
#
#Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
#IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
#OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

###
### ConvertTo-FIMManagedGroup.ps1
###
### This script is designed to create a group object in the FIM Portal based on an existing group in AD. The FIM group will:
### - Have the same DisplayName, AccountName, Scope and Type of the AD group,
### - Have the built-in FIM Administrator account as the Owner,
### - Have all AD members added as explicit memebrs where a direct match on AccountName can be made.
###
### Uses the FIMPowershell.ps1 script from http://technet.microsoft.com/en-au/library/ff720152(v=ws.10).aspx
###
### Parameters:
###  -Domain        The NETBIOS domain name
###  -SearchBase    The OU to start from when search for groups to migrate. All groups are migrated, so using a "Migration" OU is recommended.
###
### RECOMMENDATION: Set sync rule config so the AD group is moved to a "Managed" OU once the FIM and AD groups are joined.
###

Import-Module ActiveDirectory

## TODO: correct following path
. E:\FIM\Scripts\FIMPowershell.ps1

$DC =  Get-ADDomainController -Server $Domain
if (-not $DC) {Throw "Unable to find a domain controller"}
elseif ($DC.count) {$Server = $DC[0].HostName}
else {$Server = $DC.HostName}
"Using DC $Server"

"Searching OU $SearchBase"
$Groups = Get-ADGroup -filter * -SearchBase $SearchBase -Server $Server

if ($Groups)
{
    if ($Groups.count) {"Found groups: " + $Groups.count}
    else {"Found groups: 1"}

    foreach ($group in $Groups)
    {
        "Creating group " + $group.Name
        $Members = Get-ADGroupMember -Identity $group.DistinguishedName -Server $Server
    
        ## Create Group in FIM
        $GroupAccountName = $group.sAMAccountName
        $obj = Export-FIMConfig -OnlyBaseResources -CustomConfig ("/Group[AccountName='{0}']" -f $GroupAccountName)
        if (-not $obj) 
        {
            $ImportObject = CreateImportObject "Group"
            SetSingleValue $ImportObject "DisplayName" $group.Name
            SetSingleValue $ImportObject "AccountName" $group.SamAccountName
            SetSingleValue $ImportObject "Type" $group.GroupCategory
            SetSingleValue $ImportObject "Scope" $group.GroupScope
            SetSingleValue $ImportObject "Owner" "7fb2b853-24f0-4498-9534-4e10589723c4"
            SetSingleValue $ImportObject "DisplayedOwner" "7fb2b853-24f0-4498-9534-4e10589723c4"
            SetSingleValue $ImportObject "MembershipLocked" "False"
            SetSingleValue $ImportObject "MembershipAddWorkflow" "Owner Approval"
            SetSingleValue $ImportObject "Domain" $Domain
            foreach ($user in $Members)
            {
                "  Adding: " + $user.SamAccountName
                $filter = "/Person[AccountName='{0}']" -f $user.SamAccountName
                $PersonObj = Export-FIMConfig -OnlyBaseResources -CustomConfig $filter
            
                if ($PersonObj){ AddMultiValue $ImportObject "ExplicitMember" $PersonObj.ResourceManagementObject.ObjectIdentifier }
            } 
            $ImportObject.changes       
            $ImportObject | Import-FIMConfig
        }
  

    }
}
