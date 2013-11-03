use Test::More tests => 2;
use XML::XSLT;
use strict;

use FindBin qw($Bin);

my $DEBUG = 0;
my  $xslt = XML::XSLT->new (Source => "$Bin/test_data/MkFinder.xsl",debug => $DEBUG);
$xslt->transform("$Bin/test_data/catalog.xml");
ok(my $out =$xslt->toString,"open_xsl()");

my $expect =<<'EOF';
@echo off
 if not exist Xalan_Conformance_Tests\attribset\attribset01.xml echo Xalan_Conformance_Tests\attribset\attribset01.xml is missing 
 if not exist Xalan_Conformance_Tests\attribset\attribset01.xsl echo Xalan_Conformance_Tests\attribset\attribset01.xsl is missing 
 if not exist Xalan_Conformance_Tests\REF_OUT\attribset\attribset01.out echo Xalan_Conformance_Tests\REF_OUT\attribset\attribset01.out is missing 
echo DONE
EOF

chomp $expect;

is($out, $expect, "got what we expected");
