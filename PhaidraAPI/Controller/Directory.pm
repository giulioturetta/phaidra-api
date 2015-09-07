package PhaidraAPI::Controller::Directory;

use strict;
use warnings;
use v5.10;
use PhaidraAPI::Model::Uwmetadata;

use base 'Mojolicious::Controller';

sub get_org_units {
    my $self = shift;  	

	my $parent_id = $self->param('parent_id');
	my $values_namespace = $self->param('values_namespace');
	
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $terms = $metadata_model->get_org_units_terms($self, $parent_id, $values_namespace);
	
	# there are only results
    $self->render(json => { terms => $terms }, status => 200 );
}

sub get_parent_org_unit_id {
    my $self = shift;  	
	my $child_id = $self->param('child_id');		
	my $parent_id = $self->app->directory->get_parent_org_unit_id($self, $child_id);	
    $self->render(json => { parent_id => $parent_id }, status => 200 );
}

sub get_study {
    my $self = shift;  	

	my $spl = $self->param('spl');
	my @ids = $self->param('ids');
	my $values_namespace = $self->param('values_namespace');
	
	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $terms = $metadata_model->get_study_terms($self, $spl, \@ids, $values_namespace);

    $self->render(json => { terms => $terms }, status => 200 );
}

sub get_study_name {
    my $self = shift;  	

	my $spl = $self->param('spl');
	my @ids = $self->param('ids');

	my $metadata_model = PhaidraAPI::Model::Uwmetadata->new;	
	my $names = $metadata_model->get_study_name($self, $spl, \@ids);
	
    $self->render(json => { study_name => $names }, status => 200 );
}

sub get_user_name {
    my $self = shift;  	
	
	my $username = $self->stash('username');

	my $name = $self->app->directory->get_name($self, $username);
	
    $self->render(json => { name => $name }, status => 200 );
}

sub get_user_email {
    my $self = shift;  	

	my $username = $self->stash('username');

	my $email = $self->app->directory->get_email($self, $username);
	
    $self->render(json => { email => $email }, status => 200 );
}

sub get_user_data {
    my $self = shift;  	

	my $username = $self->stash('username');

	my $user_data = $self->app->directory->get_user_data($self, $username);
	
    $self->render(json => { user_data => $user_data }, status => 200 );
}

sub search_user {
    my $self = shift;  	

	my $q = $self->param('q');

	my ($r, $hits) = $self->app->directory->search_user($self, $q);
	
    $self->render(json => { accounts => $r, hits => $hits }, status => 200 );
}


1;
