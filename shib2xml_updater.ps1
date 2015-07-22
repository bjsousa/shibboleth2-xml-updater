Param(
    $mode,
    $domain,
    $site_id,
[switch] $preview,
    $filepath)
    
####################################################################
# LICENSE
####################################################################
#
# Copyright 2015, Board of Regents of the University of
# Wisconsin System. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Board of Regents of the University of Wisconsin
# System licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a
# copy of the License at:
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#####################################################################

#####################################################################
# BEGIN FUNCTIONS
#####################################################################

function helpdoc() {

Write-Host "
USAGE:

.\shib2xml_updater.ps1 -mode <add|remove> -domain <FQDN> -site_id <integer> [-preview -filepath <non-default filepath>] 
   
OPTION`t`tACCEPTABLE VALUES
-mode`t`t'add' or 'remove'
-domain`t`tany valid Fully Qualified Domain Name (no leading 'https://')
-site_id`tWindows IIS Site ID corresponding to the domain
-preview`toff by default. if flag is set, preview domain version of Host element is added
-filepath`t**OPTIONAL**  absolute path to shibboleth2.xml.  
 `t`t`totherwise it's assumed that shibboleth2.xml is in the standard 
 `t`t`tinstall directory C:\opt\shibboleth-sp\etc\shibboleth
 ";


}

function Is-Valid-XML 
{
    param ([string] $path)

    $xml = New-Object System.Xml.XmlDocument
    try 
    {
        $xml.Load($path)
        $valid = $true
    }

    catch
    {
        $valid = $false
    }

    return $valid
}

#####################################################################
# END FUNCTIONS
#####################################################################

# check before proceeding that all needed values are present 
# and in correct format
#
# otherwise print errors and output help documentation
 
if (!$mode -or !$domain) {
    Write-Host "
    **ERROR** Values must be provided for -mode and -domain
    "
    helpdoc;
    exit 1;
}

$arg_errs = 0

$mode = $mode.ToLower();
if ( ($mode -ne "add") -and ($mode -ne "remove" ) ) {
    Write-Host "**ERROR** Invalid -mode.  Only 'add' and 'remove' are acceptable.\n\n";
    $arg_errs = 1;
}

$domain = $domain.ToLower();
    if ( $domain -notmatch "^([a-z0-9-]+){1}(\.[a-z0-9-]+){1,}$" ) {
    Write-Host "**ERROR** Invalid -domain.  Not in FQDN format.\n\n";
    $arg_errs = 1;        
    }	

if ($arg_errs -eq 1) {
    helpdoc
    exit 1
}

#########################################################################
# if prod, create preview domain by removing www. if necessary
#########################################################################

$preview_domain = "";
    if ($preview) {
	if  ($domain.Substring(0, 4) -eq "www.") {
	$trunc = $domain.Substring(4)
	$preview_domain = "preview.$trunc";
    }
    else {
	$preview_domain = "preview.$domain";
    }
}

#########################################################################
# define filepath, based on argument passed or give it a value of ""
#########################################################################

if ($filepath) {
    $filepath = $filepath.ToLower()

        if  ($filepath.Contains("shibboleth2.xml")) {
        Write-Host "Yes"
	$filepath = $filepath.Replace("shibboleth2.xml", "");

    }
    
    $final_char = ($filepath.length - 1)

        if  ($filepath.Substring($final_char) -ne "\") {
	$filepath = "$filepath\"

    }
	
}

else { $filepath = "C:\opt\shibboleth-sp\etc\shibboleth\" }


#######################
# Print logging header
#######################

$timestamp = Get-Date -format "MMddyyyyHHmmss"
	
	Write-Host "`r###################################################################################################################
Updating shibboleth2.xml in '$mode' mode for domain: $domain (timestamp: $timestamp)
###################################################################################################################`r"
#########################################################################
# test if shibboleth2.xml exists.  if not, abort
# if so, define values of shib file, staging file, temp file, archive file
#########################################################################

if ((Test-Path ${filepath}shibboleth2.xml) -eq $FALSE) {
    Write-Host "
**ERROR** Unable to locate primary file ${filepath}shibboleth2.xml.  Aborting...`n`r`n`r"
exit 1
}

else {
$file = "${filepath}shibboleth2.xml"
$stagingfile = "${filepath}shibboleth2.xml.staging"
$tempfile = "${filepath}shibboleth2.xml.tmp"
$archfile = "${filepath}archive\shibboleth2.xml.$timestamp"
}

####################################################
# Move file to archive dir with timestamp appended
####################################################

	# Check that archive dir exists, create if it doesn't

if ((Test-Path ${filepath}archive) -eq $FALSE)  {
		New-Item -ItemType directory -Path ${filepath}archive
   
   if  ((Test-Path ${filepath}archive) -eq $FALSE) {
   #if unable to create the archive directory, 
   # copy to same directory as main shibboleth2.xmlfile and print warning
   $archfile = "${filepath}shibboleth2.xml.$timestamp"
    Write-Host "
**ERROR** Unable to locate or create ${filepath}archive directory.  
Archiving to $archfile instead.`r"
     }
 }

Copy-Item -Path $file -Destination $archfile

Write-Host "Archived current $file to $archfile `r"

##################################################################
# Create new temporary file based on current production shib file
##################################################################

Copy-Item -Path $file -Destination $tempfile

	Write-Host "Copied current $file to $tempfile

These are the files we will be working with:
file: $file
staging file: $stagingfile
temporary file: $tempfile
archive file: $archfile  `r"

##########################################
# open temp file and load xml into parser
##########################################

 if ((Is-Valid-XML $tempfile) -eq $TRUE) {

 $myXML = new-object System.Xml.XmlDocument
 $myXML.load($tempfile)
 Write-Host "`n`r`n`rOpened and parsed $tempfile `r"

 }

 else {

 Write-Host "`n`rError parsing XML in $tempfile.  Exiting...`n`r`n`r"
 exit 1

 }

############################################
# register the namespaces used in Shib file
############################################

$xmlNsManager = New-Object System.Xml.XmlNamespaceManager($myXML.NameTable)
$xmlNsManager.AddNamespace("conf", "urn:mace:shibboleth:2.0:native:sp:config")

#####################################################################################################
#####################################################################################################
# BEGIN UPDATE XML SECTION
#####################################################################################################
#####################################################################################################

Write-Host "Updating XML...`n`r`n`r"

#
###############################
# MODE: ADD
##############################
#
if ($mode -eq "add") {
 
# check before proceeding that site id is valid 
# and in correct format
#
# otherwise print error and output help documentation
 
if ( (!$site_id) -or ($site_id -notmatch "^[0-9]+$" ) ) {

    Write-Host "**ERROR** Invalid -site_id.  Site ID must be an integer.\n\n";
    helpdoc
    exit 1      
    
}

#########################################################################
# UPDATE Site
#########################################################################

# define context of Site nodes
$siteContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:InProcess/conf:ISAPI", $xmlNsManager)

# select Site nodes
$sites = $myXML.SelectNodes("/conf:SPConfig/conf:InProcess/conf:ISAPI/conf:Site", $xmlNsManager)

# set flag to assume site does not currently exist
$site_exists = 0

     foreach ($site in $sites) {
     $id = $site.id
     $name = $site.name
     
         # if the site id matches, but the site name does not, the node conflicts
         # with the new one and needs to be removed
           if (($site_id -eq $id) -and ( ($name -ne $preview_domain) -and ($name -ne $domain ) ) ) {
            Write-Host "Site ID already exists for other domain.  Removing node:`r";
               $siteContext.RemoveChild($site)
       }

             # if the site name matches, but the site id does not, update the id
             # and set exists flag to true
            if ( ($site_id -ne $id) -and ( ($name -eq $domain) -or ($name -eq $preview_domain) ) ) {
            Write-Host "Incorrect site id ($site_id) for domain $domain. Set ID to $site_id`r";
            $site.setAttribute("id", $site_id);
           $site_exists = 1;  
       }

       # if node didn't meet criteria above but still matches site name, set exists flag to true
       elseif ( ($name -eq $domain) -or ($name -eq $preview_domain ) ) {
           $site_exists = 1;  
            }

 }

  # add the site node if the flag is still set to false
 if ($site_exists -eq 0) {
    
    #if it's a test site, you add a simple Site node with id and name
    if (!$preview) {
        Write-Host "Adding Site element:`r"

        $newSite = $myXML.CreateElement("Site")
        $newSite.setattribute("id",$site_id)
        $newSite.setattribute("name",$domain)
        
        $siteContext.AppendChild($newsite)
        Write-Host "...`n`r`n`r"
    }
    
    # if it's a prod site, you add the preview domain as the name
    # and add a the production domain as an Alias child element
    #
    # ** this setup is not necessary but facilitates seamless
    # migration of production sites in a shared hosting environment **
     
    elseif ($preview) {
        Write-Host "Adding Site element:`r"

        $newSite = $myXML.CreateElement("Site")
        $newSite.setattribute("id",$site_id)
        $newSite.setattribute("name",$preview_domain)

        $alias= $myXML.CreateElement("Alias")
        $aliasname= $myXML.CreateTextNode($domain)
        $alias.AppendChild($aliasname)

        $newSite.AppendChild($alias)


        $siteContext.AppendChild($newSite)
         Write-Host "...`n`r`n`r"
    }

}

# skip if the flag is set to true
 else {
    Write-Host "Site element already exists with id: $site_id and name: $domain.  Skipping.
...`n`r`n`r"
 }


##############################
# UPDATE Host
##############################

# define context of Host nodes  
$hostContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:RequestMapper/conf:RequestMap", $xmlNsManager)

# select Host nodes
$hosts = $myXML.SelectNodes("/conf:SPConfig/conf:RequestMapper/conf:RequestMap/conf:Host", $xmlNsManager)

# set flag to assume host and preview host do not currently exist
$host_exists = 0
$preview_host_exists = 0

# search Host nodes for one that matches the domain being added
 foreach ($hst in $hosts) {
       $name = $hst.name
       
       if ($name -eq $domain) {

       #if one matches the domain, set the flag to true
         $host_exists = 1;
       
       }
       
       elseif ($name -eq $preview_domain) {

       #if one matches the preview domain, set the preview flag to true
        $preview_host_exists = 1;

       }
       
 }

  # add the production node if the domain flag is still set to false
 if ($host_exists -eq 0) {
        Write-Host "Adding Host element:`r"

        $newHost = $myXML.CreateElement("Host")
        $newHost.setattribute("name", $domain)
        $newHost.setattribute("applicationId", $domain)
        
        $hostContext.AppendChild($newHost)
         Write-Host "...`n`r`n`r"
}

# skip if the flag is set to true
 else {
    Write-Host "Host element already exists with name: $domain.  Skipping.
...`n`r`n`r"
 }

 # on production, check separately for and add the preview node if the
 # preview host flag is still set to false
if ($preview) {

  # add the preview node if the domain flag is still set to false
 if ($preview_host_exists -eq 0 ) {
       Write-Host "Adding Host element:`r"

        $newHost2 = $myXML.CreateElement("Host")
        $newHost2.setattribute("name", $preview_domain)
        $newHost2.setattribute("applicationId", $domain)
        
        $hostContext.AppendChild($newHost2)        
         Write-Host "...`n`r`n`r"
}

# skip if the flag is set to true
  else {
    Write-Host "Host element already exists with name: $preview_domain.  Skipping.
...`n`r`n`r"
 }

}

##############################
# UPDATE ApplicationOverride
##############################

# define context of ApplicationOverride nodes
$appContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:ApplicationDefaults", $xmlNsManager)

# select ApplicationOverride nodes
$apps = $myXML.SelectNodes("/conf:SPConfig/conf:ApplicationDefaults/conf:ApplicationOverride", $xmlNsManager)

# set flag to assume app does not currently exist
$app_exists = 0

# search ApplicationOverride nodes for one that matches the domain being added
 foreach ( $app in $apps ) {
       $app_id = $app.id

        if ($app_id -eq $domain) {
        
        #if it's found, set the flag to true
        $app_exists = 1

       }
 }
 
 # add the node if the flag is still set to false
  if ($app_exists -eq 0) {
        Write-Host "Adding ApplicationOverride element:`r"
              
        $newApp = $myXML.CreateElement("ApplicationOverride")
        $newApp.setattribute("id", $domain)
        $newApp.setattribute("entityID", "https://$domain/shibboleth")
        
        $appContext.AppendChild($newApp)
         Write-Host "...`n`r`n`r"
}

# skip if the flag is set to true
   else {
    Write-Host "ApplicationOverride element already exists with id: $domain.  Skipping.
...`n`r`n`r"
 }

 }

#
###############################
# MODE: REMOVE
##############################
#
 if ($mode -eq "remove") {

 #########################################################################
# UPDATE Site
#########################################################################

# define context of Site nodes
$siteContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:InProcess/conf:ISAPI", $xmlNsManager)

# select Site nodes
$sites = $myXML.SelectNodes("/conf:SPConfig/conf:InProcess/conf:ISAPI/conf:Site", $xmlNsManager)

# search Site nodes for one that matches the domain being removed
     foreach ($site in $sites) {
     $name = $site.name
     
       # remove node if its name matches the domain name
       if ($name -eq $domain) {
        Write-Host "Site $domain found.  Removing node:`r"
        $siteContext.RemoveChild($site)
        Write-Host "`r"
            }
        # remove node if its name matches the preview domain name
       if ($name -eq $preview_domain)  {
                Write-Host "Site $preview_domain found.  Removing node:`r"
        $siteContext.RemoveChild($site)
         Write-Host "`r"
            }

 }

    if ($preview) { $or_preview = " or $preview_domain"; }
    else { $or_preview = ""; } 

    Write-Host "Check for Sites matching $domain$or_preview complete.
...`n`r`n`r"
 


##############################
# UPDATE Host
##############################

# define context of Host nodes  
$hostContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:RequestMapper/conf:RequestMap", $xmlNsManager)

# select Host nodes
$hosts = $myXML.SelectNodes("/conf:SPConfig/conf:RequestMapper/conf:RequestMap/conf:Host", $xmlNsManager)

# search Host nodes for one that matches the domain being removed
 foreach ($hst in $hosts) {
       $name = $hst.name
       
       # remove node if its name matches the domain name
       if ($name -eq $domain) {
        Write-Host "Host $domain found.  Removing node:`r"
        $hostContext.RemoveChild($hst)
       Write-Host "`r"
       }
       
       # remove node if its name matches the preview domain name
       elseif ($name -eq $preview_domain) {

        Write-Host "Host $preview_domain found.  Removing node:`r"
        $hostContext.RemoveChild($hst)
        Write-Host "`r"
       }

       
}
    if ($preview) { $or_preview = " or $preview_domain"; }
    else { $or_preview = ""; } 
    Write-Host "Check for Hosts matching $domain$or_preview complete.
...`n`r`n`r"

##############################
# UPDATE ApplicationOverride
##############################

# define context of ApplicationOverride nodes
$appContext = $myXML.SelectSingleNode("/conf:SPConfig/conf:ApplicationDefaults", $xmlNsManager)

# select ApplicationOverride nodes
$apps = $myXML.SelectNodes("/conf:SPConfig/conf:ApplicationDefaults/conf:ApplicationOverride", $xmlNsManager)

# search ApplicationOverride nodes for one that matches the domain being removed
 foreach ( $app in $apps ) {
       $app_id = $app.id

       # remove node if its id matches the domain name
        if ($app_id -eq $domain) {

        Write-Host "ApplicationOverride $domain found.  Removing node:`r"        
         $appContext.RemoveChild($app)
         Write-Host ""
       }
 
}
     Write-Host "Check for ApplicationOverrides matching $domain complete.
...`n`r`n`r"

}


#####################################################################################################
#####################################################################################################
# END UPDATE XML SECTION
#####################################################################################################
#####################################################################################################

################################################################
# remove bare xmlns="" references to make it more human-readable
################################################################
 
  $myXML = [xml] $myXML.OuterXml.Replace(" xmlns=`"`"", "")

###################################################
# save updated XML to tempfile
###################################################

  $myXML.Save($tempfile)
  Write-Host "Saved updated XML to $tempfile`n`r`n`r"

###################################################
# copy new tempfile to main shibboleth2.xml file
###################################################

  Copy-Item -Path $tempfile -Destination $file
  Write-Host "Published formatted $tempfile to main $file`r"

  Copy-Item -Path $tempfile -Destination $stagingfile
  Write-Host "Published formatted $tempfile to staging file $stagingfile`r"

###################################################
# parse new shibboleth2.xml file
###################################################

  if (( Is-Valid-XML $file) -eq $false ) {

  # file invalid means to log the error and 
  # copy the archived version back over the 
  # main shib file to avoid bombing shibd

  Copy-Item -Path $archfile -Destination $file
  Write-Host "Error parsing $file.  Restoring $archfile to $file.
  "

  Copy-Item -Path $archfile -Destination $stagingfile
  Write-Host "Error parsing $file.  Restoring $archfile to $stagingfile.
  `r"

  }

  else {

  # otherwise log that parse check succeeded

    Write-Host "`n`r`n`rDouble-checked that new $file parses`n`r`n`r"
  }