<#
.Synopsis
   -Find and replace strings of concern in saved searches and dashboard, after human review.
.DESCRIPTION
   -Prompts users to select item(s) to update from list of searches and views having legacy windows sourcetype references
   -Drafts text replacement and displays line changes in windiff application
   -If user accepts line changes, new content is placed in clipboard
   -Opens selected view/search for editing in browser, where clipboard content and be pasted and saved.
#>

function get-splunk-search-results {

    param ($cred, $server, $port, $search)

    # This will allow for self-signed SSL certs to work
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12   #(ssl3,SystemDefault,Tls,Tls11,Tls12)

    $url = "https://${server}:${port}/services/search/jobs/export" # braces needed b/c the colon is otherwise a scope operator
    $the_search = "$($search)" # Cmdlet handles urlencoding
    $body = @{
        search = $the_search
        output_mode = "csv"
          }
    
    $SearchResults = Invoke-RestMethod -Method Post -Uri $url -Credential $cred -Body $body -TimeoutSec 300
    return $SearchResults
}

function GetMatches([string] $content, [string] $regex) {
    $returnMatches = new-object System.Collections.ArrayList
    ## Match the regular expression against the content, and    
    ## add all trimmed matches to our return list    
    $resultingMatches = [Regex]::Matches($content, $regex, "IgnoreCase")    
    foreach($match in $resultingMatches)    {        
        $cleanedMatch = $match.Groups[1].Value.Trim()        
        [void] $returnMatches.Add($cleanedMatch)    
    }
    $returnMatches 
}

# define splunk instance variables to use
$server = "splunk-dev"
$port = "8089"

# Define path to windiff tool, allowing for human review of changes:
$windiff_filepath = 'C:\Program Files (x86)\Support Tools\windiff.exe'
if (!(Test-Path -Path $windiff_filepath)) {
    write-host "Unable to verify support file in path $($windiff_filepath)."
    write-host 'Windiff is part of the the "Windows Server 2003 Resource Kit Tools" package which can be downloaded from https://www.microsoft.com/en-us/download/details.aspx?id=17657.'
    write-host 'Exiting.'
    exit
}

# Define path to preferred browser, which will later be used to open KOs for editing.
$browser_filepath = 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
if (!(Test-Path -Path $browser_filepath)) {
    write-host "Unable to verify support file in path $($browser_filepath)."
    write-host 'Please update the browser_filepath variable in this script provide the path to your preferred browswer for administering splunk.'
    write-host 'Exiting.'
    exit
}

# collect credentials from user, securely, at runtime
if (!($cred)) { $cred = Get-Credential -Message "enter splunk cred" -UserName "admin" }

# define the splunk search which returns a noramlized set of fields for savedsearches and views matching pattern of concern
$theSearch = '| rest /servicesNS/-/-/data/ui/views splunk_server=local 
| rename eai:appName as appName, eai:acl.owner as owner, eai:acl.sharing as sharing, eai:data as data, eai:type as type 
| fields type, appName, sharing, owner, title, updated, data, id
| append 
    [| rest/servicesNS/-/-/saved/searches splunk_server=local 
    | eval type="search" 
    | rename eai:acl.app as appName, eai:acl.owner as owner, qualifiedSearch as data 
    | fields type, appName, sharing, owner, title, updated, data, id
        ]
| regex data="(?msi)sourcetype\s?=\s?(\"(xml)?wineventlog:[^\"]+\"|(xml)?wineventlog:[^\s]+)" 
| sort 0 appName, type, title'

# perform the search and return results as object 
$results = get-splunk-search-results -server $server -port $port -cred $cred -search $theSearch
if (!($results)) { 
    write-host "no results found, exiting."
    exit 
}
$results = ConvertFrom-Csv -InputObject $results



# enumerate knowledge objects having text of concern
$Pattern = '(?i)(sourcetype\s?=\s?(\"(xml)?wineventlog:[^\"]+\"|(xml)?wineventlog:[^\s]+))'
$records = @()
foreach ($result in $results) {

    # identify instances of the text of concern within object data
    $Matches = GetMatches -content $result.data -regex $Pattern

    if ($Matches) {

        $data_new = $result.data
        $unique_matches = $matches | Select-Object -Unique

        # replace instances with OR statement
        foreach ($match in $unique_matches) {
            $match_newtext = $match -replace "sourcetype","source"
            $match_newtext = "($($match) OR $($match_newtext))"
            # don't bother with replacement if the replacement appears to be present already
            if ($data_new -notmatch $match_newtext) {
                $data_new = $data_new -replace $match,$match_newtext
            }
        }

        # now, after all that, only add record to recordset if there appears to be a change
        if ($result.data -ne $data_new) {

            $record = @{
                'type' =  $result.type
                'appName' =  $result.appName
                'sharing' = $result.sharing
                'owner' = $result.owner
                'title' = $result.title
                'updated' = $result.updated
                'data' = $result.data
                'id' = $result.id
                'match_count' = $Matches.count
                'matches' = $Matches          
                'data_new' = $data_new
            }

            $records += New-Object -TypeName PSObject -Property $Record
        }

    }

}


$Selected = $records | Select-object type, title, match_count, matches, updated, id | Out-GridView -PassThru  -Title 'Selected one or more objects to update.'
if (!$Selected) {
    write-host "nothing selected, exiting."
    exit 
} else {
    foreach ($item in $selected) {
        $this_item_detail = $records | ?{$_.id -eq $item.id} | Select-Object -Unique

        # write orig content to a file
        $origfile = "$($env:temp)\kodata.orig"
        if (Test-Path -Path $origfile) { Remove-Item -Path $origfile -Force }
        Add-Content -Path $origfile -Value $this_item_detail.data

        # write new content to a file
        $newfile = "$($env:temp)\kodata.new"
        if (Test-Path -Path $newfile) { Remove-Item -Path $newfile -Force }
        Add-Content -Path $newfile -Value $this_item_detail.data_new

        # launch windiff to human review proposed change in content of two files
        Start-Process -filepath $windiff_filepath -argumentlist @('"' + $origfile + '"','"' + $newfile + '"') -Wait

        # ask user if human review was acceptable and if so, do change.
        $Response = @("Yes - Put new source in my clipboard and open knowledge object for editing in browser.","No - Lets defer the change for now") | Out-GridView -Title "Proceed with change to $($this_item_detail.title)?" -PassThru
        if ($Response -match "^Yes") {     

            # build url which will enable open of knowledge object in edit mode

            if ($this_item_detail.type -eq "search") {
                $url_endpoint =  "http://$($server):8000/en-US/app/$($this_item_detail.appName)/search?s="
                $url_querystring = "/servicesNS/$($this_item_detail.owner)/$($this_item_detail.appName)/saved/searches/"
                $url_querystring += [System.Web.HttpUtility]::UrlEncode("$($this_item_detail.title)")               
                $edit_url = "$($url_endpoint)$($url_querystring)"
            }

            if ($this_item_detail.type -eq "views") {
                $url_endpoint =  "http://$($server):8000/en-US/manager/$($this_item_detail.appName)/data/ui/views/$($this_item_detail.title)?"
                $url_querystring = "action=edit&ns=$($this_item_detail.appName)&uri=/servicesNS/$($this_item_detail.owner)/$($this_item_detail.appName)/data/ui/views/"
                $url_querystring += $url_querystring = [System.Web.HttpUtility]::UrlEncode("$($this_item_detail.title)")
                $edit_url = "$($url_endpoint)$($url_querystring)"

            }

            # print a line of audit (future log) indicating user intent to edit object
            write-host "$(get-date) - User opted to apply $($this_item_detail.match_count) corrections to object with id [$($this_item_detail.id)] " 

            # get content of resultant windiff file into clipboard (in case user made overrides in file)
            Get-Content -Path $newfile | clip

            # start new browser tab where admin can paste and save updated content
            Start-Process -filepath $browser_filepath -argumentlist @($edit_url) -Wait
        }

        
    }


}
