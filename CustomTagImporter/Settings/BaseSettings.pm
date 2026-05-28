#
# Custom Tag Importer
#
# (c) 2021 AF
#
# Custom Tag Importer
#
# (c) 2021 AF
#
# Portions of code derived from the CustomScan plugin by (c) 2006 Erland Isaksson
#
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::Settings::BaseSettings;

use strict;
use warnings;
use utf8;

use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

my $plugin;
my %subPages = ();

sub new {
	my $class = shift;
	$plugin = shift;
	my $default = shift;

	if (!defined($default) || !$default) {
		Slim::Web::Pages->addPageFunction($class->page, $class);
	} else {
		$class->SUPER::new();
	}
	$subPages{$class->name()} = $class;
	return $class;
}

sub handler {
	my ($class, $client, $params) = @_;

	my %currentSubPages = ();
	for my $key (keys %subPages) {
		my $pages = $subPages{$key}->pages($client,$params);
		for my $page (@{$pages}) {
			$currentSubPages{$page->{'name'}} = $page->{'page'};
		}
	}
	$params->{'subpages'} = \%currentSubPages;
	$params->{'subpage'} = $class->currentPage($client,$params);
	return $class->SUPER::handler($client, $params);
}

1;
