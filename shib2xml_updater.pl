#!/usr/bin/perl -w

 use strict;
 use warnings;

################################################################################################
# LICENSE
################################################################################################
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
################################################################################################

#########################################################################
# BEGIN CONFIGURABLE ELEMENTS

# the email address defined here will be used for success and failure emails
my $admin_email = 'example@domain.edu';

# set to 1 if you would like to receive an email at the above address when the script runs successfully
my $success_email = 0 ;

# set to 1 if you would like to receive an email at the above address when the script fails
my $failure_email = 0 ;

# END CONFIGURABLE ELEMENTS
#########################################################################

#load modules
 use XML::Writer;
 use XML::LibXML;
 use XML::LibXML::XPathContext;
 use Getopt::Long;
 use File::Copy;
 
################################################
#initialize variables used for command arguments
################################################

my $mode;
my $domain_name;
my $filepath;
my $preview = 0;

GetOptions(
	"-mode=s"     => \$mode,
	"-domain=s"    => \$domain_name,
	"-filepath=s" => \$filepath,
	'preview' => \$preview
);

#########################################################################
#series of checks to make sure a valid set of arguments has been passed.
# if not, exit and display help text
#########################################################################

unless ($mode && $domain_name) {
    helpdoc();
    failmail();
    exit 1;
}

my $arg_errs = 0;

$mode = lc($mode);
if ($mode ne "add" && $mode ne "remove") {
    print "Invalid -mode.  Only 'add' and 'remove' are acceptable.\n\n";
    $arg_errs = 1;
}

$domain_name = lc($domain_name);
    if ( $domain_name !~ m/^([a-z0-9-]+){1}(\.[a-z0-9-]+){1,}$/) {
    print "Invalid -domain.  Not in FQDN format.\n\n";
    $arg_errs = 1;        
    }	

if ($arg_errs == 1) {
    helpdoc();
    failmail();
    exit 1;
}

#########################################################################
#if prod environment create preview domain by removing www. if necessary
#########################################################################

my $preview_domain = "";
    if ($preview == 1) {
	if  ((substr $domain_name, 0, 4) eq "www.") {
	my $trunc = (substr $domain_name, 4);
	$preview_domain = "preview.$trunc";
    }
    else {
	$preview_domain = "preview.$domain_name";
    }
}

#########################################################################
# define filepath, based on argument passed or give it a value of ""
#########################################################################

if ($filepath) {
        if  ((substr $filepath, -15) eq "shibboleth2.xml") {
	my $trunc = (substr $filepath, -15, 15, "");
    }
        if  ((substr $filepath, -1, 1) ne "/") {
	$filepath = "$filepath/";
    }
	
}

else { $filepath = "/etc/shibboleth/"; }

##########################################################
# define values of shib file, stagning file and temp file
##########################################################

my $file = "${filepath}shibboleth2.xml";
my $stagingfile = "${filepath}shibboleth2.xml.staging";
my $tempfile = "${filepath}shibboleth2.xml.tmp";

#######################
# Print logging header
#######################

	my $timestamp = get_timestamp();
	
	print "\n####################################################################################################\n";
	print "Updating shibboleth2.xml in '$mode' mode for domain: $domain_name (timestamp: $timestamp)\n";
	print "####################################################################################################\n\n";
	
####################################################
# Move file to archive dir with timestamp appended
####################################################

	my $filename = "shibboleth2.xml.$timestamp";

	# Check that archive dir exists, create if it doesn't
	if ( !( -e "$filepath"."archive" ) ) {
		mkdir "$filepath"."archive"
		  or die "Can't create $filepath"."archive: $!\n";
	}

	copy( $file, "$filepath"."archive/$filename" )
	  or die "Unable to archive old version, dying: $!\n";

	print "Archived current shibboleth2.xml to $filepath"."archive/$filename\n";

##################################################################
# Create new temporary file based on current production shib file
##################################################################

	copy( $file, $tempfile )
	  or die "Unable to save shibboleth2.xml.temp...dying: $!\n";

	print "Copied current $file to $tempfile\n\n";
	
print "These are the files we will be working with:\n";
print "file: $file\nstaging file: $stagingfile\ntemporary file: $tempfile\n\n";

##########################################
# open temp file and load xml into parser
##########################################

my $parser = XML::LibXML->new();

# make sure new temp file parses
my $parse_chk = eval { my $doc = $parser->parse_file($tempfile); };

unless($parse_chk) {
	print "Error parsing $tempfile:\n$@Exiting...\n";
	failmail();
        exit 1;
}

my $doc = $parser->parse_file($tempfile);

my $xml = XML::LibXML::XPathContext->new( $doc->documentElement() );

# open $tempfile and truncate so it contains no content while
# nodes are being added and/or removed

open out_fh, ">$tempfile" or die $!;

print "Opened and parsed $tempfile\n\n";

############################################
# register the namespaces used in Shib file
############################################

$xml->registerNs( 'md', 'urn:oasis:names:tc:SAML:2.0:metadata' );
$xml->registerNs( 'conf', 'urn:mace:shibboleth:2.0:native:sp:config' );
$xml->registerNs( 'saml', 'urn:oasis:names:tc:SAML:2.0:assertion' );
$xml->registerNs( 'samlp', 'urn:oasis:names:tc:SAML:2.0:protocol' );

#########################################################################
# BEGIN SUB FUNCTION: ADD NEW SHIBBOLETH SP
sub add() {  

my $nodes2 = $xml->findnodes('//conf:Host');
my $host_exists = 0;
my $preview_host_exists = 0;

 foreach my $context ($nodes2->get_nodelist) {
       my $host_name = $context->findvalue('./@name');
       
       if ($host_name eq $domain_name) {
         $host_exists = 1;
       }
       
       elsif ($host_name eq $preview_domain) {
        $preview_host_exists = 1;
       }
       
 }

 if ($host_exists == 0) {
        my $newHost = $doc->ownerDocument->createElement('Host');
        $newHost->setAttribute("name", $domain_name);
        $newHost->setAttribute("applicationId", $domain_name);
        
        my $nodes_insert = $xml->findnodes('//conf:RequestMap');
        $nodes_insert->push($newHost);
        $nodes_insert->[0]->addChild($newHost);
        print "Added Host element (name: $domain_name, applicationId: $domain_name)\n";        

}
 else {
    print "Host element already exists with name: $domain_name.  Skipping...\n";
 }

if ($preview == 1) {

 if ($preview_host_exists == 0 ) {
        my $newHost2 = $doc->ownerDocument->createElement('Host');
        $newHost2->setAttribute("name", $preview_domain);
        $newHost2->setAttribute("applicationId", $domain_name);
        
        my $nodes_insert = $xml->findnodes('//conf:RequestMap');
        $nodes_insert->push($newHost2);
        $nodes_insert->[0]->addChild($newHost2);
        print "Added Host element (name: $preview_domain, applicationId: $domain_name)\n";        
        

}
  else {
    print "Host element already exists with name: $preview_domain.  Skipping...\n";
 }

}

my $nodes3 = $xml->findnodes('//conf:ApplicationOverride');
my $app_exists = 0;

 foreach my $context ($nodes3->get_nodelist) {
       my $app_id = $context->findvalue('./@id');
       if ($app_id eq $domain_name) {
        $app_exists = 1;
       }
 }
 
  if ($app_exists == 0) {
        my $newApp = $doc->ownerDocument->createElement('ApplicationOverride');
        $newApp->setAttribute("id", $domain_name);
        $newApp->setAttribute("entityID", "https://$domain_name/shibboleth");
        
        my $nodes_insert = $xml->findnodes('//conf:ApplicationDefaults');
        $nodes_insert->push($newApp);
        $nodes_insert->[0]->addChild($newApp);
        print "Added ApplicationOverride (name: $domain_name, applicationId: https://$domain_name/shibboleth)\n";                

}
   else {
    print "ApplicationOverride element already exists with id: $domain_name.  Skipping...\n";
 }

}
# END SUB FUNCTION: ADD NEW SHIBBOLETH SP
#########################################################################

#########################################################################
# BEGIN SUB FUNCTION: REMOVE NEW SHIBBOLETH SP
sub remove() {

my $nodes2 = $xml->findnodes('//conf:Host');

 foreach my $context ($nodes2->get_nodelist) {
       my $host_name = $context->findvalue('./@name');
       
       if ($host_name eq $domain_name) {
         $context->unbindNode;
	print "Host $domain_name found.  Removing node...\n";
       }
       
       elsif ($host_name eq $preview_domain) {
        $context->unbindNode;
	print "Host $preview_domain found.  Removing node...\n";
       }
       
 }
    my $or_preview;
    if ($preview == 1) { $or_preview = " or $preview_domain"; }
    else { $or_preview = ""; } 
    print "Check for Hosts matching $domain_name" . "$or_preview complete.\n\n";

my $nodes3 = $xml->findnodes('//conf:ApplicationOverride');

 foreach my $context ($nodes3->get_nodelist) {
       my $app_id = $context->findvalue('./@id');
       
       if ($app_id eq $domain_name) {
        $context->unbindNode;
	print "ApplicationOverride $domain_name found.  Removing node...\n";
       }
 }

    print "Check for ApplicationOverrides matching $domain_name complete.\n";

}
# END SUB FUNCTION: REMOVE NEW SHIBBOLETH SP
#########################################################################

########################################################################
# run add or remove function on temp file as indicated by mode selected
########################################################################
 
 if ($mode eq "add") {
    
    add(); 
 }
 elsif ($mode eq "remove") {
    remove();
 }
 
 else {
    print "No valid mode selected. Exiting...\n";
    helpdoc();
    failmail();
    exit 1;    
 }

######################
# print new temp file
######################

 print out_fh $doc->toString;
 print "\nSaved updated XML to $tempfile\n";
 close out_fh;
 print "Closed $tempfile\n\n";

################################################
# publish temp file to production and staging
# using Linux xmllint command to fix formatting 
################################################
 
 system( "xmllint --format $tempfile > $file" );
 print "Published formatted $tempfile to $file\n";

 system( "xmllint --format $tempfile > $stagingfile" );
 print "Published formatted $tempfile to $stagingfile\n\n";
  
#########################################################################
#Double-check that new file parses and restore archived version if it doesn't
#########################################################################

parse();

#########################################################################
# BEGIN SUB FUNCTION: HELP TEXT
sub helpdoc {

print "\nUSAGE:

./shib2xml_updater.pl -mode <add|remove> -domain <FQDN> [-preview -filepath <non-default filepath>] 
   
OPTION\tACCEPTABLE VALUES
-mode\t\t'add' or 'remove'
-domain\t\tany valid Fully Qualified Domain Name (no leading 'https://')
-preview\toff by default. if flag is set, preview domain version of Host element is added
-filepath\t**OPTIONAL**  absolute path to shibboleth2.xml.  
 \t\totherwise it's assumed that shibboleth2.xml is in the standard 
 \t\tinstall directory /etc/shibboleth\n";

}
# END SUB FUNCTION: HELP TEXT
#########################################################################


#########################################################################
# BEGIN SUB FUNCTION: GET TIMESTAMP
sub get_timestamp {
	my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
	  localtime(time);

	$year = $year + 1900;
	$mon  = $mon + 1;

	return $year
	  . sprintf( '%02u%02u_%02u%02u%02u', $mon, $mday, $hour, $min, $sec );
}
# END SUB FUNCTION: GET TIMESTAMP
#########################################################################


#########################################################################
# BEGIN SUB FUNCTION: FAILURE EMAIL
sub failmail {

	if ($failure_email == 1) {
    system( "echo 'There was a problem with shib2xml_updater.pl, and Shib config was not updated in $mode mode for $domain_name.  Review script output for detail.' | mail -s '**Shib config was NOT updated for $domain_name' $admin_email" );
	}

}
# END SUB FUNCTION: FAILURE EMAIL
#########################################################################


#########################################################################
# BEGIN SUB FUNCTION: PARSE PRODUCTION SHIB FILE
sub parse {

open(FH, "< $file") || die ("Could not locate $file");
flock(FH, 2);    
    
my $parser = XML::LibXML->new();

my $parse_chk = eval { my $doc = $parser->parse_file($file); };

unless($parse_chk) {
	print "Error parsing XML file:\n$@\n";
	copy( "$filepath"."archive/$filename", $file )
	  or die "Unable to restore archived version, dying: $!\n";
	print "Restored archived $filepath"."archive/$filename to $file\n";	

	copy( "$filepath"."archive/$filename", $stagingfile )
	  or die "Unable to restore archived version to staging file, dying: $!\n";
	print "Restored archived $filepath"."archive/$filename to $stagingfile\n";	
	
	failmail();
        exit 1;
}

print "Double-checked that new $file parses\n\n";

	if ($success_email == 1) {
	    system( "echo '$file was updated in $mode mode for $domain_name by the shib2xml_updater.pl' | mail -s '$file was updated for $domain_name' $admin_email" );
	}
}
# END SUB FUNCTION: PARSE PRODUCTION SHIB FILE
#########################################################################
