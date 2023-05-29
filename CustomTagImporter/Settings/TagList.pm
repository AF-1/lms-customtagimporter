#
# Custom Tag Importer
#
# (c) 2021 AF
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
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
use Data::Dumper;

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
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
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return $prefs;
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;

	$result = $class->SUPER::handler($client, $paramRef);
	return $result;
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $dbh = Slim::Schema->storage->dbh();
	my $customTagSql = "select attr,value from customtagimporter_track_attributes where type='customtag' group by value";
	my %attrValHash = ();

	eval {
		my $sth = $dbh->prepare($customTagSql);
		$log->debug("Executing: $customTagSql");
		$sth->execute() or do {
			$log->error("Error executing: $customTagSql");
			$customTagSql = undef;
		};

		my $attr;
		my $value;
		$sth->bind_col(1, \$attr);
		$sth->bind_col(2, \$value);
		while ($sth->fetch()) {
			$attrValHash{$attr}{$value} = 1;
		}
	};
	if ($@) {
		$log->error("Running: $customTagSql got error:\n$@");
	}

	$log->debug('attrValHash = '.Dumper(\%attrValHash));
	$log->debug('customtagcount = '.scalar keys %attrValHash);

	$paramRef->{'attrvaluelist'} = \%attrValHash;
	$paramRef->{'customtagcount'} = scalar keys %attrValHash;
}

1;
