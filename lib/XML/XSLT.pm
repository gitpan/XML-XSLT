###############################################################################
#
# Perl module: XML::XSLT
#
# By Geert Josten, gjosten@sci.kun.nl
# and Egon Willighagen, egonw@sci.kun.nl
#
###############################################################################

=head1 NAME

XML::XSLT - A perl module for processing XSLT

=cut


######################################################################
package XML::XSLT;
######################################################################

use strict;

use XML::DOM 1.25;
use LWP::Simple qw(get);
use URI;
use Cwd;
use File::Basename qw(dirname);
use Carp;

# Namespace constants
use constant NS_XSLT         => 'http://www.w3.org/1999/XSL/Transform';
use constant NS_XHTML        => 'http://www.w3.org/TR/xhtml1/strict';

use vars qw ( $VERSION @ISA @EXPORT_OK $AUTOLOAD );

$VERSION = '0.31';

@ISA         = qw( Exporter );
@EXPORT_OK   = qw( &transform &serve );

# pretty print HTML tags (<BR /> etc...)
XML::DOM::setTagCompression (\&__my_tag_compression);

my %deprecation_used;


######################################################################
# PUBLIC DEFINITIONS

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  my %args = $self->__parse_args(@_);

  $self->{DEBUG} = defined $args{debug} ? $args{debug} : "";
  $self->{PARSER}      = XML::DOM::Parser->new;
  $self->{PARSER_ARGS} = defined $args{DOMparser_args}
    ? $args{DOMparser_args} : {};
  $self->{VARIABLES}       = defined $args{variables}
    ? $args{variables}      : {};
  $self->{WARNINGS}        = defined $args{warnings}
    ? $args{warnings}       : 0;
  $self->{INDENT}          = defined $args{indent}
    ? $args{indent}         : 0;
  $self->{INDENT_INCR}     = defined $args{indent_incr}
    ? $args{indent_incr}    : 1;
  $self->{XSL_BASE}        = defined $args{base}
    ? $args{base}    : 'file://' . cwd . '/';
  $self->{XML_BASE}        = defined $args{base}
    ? $args{base}    : 'file://' . cwd . '/';
  $self->{USE_DEPRECATED}  = defined $args{use_deprecated}
    ? $args{use_deprecated} : 0;

  $self->debug("creating parser object:");

  $self->{INDENT} += $self->{INDENT_INCR};
  $self->open_xsl(%args);
  $self->{INDENT} -= $self->{INDENT_INCR};

  return $self;
}

sub DESTROY {}			# Cuts out random dies on includes

sub serve {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my %args = $self->__parse_args(@_);
  my $ret;

  $args{http_headers}    = 1 unless defined $args{http_headers};
  $args{xml_declaration} = 1 unless defined $args{xml_declaration};
  $args{xml_version}     = "1.0" unless defined $args{xml_version};
  $args{doctype}         = "SYSTEM" unless defined $args{doctype};
  $args{clean}           = 0 unless defined $args{clean};

  $ret = $self->transform($args{Source})->toString;

  if($args{clean}) {
    eval {require HTML::Clean};

    unless($@) {
      my $hold = HTML::Clean->new(\$ret);
      $hold->strip;
      $ret = ${$hold->data};
    }
  }

  if($args{xml_declaration}) {
    $ret = '<?xml version="' . $args{xml_version} . '" encoding="UTF-8"?>'.
      "\n" . $ret;
  }

  if($args{http_headers}) {
    $ret = "Content-Type: " . $self->media_type . "\n" .
      "Content-Length: " . length($ret) . "\n\n" . $ret;
  }

  return $ret;
}


sub debug {
  my $self = shift;
  my $arg = shift || "";

  print STDERR " "x$self->{INDENT},"$arg\n"
    if $self->{DEBUG};
}

sub warn {
  my $self = shift;
  my $arg = shift || "";

  print STDERR " "x$self->{INDENT},"$arg\n"
    if $self->{DEBUG};
  print STDERR "$arg\n"
    if $self->{WARNINGS} && ! $self->{DEBUG};
}

sub open_xml {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my %args = $self->__parse_args(@_);

  if(defined $self->{XML_DOCUMENT} && not $self->{XML_PASSED_AS_DOM}) {
    $self->debug("flushing old XML::DOM::Document object...");
    $self->{XML_DOCUMENT}->dispose;
  }

  $self->{XML_PASSED_AS_DOM} = 1
    if ref $args{Source} eq 'XML::DOM::Document';

  if (defined $self->{RESULT_DOCUMENT}) {
    $self->debug("flushing result...");
    $self->{RESULT_DOCUMENT}->dispose ();
  }

  $self->debug("opening xml...");

  $args{parser_args} ||= {};
  $self->{XML_DOCUMENT} = $self->__open_document (Source => $args{Source},
						  base   => $self->{XML_BASE},
						  parser_args =>
						  {%{$self->{PARSER_ARGS}},
						   %{$args{parser_args}}},
						 );

  $self->{XML_BASE} =
    dirname(URI->new_abs($args{Source}, $self->{XML_BASE})->as_string) . '/';
  $self->{RESULT_DOCUMENT} = $self->{XML_DOCUMENT}->createDocumentFragment;
}

sub open_xsl {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my %args = $self->__parse_args(@_);

  $self->{XSL_DOCUMENT}->dispose
    if not $self->{XSL_PASSED_AS_DOM} and defined $self->{XSL_DOCUMENT};

  $self->{XSL_PASSED_AS_DOM} = 1
    if ref $args{Source} eq 'XML::DOM::Document';

  # open new document  # open new document
  $self->debug("opening xsl...");

  $args{parser_args} ||= {};
  $self->{XSL_DOCUMENT} = $self->__open_document (Source => $args{Source},
						  base   => $self->{XSL_BASE},
						  parser_args =>
						  {%{$self->{PARSER_ARGS}},
						   %{$args{parser_args}}},
						 );
  $self->{XSL_BASE} =
    dirname(URI->new_abs($args{Source}, $self->{XSL_BASE})->as_string) . '/';

  $self->__preprocess_stylesheet;
}

# Argument parsing with backwards compatibility.
sub __parse_args {
  my $self = shift;
  my %args;

  if(@_ % 2 == 1) {
    $args{Source} = shift;
    %args = (%args, @_);
  } else {
    %args = @_;
    if(not exists $args{Source}) {
      my $name = [caller(1)]->[3];
      carp "Argument syntax of call to $name deprecated.  See the documentation for $name"
	unless $self->{USE_DEPRECATED}
	  or exists $deprecation_used{$name};
      $deprecation_used{$name} = 1;
      %args = ();
      $args{Source} = shift;
      shift;
      %args = (%args, @_);
    }
  }

  return %args;
}

# private auxiliary function #
sub __my_tag_compression {
  my ($tag, $elem) = @_;

=begin internal_docs

__my_tag_compression__( $tag, $elem )

A function for DOM::XML::setTagCompression to determine the style for printing 
of empty tags and empty container tags.

XML::XSLT implements an XHTML-friendly style.

Allow tag to be preceded by a namespace: ([\w\.]+\:){0,1}

  <br> -> <br />

  or

  <myns:hr> -> <myns:hr />

Empty tag list obtained from:

  http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd

According to "Appendix C. HTML Compatibility Guidelines",
  C.3 Element Minimization and Empty Element Content

  Given an empty instance of an element whose content model is not EMPTY
  (for example, an empty title or paragraph) do not use the minimized form
  (e.g. use <p> </p> and not <p />).

However, the <p> tag is processed like an empty tag here!

Tags allowed:

  base meta link hr br param img area input col

Special Case: p (even though it violates C.3)

The tags are matched in order of expected common occurence.

=end internal_docs

=cut

  $tag = [split ':', $tag]->[1] if index($tag, ':') >= 0;
  return 2 if $tag =~ m/^(p|br|img|hr|input|meta|base|link|param|area|col)$/i;

  # Print other empty tags like this: <empty></empty>
  return 1;
}


# private auxiliary function #
sub __preprocess_stylesheet {
  my $self = $_[0];

  $self->debug("preprocessing stylesheet...");

  $self->{TOP_XSL_NODE} = $self->{XSL_DOCUMENT}->getFirstChild;
  $self->__extract_namespaces;
  $self->__get_stylesheet;

  $self->{TOP_XSL_NODE} = $self->{XSL_DOCUMENT}->getFirstChild;
  $self->__expand_xsl_includes;
  $self->__extract_top_level_variables;

  $self->__add_default_templates;
  $self->__cache_templates;	# speed optim

  $self->__set_xsl_output;
}

# private auxiliary function #
sub __get_stylesheet {
  my $self = shift;
  my $stylesheet;
  my $xsl_ns = $self->{XSL_NS};
  my $xsl = $self->{XSL_DOCUMENT};

  foreach my $child ($xsl->getElementsByTagName ('*', 0)) {
    my ($ns, $tag) = split(':', $child->getTagName);
    if(not defined $tag) {
      $tag = $ns;
      $ns  = $self->{DEFAULT_NS};
    }
    if ($tag eq 'stylesheet' ||
	$tag eq 'transform') {
      $stylesheet = $child;
      last;
    }
  }

  if (! $stylesheet) {
    # stylesheet is actually one complete template!
    # put it in a template-element

    $stylesheet = $xsl->createElement ("$ {xsl_ns}stylesheet");
    my $template = $xsl->createElement ("$ {xsl_ns}template");
    $template->setAttribute ('match', "/");

    my $template_content = $xsl->getElementsByTagName ('*', 0)->item (0);
    $xsl->replaceChild ($stylesheet, $template_content);
    $stylesheet->appendChild ($template);
    $template->appendChild ($template_content);
  }

  $self->{XSL_DOCUMENT} = $stylesheet;
}

# private auxiliary function #
sub __extract_namespaces {
  my ($self) = @_;

  foreach my $attribute ($self->{TOP_XSL_NODE}->getAttributes->getValues) {
    my ($pre, $post) = split(":", $attribute->getName, 2);
    my $value = $attribute->getValue;

    # Take care of namespaces
    if($pre eq 'xmlns' and not defined $post) {  
      $self->{DEFAULT_NS} = '';

      $self->{NAMESPACE}->{$self->{DEFAULT_NS}}->{namespace} = $value;
      $self->{XSL_NS} = ''
	if $value eq NS_XSLT;
      $self->debug("Namespace `" . $self->{DEFAULT_NS} . "' = `$value'");
    } elsif($pre eq 'xmlns') {
      $self->{NAMESPACE}->{$post}->{namespace} = $value;
      $self->{XSL_NS} = $post . ':'
	if $value eq NS_XSLT;
      $self->debug("Namespace `$post:' = `$value'");
    }

    # Take care of versions
    if ($pre eq "version" and not defined $post) {
      $self->{NAMESPACE}->{$self->{DEFAULT_NS}}->{version} = $value;
      $self->debug("Version for namespace `" . $self->{DEFAULT_NS} .
		   "' = `$value'");
    } elsif ($pre eq "version") {
      $self->{NAMESPACE}->{$post}->{version} = $value;
      $self->debug("Version for namespace `$post:' = `$value'");
    }
  }
  if(not defined $self->{DEFAULT_NS}) {
    ($self->{DEFAULT_NS}) = split(':', $self->{TOP_XSL_NODE}->getTagName);
  }
  $self->debug("Default Namespace: `" . $self->{DEFAULT_NS} . "'");
  $self->{XSL_NS} ||= $self->{DEFAULT_NS};

  $self->debug("XSL Namespace: `" .$self->{XSL_NS} ."'");
  # ** FIXME: is this right?
  $self->{NAMESPACE}->{$self->{DEFAULT_NS}}->{namespace} ||= NS_XHTML;
}

# private auxiliary function #
sub __expand_xsl_includes {
  my $self = shift;

  foreach my $include_node
    ($self->{TOP_XSL_NODE}->getElementsByTagName($self->{XSL_NS} . "include"))
      {
    my $include_file = $include_node->getAttribute('href');

    die "include tag carries no selection!"
      unless defined $include_file;

    my $include_doc;
    eval {
      my $tmp_doc =
	$self->__open_by_filename($include_file, $self->{XSL_BASE});
      $include_doc = $tmp_doc->getFirstChild->cloneNode(1);
      $tmp_doc->dispose;
    };
    die "parsing of $include_file failed: $@"
      if $@;

    $self->debug("inserting `$include_file'");
    $include_doc->setOwnerDocument($self->{XSL_DOCUMENT});
    $self->{TOP_XSL_NODE}->replaceChild($include_doc, $include_node);
    $include_doc->dispose;
  }
}

# private auxiliary function #
sub __extract_top_level_variables {
  my $self = $_[0];

  $self->debug("Extracting variables");
  foreach my $child ($self->{TOP_XSL_NODE}->getElementsByTagName ('*',0)) {
    my ($ns, $tag) = split(':', $child);

    if(($tag eq '' && $self->{XSL_NS} eq '') ||
       $self->{XSL_NS} eq $ns) {
      $tag = $ns if $tag eq '';

      if ($tag eq 'variable' || $tag eq 'param') {

	my $name = $child->getAttribute("name");
	if ($name) {
	  my $value = $child->getAttribute("select");
	  if (!$value) {
	    my $result = $self->{XML_DOCUMENT}->createDocumentFragment;
	    $self->_evaluate_template ($child, $self->{XML_DOCUMENT}, '', $result);
	    $value = $self->_string ($result);
	    $result->dispose();
	  }
	  $self->debug("Setting $tag `$name' = `$value'");
	  $self->{VARIABLES}->{$name} = $value;
	} else {
	  # Required, so we die (http://www.w3.org/TR/xslt#variables)
	  die "$tag tag carries no name!";
	}
      }
    }
  }
}

# private auxiliary function #
sub __add_default_templates {
  my $self = $_[0];
  my $doc  = $self->{TOP_XSL_NODE}->getOwnerDocument;

  # create template for '*' and '/'
  my $elem_template =
    $doc->createElement
      ($self->{XSL_NS} . "template");
  $elem_template->setAttribute('match','*|/');

  # <xsl:apply-templates />
  $elem_template->appendChild
    ($doc->createElement
     ($self->{XSL_NS} . "apply-templates"));

  # create template for 'text()' and '@*'
  my $attr_template =
    $doc->createElement
      ($self->{XSL_NS} . "template");
  $attr_template->setAttribute('match','text()|@*');

  # <xsl:value-of select="." />
  $attr_template->appendChild
    ($doc->createElement
     ($self->{XSL_NS} . "value-of"));
  $attr_template->getFirstChild->setAttribute('select','.');

  # create template for 'processing-instruction()' and 'comment()'
  my $pi_template =
    $doc->createElement($self->{XSL_NS} . "template");
  $pi_template->setAttribute('match','processing-instruction()|comment()');

  $self->debug("adding default templates to stylesheet");
  # add them to the stylesheet
  $self->{XSL_DOCUMENT}->insertBefore($pi_template,
				 $self->{TOP_XSL_NODE});
  $self->{XSL_DOCUMENT}->insertBefore($attr_template,
				 $self->{TOP_XSL_NODE});
  $self->{XSL_DOCUMENT}->insertBefore($elem_template,
				 $self->{TOP_XSL_NODE});
}

# private auxiliary function #
sub __cache_templates {
  my $self = $_[0];

  $self->{TEMPLATE} = [$self->{XSL_DOCUMENT}->getElementsByTagName ("$self->{XSL_NS}template")];

  # pre-cache template names and matches #
  # reversing the template order is much more efficient #
  foreach my $template (reverse @{$self->{TEMPLATE}}) {
    if ($template->getParentNode->getTagName =~
	/^([\w\.\-]+\:){0,1}(stylesheet|transform|include)/) {
      my $match = $template->getAttribute ('match');
      my $name = $template->getAttribute ('name');
      if ($match && $name) {
	$self->warn(qq{defining a template with both a "name" and a "match" attribute is not allowed!});
	push (@{$self->{TEMPLATE_MATCH}}, "");
	push (@{$self->{TEMPLATE_NAME}}, "");
      } elsif ($match) {
	push (@{$self->{TEMPLATE_MATCH}}, $match);
	push (@{$self->{TEMPLATE_NAME}}, "");
      } elsif ($name) {
	push (@{$self->{TEMPLATE_MATCH}}, "");
	push (@{$self->{TEMPLATE_NAME}}, $name);
      } else {
	push (@{$self->{TEMPLATE_MATCH}}, "");
	push (@{$self->{TEMPLATE_NAME}}, "");
      }
    }
  }
}

# private auxiliary function #
sub __set_xsl_output {
  my $self = $_[0];

  # default settings
  $self->{METHOD} = 'xml';
  $self->{MEDIA_TYPE} = 'text/xml';
  $self->{OMIT_XML_DECL} = 'yes';

  # extraction of top-level xsl:output tag
  my ($output) = 
    $self->{XSL_DOCUMENT}->getElementsByTagName($self->{XSL_NS} . "output",0);

  if (defined $output) {
    # extraction and processing of the attributes
    my $attribs = $output->getAttributes;
    my $media  = $attribs->getNamedItem('media-type');
    my $method = $attribs->getNamedItem('method');
    $self->{MEDIA_TYPE} = $media->getNodeValue if defined $media;
    $self->{METHOD} = $method->getNodeValue if defined $method;

    if ($self->{METHOD} eq 'xml') {
      my $omit = $attribs->getNamedItem('omit-xml-declaration');
      $self->{OMIT_XML_DECL} = defined $omit->getNodeValue ?
	$omit->getNodeValue : 'no';

      if ($self->{OMIT_XML_DECL} ne 'yes' && $self->{OMIT_XML_DECL} ne 'no') {
	$self->warn(qq{Wrong value for attribute "omit-xml-declaration" in\n\t} .
		    $self->{XSL_NS} . qq{output, should be "yes" or "no"});
      }

      if (! $self->{OMIT_XML_DECL}) {
	my $output_ver = $attribs->getNamedItem('version')->getNodeValue;
	my $output_enc = $attribs->getNamedItem('encoding')->getNodeValue;
	$self->{OUTPUT_VERSION} = $output_ver->getNodeValue
	  if defined $output_ver;
	$self->{OUTPUT_ENCODING} = $output_enc->getNodeValue
	  if defined $output_enc;

	if (not $self->{OUTPUT_VERSION} || not $self->{OUTPUT_ENCODING}) {
	  $self->warn(qq{Expected attributes "version" and "encoding" in\n\t} .
	    $self->{XSL_NS} . "output");
	}
      }
    }
    my $doctype_public = $attribs->getNamedItem('doctype-public');
    my $doctype_system = $attribs->getNamedItem('doctype-system');
    $self->{DOCTYPE_PUBLIC} = defined $doctype_public ?
      $doctype_public->getNodeValue : '';
    $self->{DOCTYPE_SYSTEM} = defined $doctype_system ?
      $doctype_system->getNodeValue : '';
  } else {
    $self->debug("Default Output options being used");
  }
}

sub open_project {
  my $self = shift;
  my $xml  = shift;
  my $xsl  = shift;
  my ($xmlflag, $xslflag, %args) = @_;

  carp "open_project is deprecated."
    unless $self->{USE_DEPRECATED}
      or exists $deprecation_used{open_project};
  $deprecation_used{open_project} = 1;

  $self->debug("opening project:");
  $self->{INDENT} += $self->{INDENT_INCR};

  $self->open_xml ($xml, %args);
  $self->open_xsl ($xsl, %args);

  $self->debug("done...");
  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub transform {
  my $self = shift;
  my %topvariables = $self->__parse_args(@_);

  $self->debug("transforming document:");
  $self->{INDENT} += $self->{INDENT_INCR};

  $self->open_xml (%topvariables);

  $self->debug("done...");
  $self->{INDENT} -= $self->{INDENT_INCR};

  $self->debug("processing project:");
  $self->{INDENT} += $self->{INDENT_INCR};

  my $root_template = $self->_match_template("match", '/', 1, '');
  croak "Can't find root template"
    unless defined $root_template;



  %topvariables = (%{$self->{VARIABLES}}, %topvariables);
  $self->_evaluate_template ( $root_template,            # starting template: the root template
			      $self->{XML_DOCUMENT},     # current XML node: the root
			      '',                        # current XML selection path: the root
			      $self->{RESULT_DOCUMENT},  # current result tree node: the root
			      {()},                      # current known variables: none
			      \%topvariables             # previously known variables: top level variables
			      );

  $self->debug("done!");
  $self->{INDENT} -= $self->{INDENT_INCR};
  $self->{RESULT_DOCUMENT};
}

sub process {
  my ($self, %topvariables) = @_;

  $self->debug("processing project:");
  $self->{INDENT} += $self->{INDENT_INCR};

  my $root_template = $self->_match_template ("match", '/', 1, '');

  %topvariables = (%{$self->{VARIABLES}}, %topvariables);

  $self->_evaluate_template (
			       $root_template, # starting template: the root template
			       $self->{XML_DOCUMENT}, # current XML node: the root
			       '', # current XML selection path: the root
			       $self->{RESULT_DOCUMENT}, # current result tree node: the root
			       {
				()}, # current known variables: none
			       \%topvariables # previously known variables: top level variables
			      );

  $self->debug("done!");
  $self->{INDENT} -= $self->{INDENT_INCR};
}

# Handles deprecations.
sub AUTOLOAD {
  my $self = shift;
  my $type = ref($self) || croak "Not a method call";
  my $name = $AUTOLOAD;
  $name =~ s/.*://;

  my %deprecation = ('output_string'      => 'asString',
		     'result_string'      => 'asString',
		     'output'             => 'asString',
		     'result'             => 'asString',
		     'result_mime_type'   => 'media_type',
		     'output_mime_type'   => 'media_type',
		     'result_tree'        => 'to_dom',
		     'output_tree'        => 'to_dom',
		     'transform_document' => 'transform',
		     'process_project'    => 'process'
		    );

  if (exists $deprecation{$name}) {
    carp "$name is deprecated.  Use $deprecation{$name}"
      unless $self->{USE_DEPRECATED}
	or exists $deprecation_used{$name};
    $deprecation_used{$name} = 1;
    eval qq{return \$self->$deprecation{$name}(\@_)};
  } else {
    croak "$name: No such method name";
  }
}

sub _my_print_text {
  my ($self, $FILE) = @_;

  # This should work with either XML::DOM 1.25 or XML::DOM 1.27
  if (UNIVERSAL::isa($self, "XML::DOM::CDATASection")) {
    $FILE->print ($self->getData);
  } else {
    $FILE->print (XML::DOM::encodeText($self->getData, "<&"));
  }
}

sub toString {
  my $self = $_[0];

  local *XML::DOM::Text::print = \&_my_print_text;

  my $string = $self->{RESULT_DOCUMENT}->toString;
  #  $string =~ s/\n\s*\n(\s*)\n/\n$1\n/g;  # Substitute multiple empty lines by one
  #  $string =~ s/\/\>/ \/\>/g;            # Insert a space before every />

  # get rid of CDATA wrappers
  #  if (! $self->{printCDATA}) {
  #    $string =~ s/\<\!\[CDATA\[//g;
  #    $string =~ s/\]\]>//g;
  #  }

  return $string;
}

sub to_dom {
  my $self = shift;

  return $self->{RESULT_DOCUMENT};
}

sub media_type {
  return ($_[0]->{MEDIA_TYPE});
}

sub print_output {
  my ($self, $file, $mime) = @_;
  $file ||= '';			# print to STDOUT by default
  $mime = 1 unless defined $mime;

  # print mime-type header etc by default

  #  $self->{RESULT_DOCUMENT}->printToFileHandle (\*STDOUT);
  #  or $self->{RESULT_DOCUMENT}->print (\*STDOUT); ???
  #  exit;

  carp "print_output is deprecated.  Use serve."
    unless $self->{USE_DEPRECATED}
      or exists $deprecation_used{print_output};
  $deprecation_used{print_output} = 1;

  if ($mime) {
    print "Content-type: $self->{MEDIA_TYPE}\n\n";

    if ($self->{METHOD} eq 'xml') {
      if (($self->{OMIT_XML_DECL} eq 'no') && $self->{OUTPUT_VERSION}
	  && $self->{OUTPUT_ENCODING}) {
	print "<?xml version=\"$self->{OUTPUT_VERSION}\" encoding=\"$self->{OUTPUT_ENCODING}\"?>\n";
      }
    }
    if ($self->{DOCTYPE_SYSTEM}) {
      my $root_name = $self->{RESULT_DOCUMENT}->getElementsByTagName('*',0)->item(0)->getTagName;
      if ($self->{DOCTYPE_PUBLIC}) {
	print qq{<!DOCTYPE $root_name PUBLIC "} . $self->{DOCTYPE_PUBLIC} .
	  qq{" "} . $self->{DOCTYPE_SYSTEM} . qq{">\n};
      } else {
	print qq{<!DOCTYPE $root_name SYSTEM "} . $self->{DOCTYPE_SYSTEM} . qq{">\n};
      }
    }
  }

  if ($file) {
    if (ref (\$file) eq 'SCALAR') {
      print $file $self->output_string,"\n"
    } else {
      if (open (FILE, ">$file")) {
	print FILE $self->output_string,"\n";
	if (! close (FILE)) {
	  die ("Error writing $file: $!. Nothing written...\n");
	}
      } else {
	die ("Error opening $file: $!. Nothing done...\n");
      }
    }
  } else {
    print $self->output_string,"\n";
  }
}
*print_result = *print_output;

sub dispose {
  #my $self = $_[0];

  #$_[0]->[PARSER] = undef if (defined $_[0]->[PARSER]);
  $_[0]->{RESULT_DOCUMENT}->dispose if (defined $_[0]->{RESULT_DOCUMENT});

  # only dispose xml and xsl when they were not passed as DOM
  if (not defined $_[0]->{XML_PASSED_AS_DOM} && defined $_-[0]->{XML_DOCUMENT}) {
    $_[0]->{XML_DOCUMENT}->dispose;
  }
  if (not defined $_[0]->{XSL_PASSED_AS_DOM} && defined $_-[0]->{XSL_DOCUMENT}) {
    $_[0]->{XSL_DOCUMENT}->dispose;
  }

  $_[0] = undef;
}


######################################################################
# PRIVATE DEFINITIONS

sub __open_document {
  my $self = shift;
  my %args = @_;
  %args = (%{$self->{PARSER_ARGS}}, %args);
  my $doc;

  $self->debug("opening document");

  eval {
    if(length $args{Source} < 255 &&
       (-f $args{Source} ||
	lc(substr($args{Source}, 0, 5)) eq 'http:' ||
	lc(substr($args{Source}, 0, 6)) eq 'https:' ||
	lc(substr($args{Source}, 0, 4)) eq 'ftp:' ||
	lc(substr($args{Source}, 0, 5)) eq 'file:')) { 
				# Filename
      $self->debug("Opening URL");
      $doc = $self->__open_by_filename($args{Source}, $args{base});
    } elsif(!ref $args{Source}) {
				# String
      $self->debug("Opening String");
      $doc = $self->{PARSER}->parse ($args{Source});
    } elsif(ref $args{Source} eq "SCALAR") {
				# Stringref
      $self->debug("Opening Stringref");
      $doc = $self->{PARSER}->parse (${$args{Source}});
    } elsif(ref $args{Source} eq "XML::DOM::Document") {
				# DOM object
      $self->debug("Opening XML::DOM");
      $doc = $args{Source};
    } else {
      $doc = undef;
    }
  };
  die "Error in parsing: $@" if $@;

  return $doc;
}

# private auxiliary function #
sub __open_by_filename {
  my ($self, $filename, $base) = @_;
  my $doc;

  # ** FIXME: currently reads the whole document into memory
  #           might not be avoidable

  # LWP should be able to deal with files as well as links
  $ENV{DOMAIN} ||= "example.com"; # hide complaints from Net::Domain

  my $file = get(URI->new_abs($filename, $base));

  return $self->{PARSER}->parse($file, %{$self->{PARSER_ARGS}});
}

sub _match_template {
  my ($self, $attribute_name, $select_value, $xml_count, $xml_selection_path,
      $mode) = @_;
  $mode ||= "";

  my $template = "";
  my @template_matches = ();

  $self->debug(qq{matching template for "$select_value" with count $xml_count\n\t} .
    qq{and path "$xml_selection_path":});

  if ($attribute_name eq "match" && ref $self->{TEMPLATE_MATCH}) {
    push @template_matches, @{$self->{TEMPLATE_MATCH}};
  } elsif ($attribute_name eq "name" && ref $self->{TEMPLATE_NAME}) {
    push @template_matches, @{$self->{TEMPLATE_NAME}};
  }

  # note that the order of @template_matches is the reverse of $self->{TEMPLATE}
  my $count = @template_matches;
  foreach my $original_match (@template_matches) {
    # templates with no match or name or with both simultaniuously
    # have no $template_match value
    if ($original_match) {
      my $full_match = $original_match;

      # multipe match? (for example: match="*|/")
      while ($full_match =~ s/^(.+?)\|//) {
	my $match = $1;
	if (&__template_matches__ ($match, $select_value, $xml_count,
				   $xml_selection_path)) {
	  $self->debug(qq{  found #$count with "$match" in "$original_match"});
	  $template = ${$self->{TEMPLATE}}[$count-1];
	  return $template;
	  #	  last;
	}
      }

      # last match?
      if (!$template) {
	if (&__template_matches__ ($full_match, $select_value, $xml_count,
				   $xml_selection_path)) {
	  $self->debug(qq{  found #$count with "$full_match" in "$original_match"});
	  $template = ${$self->{TEMPLATE}}[$count-1];
	  return $template;
	  #          last;
	} else {
	  $self->debug(qq{  #$count "$original_match" did not match});
	}
      }
    }
    $count--;
  }

  if (! $template) {
    $self->warn(qq{No template matching `$xml_selection_path' found !!});
  }

  return $template;
}

# auxiliary function #
sub __template_matches__ {
  my ($template, $select, $count, $path) = @_;
    
  my $nocount_path = $path;
  $nocount_path =~ s/\[.*?\]//g;

  if (($template eq $select) || ($template eq $path)
      || ($template eq "$select\[$count\]") || ($template eq "$path\[$count\]")) {
    # perfect match or path ends with templates match
    #print "perfect match","\n";
    return "True";
  } elsif ( ($template eq substr ($path, - length ($template)))
	    || ($template eq substr ($nocount_path, - length ($template)))
	    || ("$template\[$count\]" eq substr ($path, - length ($template)))
	    || ("$template\[$count\]" eq substr ($nocount_path, - length ($template)))
	  ) {
    # template matches tail of path matches perfectly
    #print "perfect tail match","\n";
    return "True";
  } elsif ($select =~ /\[\s*(\@.*?)\s*=\s*(.*?)\s*\]$/) {
    # match attribute test
    my $attribute = $1;
    my $value = $2;
    return "";			# False, no test evaluation yet #
  } elsif ($select =~ /\[\s*(.*?)\s*=\s*(.*?)\s*\]$/) {
    # match test
    my $element = $1;
    my $value = $2;
    return "";			# False, no test evaluation yet #
  } elsif ($select =~ /(\@\*|\@[\w\.\-\:]+)$/) {
    # match attribute
    my $attribute = $1;
    #print "attribute match?\n";
    return (($template eq '@*') || ($template eq $attribute)
	    || ($template eq "\@*\[$count\]") || ($template eq "$attribute\[$count\]"));
  } elsif ($select =~ /(\*|[\w\.\-\:]+)$/) {
    # match element
    my $element = $1;
    #print "element match?\n";
    return (($template eq "*") || ($template eq $element)
	    || ($template eq "*\[$count\]") || ($template eq "$element\[$count\]"));
  } else {
    return "";			# False #
  }
}

sub _evaluate_test {
  my ($self, $test, $current_xml_node, $current_xml_selection_path,
      $variables) = @_;

  if ($test =~ /^(.+)\/\[(.+)\]$/) {
    my $path = $1;
    $test = $2;
    
    $self->debug("evaluating test $test at path $path:");;

    $self->{INDENT} += $self->{INDENT_INCR};
    my $node = $self->_get_node_set ($path, $self->{XML_DOCUMENT},
				     $current_xml_selection_path,
				     $current_xml_node, $variables);
    if (@$node) {
      $current_xml_node = $$node[0];
    } else {
      return "";
    }
    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $self->debug("evaluating path or test $test:");;
    my $node = $self->_get_node_set ($test, $self->{XML_DOCUMENT},
				     $current_xml_selection_path,
				     $current_xml_node, $variables, "silent");
    $self->{INDENT} += $self->{INDENT_INCR};
    if (@$node) {
      $self->debug("path exists!");;
      return "true";
    } else {
      $self->debug("not a valid path, evaluating as test");;
    }
    $self->{INDENT} -= $self->{INDENT_INCR}
  }

  $self->{INDENT} += $self->{INDENT_INCR};
  my $result = &__evaluate_test__ ($self,$test, $current_xml_selection_path,$current_xml_node,$variables);
  if ($result) {
    $self->debug("test evaluates true..");
  } else {
    $self->debug("test evaluates false..");
  }
  $self->{INDENT} -= $self->{INDENT_INCR};
  return $result;
}

sub _evaluate_template {
  my ($self, $template, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  $self->debug(qq{evaluating template content with current path }
	       . qq{"$current_xml_selection_path": });
  $self->{INDENT} += $self->{INDENT_INCR};

  die "No Template"
    unless defined $template && ref $template;
  $template->normalize;
  foreach my $child ($template->getChildNodes) {
    my $ref = ref $child;

    $self->debug("$ref");
    $self->{INDENT} += $self->{INDENT_INCR};
    my $node_type = $child->getNodeType;
    if ($node_type == ELEMENT_NODE) {
      $self->_evaluate_element ($child, $current_xml_node,
				$current_xml_selection_path,
				$current_result_node, $variables,
				$oldvariables);
    } elsif ($node_type == TEXT_NODE) {
      # strip whitespace here?
      $self->_add_node ($child, $current_result_node);
    } elsif ($node_type == CDATA_SECTION_NODE) {
      my $text = $self->{XML_DOCUMENT}->createTextNode ($child->getData);
      $self->_add_node($text, $current_result_node);
    } elsif ($node_type == ENTITY_REFERENCE_NODE) {
      $self->_add_node($child, $current_result_node);
    } elsif ($node_type == DOCUMENT_TYPE_NODE) {
      # skip #
      $self->debug("Skipping Document Type node...");
    } elsif ($node_type == COMMENT_NODE) {
      # skip #
      $self->debug("Skipping Comment node...");
    } else {
      $self->warn("evaluate-template: Dunno what to do with node of type $ref !!!\n\t" .
		  "($current_xml_selection_path)");
    }

    $self->{INDENT} -= $self->{INDENT_INCR};
  }

  $self->debug("done!");
  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _add_node {
  my ($self, $node, $parent, $deep, $owner) = @_;
  $owner ||= $self->{XML_DOCUMENT};

  $self->debug("adding node (deep)..") if defined $deep;
  $self->debug("adding node (non-deep)..") unless defined $deep;

  $node = $node->cloneNode($deep);
  $node->setOwnerDocument($owner);
  if ($node->getNodeType == ATTRIBUTE_NODE) {
    $parent->setAttributeNode($node);
  } else {
    $parent->appendChild($node);
  }
}

sub _apply_templates {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  my $children;
  my $params={};
  my $newvariables={%$variables};

  my $select = $xsl_node->getAttribute ('select');

  if ($select =~ /\$/) {
    # replacing occurences of variables:
    foreach my $varname (keys (%$variables)) {
      $select =~ s/[^\\]\$$varname/$$variables{$varname}/g;
    }
  }

  if ($select) {
    $self->debug(qq{applying templates on children $select of "$current_xml_selection_path":});
    $children = $self->_get_node_set ($select, $self->{XML_DOCUMENT},
					$current_xml_selection_path,
					$current_xml_node, $variables);
  } else {
    $self->debug(qq{applying templates on all children of "$current_xml_selection_path":});
    my @children = $current_xml_node->getChildNodes;
    $children = \@children;
  }

  $self->_process_with_params ($xsl_node, $current_xml_node,
				 $current_xml_selection_path,
				 $variables, $params);

  # process xsl:sort here

  $self->{INDENT} += $self->{INDENT_INCR};

  my $count = 1;
  foreach my $child (@$children) {
    my $node_type = $child->getNodeType;
    
    if ($node_type == DOCUMENT_TYPE_NODE) {
      # skip #
      $self->debug("Skipping Document Type node...");
    } elsif ($node_type == DOCUMENT_FRAGMENT_NODE) {
      # skip #
      $self->debug("Skipping Document Fragment node...");
    } elsif ($node_type == NOTATION_NODE) {
      # skip #
      $self->debug("Skipping Notation node...");
    } else {

      my $newselect = "";
      my $newcount = $count;
      if (!$select || ($select eq '.')) {
	if ($node_type == ELEMENT_NODE) {
	  $newselect = $child->getTagName;
	} elsif ($node_type == ATTRIBUTE_NODE) {
	  $newselect = "@$child->getName";
	} elsif (($node_type == TEXT_NODE) || ($node_type == ENTITY_REFERENCE_NODE)) {
	  $newselect = "text()";
	} elsif ($node_type == PROCESSING_INSTRUCTION_NODE) {
	  $newselect = "processing-instruction()";
	} elsif ($node_type == COMMENT_NODE) {
	  $newselect = "comment()";
	} else {
	  my $ref = ref $child;
	  $self->debug("Unknown node encountered: `$ref'");
	}
      } else {
	$newselect = $select;
	if ($newselect =~ s/\[(\d+)\]$//) {
	  $newcount = $1;
	}
      }

      $self->_select_template ($child, $newselect, $newcount,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $current_result_node, $newvariables, $params);
    }
    $count++;
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _for_each {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $select = $xsl_node->getAttribute ('select') || die "No `select' attribute in for-each element";

  if ($select =~ /\$/) {
    # replacing occurences of variables:
    foreach my $varname (keys (%$variables)) {
      $select =~ s/[^\\]\$$varname/$$variables{$varname}/g;
    }
  }

  if (defined $select) {
    $self->debug("applying template for each child $select of \"$current_xml_selection_path\":");
    my $children = $self->_get_node_set ($select, $self->{XML_DOCUMENT},
					   $current_xml_selection_path,
					   $current_xml_node, $variables);
    $self->{INDENT} += $self->{INDENT_INCR};
    my $count = 1;
    foreach my $child (@$children) {
      my $node_type = $child->getNodeType;

      if ($node_type == DOCUMENT_TYPE_NODE) {
	# skip #
	$self->debug("Skipping Document Type node...");;
      } elsif ($node_type == DOCUMENT_FRAGMENT_NODE) {
	# skip #
	$self->debug("Skipping Document Fragment node...");;
      } elsif ($node_type == NOTATION_NODE) {
	# skip #
	$self->debug("Skipping Notation node...");;
      } else {

	$self->_evaluate_template ($xsl_node, $child,
				   "$current_xml_selection_path/$select\[$count\]",
				     $current_result_node, $variables, $oldvariables);
      }
      $count++;
    }

    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $self->warn("expected attribute \"select\" in <$self->{XSL_NS}for-each>");
  }

}

sub _select_template {
  my ($self, $child, $select, $count, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $ref = ref $child;
  $self->debug(qq{selecting template $select for child type $ref of "$current_xml_selection_path":});

  $self->{INDENT} += $self->{INDENT_INCR};

  my $child_xml_selection_path = "$current_xml_selection_path/$select";
  my $template = $self->_match_template ("match", $select, $count,
					   $child_xml_selection_path);

  if ($template) {

    $self->_evaluate_template ($template,
				 $child,
				 "$child_xml_selection_path\[$count\]",
				 $current_result_node, $variables, $oldvariables);
  } else {
    $self->debug("skipping template selection...");;
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _evaluate_element {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my ($ns, $xsl_tag) = split(':', $xsl_node->getTagName);
  if(not defined $xsl_tag) {
    $xsl_tag = $ns;
    $ns = $self->{DEFAULT_NS};
  } else {
    $ns .= ':';
  }
  $self->debug(qq{evaluating element `$xsl_tag' from `$current_xml_selection_path': });
  $self->{INDENT} += $self->{INDENT_INCR};

  if ($ns eq $self->{XSL_NS}) {
    $self->debug(qq{This is an xsl tag});
    if ($xsl_tag eq 'apply-templates') {
      $self->_apply_templates ($xsl_node, $current_xml_node,
				 $current_xml_selection_path,
				 $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'attribute') {
      $self->_attribute ($xsl_node, $current_xml_node,
			   $current_xml_selection_path,
			   $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'call-template') {
      $self->_call_template ($xsl_node, $current_xml_node,
			       $current_xml_selection_path,
			       $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'choose') {
      $self->_choose ($xsl_node, $current_xml_node,
			$current_xml_selection_path,
			$current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'comment') {
      $self->_comment ($xsl_node, $current_xml_node,
			 $current_xml_selection_path,
			 $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'copy') {
      $self->_copy ($xsl_node, $current_xml_node,
		      $current_xml_selection_path,
		      $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'copy-of') {
      $self->_copy_of ($xsl_node, $current_xml_node,
			 $current_xml_selection_path,
			 $current_result_node, $variables);
    } elsif ($xsl_tag eq 'element') {
      $self->_element ($xsl_node, $current_xml_node,
			 $current_xml_selection_path,
			 $current_result_node, $variables, $oldvariables);
    } elsif ($xsl_tag eq 'for-each') {
      $self->_for_each ($xsl_node, $current_xml_node,
			  $current_xml_selection_path,
			  $current_result_node, $variables, $oldvariables);

    } elsif ($xsl_tag eq 'if') {
      $self->_if ($xsl_node, $current_xml_node,
		    $current_xml_selection_path,
		    $current_result_node, $variables, $oldvariables);

      #      } elsif ($xsl_tag eq 'output') {

    } elsif ($xsl_tag eq 'param') {
      $self->_variable ($xsl_node, $current_xml_node,
			  $current_xml_selection_path,
			  $current_result_node, $variables, $oldvariables, 1);

    } elsif ($xsl_tag eq 'processing-instruction') {
      $self->_processing_instruction ($xsl_node, $current_result_node);

    } elsif ($xsl_tag eq 'text') {
      $self->_text ($xsl_node, $current_result_node);

    } elsif ($xsl_tag eq 'value-of') {
      $self->_value_of ($xsl_node, $current_xml_node,
			  $current_xml_selection_path,
			  $current_result_node, $variables);

    } elsif ($xsl_tag eq 'variable') {
      $self->_variable ($xsl_node, $current_xml_node,
			  $current_xml_selection_path,
			  $current_result_node, $variables, $oldvariables, 0);

    } else {
      $self->_add_and_recurse ($xsl_node, $current_xml_node,
				 $current_xml_selection_path,
				 $current_result_node, $variables, $oldvariables);
    }
  } else {
    $self->debug($ns ." does not match ". $self->{XSL_NS});
    $self->_check_attributes_and_recurse ($xsl_node, $current_xml_node,
					    $current_xml_selection_path,
					    $current_result_node, $variables, $oldvariables);
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _add_and_recurse {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  # the addition is commented out to prevent unknown xsl: commands to be printed in the result
  $self->_add_node ($xsl_node, $current_result_node);
  $self->_evaluate_template ($xsl_node, $current_xml_node,
			       $current_xml_selection_path,
			       $current_result_node, $variables, $oldvariables); #->getLastChild);
}

sub _check_attributes_and_recurse {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  $self->_add_node ($xsl_node, $current_result_node);
  $self->_attribute_value_of ($current_result_node->getLastChild,
				$current_xml_node,
				$current_xml_selection_path, $variables);
  $self->_evaluate_template ($xsl_node, $current_xml_node,
			       $current_xml_selection_path,
			       $current_result_node->getLastChild, $variables, $oldvariables);
}

sub _element {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  
  my $name = $xsl_node->getAttribute ('name');
  $self->debug("inserting Element named \"$name\":");
  $self->{INDENT} += $self->{INDENT_INCR};

  if (defined $name) {
    my $result = $self->{XML_DOCUMENT}->createElement($name);

    $self->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result, $variables, $oldvariables);


    $current_result_node->appendChild($result);
  } else {
    $self->warn(q{expected attribute "name" in <} .
		$self->{XSL_NS} . q{element>});
  }
  $self->{INDENT} -= $self->{INDENT_INCR};
}

{
  ######################################################################
  # Auxiliary package for disable-output-escaping
  ######################################################################

  package XML::XSLT::DOM::TextDOE;
  use vars qw( @ISA );
  @ISA = qw( XML::DOM::Text );

  sub print {
    my ($self, $FILE) = @_;
    $FILE->print ($self->getData);
  }
}


sub _value_of {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables) = @_;

  my $select = $xsl_node->getAttribute('select');
  my $xml_node;

  if (defined $select) {
    $xml_node = $self->_get_node_set ($select, $self->{XML_DOCUMENT},
					$current_xml_selection_path,
					$current_xml_node, $variables);

    $self->debug("stripping node to text:");

    $self->{INDENT} += $self->{INDENT_INCR};
    my $text = '';
    $text = $self->__string__ ($$xml_node[0]) if @$xml_node;
    $self->{INDENT} -= $self->{INDENT_INCR};

    if ($text ne '') {
      my $node = $self->{XML_DOCUMENT}->createTextNode ($text);
      if ($xsl_node->getAttribute ('disable-output-escaping') eq 'yes')
        {
        $self->debug("disabling output escaping");
        bless $node,'XML::XSLT::DOM::TextDOE' ;
      }
      $self->_move_node ($node, $current_result_node); 
    } else {
      $self->debug("nothing left..");
    }
  } else {
    $self->warn(qq{expected attribute "select" in <} .
		$self->{XSL_NS} . q{value-of>});
  }
}

sub __strip_node_to_text__ {
  my ($self, $node) = @_;
    
  my $result = "";

  my $node_type = $node->getNodeType;
  if ($node_type == TEXT_NODE) {
    $result = $node->getData;
  } elsif (($node_type == ELEMENT_NODE)
	   || ($node_type == DOCUMENT_FRAGMENT_NODE)) {
    $self->{INDENT} += $self->{INDENT_INCR};
    foreach my $child ($node->getChildNodes) {
      $result .= &__strip_node_to_text__ ($self, $child);
    }
    $self->{INDENT} -= $self->{INDENT_INCR};
  }
  return $result;
}

sub __string__ {
  my ($self, $node,$depth) = @_;

  my $result = "";

  if (defined $node) {
    my $ref = (ref ($node) || "not a reference");
    $self->debug("stripping child nodes ($ref):");

    $self->{INDENT} += $self->{INDENT_INCR};

    if ($ref eq "ARRAY") {
      return $self->__string__ ($$node[0], $depth);
    } else {
      my $node_type = $node->getNodeType;

      if (($node_type == ELEMENT_NODE)
	  || ($node_type == DOCUMENT_FRAGMENT_NODE)
	  || ($node_type == DOCUMENT_NODE)) {
	foreach my $child ($node->getChildNodes) {
	  $result .= &__string__ ($self, $child,1);
	}
      } elsif ($node_type == ATTRIBUTE_NODE) {
	$result .= $node->getValue;
      } elsif (($node_type == TEXT_NODE)
	       || ($node_type == CDATA_SECTION_NODE)
	       || ($node_type == ENTITY_REFERENCE_NODE)) {
	$result .= $node->getData;
      } elsif (!$depth && (  ($node_type == PROCESSING_INSTRUCTION_NODE)
			     || ($node_type == COMMENT_NODE) )) {
	$result .= $node->getData; # COM,PI - only in 'top-level' call
      } else {
	# just to be consistent
	$self->warn("Can't get string-value for node of type $ref !");
      }
    }

    $self->debug("  \"$result\"");
    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $self->debug(" no result");
  }

  return $result;
}

sub _move_node {
  my ($self, $node, $parent) = @_;

  $self->debug("moving node..");;

  $parent->appendChild($node);
}

sub _get_node_set {
  my ($self, $path, $root_node, $current_path, $current_node, $variables,
      $silent) = @_;
  $current_path ||= "/";
  $current_node ||= $root_node;
  $silent ||= 0;

  $self->debug(qq{getting node-set "$path" from "$current_path"});

  $self->{INDENT} += $self->{INDENT_INCR};

  # expand abbriviated syntax
  $path =~ s/\@/attribute\:\:/g;
  $path =~ s/\.\./parent\:\:node\(\)/g;
  $path =~ s/\./self\:\:node\(\)/g;
  $path =~ s/\/\//\/descendant\-or\-self\:\:node\(\)\//g;
  #$path =~ s/\/[^\:\/]*?\//attribute::/g;

  if ($path =~ /^\$([\w\.\-]+)$/) {
    my $varname = $1;
    my $var = $$variables{$varname};
    if (defined $var) {
      if (ref ($$variables{$varname}) eq 'ARRAY') {
	# node-set array-ref
	return $$variables{$varname};
      } elsif (ref ($$variables{$varname}) eq 'XML::DOM::NodeList') {
	# node-set nodelist
	return [@{$$variables{$varname}}];
      } elsif (ref ($$variables{$varname}) eq 'XML::DOM::DocumentFragment') {
	# node-set documentfragment
	return [$$variables{$varname}->getChildNodes];
      } else {
	# string or number?
	return [$self->{XML_DOCUMENT}->createTextNode ($$variables{$varname})];
      }
    } else {
      # var does not exist
      return [];
    }
  } elsif ($path eq $current_path || $path eq 'self::node()') {
    $self->debug("direct hit!");;
    return [$current_node];
  } else {
    # open external documents first #
    if ($path =~ /^\s*document\s*\(["'](.*?)["']\s*(,\s*(.*)\s*){0,1}\)\s*(.*)$/) {
      my $filename = $1;
      my $sec_arg = $3;
      $path = ($4 || "");

      $self->debug(qq{external selection ("$filename")!});

      if ($sec_arg) {
	$self->warn("Ignoring second argument of $path");
      }

      ($root_node) = $self->__open_by_filename ($filename, $self->{XSL_BASE});
    }

    if ($path =~ /^\//) {
      # start from the root #
      $current_node = $root_node;
    } elsif ($path =~ /^self\:\:node\(\)\//) { #'#"#'#"
      # remove preceding dot from './etc', which is expanded to 'self::node()'
      # at the top of this subroutine #
      $path =~ s/^self\:\:node\(\)//;
    } else {
      # to facilitate parsing, precede path with a '/' #
      $path = "/$path";
    }

    $self->debug(qq{using "$path":});

    if ($path eq '/') {
      $current_node = [$current_node];
    } else {
      $current_node = &__get_node_set__ ($self, $path, [$current_node], $silent);
    }

    $self->{INDENT} -= $self->{INDENT_INCR};
    
    return $current_node;
  }
}


# auxiliary function #
sub __get_node_set__ {
  my ($self, $path, $node, $silent) = @_;

  # a Qname (?) should actually be: [a-Z_][\w\.\-]*\:[a-Z_][\w\.\-]*

  if ($path eq "") {

    $self->debug("node found!");;
    return $node;

  } else {
    my $list = [];
    foreach my $item (@$node) {
      my $sublist = &__try_a_step__ ($self, $path, $item, $silent);
      push (@$list, @$sublist);
    }
    return $list;
  }
}

sub __try_a_step__ {
  my ($self, $path, $node, $silent) = @_;

  study ($path);
  if ($path =~ s/^\/parent\:\:node\(\)//) {
    # /.. #
    $self->debug(qq{getting parent ("$path")});
    return &__parent__ ($self, $path, $node, $silent);

  } elsif ($path =~ s/^\/attribute\:\:(\*|[\w\.\:\-]+)//) {
    # /@attr #
    $self->debug(qq{getting attribute `$1' ("$path")});
    return &__attribute__ ($self, $1, $path, $node, $silent);

  } elsif ($path =~ s/^\/descendant\-or\-self\:\:node\(\)\/(child\:\:|)(\*|[\w\.\:\-]+)\[(\S+?)\]//) {
    # //elem[n] #
    $self->debug(qq{getting deep indexed element `$1' `$2' ("$path")});
    return &__indexed_element__ ($self, $1, $2, $path, $node, $silent, "deep");

  } elsif ($path =~ s/^\/descendant\-or\-self\:\:node\(\)\/(\*|[\w\.\:\-]+)//) {
    # //elem #
    $self->debug(qq{getting deep element `$1' ("$path")});
    return &__element__ ($self, $1, $path, $node, $silent, "deep");

  } elsif ($path =~ s/^\/(child\:\:|)(\*|[\w\.\:\-]+)\[(\S+?)\]//) {
    # /elem[n] #
    $self->debug(qq{getting indexed element `$2' `$3' ("$path")});
    return &__indexed_element__ ($self, $2, $3, $path, $node, $silent);

  } elsif ($path =~ s/^\/(child\:\:|)(\*|[\w\.\:\-]+)//) {
    # /elem #
    $self->debug(qq{getting element `$2' ("$path")});
    return &__element__ ($self, $2, $path, $node, $silent);

  } elsif ($path =~ s/^\/(child\:\:|)text\(\)//) {
    # /text() #
    $self->debug(qq{getting text ("$path")});
    return &__get_nodes__ ($self, TEXT_NODE, $path, $node, $silent);

  } elsif ($path =~ s/^\/(child\:\:|)processing-instruction\(\)//) {
    # /processing-instruction() #
    $self->debug(qq{getting processing instruction ("$path")});
    return &__get_nodes__ ($self, PROCESSING_INSTRUCTION_NODE, $path, $node, $silent);

  } elsif ($path =~ s/^\/(child\:\:|)comment\(\)//) {
    # /comment() #
    $self->debug(qq{getting comment ("$path")});
    return &__get_nodes__ ($self, COMMENT_NODE, $path, $node, $silent);

  } else {
    $self->warn("get-node-from-path: Don't know what to do with path $path !!!");
    return [];
  }
}

sub __parent__ {
  my ($self, $path, $node, $silent) = @_;

  $self->{INDENT} += $self->{INDENT_INCR};
  if (($node->getNodeType == DOCUMENT_NODE)
      || ($node->getNodeType == DOCUMENT_FRAGMENT_NODE)) {
    $self->debug("no parent!");;
    $node = [];
  } else {
    $node = $node->getParentNode;

    $node = &__get_node_set__ ($self, $path, [$node], $silent);
  }
  $self->{INDENT} -= $self->{INDENT_INCR};

  return $node;
}

sub __indexed_element__ {
  my ($self, $element, $index, $path, $node, $silent, $deep) = @_;
  $index ||= 0;
  $deep ||= "";			# False #

  if ($index =~ /^first\s*\(\)/) {
    $index = 0;
  } elsif ($index =~ /^last\s*\(\)/) {
    $index = -1;
  } else {
    $index--;
  }

  my @list = $node->getElementsByTagName($element, $deep);
        
  if (@list) {
    $node = $list[$index];
  } else {
    $node = "";
  }

  $self->{INDENT} += $self->{INDENT_INCR};
  if ($node) {
    $node = &__get_node_set__ ($self, $path, [$node], $silent);
  } else {
    $self->debug("failed!");;
    $node = [];
  }
  $self->{INDENT} -= $self->{INDENT_INCR};

  return $node;
}

sub __element__ {
  my ($self, $element, $path, $node, $silent, $deep) = @_;
  $deep ||= "";			# False #

  $node = [$node->getElementsByTagName($element, $deep)];

  $self->{INDENT} += $self->{INDENT_INCR};
  if (@$node) {
    $node = &__get_node_set__($self, $path, $node, $silent);
  } else {
    $self->debug("failed!");;
  }
  $self->{INDENT} -= $self->{INDENT_INCR};

  return $node;
}

sub __attribute__ {
  my ($self, $attribute, $path, $node, $silent) = @_;

  if ($attribute eq '*') {
    $node = [$node->getAttributes->getValues];

    $self->{INDENT} += $self->{INDENT_INCR};
    if ($node) {
      $node = &__get_node_set__ ($self, $path, $node, $silent);
    } else {
      $self->debug("failed!");;
    }
    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $node = $node->getAttributeNode($attribute);

    $self->{INDENT} += $self->{INDENT_INCR};
    if ($node) {
      $node = &__get_node_set__ ($self, $path, [$node], $silent);
    } else {
      $self->debug("failed!");;
      $node = [];
    }
    $self->{INDENT} -= $self->{INDENT_INCR};
  }

  return $node;
}

sub __get_nodes__ {
  my ($self, $node_type, $path, $node, $silent) = @_;

  my $result = [];

  $self->{INDENT} += $self->{INDENT_INCR};
  foreach my $child ($node->getChildNodes) {
    if ($child->getNodeType == $node_type) {
      $result = [@$result, &__get_node_set__ ($self, $path, [$child], $silent)];
    }
  }
  $self->{INDENT} -= $self->{INDENT_INCR};
	
  if (! @$result) {
    $self->debug("failed!");;
  }
        
  return $result;
}


sub _attribute_value_of {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $variables) = @_;

  foreach my $attribute ($xsl_node->getAttributes->getValues) {
    my $value = $attribute->getValue;
    study ($value);
    #$value =~ s/(\*|\$|\@|\&|\?|\+|\\)/\\$1/g;
    $value =~ s/(\*|\?|\+)/\\$1/g;
    study ($value);
    while ($value =~ /\G[^\\]?\{(.*?[^\\]?)\}/) {
      my $node = $self->_get_node_set ($1, $self->{XML_DOCUMENT},
					 $current_xml_selection_path,
					 $current_xml_node, $variables);
      if (@$node) {
	$self->{INDENT} += $self->{INDENT_INCR};
	my $text = $self->__string__ ($$node[0]);
	$self->{INDENT} -= $self->{INDENT_INCR};
	$value =~ s/(\G[^\\]?)\{(.*?)[^\\]?\}/$1$text/;
      } else {
	$value =~ s/(\G[^\\]?)\{(.*?)[^\\]?\}/$1/;
      }
    }
    #$value =~ s/\\(\*|\$|\@|\&|\?|\+|\\)/$1/g;
    $value =~ s/\\(\*|\?|\+)/$1/g;
    $value =~ s/\\(\{|\})/$1/g;
    $attribute->setValue ($value);
  }
}

sub _processing_instruction {
  my ($self, $xsl_node, $current_result_node, $variables, $oldvariables) = @_;

  my $new_PI_name = $xsl_node->getAttribute('name');

  if ($new_PI_name eq "xml") {
    $self->warn("<" . $self->{XSL_NS} . "processing-instruction> may not be used to create XML");
    $self->warn("declaration. Use <" . $self->{XSL_NS} . "output> instead...");
  } elsif ($new_PI_name) {
    my $text = $self->__string__ ($xsl_node);
    my $new_PI = $self->{XML_DOCUMENT}->createProcessingInstruction($new_PI_name, $text);

    if ($new_PI) {
      $self->_move_node ($new_PI, $current_result_node);
    }
  } else {
    $self->warn(q{Expected attribute "name" in <} .
		$self->{XSL_NS} . "processing-instruction> !");
  }
}

sub _process_with_params {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $variables, $params) = @_;

  my @params = $xsl_node->getElementsByTagName("$self->{XSL_NS}with-param");
  foreach my $param (@params) {
    my $varname = $param->getAttribute('name');

    if ($varname) {
      my $value = $param->getAttribute('select');

      if (!$value) {
	# process content as template
	$value = $self->{XML_DOCUMENT}->createDocumentFragment;

	$self->_evaluate_template ($param,
				     $current_xml_node,
				     $current_xml_selection_path,
				     $value, $variables, {} );
	$$params{$varname} = $value;

      }
    } else {
      $self->warn(q{Expected attribute "name" in <} .
		  $self->{XSL_NS} . q{with-param> !});
    }
  }

}

sub _call_template {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $params={};
  my $newvariables = {%$variables};

  my $name = $xsl_node->getAttribute('name');
  
  if ($name) {
    $self->debug("calling template named \"$name\"");;

    $self->_process_with_params ($xsl_node, $current_xml_node,
				   $current_xml_selection_path,
				   $current_result_node, $variables, $params);

    $self->{INDENT} += $self->{INDENT_INCR};
    my $template = $self->_match_template ("name", $name, 0, '');

    if ($template) {
      $self->_evaluate_template ($template, $current_xml_node,
				   $current_xml_selection_path,
				   $current_result_node, $newvariables, $params);
    } else {
      $self->warn("no template named $name found!");
    }
    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $self->warn(q{Expected attribute "name" in <} .
		$self->{XSL_NS} . q{call-template/>});
  }
}

sub _choose {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  $self->debug("evaluating choose:");;

  $self->{INDENT} += $self->{INDENT_INCR};

  my $notdone = "true";
  my $testwhen = "active";
  foreach my $child ($xsl_node->getElementsByTagName ('*', 0)) {
    if ($notdone && $testwhen && ($child->getTagName eq $self->{XSL_NS} ."when")) {
      my $test = $child->getAttribute ('test');

      if ($test) {
	my $test_succeeds = $self->_evaluate_test ($test, $current_xml_node,
						     $current_xml_selection_path,
						     $variables);
	if ($test_succeeds) {
	  $self->_evaluate_template ($child, $current_xml_node,
				       $current_xml_selection_path,
				       $current_result_node, $variables, $oldvariables);
	  $testwhen = "";
	  $notdone = "";
	}
      } else {
	$self->warn(q{expected attribute "test" in <} .
		    $self->{XSL_NS} . q{when>});
      }
    } elsif ($notdone && ($child->getTagName eq $self->{XSL_NS} . "otherwise")) {
      $self->_evaluate_template ($child, $current_xml_node,
				   $current_xml_selection_path,
				   $current_result_node, $variables, $oldvariables);
      $notdone = "";
    }
  }

  if ($notdone) {
    $self->debug("nothing done!");;
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _if {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  $self->debug("evaluating if:");;

  $self->{INDENT} += $self->{INDENT_INCR};

  my $test = $xsl_node->getAttribute ('test');

  if ($test) {
    my $test_succeeds = $self->_evaluate_test ($test, $current_xml_node,
						 $current_xml_selection_path,
						 $variables);
    if ($test_succeeds) {
      $self->_evaluate_template ($xsl_node, $current_xml_node,
				   $current_xml_selection_path,
				   $current_result_node, $variables, $oldvariables);
    }
  } else {
    $self->warn(q{expected attribute "test" in <} .
		$self->{XSL_NS} . q{if>});
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub __evaluate_test__ {
  my ($self,$test, $path,$node,$variables) = @_;

  #print "testing with \"$test\" and ", ref $node,"\n";
  if ($test =~ /^\s*\@([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
    my $attr = $node->getAttribute($1);
    return ($attr ne $2);
  } elsif ($test =~ /^\s*\@([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
    my $attr = $node->getAttribute($1);
    return ($attr eq $2);
  } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
    my $expval=$2;
    my $nodeset=&_get_node_set($self,$1,$self->{XML_DOCUMENT},$path,$node,$variables);
    return ($expval ne '') unless @$nodeset;
    my $content = &__string__($self,$$nodeset[0]);
    return ($content ne $expval);
  } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
    my $expval=$2;
    my $nodeset=&_get_node_set($self,$1,$self->{XML_DOCUMENT},$path,$node,$variables);
    return ($expval eq '') unless @$nodeset;
    my $content = &__string__($self,$$nodeset[0]);
    return ($content eq $expval);
  } else {
    return "";
  }
}

sub _copy_of {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables) = @_;

  my $nodelist;
  my $select = $xsl_node->getAttribute('select');
  $self->debug("evaluating copy-of with select \"$select\":");;
  
  $self->{INDENT} += $self->{INDENT_INCR};
  if ($select) {
    $nodelist = $self->_get_node_set ($select, $self->{XML_DOCUMENT},
					$current_xml_selection_path,
					$current_xml_node, $variables);
  } else {
    $self->warn(q{expected attribute "select" in <} .
		$self->{XSL_NS} . q{copy-of>});
  }
  foreach my $node (@$nodelist) {
    $self->_add_node ($node, $current_result_node, "deep");
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _copy {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;


  $self->debug("evaluating copy:");;

  $self->{INDENT} += $self->{INDENT_INCR};
  if ($current_xml_node->getNodeType == ATTRIBUTE_NODE) {
    my $attribute = $current_xml_node->cloneNode(0);
    $current_result_node->setAttributeNode($attribute);
  } elsif (($current_xml_node->getNodeType == COMMENT_NODE)
	   || ($current_xml_node->getNodeType == PROCESSING_INSTRUCTION_NODE)) {
    $self->_add_node ($current_xml_node, $current_result_node);
  } else {
    $self->_add_node ($current_xml_node, $current_result_node);
    $self->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $current_result_node->getLastChild,
				 $variables, $oldvariables);
  }
  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _text {
  #=item addText (text)
  #
  #Appends the specified string to the last child if it is a Text node, or else 
  #appends a new Text node (with the specified text.)
  #
  #Return Value: the last child if it was a Text node or else the new Text node.
  my ($self, $xsl_node, $current_result_node) = @_;

  $self->debug("inserting text:");

  $self->{INDENT} += $self->{INDENT_INCR};

  $self->debug("stripping node to text:");

  $self->{INDENT} += $self->{INDENT_INCR};
  my $text = $self->__string__ ($xsl_node);
  $self->{INDENT} -= $self->{INDENT_INCR};

  if ($text ne '') {
    my $node = $self->{XML_DOCUMENT}->createTextNode ($text);
    if ($xsl_node->getAttribute ('disable-output-escaping') eq 'yes')
      {
      $self->debug("disabling output escaping");
      bless $node,'XML::XSLT::DOM::TextDOE' ;
    }
    $self->_move_node ($node, $current_result_node);
  } else {
    $self->debug("nothing left..");
  }

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _attribute {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  
  my $name = $xsl_node->getAttribute ('name');
  $self->debug("inserting attribute named \"$name\":");
  $self->{INDENT} += $self->{INDENT_INCR};

  if ($name) {
    my $result = $self->{XML_DOCUMENT}->createDocumentFragment;

    $self->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result, $variables, $oldvariables);

    $self->{INDENT} += $self->{INDENT_INCR};
    my $text = $self->__string__ ($result);
    $self->{INDENT} -= $self->{INDENT_INCR};

    $current_result_node->setAttribute($name, $text);
    $result->dispose();
  } else {
    $self->warn(q{expected attribute "name" in <} .
		$self->{XSL_NS} . q{attribute>});
  }
  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _comment {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  $self->debug("inserting comment:");

  $self->{INDENT} += $self->{INDENT_INCR};

  my $result = $self->{XML_DOCUMENT}->createDocumentFragment;

  $self->_evaluate_template ($xsl_node,
			       $current_xml_node,
			       $current_xml_selection_path,
			       $result, $variables, $oldvariables);

  $self->{INDENT} += $self->{INDENT_INCR};
  my $text = $self->__string__ ($result);
  $self->{INDENT} -= $self->{INDENT_INCR};

  $self->_move_node ($self->{XML_DOCUMENT}->createComment ($text), $current_result_node);
  $result->dispose();

  $self->{INDENT} -= $self->{INDENT_INCR};
}

sub _variable {
  my ($self, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $params, $is_param) = @_;
  
  my $varname = $xsl_node->getAttribute ('name');
  
  if ($varname) {
    $self->debug("definition of variable \$$varname:");;

    $self->{INDENT} += $self->{INDENT_INCR};

    if ( $is_param and exists $$params{$varname} ) {
      # copy from parent-template

      $$variables{$varname} = $$params{$varname};

    } else {
      # new variable definition

      my $value = $xsl_node->getAttribute ('select');

      if (! $value) {
	#tough case, evaluate content as template

	$value = $self->{XML_DOCUMENT}->createDocumentFragment;

	$self->_evaluate_template ($xsl_node,
				   $current_xml_node,
				   $current_xml_selection_path,
				   $value, $variables, $params);
      }

      $$variables{$varname} = $value;
    }

    $self->{INDENT} -= $self->{INDENT_INCR};
  } else {
    $self->warn(q{expected attribute "name" in <} .
		$self->{XSL_NS} . q{param> or <} .
		$self->{XSL_NS} . q{variable>});
  }
}

1;

__END__

=head1 SYNOPSIS

 use XML::XSLT;

 my $xslt = XML::XSLT->new ($xsl, warnings => 1);

 $xslt->transform ($xmlfile)
 print $xslt->asString

 $xslt->dispose ();

=head1 DESCRIPTION

This module implements the W3C's XSLT specification. The goal is full
implementation of this spec, but we have not yet achieved
that. However, it already works well.  See L<XML::XSLT Commands> for
the current status of each command.

XML::XSLT makes use of XML::DOM and LWP::Simple, while XML::DOM
uses XML::Parser.  Therefore XML::Parser, XML::DOM and LWP::Simple
have to be installed properly for XML::XSLT to run.

=head1 Specifying Sources

The stylesheets and the documents may be passed as filenames, file
handles regular strings, string references or DOM-trees.  Functions
that require sources (e.g. new), will accept either a named parameter
or simply the argument.

Either of the following are allowed:

 my $xslt = XML::XSLT->new($xsl);
 my $xslt = XML::XSLT->new(Source => $xsl);

In documentation, the named parameter `Source' is always shown, but it
is never required.

=head1 METHODS

=head2 new(Source => $xml [, %args])

Returns a new XSLT parser object.  Valid flags are:

=over 4

=item DOMparser_args

Hashref of arguments to pass to the XML::DOM::Parser object's parse
method.

=item variables

Hashref of variables and their values for the stylesheet.

=item base

Base of URL for file inclusion.

=item debug

Turn on debugging messages.

=item warnings

Turn on warning messages.

=item indent

Starting amount of indention for debug messages.  Defaults to 0.

=item indent_incr

Amount to indent each level of debug message.  Defaults to 1.

=back

=head2 open_xml(Source => $xml [, %args])

Gives the XSLT object new XML to process.  Returns an XML::DOM object
corresponding to the XML.

=over 4

=item base

The base URL to use for opening documents.

=item parser_args

Arguments to pase to the parser.

=back

=head2 open_xsl(Source => $xml, [, %args])

Gives the XSLT object a new stylesheet to use in processing XML.
Returns an XML::DOM object corresponding to the stylesheet.  Any
arguments present are passed to the XML::DOM::Parser.

=over 4

=item base

The base URL to use for opening documents.

=item parser_args

Arguments to pase to the parser.

=back

=head2 process(%variables)

Processes the previously loaded XML through the stylesheet using the
variables set in the argument.

=head2 transform(Source => $xml [, %args])

Processes the given XML through the stylesheet.  Returns an XML::DOM
object corresponding to the transformed XML.  Any arguments present
are passed to the XML::DOM::Parser.

=head2 serve(Source => $xml [, %args])

Processes the given XML through the stylesheet.  Returns a string
containg the result.  Example:

  use XML::XSLT qw(serve);

  $xslt = XML::XSLT->new($xsl);
  print $xslt->serve $xml;

=over 4

=item http_headers

If true, then prepends the appropriate HTTP headers (e.g. Content-Type,
Content-Length);

Defaults to true.

=item xml_declaration

If true, then the result contains the appropriate <?xml?> header.

Defaults to true.

=item xml_version

The version of the XML.

Defaults to 1.0.

=item doctype

The type of DOCTYPE this document is.  Defaults to SYSTEM.

=back

=head2 toString

Returns the result of transforming the XML with the stylesheet as a
string.

=head2 to_dom

Returns the result of transforming the XML with the stylesheet as an
XML::DOM object.

=head2 media_type

Returns the media type (aka mime type) of the object.

=head2 dispose

Executes the C<dispose> method on each XML::DOM object.

=head1 XML::XSLT Commands

=head2 xsl:apply-imports		no

Not supported yet.

=head2 xsl:apply-templates		limited

Attribute 'select' is supported to the same extent as xsl:value-of
supports path selections.

Not supported yet:
- attribute 'mode'
- xsl:sort and xsl:with-param in content

=head2 xsl:attribute			partially

Adds an attribute named to the value of the attribute 'name' and as value
the stringified content-template.

Not supported yet:
- attribute 'namespace'

=head2 xsl:attribute-set		no

Not supported yet.

=head2 xsl:call-template		yes

Takes attribute 'name' which selects xsl:template's by name.

Not supported yet:
- xsl:sort and xsl:with-param in content

=head2 xsl:choose			yes

Tests sequentially all xsl:whens until one succeeds or
until an xsl:otherwise is found. Limited test support, see xsl:when

=head2 xsl:comment			yes

Supported.

=head2 xsl:copy				partially

Not supported yet:
- attribute 'use-attribute-sets'

=head2 xsl:copy-of			limited

Attribute 'select' functions as well as with
xsl:value-of

=head2 xsl:decimal-format		no

Not supported yet.

=head2 xsl:element			yes

=head2 xsl:fallback			no

Not supported yet.

=head2 xsl:for-each			limited

Attribute 'select' functions as well as with
xsl:value-of

Not supported yet:
- xsl:sort in content

=head2 xsl:if				limited

Identical to xsl:when, but outside xsl:choose context.

=head2 xsl:import			no

Not supported yet.

=head2 xsl:include			yes

Takes attribute href, which can be relative-local, 
absolute-local as well as an URL (preceded by
identifier http:).

=head2 xsl:key				no

Not supported yet.

=head2 xsl:message			no

Not supported yet.

=head2 xsl:namespace-alias		no

Not supported yet.

=head2 xsl:number			no

Not supported yet.

=head2 xsl:otherwise			yes

Supported.

=head2 xsl:output			no

Not supported yet.

=head2 xsl:param			experimental

Synonym for xsl:variable (currently). See xsl:variable for support.

=head2 xsl:preserve-space		no

Not supported yet. Whitespace is always preserved.

=head2 xsl:processing-instruction	yes

Supported.

=head2 xsl:sort				no

Not supported yet.

=head2 xsl:strip-space			no

Not supported yet. No whitespace is stripped.

=head2 xsl:stylesheet			limited

Minor namespace support: other namespace than 'xsl:' for xsl-commands
is allowed if xmlns-attribute is present. xmlns URL is verified.
Other attributes are ignored.

=head2 xsl:template			limited

Attribute 'name' and 'match' are supported to minor extend.
('name' must match exactly and 'match' must match with full
path or no path)

Not supported yet:
- attributes 'priority' and 'mode'

=head2 xsl:text				yes

Supported.

=head2 xsl:transform			limited

Synonym for xsl:stylesheet

=head2 xsl:value-of			limited

Inserts attribute or element values. Limited support:

<xsl:value-of select="."/>

<xsl:value-of select="/root-elem"/>

<xsl:value-of select="elem"/>

<xsl:value-of select="//elem"/>

<xsl:value-of select="elem[n]"/>

<xsl:value-of select="//elem[n]"/>

<xsl:value-of select="@attr"/>

<xsl:value-of select="text()"/>

<xsl:value-of select="processing-instruction()"/>

<xsl:value-of select="comment()"/>

and combinations of these.

Not supported yet:
- attribute 'disable-output-escaping'

=head2 xsl:variable			experimental

Very limited. It should be possible to define a variable and use it with
&lt;xsl:value select="$varname" /&gt; within the same template.

=head2 xsl:when				limited

Only inside xsl:choose. Limited test support:

<xsl:when test="@attr='value'">

<xsl:when test="elem='value'">

<xsl:when test="path/[@attr='value']">

<xsl:when test="path/[elem='value']">

<xsl:when test="path">

path is supported to the same extend as with xsl:value-of

=head2 xsl:with-param			experimental

It is currently not functioning. (or is it?)

=head1 SUPPORT

General information, bug reporting tools, the latest version, mailing
lists, etc. can be found at the XML::XSLT homepage:

  http://xmlxslt.sourceforge.net/

=head1 DEPRECATIONS

Methods and interfaces from previous versions that are not documented in this
version are deprecated.  Each of these deprecations can still be used
but will produce a warning when the deprecation is first used.  You
can use the old interfaces without warnings by passing C<new()> the
flag C<use_deprecated>.  Example:

 $parser = XML::XSLT->new($xsl, "FILE",
                          use_deprecated => 1);

The deprecations will disappear by the time a 1.0 release is made.

=head1 BUGS

Yes.

=head1 HISTORY

Geert Josten and Egon Willighagen developed and maintained XML::XSLT
up to version 0.22.  At that point, Mark Hershberger started moving
the project to Sourceforge and began working on it with Bron Gondwana.

=head1 LICENCE

Copyright (c) 1999 Geert Josten & Egon Willighagen. All Rights
Reserverd.  This module is free software, and may be distributed under
the same terms and conditions as Perl.

=head1 AUTHORS

Geert Josten <gjosten@sci.kun.nl>,
Egon Willighagen <egonw@sci.kun.nl>,
Mark A. Hershberger <mah@everybody.org>
Bron Gondwana <perlcode@brong.net>,

=head1 SEE ALSO

L<XML::DOM>, L<LWP::Simple>, L<XML::Parser>

=cut

Filename: $RCSfile: XSLT.pm,v $
Revision: $Revision: 1.2 $
   Label: $Name:  $

Last Chg: $Author: hexmode $ 
      On: $Date: 2001/01/16 03:17:35 $

  RCS ID: $Id: XSLT.pm,v 1.2 2001/01/16 03:17:35 hexmode Exp $
    Path: $Source: /cvsroot/xmlxslt/XML-XSLT/lib/XML/XSLT.pm,v $
