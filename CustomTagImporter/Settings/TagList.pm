#
# Custom Tag Importer
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::Settings::TagList;

use strict;
use warnings;
use utf8;

use base qw(Plugins::CustomTagImporter::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Strings qw(string cstring);

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

sub new {
	my ($class, $plugin) = @_;
	$class->SUPER::new($plugin);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CUSTOMTAGIMPORTER_TAGLIST');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/CustomTagImporter/settings/taglist.html');
}

sub currentPage {
	return name();
}

sub pages {
	return [{ 'name' => name(), 'page' => page() }];
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $dbh = Slim::Schema->storage->dbh();
	my %attrValues = ();
	my %attrTrackCount = ();

	eval {
		my ($attr, $value, $count);
		my $sth = $dbh->prepare("SELECT attr, value, count(DISTINCT id) FROM customtagimporter_track_attributes WHERE type = 'customtag' GROUP BY attr, value");
		$sth->execute();
		$sth->bind_columns(\$attr, \$value, \$count);
		while ($sth->fetch()) {
			# SQLite returns raw bytes, so decode them for correct display
			push @{$attrValues{Slim::Utils::Unicode::utf8decode($attr, 'utf8')}}, {
				'value' => Slim::Utils::Unicode::utf8decode($value // '', 'utf8'),
				'count' => $count,
			};
		}
		$sth->finish();

		$sth = $dbh->prepare("SELECT attr, count(DISTINCT track) FROM customtagimporter_track_attributes WHERE type = 'customtag' GROUP BY attr");
		$sth->execute();
		$sth->bind_columns(\$attr, \$count);
		while ($sth->fetch()) {
			$attrTrackCount{Slim::Utils::Unicode::utf8decode($attr, 'utf8')} = $count;
		}
		$sth->finish();
	};
	if ($@) {
		$log->error("Error getting custom tag values:\n$@");
	}

	# Pass a plain sorted list to the template to avoid hash lookups with non-ASCII keys there
	my @tagList = ();
	foreach my $thisAttr (sort { lc($a) cmp lc($b) } keys %attrValues) {
		push @tagList, {
			'name' => $thisAttr,
			'trackCount' => $attrTrackCount{$thisAttr} || 0,
			'valuelist' => [sort { lc($a->{'value'}) cmp lc($b->{'value'}) } @{$attrValues{$thisAttr}}],
		};
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('tagList = '.Data::Dump::dump(\@tagList));

	$paramRef->{'taglist'} = \@tagList;
	$paramRef->{'customtagcount'} = scalar @tagList;
}

1;
