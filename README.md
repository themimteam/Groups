# Groups
Groups

# Author
Carol Wapshere

# Analyse-ADGroups.ps1
Exports statistics about existing AD groups and produces a report showing where most groups and their members are located, what types of groups there are, and how many are nested. This is to help with a quick evaluation of how difficult it will be to convert groups to FIM-managed.

# ConvertTo-FIMManagedGroup.ps1
This script is designed to create a group object in the FIM Portal based on an existing group in AD. The FIM group will:

* Have the same DisplayName, AccountName, Scope and Type of the AD group,
* Have the built-in FIM Administrator account as the Owner,
* Have all AD members added as explicit memebrs where a direct match on AccountName can be made.