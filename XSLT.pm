################################################################################
#
# Perl module: XML::XSLT
#
# By Geert Josten, gjosten@sci.kun.nl
# and Egon Willighagen, egonw@sci.kun.nl
#
################################################################################

######################################################################
package XML::XSLT;
######################################################################

use strict;
use vars qw ( $VERSION @ISA @EXPORT
              $ELEMENT_NODE $ATTRIBUTE_NODE $TEXT_NODE
	      $CDATA_SECTION_NODE $ENTITY_REFERENCE_NODE
              $ENTITY_NODE $PROCESSING_INSTRUCTION_NODE
	      $COMMENT_NODE $DOCUMENT_NODE $DOCUMENT_TYPE_NODE
	      $DOCUMENT_FRAGMENT_NODE $NOTATION_NODE
            );
	      #$UNKNOWN_NODE
              #$ELEMENT_DECL_NODE $ATT_DEF_NODE
	      #$XML_DECL_NODE $ATTLIST_DECL_NODE

use LWP::UserAgent;
use XML::DOM;

BEGIN {
  require XML::DOM;

  my $needVersion = '1.25';
  my $domVersion = $XML::DOM::VERSION;
  die "need at least XML::DOM version $needVersion (current=$domVersion)"
    unless $domVersion >= $needVersion;

  $VERSION = '0.21';

  @ISA         = qw( Exporter );
  @EXPORT      = qw( &new &transform_document &result_string
                     &result_tree &print_result &dispose);

  # pretty print HTML tags (<BR /> etc...)
  XML::DOM::setTagCompression (\&__my_tag_compression__);

  ### added for efficiency reasons
  $ELEMENT_NODE 	       = ELEMENT_NODE;
  $ATTRIBUTE_NODE	       = ATTRIBUTE_NODE;
  $TEXT_NODE		       = TEXT_NODE;
  $CDATA_SECTION_NODE	       = CDATA_SECTION_NODE;
  $ENTITY_REFERENCE_NODE       = ENTITY_REFERENCE_NODE;
  $ENTITY_NODE  	       = ENTITY_NODE;
  $PROCESSING_INSTRUCTION_NODE = PROCESSING_INSTRUCTION_NODE;
  $COMMENT_NODE 	       = COMMENT_NODE;
  $DOCUMENT_NODE	       = DOCUMENT_NODE;
  $DOCUMENT_TYPE_NODE	       = DOCUMENT_TYPE_NODE;
  $DOCUMENT_FRAGMENT_NODE      = DOCUMENT_FRAGMENT_NODE;
  $NOTATION_NODE	       = NOTATION_NODE;
  ### these node ID's are not part of the Reccomendation
  #$UNKNOWN_NODE		= UNKNOWN_NODE;
  #$ELEMENT_DECL_NODE  	 	= ELEMENT_DECL_NODE;
  #$ATT_DEF_NODE		= ATT_DEF_NODE;
  #$XML_DECL_NODE		= XML_DECL_NODE;
  #$ATTLIST_DECL_NODE  	 	= ATTLIST_DECL_NODE;
}

    # private auxiliary function #
    sub __my_tag_compression__ {
       my ($tag, $elem) = @_;

       # Print empty br, hr and img tags like this: <br />
       # also when preceded by a namespace: ([\w\.]+\:){0,1}
       return 2 if $tag =~ /^([\w\.\-]+\:){0,1}(br|p|hr|img|meta|base|link)$/i;

       # Print other empty tags like this: <empty></empty>
       return 1;
    }


######################################################################
# PUBLIC DEFINITIONS


sub new {
  my ($class, $xsl, $xsl_flag, %args) = @_;

  $args{DOMparser_args} ||= {'KeepCDATA' => 1}; # Default #
  $args{debug} ||= "";         # False if undef #
  $args{indent} ||= 0;         # Default to 0   #
  $args{indent_incr} ||= 1;    # Default to 1   #

  if (!$xsl) {
    warn "No stylesheet was passed to new(), no parser object is created!";
    return undef;
  }

  my $parser = bless { DOMparser => XML::DOM::Parser->new (),
                       DOMparser_args => $args{DOMparser_args},
                       xml => undef, xml_flag => undef, xml_dir => undef,
	               xsl => undef, xsl_flag => undef, xsl_dir => undef,
	               result => undef,
		       stylesheet => undef, templates => undef,
		       template_matches => undef, template_names => undef,
		       xsl_ns => "", xsl_version => undef,
		       namespaces => {()},
	               variables => \%args,
		       debug => $args{debug},
		       warnings => ($args{warnings} && ! $args{debug}),
	               indent => $args{indent}, indent_incr => $args{indent_incr}
		     }, $class;

  $parser->open_xsl ($xsl, $xsl_flag, %args);

  return $parser;
}

sub open_xml {
  my ($parser, $xml, $xmlflag, %args) = @_;

  # clean up a little
  if ($parser->{xml_flag} && $parser->{xml_flag} !~ /^DOM/i) {  
    print " "x$parser->{indent},"disposing old xsl...$/" if $parser->{debug};
    $parser->{xml}->dispose ()     if (defined $parser->{xml});
  }
  if (defined $parser->{result}) {
    print " "x$parser->{indent},"flushing result...$/" if $parser->{debug};
    $parser->{result}->dispose ();
  }

  print " "x$parser->{indent},"opening xml...$/" if $parser->{debug};

  # open new document
  ($parser->{xml}, $parser->{xml_dir})
    = $parser->_open_document ($xml, $xmlflag, ".", %args);
  $parser->{xml_flag} = $xmlflag;

  $parser->{result} = $parser->{xml}->createDocumentFragment;
}

sub open_xsl {
  my ($parser, $xsl, $xslflag, %args) = @_;
  $xslflag ||= "FILE";

  # clean up a little
  if ($parser->{xsl_flag} && $parser->{xsl_flag} !~ /^DOM/i) {
    print " "x$parser->{indent},"disposing old xsl...$/" if $parser->{debug};
    $parser->{xsl}->dispose ()     if (defined $parser->{xsl});
  }

  print " "x$parser->{indent},"opening xsl...$/" if $parser->{debug};

  # open new document
  ($parser->{xsl}, $parser->{xml_dir})
    = $parser->_open_document ($xsl, $xslflag, ".", %args);
  $parser->{xsl_flag} = $xslflag;

  $parser->__preprocess_stylesheet;
}

    # private auxiliary function #
    sub __preprocess_stylesheet {
      my $parser = $_[0];

      print " "x$parser->{indent},"preprocessing stylesheet...$/" if $parser->{debug};

      ($parser->{stylesheet}, $parser->{xsl_ns})
        = $parser->__get_stylesheet ($parser->{xsl});

      ($parser->{xsl_version})
        = $parser->__extract_namespaces ($parser->{stylesheet}, $parser->{xsl_ns});
      $parser->__expand_xsl_includes ($parser->{xsl}, $parser->{xsl_ns}, $parser->{xsl_dir});
      $parser->__extract_top_level_variables;

      $parser->__add_default_templates;
      $parser->__cache_templates; # speed optim #
    }

        # private auxiliary function #
	sub __get_stylesheet {
	  my ($parser, $xsl) = @_;
	  my $stylesheet = "";
          my $xsl_ns = "";

	  foreach my $child ($xsl->getElementsByTagName ('*', 0)) {
	    if ($child->getTagName =~ /^(([\w\.\-]+)\:){0,1}(stylesheet|transform)$/i) {
              $stylesheet = $child;
	      $xsl_ns = ($2 || "");
	      last;
	    }
          }

	  if (! $stylesheet) {
            # stylesheet is actually one compleet template! #
	    # put it in a template-element #
	    
            $stylesheet = $xsl->createElement ("$xsl_ns:stylesheet");
	    my $template = $xsl->createElement ("$xsl_ns:template");
	    $template->setAttribute ('match', "/");

            my $template_content = $xsl->getElementsByTagName ('*', 0)->item (0);
	    $xsl->replaceChild ($stylesheet, $template_content);
            $stylesheet->appendChild ($template);
	    $template->appendChild ($template_content);
	  }
	  
	  return ($stylesheet, "$xsl_ns:");
	}

	# private auxiliary function #
	sub __extract_namespaces {
	  my ($parser, $stylesheet, $xsl_ns) = @_;
	  my $xsl_version = "";

	  foreach my $attribute ($stylesheet->getAttributes->getValues) {
	    my $name = $attribute->getName;
	    my $value = $attribute->getValue;
            if ($value) {
              if ($name eq "version") {
	        $xsl_version = $value;
	      } elsif ($name =~ /^xmlns(\:([\w\.\-]+)){0,1}/i) {
	        my $namespace = ("$2:" || "");
	        if (($namespace eq $xsl_ns)
	        && ($value !~ /^http\:\/\/www\.w3\.org\/1999\/XSL\/Transform/i)) {
	          warn "XML::XSLT implements the specs of http://www.w3.org/1999/XSL/Transform. URL $value might be depricated.$/"
		    if $parser->{warnings};
	        }
	        $parser->{namespaces} = {%{$parser->{namespaces}}, $namespace => $value};
	      }
            } else {
              print " "x$parser->{indent},"attribute $name carries no value$/" if $parser->{debug};
            }
	  }
	  
	  if (! exists ${$parser->{namespaces}}{""}) {
	    $parser->{namespaces} = {%{$parser->{namespaces}}, "" => 'http://www.w3.org/TR/xhtml1/strict'};
	  }
	}

	# private auxiliary function #
	sub __expand_xsl_includes {
	  my ($parser, $xsl, $xsl_ns, $xsl_dir) = @_;

	  foreach my $include_node ($xsl->getElementsByTagName("{$xsl_ns}include")) {
	    my $include_file = $include_node->getAttribute('href');

	    if ($include_file) {
              my ($include_doc, $dir);
	      eval {
	        ($include_doc, $dir) = $parser->_open_by_filename ($include_file, $xsl_dir);
	      };
	      
	      if ($@) {
	        chomp ($@);
                print " "x$parser->{indent},"inclusion of $include_file failed! ($@)$/" if $parser->{debug};
                warn "inclusion of $include_file failed! ($@)$/" if $parser->{warnings};
	      } else {
                my ($stylesheet, $ns) = $parser->__get_stylesheet ($include_doc);
	        my $version = $parser->__extract_namespaces ($stylesheet, $ns);
		$parser->__expand_xsl_includes ($include_doc, $ns, $dir);

	        foreach my $child ($stylesheet->getChildNodes) {
		  $include_node->appendChild($child);
	        }
	      }

	    } else {
              print " "x$parser->{indent},"$parser->{xsl_ns}include tag carries no selection!$/" if $parser->{debug};
              warn "$parser->{xsl_ns}include tag carries no selection!$/" if $parser->{warnings};
	    }
	  }
	}

	# private auxiliary function #
	sub __extract_top_level_variables {
	  my $parser = $_[0];

	  foreach my $child ($parser->{stylesheet}->getElementsByTagName ('*',0)) {
	    if ($child =~ /^$parser->{xsl_ns}(variable|param)/i) {
              my $vartag = $1;

              my $name = $child->getAttribute("name");
              if ($name) {
                my $value = $child->getAttribute("select");
                if (!$value) {
                  my $result = $parser->{xml}->createDocumentFragment;
                  $parser->_evaluate_template ($child, $parser->{xml}, '', $result);
                  $value = $parser->_string ($result);
                  $result->dispose();
                }
                %{$parser->{variables}} = (%{$parser->{variables}}, $name => $value);
              } else {
                print " "x$parser->{indent},"$parser->{xsl_ns}$vartag tag carries no name!$/" if $parser->{debug};
                warn "$parser->{xsl_ns}include tag carries no name!$/" if $parser->{warnings};
              }

	    }
	  }
	}

	# private auxiliary function #
	sub __add_default_templates {
	  my $parser = $_[0];

	  # create template for '*' and '/' #
	  my $elem_template = $parser->{xsl}->createElement ("$parser->{xsl_ns}template");
	  $elem_template->setAttribute('match','*|/');
	  # <xsl:apply-templates />
	  $elem_template->appendChild ($parser->{xsl}->createElement ("$parser->{xsl_ns}apply-templates"));

	  # create template for 'text()' and '@*' #
	  my $attr_template = $parser->{xsl}->createElement ("$parser->{xsl_ns}template");
	  $attr_template->setAttribute('match','text()|@*');
	  # <xsl:value-of select="." />
	  $attr_template->appendChild ($parser->{xsl}->createElement ("$parser->{xsl_ns}value-of"));
          $attr_template->getFirstChild->setAttribute('select','.');

	  # create template for 'processing-instruction()' and 'comment()' #
	  my $pi_template = $parser->{xsl}->createElement ("$parser->{xsl_ns}template");
	  $pi_template->setAttribute('match','processing-instruction()|comment()');
          # do nothing :-)

	  # add them to the stylesheet #
	  my $first_child = $parser->{stylesheet}->getFirstChild ();
	  $parser->{stylesheet}->insertBefore ($pi_template, $first_child);
	  $parser->{stylesheet}->insertBefore ($attr_template, $first_child);
	  $parser->{stylesheet}->insertBefore ($elem_template, $first_child);
	}

	# private auxiliary function #
	sub __cache_templates {
	  my $parser = $_[0];

	  $parser->{templates} = [$parser->{xsl}->getElementsByTagName ("$parser->{xsl_ns}template")];

	  # pre-cache template names and matches #
	  # reversing the template order is much more efficient #
	  foreach my $template (reverse @{$parser->{templates}}) {
	    if ($template->getParentNode->getTagName =~
	        /^([\w\.\-]+\:){0,1}(stylesheet|transform|include)/i) {
	      my $match = $template->getAttribute ('match');
	      my $name = $template->getAttribute ('name');
              if ($match && $name) {
                print " "x$parser->{indent},"defining a template with both a \"name\" and a \"match\" attribute is not allowed!$/" if $parser->{debug};
                warn "defining a template with both a \"name\" and a \"match\" attribute is not allowed!$/" if $parser->{warnings};
	        push (@{$parser->{template_matches}}, "");
	        push (@{$parser->{template_names}}, "");
              } elsif ($match) {
	        push (@{$parser->{template_matches}}, $match);
	        push (@{$parser->{template_names}}, "");
              } elsif ($name) {
	        push (@{$parser->{template_matches}}, "");
  	        push (@{$parser->{template_names}}, $name);
              } else {
	        push (@{$parser->{template_matches}}, "");
	        push (@{$parser->{template_names}}, "");
              }
	    }
	  }
	}


sub open_project {
  my ($parser, $xml, $xsl, $xmlflag, $xslflag, %args) = @_;

  print " "x$parser->{indent},"opening project:$/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

    $parser->open_xml ($xml, $xmlflag, %args);
    $parser->open_xsl ($xsl, $xslflag, %args);

    print " "x$parser->{indent},"done...$/" if $parser->{debug};
  $parser->{indent} -= $parser->{indent_incr};
}

sub transform_document {
  my ($parser, $xml, $xmlflag, %topvariables) = @_;

  print " "x$parser->{indent},"opening project:$/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

    $parser->open_xml ($xml, $xmlflag, %topvariables);

    print " "x$parser->{indent},"done...$/" if $parser->{debug};
  $parser->{indent} -= $parser->{indent_incr};
  print " "x$parser->{indent},"processing project:$/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

    my $root_template = $parser->_match_template ("match", '/', 1, '');

    %topvariables = (%{$parser->{variables}}, %topvariables);

    $parser->_evaluate_template (
        $root_template,		# starting template: the root template
        $parser->{xml},		# current XML node: the root
        '',			# current XML selection path: the root
        $parser->{result},	# current result tree node: the root
        {()},                   # current known variables: none
        \%topvariables          # previously known variables: top level variables
    );

  print " "x$parser->{indent},"done!$/" if $parser->{debug};
  $parser->{indent} -= $parser->{indent_incr};
}

sub process_project {
  my ($parser, %topvariables) = @_;

  print " "x$parser->{indent},"processing project:$/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

    my $root_template = $parser->_match_template ("match", '/', 1, '');

    %topvariables = (%{$parser->{variables}}, %topvariables);

    $parser->_evaluate_template (
        $root_template,		# starting template: the root template
        $parser->{xml},		# current XML node: the root
        '',			# current XML selection path: the root
        $parser->{result},	# current result tree node: the root
        {()},                   # current known variables: none
        \%topvariables          # previously known variables: top level variables
    );

  print " "x$parser->{indent},"done!$/" if $parser->{debug};
  $parser->{indent} -= $parser->{indent_incr};
}

sub result_string {
  my $parser = $_[0];

  my $string = $parser->{result}->toString;
  $string =~ s/\n\s*\n(\s*)\n/\n$1\n/g; # Substitute multiple empty lines by one
#  $string =~ s/\/\>/ \/\>/g;            # Insert a space before every />

  return $string;
}

sub result_tree {
  return $_[0]->{result};
}

sub result {
  return $_[0]->result_string;
}

sub print_result {
  my ($parser, $file) = @_;

#  $parser->{result}->printToFileHandle (\*STDOUT);
#  or $parser->{result}->print (\*STDOUT); ???
#  exit;

  if (defined $file) {
    if (ref (\$file) !~ /^SCALAR/i) {
      print $file $parser->result_string,$/;
    } else {
      if (open (FILE, ">$file")) {
        print FILE $parser->result_string,$/;
        if (! close (FILE)) {
          die ("Error writing $file: $!. Nothing written...$/");
        }
      } else {
        die ("Error opening $file: $!. Nothing done...$/");
      }
    }
  } else {
    print $parser->result_string,$/;
  }
}

sub dispose {
  #my $parser = $_[0];

  $_[0]->{DOMparser}->dispose () if (defined $_[0]->{DOMparser});
  $_[0]->{result}->dispose ()    if (defined $_[0]->{result});

  # only dispose xml and xsl when they were not passed as DOM
  if ($_[0]->{xml_flag} && $_[0]->{xml_flag} !~ /^DOM/i) {  
    $_[0]->{xml}->dispose ()     if (defined $_[0]->{xml});
  }
  if ($_[0]->{xsl_flag} && $_[0]->{xsl_flag} !~ /^DOM/i) {  
    $_[0]->{xsl}->dispose ()     if (defined $_[0]->{xsl});
  }

  $_[0] = undef;
}


######################################################################
# PRIVATE DEFINITIONS


sub _open_document {
  my ($parser, $parse_object, $object_type, $dir, %args) = @_;
  $object_type ||= "FILENAME";
  %args = (%{$parser->{DOMparser_args}}, (%args || ()));
  my $doc;

  print " "x$parser->{indent},"opening document of type $object_type...$/" if $parser->{debug};

  # A filename or a filehandle/stream could be passed
  if ($object_type =~ /^FILE/i) {
    if (ref (\$parse_object) !~ /^SCALAR/i) {
      # it is not a filename, let XML::Parser take care of it
      $doc = $parser->{DOMparser}->parse ($parse_object, %args);
    } else {
      # it is a filename. http:? file:? relative path?
      ($doc, $dir) = $parser->_open_by_filename ($parse_object, $dir, %args);
    }

  # but a DOM tree could be passed as well    
  } elsif ($object_type =~ /^DOM/i) {
    if (ref ($parse_object) =~ /^XML::DOM::Document/i) {
      $doc = $parse_object;
    } else {
      die ("Error: pass a DOM Document node to open_project when passing a DOM tree$/");
    }

  # or a scalar or even a scalar ref!
  } elsif ($object_type =~ /^STRING/i) {
    if (ref ($parse_object) =~ /^SCALAR/i) {
      $doc = $parser->{DOMparser}->parse ($$parse_object, %args);
    } else {
      $doc = $parser->{DOMparser}->parse ($parse_object, %args);
    }

  # I don't know, it's not FILE, STRING nor DOM
  } else {
    die ("Error: cannot open documents of type \"$object_type\"$/");
  }

  return ($doc, $dir);
}

  # private auxiliary function #
  sub _open_by_filename {
    my ($parser, $filename, $dir, %args) = @_;
    my $doc;

    # it's a http link!
    if ($filename =~ /^http:/i) {
      my $request = HTTP::Request->new (GET => $filename);
      my $result = LWP::UserAgent->new()->request($request);

      if ($result->is_success) {
	$doc = $parser->{DOMparser}->parse ($result->content, %args);
      } else {
	die ("Error: cannot open document from URL \"$filename\"$/");
      }

      $dir = $filename;
      $dir =~ s/\/[^\/]+$//i;

    # no? then it must be a file path...
    } else {
      $filename =~ s/^file://i;

      if ($filename =~ /^\//i) {
	$dir = $filename;
	$dir =~ s/\/[^\/]+$//i;
      } else {
	$filename = "$dir/$filename";
      }

      if (-f $filename) {
	$doc = $parser->{DOMparser}->parsefile ($filename, %args);
      } else {
	die ("Error: cannot open document from path \"$filename\"$/");
      }
    }

    return ($doc, $dir);
  }

sub _match_template {
  my ($parser, $attribute_name, $select_value, $xml_count, $xml_selection_path,
      $mode) = @_;
  $mode ||= "";
  
  my $template = "";
  my @template_matches = ();

  print " "x$parser->{indent},"matching template for \"$select_value\" with count $xml_count and path \"$xml_selection_path\":$/" if $parser->{debug};
  
  if ($attribute_name eq "match") {
    @template_matches = @{$parser->{template_matches}};
  } elsif ($attribute_name eq "name") {
    @template_matches = @{$parser->{template_names}};
  }

  # note that the order of @template_matches is the reverse of $parser->{templates}
  my $count = @template_matches;
  foreach my $original_match (@template_matches) {
    # templates with no match or name or with both simultaniuously
    # have no $template_match value
    if ($original_match) {
      my $full_match = $original_match;

      # multipe match? (for example: match="*|/")
      while ($full_match =~ s/^(.+?)\|//i) {
        my $match = $1;
        if (&__template_matches__ ($match, $select_value, $xml_count,
                                   $xml_selection_path)) {
	  print " "x$parser->{indent},"  found #$count with \"$match\" in \"$original_match\" $/" if $parser->{debug};
	  $template = ${$parser->{templates}}[$count-1];
  return $template;
#	  last;
        }
      }

      # last match?
      if (!$template) {
        if (&__template_matches__ ($full_match, $select_value, $xml_count,
                                   $xml_selection_path)) {
          print " "x$parser->{indent},"  found #$count with \"$full_match\" in \"$original_match\"$/" if $parser->{debug};
          $template = ${$parser->{templates}}[$count-1];
  return $template;
#          last;
        } else {
          print " "x$parser->{indent},"  #$count \"$original_match\" did not match$/" if $parser->{debug};
        }
      }
    }
    $count--;
  }

  if (! $template) {
    print "no template found! $/" if $parser->{debug};
    warn "No template matching $xml_selection_path found !!$/" if $parser->{warnings};
  }

  return $template;
}

  # auxiliary function #
  sub __template_matches__ {
    my ($template, $select, $count, $path) = @_;
    
    my $nocount_path = $path;
    $nocount_path =~ s/\[.*?\]//ig;

    if (($template eq $select) || ($template eq $path)
    || ($template eq "$select\[$count\]") || ($template eq "$path\[$count\]")) {
      # perfect match or path ends with templates match
#print "perfect match",$/;
      return "True";
    } elsif ( ($template eq substr ($path, - length ($template)))
           || ($template eq substr ($nocount_path, - length ($template)))
           || ("$template\[$count\]" eq substr ($path, - length ($template)))
           || ("$template\[$count\]" eq substr ($nocount_path, - length ($template)))
            ) {
      # template matches tail of path matches perfectly
#print "perfect tail match",$/;
      return "True";
    } elsif ($select =~ /\[\s*(\@.*?)\s*=\s*(.*?)\s*\]$/i) {
      # match attribute test
      my $attribute = $1;
      my $value = $2;
      return ""; # False, no test evaluation yet #
    } elsif ($select =~ /\[\s*(.*?)\s*=\s*(.*?)\s*\]$/i) {
      # match test
      my $element = $1;
      my $value = $2;
      return ""; # False, no test evaluation yet #
    } elsif ($select =~ /(\@\*|\@[\w\.\-\:]+)$/i) {
      # match attribute
      my $attribute = $1;
#print "attribute match?",$/;
      return (($template eq '@*') || ($template eq $attribute)
           || ($template eq "\@*\[$count\]") || ($template eq "$attribute\[$count\]"));
    } elsif ($select =~ /(\*|[\w\.\-\:]+)$/) {
      # match element
      my $element = $1;
#print "element match?",$/;
      return (($template eq "*") || ($template eq $element)
           || ($template eq "*\[$count\]") || ($template eq "$element\[$count\]"));
    } else {
      return ""; # False #
    }
  }

sub _evaluate_template {
  my ($parser, $template, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  print " "x$parser->{indent},"evaluating template content with current path \"$current_xml_selection_path\": $/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

    $template->normalize();
    foreach my $child ($template->getChildNodes) {
      my $ref = ref $child;

      print " "x$parser->{indent},"$ref$/" if $parser->{debug};
      $parser->{indent} += $parser->{indent_incr};
        my $node_type = $child->getNodeType;
        if ($node_type == $ELEMENT_NODE) {
          $parser->_evaluate_element ($child, $current_xml_node,
                                      $current_xml_selection_path,
                                      $current_result_node, $variables, $oldvariables);
        } elsif ($node_type == $TEXT_NODE) {
          # strip whitespace here?
          $parser->_add_node ($child, $current_result_node);
        } elsif ($node_type == $CDATA_SECTION_NODE) {
          my $text = $parser->{xml}->createTextNode ($child->getData);
          $parser->_add_node($text, $current_result_node);
        } elsif ($node_type == $ENTITY_REFERENCE_NODE) {
          $parser->_add_node($child, $current_result_node);
        } elsif ($node_type == $DOCUMENT_TYPE_NODE) {
          # skip #
          print " "x$parser->{indent},"Skipping Document Type node...$/" if $parser->{debug};
        } elsif ($node_type == $COMMENT_NODE) {
          # skip #
          print " "x$parser->{indent},"Skipping Comment node...$/" if $parser->{debug};
        } else {
          print " "x$parser->{indent},"Cannot evaluate node of type $ref !$/" if $parser->{debug};
          warn ("evaluate-template: Dunno what to do with node of type $ref !!! ($current_xml_selection_path)$/") if $parser->{warnings};
        }

      $parser->{indent} -= $parser->{indent_incr};
    }

    print " "x$parser->{indent},"done!$/" if $parser->{debug};
  $parser->{indent} -= $parser->{indent_incr};
}

sub _add_node {
  my ($parser, $node, $parent, $deep, $owner) = @_;
  $deep ||= ""; # False #
  $owner ||= $parser->{xml};

  print " "x$parser->{indent},"adding node (deep)..$/" if $parser->{debug} && $deep;
  print " "x$parser->{indent},"adding node (non-deep)..$/" if $parser->{debug} && !$deep;

  $node = $node->cloneNode($deep);
  $node->setOwnerDocument($owner);
  $parent->appendChild($node);
}

sub _apply_templates {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  my $children;
  my $newvariables = {()};
  
  my $select = $xsl_node->getAttribute ('select');
  
  if ($select =~ /\$/) {
    # replacing occurences of variables:
    foreach my $varname (keys (%$variables)) {
      $select =~ s/[^\\]\$$varname/$$variables{$varname}/g;
    }
  }
  
  if ($select) {
    print " "x$parser->{indent},"applying templates on children $select of \"$current_xml_selection_path\":$/" if $parser->{debug};
    $children = $parser->_get_node_set ($select, $parser->{xml},
                                        $current_xml_selection_path,
    					$current_xml_node, $variables);
  } else {
    print " "x$parser->{indent},"applying templates on all children of \"$current_xml_selection_path\":$/" if $parser->{debug};
    my @children = $current_xml_node->getChildNodes;
    $children = \@children;
  }

  $parser->_process_with_params ($xsl_node, $current_xml_node,
      				 $current_xml_selection_path,
                                 $current_result_node, $variables, $oldvariables);

  # process xsl:sort here

  $parser->{indent} += $parser->{indent_incr};

    my $count = 1;
    foreach my $child (@$children) {
      my $node_type = $child->getNodeType;
    
      if ($node_type == $DOCUMENT_TYPE_NODE) {
        # skip #
        print " "x$parser->{indent},"Skipping Document Type node...$/" if $parser->{debug};
      } elsif ($node_type == $DOCUMENT_FRAGMENT_NODE) {
        # skip #
        print " "x$parser->{indent},"Skipping Document Fragment node...$/" if $parser->{debug};
      } elsif ($node_type == $NOTATION_NODE) {
        # skip #
        print " "x$parser->{indent},"Skipping Notation node...$/" if $parser->{debug};
      } else {

	my $newselect = "";
        my $newcount = $count;
        if (!$select) {
          if ($node_type == $ELEMENT_NODE) {
	    $newselect = $child->getTagName;
          } elsif ($node_type == $ATTRIBUTE_NODE) {
            $newselect = "@$child->getName";
          } elsif (($node_type == $TEXT_NODE) || ($node_type == $ENTITY_REFERENCE_NODE)) {
            $newselect = "text()";
          } elsif ($node_type == $PROCESSING_INSTRUCTION_NODE) {
            $newselect = "processing-instruction()";
          } elsif ($node_type == $COMMENT_NODE) {
            $newselect = "comment()";
          } else {
            my $ref = ref $child;
            print " "x$parser->{indent},"Unknown node encountered: $ref$/" if $parser->{debug};
          }
	} else {
          $newselect = $select;
          if ($newselect =~ s/\[(\d+)\]$//) {
            $newcount = $1;
          }
        }

        $parser->_select_template ($child, $newselect, $newcount,
                                   $current_xml_node,
                                   $current_xml_selection_path,
                                   $current_result_node, $newvariables, $variables);
      }
      $count++;
    }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _for_each {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $select = $xsl_node->getAttribute ('select');
  
  if ($select =~ /\$/) {
    # replacing occurences of variables:
    foreach my $varname (keys (%$variables)) {
      $select =~ s/[^\\]\$$varname/$$variables{$varname}/g;
    }
  }
  
  if ($select) {
    print " "x$parser->{indent},"applying template for each child $select of \"$current_xml_selection_path\":$/" if $parser->{debug};
    my $children = $parser->_get_node_set ($select, $parser->{xml},
                                           $current_xml_selection_path,
    					   $current_xml_node, $variables);
    $parser->{indent} += $parser->{indent_incr};
      my $count = 1;
      foreach my $child (@$children) {
	my $node_type = $child->getNodeType;

        if ($node_type == $DOCUMENT_TYPE_NODE) {
          # skip #
          print " "x$parser->{indent},"Skipping Document Type node...$/" if $parser->{debug};
        } elsif ($node_type == $DOCUMENT_FRAGMENT_NODE) {
          # skip #
          print " "x$parser->{indent},"Skipping Document Fragment node...$/" if $parser->{debug};
        } elsif ($node_type == $NOTATION_NODE) {
          # skip #
          print " "x$parser->{indent},"Skipping Notation node...$/" if $parser->{debug};
        } else {

          $parser->_evaluate_template ($xsl_node, $child,
                                       "$current_xml_selection_path/$select\[$count\]",
                                       $current_result_node, $variables, $oldvariables);
	}
	$count++;
      }

    $parser->{indent} -= $parser->{indent_incr};
  } else {
    print " "x$parser->{indent},"expected attribute \"select\" in <$parser->{xsl_ns}for-each>$/" if $parser->{debug};
    warn "expected attribute \"select\" in <$parser->{xsl_ns}for-each>$/" if $parser->{warnings};
  }

}

sub _select_template {
  my ($parser, $child, $select, $count, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $ref = ref $child if $parser->{debug};
  print " "x$parser->{indent},"selecting template $select for child type $ref of \"$current_xml_selection_path\":$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

    my $child_xml_selection_path = "$current_xml_selection_path/$select";
    my $template = $parser->_match_template ("match", $select, $count,
                                             $child_xml_selection_path);

    if ($template) {

        $parser->_evaluate_template ($template,
		 	             $child,
                                     "$child_xml_selection_path\[$count\]",
                                     $current_result_node, $variables, $oldvariables);
    } else {
      print " "x$parser->{indent},"skipping template selection...$/" if $parser->{debug};
    }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _evaluate_element {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $xsl_tag = $xsl_node->getTagName;
  print " "x$parser->{indent},"evaluating element $xsl_tag from \"$current_xml_selection_path\": $/" if $parser->{debug};
  $parser->{indent} += $parser->{indent_incr};

  if ($xsl_tag =~ /^$parser->{xsl_ns}/i) {
      if ($xsl_tag =~ /^$parser->{xsl_ns}apply-templates$/i) {
          $parser->_apply_templates ($xsl_node, $current_xml_node,
        			     $current_xml_selection_path,
                                     $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}attribute$/i) {
          $parser->_attribute ($xsl_node, $current_xml_node,
        		       $current_xml_selection_path,
                               $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}call-template$/i) {
          $parser->_call_template ($xsl_node, $current_xml_node,
        			   $current_xml_selection_path,
                                   $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}choose$/i) {
          $parser->_choose ($xsl_node, $current_xml_node,
        		    $current_xml_selection_path,
                            $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}comment$/i) {
          $parser->_comment ($xsl_node, $current_xml_node,
        		     $current_xml_selection_path,
                             $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}copy$/i) {
          $parser->_copy ($xsl_node, $current_xml_node,
        		  $current_xml_selection_path,
                          $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}copy-of$/i) {
          $parser->_copy_of ($xsl_node, $current_xml_node,
        		     $current_xml_selection_path,
                             $current_result_node, $variables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}for-each$/i) {
          $parser->_for_each ($xsl_node, $current_xml_node,
        		      $current_xml_selection_path,
                              $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}if$/i) {
          $parser->_if ($xsl_node, $current_xml_node,
        		$current_xml_selection_path,
                        $current_result_node, $variables, $oldvariables);

#      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}output$/i) {

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}param$/i) {
          $parser->_variable ($xsl_node, $current_xml_node,
                              $current_xml_selection_path,
                              $current_result_node, $variables, $oldvariables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}processing-instruction$/i) {
          $parser->_processing_instruction ($xsl_node, $current_result_node);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}text$/i) {
          $parser->_text ($xsl_node, $current_result_node);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}value-of$/i) {
          $parser->_value_of ($xsl_node, $current_xml_node,
                              $current_xml_selection_path,
                              $current_result_node, $variables);

      } elsif ($xsl_tag =~ /^$parser->{xsl_ns}variable$/i) {
          $parser->_variable ($xsl_node, $current_xml_node,
                              $current_xml_selection_path,
                              $current_result_node, $variables, $oldvariables);

      } else {
          $parser->_add_and_recurse ($xsl_node, $current_xml_node,
                                     $current_xml_selection_path,
                                     $current_result_node, $variables, $oldvariables);
      }
  } else {

      $parser->_check_attributes_and_recurse ($xsl_node, $current_xml_node,
                                              $current_xml_selection_path,
                                              $current_result_node, $variables, $oldvariables);
  }

  $parser->{indent} -= $parser->{indent_incr};
}

  sub _add_and_recurse {
    my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
        $current_result_node, $variables, $oldvariables) = @_;

    # the addition is commented out to prevent unknown xsl: commands to be printed in the result
    #$parser->_add_node ($xsl_node, $current_result_node);
    $parser->_evaluate_template ($xsl_node, $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node, $variables, $oldvariables);#->getLastChild);
  }

  sub _check_attributes_and_recurse {
    my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
        $current_result_node, $variables, $oldvariables) = @_;

    $parser->_add_node ($xsl_node, $current_result_node);
    $parser->_attribute_value_of ($current_result_node->getLastChild,
    				  $current_xml_node,
                                  $current_xml_selection_path, $variables);
    $parser->_evaluate_template ($xsl_node, $current_xml_node,
                                 $current_xml_selection_path,
                                 $current_result_node->getLastChild, $variables, $oldvariables);
  }

sub _value_of {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables) = @_;

  my $select = $xsl_node->getAttribute('select');
  my $xml_node;

  if ($select) {
  
    $xml_node = $parser->_get_node_set ($select, $parser->{xml},
                                        $current_xml_selection_path,
                                        $current_xml_node, $variables);

    print " "x$parser->{indent},"stripping node to text:$/" if $parser->{debug};

    $parser->{indent} += $parser->{indent_incr};
      my $text = "";
      $text = $parser->__string__ ($$xml_node[0]) if @$xml_node;
    $parser->{indent} -= $parser->{indent_incr};

    if ($text) {
      $parser->_add_node ($parser->{xml}->createTextNode($text), $current_result_node);
    } else {
      print " "x$parser->{indent},"nothing left..$/" if $parser->{debug};
    }
  } else {
    print " "x$parser->{indent},"expected attribute \"select\" in <$parser->{xsl_ns}value-of>$/" if $parser->{debug};
    warn "expected attribute \"select\" in <$parser->{xsl_ns}value-of>$/" if $parser->{warnings};
  }
}

  sub __strip_node_to_text__ {
    my ($parser, $node) = @_;
    
    my $result = "";

    my $node_type = $node->getNodeType;
    if ($node_type == $TEXT_NODE) {
      $result = $node->getData;
    } elsif (($node_type == $ELEMENT_NODE)
         || ($node_type == $DOCUMENT_FRAGMENT_NODE)) {
      $parser->{indent} += $parser->{indent_incr};
      foreach my $child ($node->getChildNodes) {
        $result .= &__strip_node_to_text__ ($parser, $child);
      }
      $parser->{indent} -= $parser->{indent_incr};
    }
    return $result;
  }

  sub __string__ {
    my ($parser, $node) = @_;
    
    my $result = "";

    if ($node) {
      my $ref = (ref ($node) || "ARRAY") if $parser->{debug};
      print " "x$parser->{indent},"stripping child nodes ($ref):$/" if $parser->{debug};

      $parser->{indent} += $parser->{indent_incr};

        if ($node =~ /ARRAY/) {
          return $parser->__string__ ($$node[0]);
        } else {
          my $node_type = $node->getNodeType;

          if (($node_type == $ELEMENT_NODE)
          || ($node_type == $DOCUMENT_FRAGMENT_NODE)
          || ($node_type == $DOCUMENT_NODE)) {
            foreach my $child ($node->getChildNodes) {
	      $result .= &__string__ ($parser, $child);
            }
          } elsif ($node_type == $ATTRIBUTE_NODE) {
	    $result .= $node->getValue;
          } elsif (($node_type == $TEXT_NODE)
          || ($node_type == $ENTITY_REFERENCE_NODE)) {
	    $result .= $node->getData;
          }
        }

        print " "x$parser->{indent},"  \"$result\"$/" if $parser->{debug};
      $parser->{indent} -= $parser->{indent_incr};
    } else {
      print " "x$parser->{indent}," no result$/" if $parser->{debug};
    }
 
    return $result;
  }

sub _move_node {
  my ($parser, $node, $parent) = @_;

  print " "x$parser->{indent},"moving node..$/" if $parser->{debug};

  $parent->appendChild($node);
}

sub _get_node_set {
  my ($parser, $path, $root_node, $current_path, $current_node, $variables,
      $silent) = @_;
  $current_path ||= "/";
  $current_node ||= $root_node;
  $silent ||= 0;
  
  print " "x$parser->{indent},"getting node-set \"$path\" from \"$current_path\":$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

    if ($path =~ /^\$([\w\.\-]+)$/) {
      my $varname = $1;
      my $var = $$variables{$varname};
      if ($var) {
        if ($$variables{$varname} =~ /^ARRAY/i) {
          # node-set array
          return $$variables{$varname};
        } elsif (ref ($$variables{$varname}) =~ /^XML::DOM::NodeList/i) {
          # node-set nodelist
          return [@{$$variables{$varname}}];
        } elsif (ref ($$variables{$varname}) =~ /^XML::DOM::DocumentFragment/i) {
          # node-set nodelist
          return [$$variables{$varname}->getChildNodes];
        } else {
          # string or number?
          return [$parser->{xml}->createTextNode ($$variables{$varname})];
        }
      } else {
        # var does not exist
        return [];
      }
    } elsif ($path eq $current_path || $path eq ".") {
      print " "x$parser->{indent},"direct hit!$/" if $parser->{debug};
      return [$current_node];
    } else {
      # open external documents first #
      if ($path =~ /^\s*document\s*\(["'](.*?)["']\s*(,\s*(.*)\s*){0,1}\)\s*(.*)$/i) {
        my $filename = $1;
        my $sec_arg = $3;
        $path = ($4 || "");

        print " "x$parser->{indent},"external selection (\"$filename\")!$/" if $parser->{debug};

        if ($sec_arg) {
	  print " "x$parser->{indent}," Ignoring second argument of $path$/" if $parser->{debug};
	  warn "Ignoring second argument of $path$/" if $parser->{warnings} && !$silent;
        }

        ($root_node) = $parser->_open_by_filename ($parser, $filename, $parser->{xsl_dir});
      }

      if ($path =~ /^\//) {
        # start from the root #
        $current_node = $root_node;
      } elsif ($path =~ /^\.\//) {
        # remove preceding dot from './etc' #
        $path =~ s/^\.//;
      } else {
        # to facilitate parsing, precede path with a '/' #
        $path = "/$path";
      }

      print " "x$parser->{indent},"using \"$path\": $/" if $parser->{debug};

      $current_node = &__get_node_set__ ($parser, $path, [$current_node], $silent);

    $parser->{indent} -= $parser->{indent_incr};
    
    return $current_node;
  }
}


  # auxiliary function #
  sub __get_node_set__ {
    my ($parser, $path, $node, $silent) = @_;

    # a Qname (?) should actually be: [a-Z_][\w\.\-]*\:[a-Z_][\w\.\-]*

    if ($path eq "" || $path eq "/") {

      print " "x$parser->{indent},"node found!$/" if $parser->{debug};
      return $node;

    } else {
      my $list = [];
      foreach my $item (@$node) {
        my $sublist = &__try_a_step__ ($parser, $path, $item, $silent);
        push (@$list, @$sublist);
      }
      return $list;
    }
  }

    sub __try_a_step__ {
      my ($parser, $path, $node, $silent) = @_;

      study ($path);
      if ($path =~ s/^\/\.\.\///) {
        # /.. #
        print " "x$parser->{indent},"getting parent (\"$path\")$/" if $parser->{debug};
        return &__parent__ ($parser, $path, $node, $silent);

      } elsif ($path =~ s/^\/(\*|[\w\.\:\-]+)\[(\S+?)\]//) {
        # /elem[n] #
        print " "x$parser->{indent},"getting indexed element $1 $2 (\"$path\")$/" if $parser->{debug};
        return &__indexed_element__ ($parser, $1, $2, $path, $node, $silent);

      } elsif ($path =~ s/^\/(\*|[\w\.\:\-]+)//) {
        # /elem #
        print " "x$parser->{indent},"getting element $1 (\"$path\")$/" if $parser->{debug};
        return &__element__ ($parser, $1, $path, $node, $silent);

      } elsif ($path =~ s/^\/\/(\*|[\w\.\:\-]+)\[(\S+?)\]//) {
        # //elem[n] #
        print " "x$parser->{indent},"getting deep indexed element $1 $2 (\"$path\")$/" if $parser->{debug};
        return &__indexed_element__ ($parser, $1, $2, $path, $node, $silent, "deep");

      } elsif ($path =~ s/^\/\/(\*|[\w\.\:\-]+)//) {
        # //elem #
        print " "x$parser->{indent},"getting deep element $1 (\"$path\")$/" if $parser->{debug};
        return &__element__ ($parser, $1, $path, $node, $silent, "deep");

      } elsif ($path =~ s/^\/\@(\*|[\w\.\:\-]+)//) {
        # /@attr #
        print " "x$parser->{indent},"getting attribute $1 (\"$path\")$/" if $parser->{debug};
        return &__attribute__ ($parser, $1, $path, $node, $silent);

      } elsif ($path =~ s/^\/text\(\)//) {
        # /text() #
        print " "x$parser->{indent},"getting text (\"$path\")$/" if $parser->{debug};
        return &__get_nodes__ ($parser, $TEXT_NODE, $path, $node, $silent);

      } elsif ($path =~ s/^\/processing-instruction\(\)//) {
        # /processing-instruction() #
        print " "x$parser->{indent},"getting processing instruction (\"$path\")$/" if $parser->{debug};
        return &__get_nodes__ ($parser, $PROCESSING_INSTRUCTION_NODE, $path, $node, $silent);

      } elsif ($path =~ s/^\/comment\(\)//) {
        # /comment() #
        print " "x$parser->{indent},"getting comment (\"$path\")$/" if $parser->{debug};
        return &__get_nodes__ ($parser, $COMMENT_NODE, $path, $node, $silent);

      } else {
        print " "x$parser->{indent},"dunno what to do with path $path !!!$/" if $parser->{debug};
        warn ("get-node-from-path: Dunno what to do with path $path !!!$/") if $parser->{warnings} && !$silent;
        return [];
      }
    }

    sub __parent__ {
        my ($parser, $path, $node, $silent) = @_;

        $parser->{indent} += $parser->{indent_incr};
          if (($node->getNodeType == $DOCUMENT_NODE)
            || ($node->getNodeType == $DOCUMENT_FRAGMENT_NODE)) {
            print " "x$parser->{indent},"no parent!$/" if $parser->{debug};
	    $node = [];
          } else {
            $node = $node->getParentNode;

            $node = &__get_node_set__ ($parser, $path, [$node], $silent);
          }
        $parser->{indent} -= $parser->{indent_incr};

        return $node;
    }

    sub __indexed_element__ {
        my ($parser, $element, $index, $path, $node, $silent, $deep) = @_;
	$index ||= 0;
        $deep ||= ""; # False #

        if ($index =~ /^first\s*\(\)/i) {
          $index = 0;
	} elsif ($index =~ /^last\s*\(\)/i) {
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

        $parser->{indent} += $parser->{indent_incr};
          if ($node) {
            $node = &__get_node_set__ ($parser, $path, [$node], $silent);
          } else {
            print " "x$parser->{indent},"failed!$/" if $parser->{debug};
	    $node = [];
          }
        $parser->{indent} -= $parser->{indent_incr};

        return $node;
    }

    sub __element__ {
        my ($parser, $element, $path, $node, $silent, $deep) = @_;
        $deep ||= ""; # False #

        $node = [$node->getElementsByTagName($element, $deep)];

        $parser->{indent} += $parser->{indent_incr};
          if (@$node) {
            $node = &__get_node_set__($parser, $path, $node, $silent);
          } else {
            print " "x$parser->{indent},"failed!$/" if $parser->{debug};
          }
        $parser->{indent} -= $parser->{indent_incr};

        return $node;
    }

    sub __attribute__ {
        my ($parser, $attribute, $path, $node, $silent) = @_;

        if ($attribute eq '*') {
          $node = $node->getAttributes->getValues;
        
          $parser->{indent} += $parser->{indent_incr};
            if ($node) {
              $node = &__get_node_set__ ($parser, $path, $node, $silent);
            } else {
              print " "x$parser->{indent},"failed!$/" if $parser->{debug};
            }
          $parser->{indent} -= $parser->{indent_incr};
        } else {
          $node = $node->getAttributeNode($attribute);
        
          $parser->{indent} += $parser->{indent_incr};
            if ($node) {
              $node = &__get_node_set__ ($parser, $path, [$node], $silent);
            } else {
              print " "x$parser->{indent},"failed!$/" if $parser->{debug};
              $node = [];
            }
          $parser->{indent} -= $parser->{indent_incr};
        }

	return $node;
    }

    sub __get_nodes__ {
        my ($parser, $node_type, $path, $node, $silent) = @_;

        my $result = [];

        $parser->{indent} += $parser->{indent_incr};
        foreach my $child ($node->getChildNodes) {
	  if ($child->getNodeType == $node_type) {
	    $result = [@$result, &__get_node_set__ ($parser, $path, [$child], $silent)];
	  }
	}
        $parser->{indent} -= $parser->{indent_incr};
	
	if (! @$result) {
	  print " "x$parser->{indent},"failed!$/" if $parser->{debug};
        }
        
	return $result;
    }


sub _attribute_value_of {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $variables) = @_;

  foreach my $attribute ($xsl_node->getAttributes->getValues) {
    my $value = $attribute->getValue;
    study ($value);
    #$value =~ s/(\*|\$|\@|\&|\?|\+|\\)/\\$1/g;
    $value =~ s/(\*|\?|\+)/\\$1/g;
    study ($value);
    while ($value =~ /\G[^\\]?\{(.*?[^\\]?)\}/) {
      my $node = $parser->_get_node_set ($1, $parser->{xml},
                                         $current_xml_selection_path,
                                         $current_xml_node, $variables);
      if (@$node) {
        $parser->{indent} += $parser->{indent_incr};
          my $text = $parser->__string__ ($$node[0]);
        $parser->{indent} -= $parser->{indent_incr};
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
  my ($parser, $xsl_node, $current_result_node, $variables, $oldvariables) = @_;

  my $new_PI_name = $xsl_node->getAttribute('name');

  if ($new_PI_name eq "xml") {
    print " "x$parser->{indent},"<$parser->{xsl_ns}processing-instruction> may not be used to create XML$/" if $parser->{debug};
    print " "x$parser->{indent},"declaration. Use <$parser->{xsl_ns}output> instead...$/" if $parser->{debug};
    warn "<$parser->{xsl_ns}processing-instruction> may not be used to create XML$/" if $parser->{warnings};
    warn "declaration. Use <$parser->{xsl_ns}output> instead...$/" if $parser->{warnings};
  } elsif ($new_PI_name) {
    my $text = $parser->__string__ ($xsl_node);
    my $new_PI = $parser->{xml}->createProcessingInstruction($new_PI_name, $text);

    if ($new_PI) {
      $parser->_move_node ($new_PI, $current_result_node);
    }
  } else {
    print " "x$parser->{indent},"expected attribute \"name\" in <$parser->{xsl_ns}processing-instruction> !$/" if $parser->{debug};
    warn "Expected attribute \"name\" in <$parser->{xsl_ns}processing-instruction> !$/" if $parser->{warnings};
  }
}

sub _process_with_params {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $variables, $oldvariables) = @_;

  my @params = $xsl_node->getElementsByTagName("$parser->{xsl_ns}with-param");
  foreach my $param (@params) {
    my $varname = $param->getAttribute('name');

    if ($varname) {
      if ($$oldvariables{$varname}) {
        $$variables{$varname} = $$oldvariables{$varname};
      } else {
        my $value = $param->getAttribute('select');
        
        if (!$value) {
          # process content as template
          my $result = $parser->{xml}->createDocumentFragment;

          $parser->_evaluate_template ($param,
				       $current_xml_node,
				       $current_xml_selection_path,
				       $result, $variables, $oldvariables);

          $parser->{indent} += $parser->{indent_incr};
            $value = $parser->__string__ ($result);
          $parser->{indent} -= $parser->{indent_incr};

          $result->dispose();
        }
        
        $$variables{$varname} = $value;
      }
    } else {
      print " "x$parser->{indent},"expected attribute \"name\" in <$parser->{xsl_ns}with-param> !$/" if $parser->{debug};
      warn "Expected attribute \"name\" in <$parser->{xsl_ns}with-param> !$/" if $parser->{warnings};
    }

  }

}

sub _call_template {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  my $newvariables = {()};

  my $name = $xsl_node->getAttribute('name');
  
  if ($name) {
    print " "x$parser->{indent},"calling template named \"$name\"$/" if $parser->{debug};

    $parser->_process_with_params ($xsl_node, $current_xml_node,
      				   $current_xml_selection_path,
                                   $current_result_node, $variables, $oldvariables);

    $parser->{indent} += $parser->{indent_incr};
    my $template = $parser->_match_template ("name", $name, 0, '');

    if ($template) {
      $parser->_evaluate_template ($template, $current_xml_node,
      				   $current_xml_selection_path,
                                   $current_result_node, $variables, $oldvariables);
    } else {
      print " "x$parser->{indent},"no template found!$/" if $parser->{debug};
      warn "no template named $name found!$/" if $parser->{warnings};
    }
    $parser->{indent} -= $parser->{indent_incr};
  } else {
    print " "x$parser->{indent},"expected attribute \"name\" in <$parser->{xsl_ns}call-template/>$/" if $parser->{debug};
    warn "Expected attribute \"name\" in <$parser->{xsl_ns}call-template/>$/" if $parser->{warnings};
  }
}

sub _choose {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  print " "x$parser->{indent},"evaluating choose:$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

  my $notdone = "true";
  my $testwhen = "active";
  foreach my $child ($xsl_node->getElementsByTagName ('*', 0)) {
    if ($notdone && $testwhen && ($child->getTagName eq "$parser->{xsl_ns}when")) {
      my $test = $child->getAttribute ('test');

      if ($test) {
        my $test_succeeds = $parser->_evaluate_test ($test, $current_xml_node,
      						     $current_xml_selection_path,
                                                     $variables);
        if ($test_succeeds) {
          $parser->_evaluate_template ($child, $current_xml_node,
        			       $current_xml_selection_path,
                                       $current_result_node, $variables, $oldvariables);
          $testwhen = "";
          $notdone = "";
        }
      } else {
        print " "x$parser->{indent},"expected attribute \"test\" in <$parser->{xsl_ns}when>$/" if $parser->{debug};
        warn "expected attribute \"test\" in <$parser->{xsl_ns}when>$/" if $parser->{warnings};
      }
    } elsif ($notdone && ($child->getTagName eq "$parser->{xsl_ns}otherwise")) {
      $parser->_evaluate_template ($child, $current_xml_node,
        			   $current_xml_selection_path,
                                   $current_result_node, $variables, $oldvariables);
      $notdone = "";
    }
  }
  
  if ($notdone) {
  print " "x$parser->{indent},"nothing done!$/" if $parser->{debug};
  }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _if {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;

  print " "x$parser->{indent},"evaluating if:$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

    my $test = $xsl_node->getAttribute ('test');

    if ($test) {
      my $test_succeeds = $parser->_evaluate_test ($test, $current_xml_node,
      						   $current_xml_selection_path,
                                                   $variables);
      if ($test_succeeds) {
        $parser->_evaluate_template ($xsl_node, $current_xml_node,
        			     $current_xml_selection_path,
                                     $current_result_node, $variables, $oldvariables);
      }
    } else {
      print " "x$parser->{indent},"expected attribute \"test\" in <$parser->{xsl_ns}if>$/" if $parser->{debug};
      warn "expected attribute \"test\" in <$parser->{xsl_ns}if>$/" if $parser->{warnings};
    }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _evaluate_test {
  my ($parser, $test, $current_xml_node, $current_xml_selection_path,
      $variables) = @_;

  if ($test =~ /^(.+)\/\[(.+)\]$/) {
    my $path = $1;
    $test = $2;
    
    print " "x$parser->{indent},"evaluating test $test at path $path:$/" if $parser->{debug};

    $parser->{indent} += $parser->{indent_incr};
      my $node = $parser->_get_node_set ($path, $parser->{xml},
                                         $current_xml_selection_path,
                                         $current_xml_node, $variables);
      if (@$node) {
        $current_xml_node = $$node[0];
      } else {
        return "";
      }
    $parser->{indent} -= $parser->{indent_incr};
  } else {
    print " "x$parser->{indent},"evaluating path or test $test:$/" if $parser->{debug};
    my $node = $parser->_get_node_set ($test, $parser->{xml},
                                       $current_xml_selection_path,
                                       $current_xml_node, $variables, "silent");
    $parser->{indent} += $parser->{indent_incr};
      if (@$node) {
        print " "x$parser->{indent},"path exists!$/" if $parser->{debug};
        return "true";
      } else {
        print " "x$parser->{indent},"not a valid path, evaluating as test$/" if $parser->{debug};
      }
    $parser->{indent} -= $parser->{indent_incr};
  }

  $parser->{indent} += $parser->{indent_incr};
    my $result = &__evaluate_test__ ($test, $current_xml_node);
    if ($result) {
      print " "x$parser->{indent},"test evaluates true..$/" if $parser->{debug};
    } else {
      print " "x$parser->{indent},"test evaluates false..$/" if $parser->{debug};
    }
  $parser->{indent} -= $parser->{indent_incr};
  return $result;
}

  sub __evaluate_test__ {
    my ($test, $node) = @_;

#print "testing with \"$test\" and ", ref $node,$/;
    if ($test =~ /^\s*\@([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr ne $2);
    } elsif ($test =~ /^\s*\@([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
      my $attr = $node->getAttribute($1);
      return ($attr eq $2);
    } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*!=\s*['"](.*)['"]\s*$/) {
      $node->normalize;
      my $content = $node->getFirstChild->getValue;
      return ($content !~ /$2/m);
    } elsif ($test =~ /^\s*([\w\.\:\-]+)\s*=\s*['"](.*)['"]\s*$/) {
      $node->normalize;
      my $content = $node->getFirstChild->getValue;
      return ($content =~ /^\s*$2\s*/m);
    } else {
      return "";
    }
  }

sub _copy_of {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables) = @_;

  my $nodelist;
  my $select = $xsl_node->getAttribute('select');
  print " "x$parser->{indent},"evaluating copy-of with select \"$select\":$/" if $parser->{debug};
  
  $parser->{indent} += $parser->{indent_incr};
  if ($select) {
    $nodelist = $parser->_get_node_set ($select, $parser->{xml},
                                        $current_xml_selection_path,
    			  		$current_xml_node, $variables);
  } else {
    print " "x$parser->{indent},"expected attribute \"select\" in <$parser->{xsl_ns}copy-of>$/" if $parser->{debug};
    warn "expected attribute \"select\" in <$parser->{xsl_ns}copy-of>$/" if $parser->{warnings};
  }
  foreach my $node (@$nodelist) {
    $parser->_add_node ($node, $current_result_node, "deep");
  }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _copy {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;


  print " "x$parser->{indent},"evaluating copy:$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};
    if ($current_xml_node->getNodeType == $ATTRIBUTE_NODE) {
      my $attribute = $current_xml_node->cloneNode(0);
      $current_result_node->setAttributeNode($attribute);
    } elsif (($current_xml_node->getNodeType == $COMMENT_NODE)
    || ($current_xml_node->getNodeType == $PROCESSING_INSTRUCTION_NODE)) {
      $parser->_add_node ($current_xml_node, $current_result_node);
    } else {
      $parser->_add_node ($current_xml_node, $current_result_node);
      $parser->_evaluate_template ($xsl_node,
				   $current_xml_node,
				   $current_xml_selection_path,
				   $current_result_node->getLastChild,
                                   $variables, $oldvariables);
    }
  $parser->{indent} -= $parser->{indent_incr};
}

sub _text {
  #=item addText (text)
  #
  #Appends the specified string to the last child if it is a Text node, or else 
  #appends a new Text node (with the specified text.)
  #
  #Return Value: the last child if it was a Text node or else the new Text node.
  my ($parser, $xsl_node, $current_result_node) = @_;

  print " "x$parser->{indent},"inserting text:$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

    print " "x$parser->{indent},"stripping node to text:$/" if $parser->{debug};

    $parser->{indent} += $parser->{indent_incr};
      my $text = $parser->__string__ ($xsl_node);
    $parser->{indent} -= $parser->{indent_incr};

    if ($text) {
      $parser->_move_node ($parser->{xml}->createTextNode ($text), $current_result_node);
    } else {
      print " "x$parser->{indent},"nothing left..$/" if $parser->{debug};
    }

  $parser->{indent} -= $parser->{indent_incr};
}

sub _attribute {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  
  my $name = $xsl_node->getAttribute ('name');
  print " "x$parser->{indent},"inserting attribute named \"$name\":$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};
  if ($name) {
    my $result = $parser->{xml}->createDocumentFragment;

    $parser->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result, $variables, $oldvariables);

    $parser->{indent} += $parser->{indent_incr};
      my $text = $parser->__string__ ($result);
    $parser->{indent} -= $parser->{indent_incr};

    $current_result_node->setAttribute($name, $text);
    $result->dispose();
  } else {
    print " "x$parser->{indent},"expected attribute \"name\" in <$parser->{xsl_ns}attribute>$/" if $parser->{debug};
    warn "expected attribute \"name\" in <$parser->{xsl_ns}attribute>$/" if $parser->{warnings};
  }
  $parser->{indent} -= $parser->{indent_incr};
}

sub _comment {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  
  print " "x$parser->{indent},"inserting comment:$/" if $parser->{debug};

  $parser->{indent} += $parser->{indent_incr};

    my $result = $parser->{xml}->createDocumentFragment;

    $parser->_evaluate_template ($xsl_node,
				 $current_xml_node,
				 $current_xml_selection_path,
				 $result, $variables, $oldvariables);

    $parser->{indent} += $parser->{indent_incr};
      my $text = $parser->__string__ ($result);
    $parser->{indent} -= $parser->{indent_incr};

    $parser->_move_node ($parser->{xml}->createComment ($text), $current_result_node);
    $result->dispose();

  $parser->{indent} -= $parser->{indent_incr};
}

sub _variable {
  my ($parser, $xsl_node, $current_xml_node, $current_xml_selection_path,
      $current_result_node, $variables, $oldvariables) = @_;
  
  my $varname = $xsl_node->getAttribute ('name');
  
  if ($varname) {
    print " "x$parser->{indent},"definition of variable \$$varname:$/" if $parser->{debug};

    $parser->{indent} += $parser->{indent_incr};

      if ($$oldvariables{$varname}) {
        # copy from parent-template
        
        $$variables{$varname} = $$oldvariables{$varname};
        
      } else {
        # new variable definition
        
        my $value = $xsl_node->getAttribute ('select');

        if (! $value) {
          #tough case, evaluate content as template

          $value = $parser->{xml}->createDocumentFragment;

          $parser->_evaluate_template ($xsl_node,
				       $current_xml_node,
				       $current_xml_selection_path,
				       $value, $variables, $oldvariables);
        }
        
        $$variables{$varname} = $value;
      }

    $parser->{indent} -= $parser->{indent_incr};
  } else {
    print " "x$parser->{indent},"expected attribute \"name\" in <$parser->{xsl_ns}param> or <$parser->{xsl_ns}variable>$/" if $parser->{debug};
    warn "expected attribute \"name\" in <$parser->{xsl_ns}param> or <$parser->{xsl_ns}variable>$/" if $parser->{warnings};
  }
}

1;

__END__


=head1 NAME

XML::XSLT - A perl module for processing XSLT

=head1 SYNOPSIS

 use XML::XSLT;

 my $parser = XML::XSLT->new ($xslfile, $xslflag, warnings => "Active");

 $parser->transform_document ($xmlfile, $xmlflag);
 $parser->print_result;  

 $parser->dispose ();

	The variables $xmlfile and $xslfile are filenames, e.g. "filename",
        regular Perl filehandles, pass those with *FILEHANDLE, or Perl streams.

        After dispose, the parser object is destroyed. The result thus also!

# Alternative sources

The stylesheets and the documents may be passed as filenames, file handles
regular strings, string references or DOM-trees. The source type is identified
by the flags "FILE" (filename and -handle), "STRING" (string and string ref)
and "DOM" (DOM-tree). For example:
 
 my $parser = XML::XSLT->new ($xslstring, "STRING", warnings => "Active");

 $parser->transform_document ($xmldom_rootnode, "DOM");
 $parser->print_result;

# Alternatives for print_result()

Instead of printing to STDOUT, a filename or file can be passed to
print_result():

 $parser->print_result($outputfile);

        The variable $outputfile is a filename, e.g. "filename" or a regular
        Perl filehandle. Pass the latter with *FILEHANDLE.

Instead of printing at all, the result can be requested as a string or a DOM
tree as well with:

 $parser->result_string;
 
 $parser->result_tree;

# Reusable parser objects

This approach attaches one stylesheet to one parser object. The stylesheet can
be applied to multiple documents and multiple parser objects can co-exist:

 my $parser1 = XML::XSLT->new ($xslfile1, $xslflag1, warnings => "Active");
 my $parser2 = XML::XSLT->new ($xslfile2, $xslflag2, warnings => "Active");

 $parser1->transform_document ($xmlfile1, $xmlflag1);
 $parser1->print_result ($xmlout1);
 $parser1->transform_document ($xmlfile2, $xmlflag2);
 $parser1->print_result ($xmlout2);  
 $parser2->transform_document ($xmlfile1, $xmlflag1);
 $parser2->print_result ($xmlout3);  
 $parser2->transform_document ($xmlfile2, $xmlflag2);
 $parser2->print_result ($xmlout4);  

This way the stylesheet-file does not have to be parsed all over again, but is
reused each time.

=head1 DESCRIPTION

This module implements the W3C's XSLT specification. The goal
is full implementation of this spec, but it isn't yet. However,
it already works well. Below is given the set of working xslt
commands.

XML::XSLT makes use of XML::DOM and LWP::UserAgent, while XML::DOM uses XML::Parser.
Therefore XML::Parser, XML::DOM and LWP::UserAgent have to be installed properly
for XML::XSLT to run.

=head1 LICENCE

Copyright (c) 1999 Geert Josten & Egon Willighagen. All Rights Reserverd.
This module is free software, and may be distributed under the
same terms and conditions as Perl.


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

=head2 xsl:element			no

Not supported yet.

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

=head2 xsl:text				partially

Not supported yet:
- attribute 'disable-output-escaping'

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

and combinations of these;

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

Support can be obtained from the XML::XSLT mailling list:

  http://xmlxslt.listbot.com/

General information, like bugs and current functionality, can
be found at the XML::XSLT homepage:

  http://www.sci.kun.nl/sigma/Persoonlijk/egonw/xslt/

=cut
