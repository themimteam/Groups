PARAM([string]$Domain,[string]$ReportFolder=".")

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
### Analyse-ADGroups.ps1
###
### Exports statistics about existing AD groups and produces a report showing where most groups and their members are located,
### what types of groups there are, and how many are nested. This is to help with a quick evaluation of how difficult it will be
### to convert groups to FIM-managed. 
###

Import-Module ActiveDirectory

## If no domain name provided use current domain
if (-not $Domain) 
{
    $Domain = (Get-ADDomain).NetBIOSName
    $SearchBase = (Get-ADDomain).DistinguishedName
}
else
{
    $SearchBase = (Get-ADDomain $Domain).DistinguishedName
}

## Get a domain controller
$DomainControllers =  Get-ADDomainController -Server $Domain
if (-not $DomainControllers) {Throw "Unable to find a domain controller"}
elseif ($DomainControllers.count) {$DC = $DomainControllers[0].HostName}
else {$DC = $DomainControllers.HostName}
write-host "Using DC $DC"

write-host "Querying AD..."
$ADObjs = Get-ADGroup -SearchBase $SearchBase -Server $DC -Filter * -Properties *
write-host "Exported" $ADObjs.count "groups"
 
$hashADGroups = @{}
$arrMembers = @()
$hashMemberOUs = @{}

foreach ($obj in $ADObjs)
{
    $hashADGroups.Add($obj.DistinguishedName,@{})
    $hashADGroups.($obj.DistinguishedName).Add("Name",$obj.Name)
    $hashADGroups.($obj.DistinguishedName).Add("Description",$obj.Description)
    $hashADGroups.($obj.DistinguishedName).Add("AccountName",$obj.SamAccountName)
    $hashADGroups.($obj.DistinguishedName).Add("Scope",$obj.GroupScope)
    $hashADGroups.($obj.DistinguishedName).Add("Type",$obj.GroupCategory)

    if ($obj.mail) {$hashADGroups.($obj.DistinguishedName).Add("MailEnabled","Yes")}
    else {$hashADGroups.($obj.DistinguishedName).Add("MailEnabled","No")}

    if ($obj.MemberOf) {$hashADGroups.($obj.DistinguishedName).Add("Nested","Yes")}
    else {$hashADGroups.($obj.DistinguishedName).Add("Nested","No")}

    if ($obj.Members)
    {
        $hashADGroups.($obj.DistinguishedName).Add("Members",@{})
        foreach ($MemberDN in $obj.Members)
        {
            if ($MemberDN.contains("CN=Users")) {$MemberOU = $MemberDN.SubString($MemberDN.IndexOf(",CN=")+1)}
            else {$MemberOU = $MemberDN.SubString($MemberDN.IndexOf(",OU=")+1)}

            if (-not $hashADGroups.($obj.DistinguishedName).Members.ContainsKey($MemberOU))
            {
                $hashADGroups.($obj.DistinguishedName).Members.Add($MemberOU,1)
            }
            else
            {
                $hashADGroups.($obj.DistinguishedName).Members.($MemberOU) = $hashADGroups.($obj.DistinguishedName).Members.($MemberOU) + 1
            }

            if ($arrMembers -notcontains $MemberDN)
            {
                $arrMembers += $MemberDN
                if (-not $hashMemberOUs.ContainsKey($MemberOU))
                {
                    $hashMemberOUs.Add($MemberOU,1)
                }
                else
                {
                    $hashMemberOUs.($MemberOU) = $hashMemberOUs.($MemberOU) + 1
                }

            }
        }
    }
}
write-host "Finished parsing groups"

## Export CSV Files
$GroupCSV = "$ReportFolder\Groups_" + $Domain + "_" + (get-date -format "yyyyMMdd-HHMMss") + ".csv"
"DN;Name;AccountName;Description;Type;Scope;MailEnabled;Nested" | Out-File $GroupCSV -Encoding Default

$MemberCountCSV = "$ReportFolder\GroupMemberCount_" + $Domain + "_" + (get-date -format "yyyyMMdd-HHMMss") + ".csv"
"DN;MemberOU;Count" | Out-File $MemberCountCSV -Encoding Default

foreach ($GroupDN in $hashADGroups.Keys)
{
    $GroupDN + ";" + $hashADGroups.($GroupDN).Name + ";" + $hashADGroups.($GroupDN).AccountName + ";" + $hashADGroups.($GroupDN).Description + ";" + $hashADGroups.($GroupDN).Type + ";" + $hashADGroups.($GroupDN).Scope + ";" + $hashADGroups.($GroupDN).MailEnabled + ";" + $hashADGroups.($GroupDN).Nested | Add-Content $GroupCSV
    if ($hashADGroups.($GroupDN).Members)
    {
        foreach ($MemberOU in $hashADGroups.($GroupDN).Members.Keys)
        {
            $GroupDN + ";" + $MemberOU + ";" + $hashADGroups.($GroupDN).Members.($MemberOU) | Add-Content $MemberCountCSV
        }
    }
}
write-host "Exported CSV files to $ReportFolder"

## Counts
$numGroups = 0
$numSecGroups = 0
$numDLs = 0
$numNested = 0
$numMailEnabledSecurity = 0
$GroupOUs = @{}
foreach ($GroupDN in $hashADGroups.Keys)
{
    $numGroups += 1

    $GroupOU = $GroupDN.SubString($GroupDN.IndexOf(",OU=")+1)
    if (-not $GroupOUs.ContainsKey($GroupOU))
    {
        $GroupOUs.Add($GroupOU,1)
    }
    else
    {
        $GroupOUs.($GroupOU) = $GroupOUs.($GroupOU) + 1
    }
            
    if ($hashADGroups.($GroupDN).Type -eq "Security"){$numSecGroups += 1}
    if ($hashADGroups.($GroupDN).Type -eq "Distribution"){$numDLs += 1}
    if ($hashADGroups.($GroupDN).Nested -eq "Yes"){$numNested += 1}
    if ($hashADGroups.($GroupDN).MailEnabled -eq "Yes" -and $hashADGroups.($GroupDN).Type -eq "Security"){$numMailEnabledSecurity += 1}

}

## Start Report file
$ReportFile = "$ReportFolder\GroupAnalysis_" + $Domain + "_" + (get-date -format "yyyyMMdd-HHMMss") + ".html"
"<html><body>" | Add-Content $ReportFile

# Group Types
$content = @"
<h2>Group Types</h2>
<table border="0">
<tr><td><b>Total Groups</b></td><td>$numGroups</td></tr>
<tr><td><b>Security Groups</b></td><td>$numSecGroups</td></tr>
<tr><td><b>Mail-Enabled Security Groups</b></td><td>$numMailEnabledSecurity</td></tr>
<tr><td><b>Distribution Groups</b></td><td>$numDLs</td></tr>
<tr><td><b>Nested Groups</b></td><td>$numNested</td></tr>
</table>
"@
$content | Add-Content $ReportFile

# Group Locations
$content = @"
<h2>Group OU Locations</h2>
<p>The following table shows a total count of the number of groups found in each OU location.
<table border="1">
<tr><td><b>OU</b></td><td><b>Count</b></td></tr>
"@
foreach ($entry in $GroupOUs.GetEnumerator() | Sort-Object Value -descending)
{
    $content = $content + "<tr><td>" + $entry.Key + "</td><td>" + $entry.Value + "</td></tr>`n"
}
$content = $content + "</table>"

$content | Add-Content $ReportFile

# Group member locations
$content = @"
<h2>Member OU Locations</h2>
<p>The following table shows a count for each OU location where group members have been found. Each member is counted once, even if they belogn to multiple groups.
<table border="1">
<tr><td><b>OU</b></td><td><b>Count</b></td></tr>
"@
foreach ($entry in $hashMemberOUs.GetEnumerator() | Sort-Object Value -descending)
{
    $content = $content + "<tr><td>" + $entry.Key + "</td><td>" + $entry.Value + "</td></tr>`n"
}
$content = $content + "</table>"

$content | Add-Content $ReportFile

# End Report
"</body></html>" | Add-Content $ReportFile
write-host "Exported HTML report $ReportFile"
