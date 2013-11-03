use Test::More tests => 1;
use XML::XSLT;
use strict;

use FindBin qw($Bin);

my $xslt;
eval
{
 local $^W = 0; # don't understand the Expat warning yet
 $xslt = XML::XSLT->new (Source => "$Bin/test_data/open.xsl",debug => 0);
 $xslt->open_xsl("$Bin/test_data/open.xsl");
 $xslt->transform("$Bin/test_data/open.xml");
};
SKIP:
{
TODO:
{
   skip "Hmm",1 if $@;
   local $TODO = "open_xsl() doesn't work a second time";
   ok($xslt->toString,"open_xsl()");
}
}
