use Test::More tests => 1;
use XML::XSLT;
use strict;

my $xslt;
eval
{
 local $^W = 0; # don't understand the Expat warning yet
 $xslt = XML::XSLT->new (Source => 't/open.xsl',debug => 0);
 $xslt->open_xsl('t/open.xsl');
 $xslt->transform('t/open.xml');
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
