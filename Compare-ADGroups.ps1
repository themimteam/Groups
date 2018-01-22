PARAM(
    $SearchBaseA,
    $SearchScopeA="Subtree",
    $SearchFilterA="*",
    $SearchBaseB,
    $SearchScopeB="Subtree",
    $SearchFilterB="*",
    $CSVGroupsB,
    $Delimiter="`t",
    $MinMember = 5,
    $CountPercentThreshold = 75,
    $ReportThreshold = 50,
    $ReportFile = ".\GroupMembershipComparison.csv"
)
<#-----------------------------------------------------------------------------
Group report & Search for groups with duplicate group membership

Based on an original script from:
    Ashley McGlone - GoateePFE
    Microsoft Premier Field Engineer
    http://aka.ms/GoateePFE
    January, 2014

Updated to help with RBAC group analysis by:
    Carol Wapshere MVP (MIM / Enterprise Mobility)
    www.wapshere.com
    January 2016

-------------------------------------------------------------------------------
LEGAL DISCLAIMER
This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys’ fees, that arise or result
from the use or distribution of the Sample Code.
-------------------------------------------------------------------------------

This script has been modified from the original which compares group memberships
in an entire domain to find membership duplication. This script adds the following 
extra functions:
- Compare groups in one OU/entire domain to groups in another OU, OR
- Compare groups in one OU/entire domain to a CSV of proposed groups.

This script also continuously writes the report file rather than waiting until the
end, allowing the script to be stopped. Parameters have been added as follows.

PARAMETERS:
-SearchBaseA    (Optional) Select the "A" list of groups from this OU only,
-SearchScopeA   (Optional) Set to either "OneLevel" or "Subtree" for use with SearchBaseA.
-SearchFilterA  (Optional) Filter to use in selecting groups - see below for examples. Default is "*" - all.
-SearchBaseB    (Optional) Select the "B" list of groups from this OU only,
-SearchScopeB   (Optional) Set to either "OneLevel" or "Subtree" for use with SearchBaseB.
-SearchFilterB  (Optional) Filter to use in selecting groups - see below for examples. Default is "*" - all.
-CSVGroupsB     (Optional) Use instead of SearchBaseB to define the group "B" list, in this case
                           they are proposed rather than actual groups. The column headers must be
                           "Name" and "DN", where the DN column contains the DN of expected members.
-Delimiter      (Optional) Set a different delimiter for CSVGroupsB. Default is "`t" tab character.
-MinMember      (Required) Minimum size of group to compare. Must be at least 1.
-CountPercentThreshold   (Required) Only compare groups with a membership within this percent
                         size of each other. Set to 0 to disable this check. This is useful if
                         looking for possible role-based groups to nest in a larger group without
                        necessarily matching the entire membership.
-ReportThreshold (Required) Only add group pairs to the report where the percent matched
                            is greater than this number.
                            
 Search Filter examples:
- group name pattern
      {name -like "*foo*"}
- group scope
      {GroupScope -eq 'Global'}
- group category
      {GroupCategory -eq 'Security'}

-------------------------------------------------------------------------------
Original script notes:

Comparing all groups in AD involves an "n * n-1" number of comparisons. The following
steps have been taken to make the comparisons more efficient:

- Minimum number of members in a group before it is considered for matching
  This automatically filters out empty groups and those with only a few members.
  This is an arbitrary number. Default is 5. Must be at least 1.

- Minimum percentage of overlap between group membership counts to compare
  ie. It only makes sense to compare groups whose total membership are close
  in number. You wouldn't compare a group with 5 members to a group with 65
  members when seeking a high number of group member duplicates. By default
  the lowest group count must be within 25% of the highest group count.

- Does not compare the group to itself.

- The pair of groups has not already been compared.

Groups of all types are compared against each other in order to give a complete
picture of group duplication (Domain Local, Global, Universal, Security,
Distribution). If desired, mismatched group category and scope can be filtered
out in Excel when viewing the CSV file output.

Using the data from this report you can then go investigate groups for
consolidation based on high match percentages.

-------------------------------------------------------------------------------

The group list report gives you handy fields for analyzing your groups for
cleanup:  whenCreated, whenChanged, MemberCount, MemberOfCount, SID,
SIDHistory, DaysSinceChange, etc.  Use these columns to filter or pivot in
Excel for rich reports.  For example:
- Groups with zero members
- Groups unchanged in 1 year
- Groups with SID history to cleanup
- Etc.
-------------------------------------------------------------------------sdg-#>

Import-Module ActiveDirectory

# Depending on whether we're comparing real or proposed groups we need to use a different
# type of identifier to log the comparison as "done".
$idA = "SID"
if ($CSVGroupsB) {$idB = "Name"} else {$idB = "SID"}

# If Search Bases not specified get from the current domain
$MyDomain = (Get-ADDomain).DistinguishedName
if (-not $SearchBaseA) {$SearchBaseA = $MyDomain}
if (-not $SearchBaseB) {$SearchBaseB = $MyDomain}


#region########################################################################
# List of all groups and the count of their member/memberOf

Write-Progress -Activity "Getting group A list..." -Status "..."
$GroupListA = Get-ADGroup -Filter $SearchFilterA -SearchBase $SearchBaseA -SearchScope $SearchScopeA `
        -Properties Name, DistinguishedName, `
        GroupCategory, GroupScope, whenCreated, whenChanged, member, `
        memberOf, sIDHistory, SamAccountName, Description |
    Select-Object Name, DistinguishedName, GroupCategory, GroupScope, `
        whenCreated, whenChanged, member, memberOf, SID, SamAccountName, `
        Description, `
        @{name='MemberCount';expression={$_.member.count}}, `
        @{name='MemberOfCount';expression={$_.memberOf.count}}, `
        @{name='SIDHistory';expression={$_.sIDHistory -join ','}}, `
        @{name='DaysSinceChange';expression=`
            {[math]::Round((New-TimeSpan $_.whenChanged).TotalDays,0)}} |
    Sort-Object Name

$GroupListA |
    Select-Object Name, SamAccountName, Description, DistinguishedName, `
        GroupCategory, GroupScope, whenCreated, whenChanged, DaysSinceChange, `
        MemberCount, MemberOfCount, SID, SIDHistory |
    Export-CSV .\GroupListA.csv -NoTypeInformation


if ($CSVGroupsB)
{
    $GroupListB = @()
    $added=@()
    $CSVList = import-csv $CSVGroupsB -Delimiter $Delimiter
    foreach ($row in $CSVList)
    {
        if ($added -notcontains $row.Name)
        {
            $rowcount = 1
            if (($CSVList | where {$_.Name -eq $row.Name}).count) {$rowcount = ($CSVList | where {$_.Name -eq $row.Name}).count}
            
            $memberDNs = @()
            foreach ($entry in ($CSVList | where {$_.Name -eq $row.Name})) {$memberDNs += $entry.DN}
            
            $GroupListB += New-Object -TypeName PSCustomObject -Property @{
                Name = $row.Name
                MemberCount = $rowcount
                Member = $memberDNs
            }
            $added += $row.Name
        }    
    }
    $added = $null
    $memberDNs = $null
}
elseif ($SearchBaseA -eq $SearchBaseB -and $SearchScopeA -eq $SearchScopeB -and $SearchFilterA -eq $SearchFilterB)
{
    $GroupListB = $GroupListA
}
else
{
    Write-Progress -Activity "Getting group B list..." -Status "..."
    $GroupListB = Get-ADGroup -Filter $SearchFilterB -SearchBase $SearchBaseB -SearchScope $SearchScopeB `
            -Properties Name, DistinguishedName, `
            GroupCategory, GroupScope, whenCreated, whenChanged, member, `
            memberOf, sIDHistory, SamAccountName, Description |
        Select-Object Name, DistinguishedName, GroupCategory, GroupScope, `
            whenCreated, whenChanged, member, memberOf, SID, SamAccountName, `
            Description, `
            @{name='MemberCount';expression={$_.member.count}}, `
            @{name='MemberOfCount';expression={$_.memberOf.count}}, `
            @{name='SIDHistory';expression={$_.sIDHistory -join ','}}, `
            @{name='DaysSinceChange';expression=`
                {[math]::Round((New-TimeSpan $_.whenChanged).TotalDays,0)}} |
        Sort-Object Name

    $GroupListB |
        Select-Object Name, SamAccountName, Description, DistinguishedName, `
            GroupCategory, GroupScope, whenCreated, whenChanged, DaysSinceChange, `
            MemberCount, MemberOfCount, SID, SIDHistory |
        Export-CSV .\GroupListB.csv -NoTypeInformation

}

#endregion#####################################################################

#region########################################################################
# Build the list of comparisons to do
$ToDo = @{}
$i = 0
foreach ($GroupA in ($GroupListA | Where-Object {$_.MemberCount -ge $MinMember}))
{
    $ToDo.Add($GroupA.($idA),@())
    $CountA = $GroupA.MemberCount

    foreach ($GroupB in ($GroupListB | Where-Object {$_.MemberCount -ge $MinMember}))
    {
        if ($GroupB.($idB) -ne $GroupA.($idA) `
            -and -not $ToDo.ContainsKey($GroupB.($idB)))
        {
            $CountB = $GroupB.MemberCount

            # Calculate the percentage size difference between the two groups
            If ($CountA -le $CountB) {
                $CountPercent = $CountA / $CountB * 100
            } Else {
                $CountPercent = $CountB / $CountA * 100
            }

            # If specified check the percentage difference in two group sizes is not more than $CountPercentThreshold
            If ( ($CountPercentThreshold -eq 0) -or `
             $CountPercent -ge $CountPercentThreshold ) 
            {
                $ToDo.($GroupA.($idA)) += $GroupB.($idB)
                $i += 1
            }
        }
    }
}
write-host "$i group comparisons will be made"

#endregion#####################################################################

#region########################################################################

# Start writing report file

"NameA,NameB,CountA,CountB,CountEqual,MatchPercentA,MatchPercentB,ScopeA,ScopeB,CategoryA,CategoryB,DNA,DNB" | out-file $ReportFile -Encoding Default

# Outer loop through A groups

$progress = 0
ForEach ($a in $ToDo.Keys) 
{
    $GroupA = $GroupListA | where {$_.($idA) -eq $a}
    $CountA = $GroupA.MemberCount
    $progress += 1

    # Inner loop through B groups

    ForEach ($b in $ToDo.($a)) 
    {
        $GroupB = $GroupListB | where {$_.($idB) -eq $b}
        $CountB = $GroupB.MemberCount

        Write-Progress `
            -Activity "Comparing members of $($GroupA.Name)" `
            -Status "To members of $($GroupB.Name)" `
            -PercentComplete ($progress/$ToDo.Count * 100)
        
        
        # This is the heart of the script. Compare group memberships.
        $co = Compare-Object -IncludeEqual `
            -ReferenceObject $GroupA.Member `
            -DifferenceObject $GroupB.Member
        $CountEqual = ($co | Where-Object {$_.SideIndicator -eq '=='} | `
            Measure-Object).Count

        $PercentMatchA = [math]::Round($CountEqual / $CountA * 100,2)
        $PercentMatchB = [math]::Round($CountEqual / $CountB * 100,2)

        # Add an entry to the report file for GroupA/GroupB
        if ($PercentMatchA -ge $ReportThreshold -or $PercentMatchB -ge $ReportThreshold)
        {
            $report = '"' + $GroupA.Name + '","' +
                            $GroupB.Name + '","' +
                            $CountA + '","' +
                            $CountB + '","' +
                            $CountEqual + '","' +
                            $PercentMatchA + '","' +
                            $PercentMatchB + '","' +
                            $GroupA.GroupScope + '","' +
                            $GroupB.GroupScope + '","' +
                            $GroupA.GroupCategory + '","' +
                            $GroupB.GroupCategory + '","' +
                            $GroupA.DistinguishedName + '","' +
                            $GroupB.DistinguishedName
            $report | Add-Content $ReportFile
        }
    }
} 

#endregion#####################################################################

