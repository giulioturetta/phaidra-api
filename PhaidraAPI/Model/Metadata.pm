package PhaidraAPI::Model::Metadata;

use strict;
use warnings;
use v5.10;
use base qw/Mojo::Base/;

sub metadata_format {
	
    my ($self, $c, $v) = @_;
 
 	if($v eq '1'){
 		return $self->get_metadata_format($c);	
 	}else{ 		
 		$c->stash( 'message' => 'Unknown metadata format version requested.');
 		$c->app->log->error($c->stash->{'message'}); 		
		return -1;
 	}
  
}

sub get_metadata_format {
	
	my ($self, $c) = @_;
	
	my %format;
	my @metadata_format;
	my %id_hash;
	
	my $sth;
	my $ss;
	
	$ss = qq/SELECT 
			m.MID, m.VEID, m.xmlname, m.xmlns, m.lomref, 
			m.searchable, m.mandatory, m.autofield, m.editable, m.OID,
			m.datatype, m.valuespace, m.MID_parent, m.cardinality, m.ordered, m.fgslabel,
			m.VID, m.defaultvalue, m.sequence
			FROM metadata m
			ORDER BY m.sequence ASC/;
	$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
	$sth->execute();
	
	my $mid; # id of the element 
	my $veid; # id of the vocabulary entry defining the label of the element (in multiple languages)
	my $xmlname; # name of the element (name and namespace constitute URI)
	my $xmlns; # namespace of the element (name and namespace constitute URI)
	my $lomref; # id in LOM schema (if the element comes from LOM)
	my $searchable; # 1 if the element is visible in advanced search
	my $mandatory; # 1 if the element is mandatory
	my $autofield; # ? i found no use for this one
	my $editable; # 1 if the element is availablein metadataeditor
	my $oid; # this was meant for metadata-owner feature 
	my $datatype; # Phaidra datatype (/usr/local/fedora/cronjobs/XSD/datatypes.xsd)
	my $valuespace; # regex constraining the value
	my $mid_parent; # introduces structure, eg firstname is under entity, etc
	my $cardinality; # eg 1, 2, * - any
	my $ordered; # Y if the order of elements have to be preserved (eg entity is ordered as the order of authors is important)
	my $fgslabel; # label for the search engine (is used in index and later in search queries)
	my $vid; # if defined then id of the controlled vocabulary which represents the possible values
	my $defaultvalue; # currently there's only #FIRSTNAME, #LASTNAME and #TODAY or NULL
	my $sequence; # order of the element among it's siblings
	
	$sth->bind_columns(undef, \$mid, \$veid, \$xmlname, \$xmlns, \$lomref, \$searchable, \$mandatory, \$autofield, \$editable, \$oid, \$datatype, \$valuespace, \$mid_parent, \$cardinality, \$ordered, \$fgslabel, \$vid, \$defaultvalue, \$sequence);
	
	# fill the hash with raw table data
	while($sth->fetch) {		
		$format{$mid} = { veid => $veid, xmlname => $xmlname, xmlns => $xmlns, lomref => $lomref, searchable => $searchable, mandatory => $mandatory, autofield => $autofield, editable => $editable, oid => $oid, datatype => $datatype, valuespace => $valuespace, mid_parent => $mid_parent, cardinality => $cardinality, ordered => $ordered, fgslabel => $fgslabel, vid => $vid, defaultvalue => $defaultvalue, sequence => $sequence };
		$id_hash{$mid} = $format{$mid}; # we will use this later for direct id -> element access 		
	}
	
	# create the hierarchy
	my @todelete;
	my %parents;
	foreach my $key (keys %format){
		if($format{$key}{mid_parent}){
			$parents{$format{$key}{mid_parent}} = $format{$format{$key}{mid_parent}};
			push @todelete, $key;
			push @{$format{$format{$key}{mid_parent}}{children}}, $format{$key};			
		}
	}	
	delete @format{@todelete};
	
	# now just as children are just an array, also the top level will be only an array
	# we do this because we don't want to hardcode the mids anywhere
	# we should just work with namespace and name
	while ( my ($key, $element) = each %format ){	
		push @metadata_format, $element;
	}
	
	# and sort it
	@metadata_format = sort { $a->{sequence} <=> $b->{sequence} } @metadata_format;	
	
	# and sort the children
	foreach my $key (keys %parents){
		@{$id_hash{$key}{children}} = sort { $a->{sequence} <=> $b->{sequence} } @{$parents{$key}{children}};		
	}
	
	# get the element labels
	$ss = qq/SELECT m.mid, ve.entry, ve.isocode FROM metadata AS m LEFT JOIN vocabulary_entry AS ve ON ve.veid = m.veid;/;
	$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
	$sth->execute();	
	
	my $entry; # element label (name of the field, eg 'Title')
	my $isocode; # 2 letter isocode defining language of the entry	
	
	$sth->bind_columns(undef, \$mid, \$entry, \$isocode);	
	while($sth->fetch) {
		$id_hash{$mid}{labels}{$isocode} = $entry; 			
	}

	# get the vocabularies (HINT: this crap will be overwritten when we have vocabulary server)
	while ( my ($key, $element) = each %id_hash ){	
		if($element->{vid}){
			
			my %vocabulary;
			
			# get vocabulary info
			$ss = qq/SELECT description FROM vocabulary WHERE vid = (?);/;
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute($element->{vid});
			
			my $desc; # some short text describing the vocabulary (it's not multilanguage, sorry)
			my $vocabulary_namespace; # there's none, i'm fabricating this
			
			$sth->bind_columns(undef, \$desc);
			$sth->fetch;
			
			$vocabulary{description} = $desc;
			$vocabulary{namespace} = $element->{xmlns}.'/voc_'.$element->{vid}.'/';
			
			# get vocabulary values/codes
			$ss = qq/SELECT veid, entry, isocode FROM vocabulary_entry WHERE vid = (?);/;
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute($element->{vid});
			
			my $veid; # the code, together with namespace this creates URI, that's the current hack
			my $entry; # value label (eg 'Wood-engraver')
			my $isocode; # 2 letter isocode defining language of the entry
			
			$sth->bind_columns(undef, \$veid, \$entry, \$isocode);
			
			# fetshing data using hash, so that we quickly find the place for the entry but later ... [x] 
			while($sth->fetch) {
				$vocabulary{'terms'}{$veid}{uri} = $vocabulary{namespace}.$veid; # this gets overwritten for the same entry
				$vocabulary{'terms'}{$veid}{$isocode} = $entry; # this should always contain another language for the same entry
			}
			
			# [x] ... we remove the id hash
			# because we should work with URI - namespace and code, ignoring the current 'id' structure
			my @termarray;
			while ( my ($key, $element) = each %{$vocabulary{'terms'}} ){	
				push @termarray, $element;
			}
			$vocabulary{'terms'} = \@termarray;
			
			# maybe we want to support multiple vocabularies for one field in future
			push @{$element->{vocabularies}}, \%vocabulary;
					
		}
	}
	
	# delete ids, we don't need them
	while ( my ($key, $element) = each %id_hash ){
		delete $element->{vid};
		delete $element->{veid};
		delete $element->{mid_parent};
	}

	return \@metadata_format;
}

sub get_metadata_format_old {
	
	my ($self, $c, $mid_parent) = @_;
	
	#return { root => 'tbd' };

	my $sth;
	my $ss;

	if (defined($mid_parent)) {
		$ss = qq/SELECT m.mid, m.mandatory, m.xmlname, m.xmlns, m.veid, m.lomref, m.searchable, m.autofield, m.editable, m.oid, m.datatype, m.mid_parent, m.cardinality, m.ordered, m.fgslabel, m.vid, m.defaultvalue, m.sequence, m.valuespace
			FROM metadata m
			WHERE m.mid_parent = ?
			ORDER BY m.sequence ASC/;
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute($mid_parent);
	} else {
		$ss = qq/SELECT m.mid, m.mandatory, m.xmlname, m.xmlns, m.veid, m.lomref, m.searchable, m.autofield, m.editable, m.oid, m.datatype, m.mid_parent, m.cardinality, m.ordered, m.fgslabel, m.vid, m.defaultvalue, m.sequence, m.valuespace
			FROM metadata m
			WHERE m.mid_parent is null
			ORDER BY m.sequence ASC/;
			$sth = $c->app->db_metadata->prepare($ss) or print $c->app->db_metadata->errstr;
			$sth->execute();
	}
	my ($mid, $mandatory, $xmlname, $xmlns, $veid, $lomref, $searchable, $autofield, $editable, $oid, $datatype, $mmid_parent, $cardinality, $ordered, $fgslabel, $vid, $defaultvalue, $sequence, $valuespace);
	$sth->bind_columns(undef, \$mid, \$mandatory, \$xmlname, \$xmlns, \$veid, \$lomref, \$searchable, \$autofield, \$editable, \$oid, \$datatype, \$mmid_parent, \$cardinality, \$ordered, \$fgslabel, \$vid, \$defaultvalue, \$sequence, \$valuespace);
	
	my $current_mid = -1;
	my $currentElement;
	my $root;
	
	while($sth->fetch) {
		
		# if $mid == $current_mid then this row is the same as the one before only with another description
		if($mid != $current_mid) {
			
			if(defined($currentElement)) {
				my $metadata_subs = $self->get_metadata_format($c, $current_mid);
				my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
				if ($children > 0) {
					push @{$currentElement->{metadatas}}, $metadata_subs;
				}
				push @{$root->{metadatas}}, $currentElement; 

			}
			
			$currentElement->{mandatory} = defined($mandatory) ? $mandatory : "";
			$currentElement->{ID} = defined($mid) ? $mid : "";
			$currentElement->{forxmlname} = defined($xmlname) ? $xmlname : "";
			$currentElement->{fornamespace} = defined($xmlns) ? $xmlns : "";
			$currentElement->{veid} = defined($veid) ? $veid : "";
			$currentElement->{lomref} = defined($lomref) ? $lomref : "";
			$currentElement->{searchable} = defined($searchable) ? $searchable : "";
			$currentElement->{autofield} = defined($autofield) ? $autofield : "";
			$currentElement->{editable} = defined($editable) ? $editable : "";
			$currentElement->{oid} = defined($oid) ? $oid : "";
			$currentElement->{datatype} = defined($datatype) ? $datatype : "";
			$currentElement->{mid_parent} = defined($mmid_parent) ? $mmid_parent : "";
			$currentElement->{cardinality} = defined($cardinality) ? $cardinality : "";
			$currentElement->{ordered} = defined($ordered) ? $ordered : "";
			$currentElement->{fgslabel} = defined($fgslabel) ? $fgslabel : "";
			$currentElement->{vid} = defined($vid) ? $vid : "";
			$currentElement->{defaultvalue} = defined($defaultvalue) ? $defaultvalue : "";
			$currentElement->{sequence} = defined($sequence) ? $sequence : "";
			$currentElement->{valuespace} = defined($valuespace) ? $valuespace : "";
			
			if($sth->rows <= 2)
            {
				my $metadata_subs = $self->get_metadata_format($c, $current_mid);
				my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
				if ($children > 0) {
					push @{$currentElement->{metadatas}}, $metadata_subs;
				}
				push @{$root->{metadatas}}, $currentElement;
			}
			
			$current_mid = $mid;
		}
	
	}
	push (@{$root->{metadatas}}, $currentElement) if(defined($currentElement));
	
	my $rootchildren = defined($root->{metadatas}) ? scalar @{$root->{metadatas}} : 0;
	my $tmpelmchildren = defined($currentElement->{metadatas}) ? scalar @{$currentElement->{metadatas}} : 0;
	if ($rootchildren > 0 && $tmpelmchildren > 0) {
		my $metadata_subs = $self->get_metadata_format($c, $current_mid);
		my $children = defined($metadata_subs->{metadatas}) ? scalar @{$metadata_subs->{metadatas}} : 0;
		if ($children > 0) {
			push @{$currentElement->{metadatas}}, $metadata_subs;
		}
		push @{$root->{metadatas}}, $currentElement;
	}
	
	return $root;
	
}

1;
__END__
